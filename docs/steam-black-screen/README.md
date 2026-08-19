# Steam Black Login/UI Screen on Wine/macOS

This document records the Steam Chromium Embedded Framework (CEF) black-screen problem found and fixed in GameVerse while running the Windows Steam client through Wine on Apple Silicon macOS.

## Environment

- GameVerse on Apple Silicon macOS
- Wine 11.0 running through Rosetta 2
- Windows Steam client build `1785799196`
- Steam CEF/`steamwebhelper.exe`
- Both 64-bit (`cef.win64`) and legacy 32-bit (`cef.win7`) helper locations supported

GameVerse currently uses a custom Wine 11 runtime with DXVK. Its Steam UI fix does not depend on game rendering through DXVK: the Steam interface and launched games run in separate processes and can use different rendering paths.

## Symptom

Steam starts and creates a visible window, but the login page or main client area is completely black. The process remains alive, and native window controls or menus may still respond.

Common variations include:

- A black login window with working borders and controls.
- A black Store or Library area after Steam starts.
- CEF menus, icons, or popups flickering.
- Steam remaining alive while its web-based interface never paints.
- The UI working temporarily after a repair, then becoming black again on the next launch.

This is different from a Steam networking or authentication failure. In the black-screen case, the CEF browser exists and may render internally, but Wine does not reliably present the resulting surface to the macOS window.

## Architecture involved

Modern Steam renders most of its interface with CEF. A normal CEF launch divides work between several Windows processes:

```text
Steam.exe
  └─ steamwebhelper.exe (browser)
       ├─ renderer process
       ├─ GPU process
       └─ utility/network processes
```

On Wine/macOS, this process split introduces a fragile cross-process rendering and window-presentation path. The GPU or renderer process can produce frames while the browser process's native macOS window remains black. Separate CEF processes also amplify macOS window visibility and composition races that can appear as popup or menu flicker.

## Root cause

Two related conditions caused the GameVerse failure:

1. Steam's accelerated, multi-process CEF path did not reliably present its rendered surface through Wine's macOS driver.
2. Steam's bootstrap verification could silently replace GameVerse's patched `steamwebhelper.exe` with Valve's original helper before CEF started.

Passing only Steam-level `-cef-*` arguments was not sufficient. Steam recognizes a limited set of its own CEF switches, but it does not reliably forward arbitrary Chromium arguments to `steamwebhelper.exe`. The important Chromium arguments must reach the helper process itself:

```text
--disable-gpu --single-process
```

`--disable-gpu` moves the Steam interface to software rendering. `--single-process` keeps CEF's browser, renderer, GPU fallback, and utility work inside one helper process, avoiding the failing cross-process presentation boundary.

## Fix overview

GameVerse applies the fix in two layers:

1. It launches `Steam.exe` with supported Steam-level safety arguments.
2. It replaces each installed `steamwebhelper.exe` with an architecture-matched wrapper that launches Valve's genuine helper with the required Chromium arguments.

Steam-level arguments:

```text
-no-cef-sandbox
-cef-disable-gpu
-cef-single-process
-noverifyfiles
```

Helper-level arguments injected by the wrapper:

```text
--disable-gpu --single-process
```

The wrapper reads the optional `GAMEVERSE_CEF_FLAGS` environment variable. If it is not set, the wrapper uses the software/single-process arguments above.

## Helper layout

Steam can install more than one CEF architecture. GameVerse handles both locations:

```text
Steam/bin/cef/cef.win64/steamwebhelper.exe
Steam/bin/cef/cef.win7/steamwebhelper.exe
```

For each existing location, GameVerse produces this layout:

```text
steamwebhelper.exe       # GameVerse wrapper
steamwebhelper_real.exe  # Valve's genuine helper
```

The bundled wrappers are:

```text
GVEngine/Sources/Resources/Shims/steamwebhelper_x64.exe
GVEngine/Sources/Resources/Shims/steamwebhelper_x86.exe
```

Both wrappers launch `steamwebhelper_real.exe` with the original command line plus the GameVerse CEF arguments.

## Why `-noverifyfiles` is required

Steam verifies executable checksums during startup. Without `-noverifyfiles`, its bootstrapper can detect the smaller wrapper and restore Valve's original `steamwebhelper.exe` before launching CEF.

The relevant bootstrap log can look like this:

```text
BVerifyInstalledFiles: bin\cef\cef.win64\steamwebhelper.exe is 18432 bytes, expected 7489176
Installing update...
Verifying installation...
```

The apparent sequence is:

```text
GameVerse installs wrapper
  → Steam verifies executable checksums
  → Steam restores the genuine helper
  → CEF starts without --disable-gpu --single-process
  → Steam window becomes black
```

`-noverifyfiles` prevents that launch-time replacement. GameVerse does not use the stronger update-blocking arguments `-nobootstrapupdate`, `-skipinitialbootstrap`, or `-norepairfiles`, because freezing Steam updates can leave mixed 32-bit and 64-bit client files.

## Safe wrapper and update lifecycle

The wrapper installer must distinguish three states:

### First installation

Valve's helper is at `steamwebhelper.exe` and no backup exists. GameVerse moves it to `steamwebhelper_real.exe`, then copies in the wrapper.

### Wrapper already installed

GameVerse compares the installed helper with its bundled wrapper. If they are identical and the genuine backup exists, repair is idempotent and leaves both files untouched.

### Steam updated the helper

Steam may replace `steamwebhelper.exe` with a newer genuine version during a client update. GameVerse detects that the target no longer matches its wrapper, replaces the old `steamwebhelper_real.exe` backup with this newer genuine helper, and then reinstalls the wrapper.

This detail is important. An older repair implementation restored the existing backup before every launch. If Steam had just updated its helper, that behavior discarded the update and preserved an obsolete helper. The current implementation refreshes the genuine backup instead.

If the wrapper exists but `steamwebhelper_real.exe` is missing, GameVerse stops with a repair error. Continuing would make the wrapper recursively launch itself or leave Steam without a genuine helper.

The implementation is in:

```text
GVEngine/Sources/Core/SteamFixup.swift
GVEngine/Sources/Steam/SteamLauncher.swift
```

## Additional repair steps

Before installing the wrapper, GameVerse also repairs state that can resemble or compound a black CEF window.

### Clear CEF HTML caches

GameVerse removes every matching cache under the prefix instead of assuming that the Windows user has the same name as the macOS account:

```text
drive_c/users/*/AppData/Local/Steam/htmlcache
```

Wine prefixes may use names such as the host username, `steamuser`, or `crossover`. Clearing only one hard-coded username can leave the active corrupt cache untouched.

### Ensure Steam loopback resolution

Steam's web UI communicates with the native client through `steamloopback.host`. GameVerse adds both mappings to Wine's Windows hosts file when missing:

```text
127.0.0.1 steamloopback.host
::1 steamloopback.host
```

The target file is:

```text
drive_c/windows/system32/drivers/etc/hosts
```

### Surface repair failures

Steam launch now propagates wrapper installation errors instead of discarding them with `try?`. This prevents GameVerse from knowingly launching an unpatched helper and presenting another unexplained black window.

## Applying the fix manually

GameVerse performs these steps automatically. For diagnosis or another Wine launcher, the equivalent procedure is:

1. Fully stop Steam and the affected Wine prefix.
2. Locate every `Steam/bin/cef/cef.win*/steamwebhelper.exe` directory.
3. Preserve Valve's genuine helper as `steamwebhelper_real.exe`.
4. Install an architecture-matched wrapper as `steamwebhelper.exe`.
5. Configure the wrapper to append `--disable-gpu --single-process`.
6. Launch Steam with `-no-cef-sandbox -cef-disable-gpu -cef-single-process -noverifyfiles`.
7. Confirm Steam does not replace the wrapper during startup.

Do not copy the 64-bit wrapper into `cef.win7`, or the 32-bit wrapper into `cef.win64`.

## Verification

Confirm all of the following:

- The Steam login and main client UI render instead of remaining black.
- `steamwebhelper.exe` matches the GameVerse wrapper after Steam has started.
- `steamwebhelper_real.exe` exists and is substantially larger than the wrapper.
- The wrapper contains `GAMEVERSE_CEF_FLAGS` and the default `--disable-gpu --single-process` string.
- `bootstrap_log.txt` does not replace the helper during this launch.
- Both login and post-login navigation work.

Useful logs inside the Steam installation include:

```text
logs/bootstrap_log.txt
logs/webhelper.txt
logs/webhelper_gpu.txt
logs/cef_log.txt
```

When gathering a failure report, record the Steam client build, Wine version, helper architecture, effective Steam arguments, and whether the installed helper still matches the wrapper.

## Trade-offs

Steam's interface is CPU-rendered with this workaround, so animated pages may redraw more slowly than a fully accelerated CEF session. Games are not forced into software rendering: they launch as separate Wine processes and continue to use the bottle's configured DXVK or other game renderer.

The software/single-process path is the reliability default. Experimental accelerated CEF paths can be supplied through `GAMEVERSE_CEF_FLAGS`, but they may bring back the original black surface or window flicker.

## Regression coverage

GameVerse tests cover:

- The supported Steam launch argument set.
- Initial wrapper installation and genuine-helper preservation.
- Idempotent repeated repair.
- Refreshing the genuine backup after a simulated Steam update.
- Clearing CEF caches for multiple Wine users.
- Steam game launch arguments retaining the Steam fix arguments.

The tests are located in:

```text
GVEngine/Tests/GVEngineTests/SteamFixupTests.swift
GVEngine/Tests/GVEngineTests/SteamLauncherTests.swift
```

## References

- [notpop/steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine) — independent Apple Silicon Wine setup using the same software/single-process CEF workaround.
- [ValveSoftware/steam-for-linux issue #10561](https://github.com/ValveSoftware/steam-for-linux/issues/10561) — a Steam black-window report resolved by disabling CEF GPU rendering.
- [ValveSoftware/steam-for-linux issue #13278](https://github.com/ValveSoftware/steam-for-linux/issues/13278) — investigation of Steam's recognized CEF switches and GPU fallback behavior.
