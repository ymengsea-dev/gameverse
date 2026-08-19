# Steam Client Service Error on Wine/macOS

This document records a Steam Client Service failure found and fixed in GameVerse while running the Windows Steam client through Wine 11 on macOS.

## Environment

- GameVerse on Apple Silicon macOS
- Wine 11.0
- Windows Steam client build `1785799196`
- 64-bit `steam.exe`
- 32-bit `SteamService.exe` and `SteamService.dll`

## Symptom

Steam starts, renders the login interface, and completes authentication. After reaching the home page, Steam displays a **Steam Client Service** error.

Selecting **Install Service** opens a loading screen that never completes. Reinstalling the service does not fix the problem, even though these files exist:

```text
C:\Program Files (x86)\Common Files\Steam\SteamService.exe
C:\Program Files (x86)\Common Files\Steam\SteamService.dll
```

The service can also already be registered under:

```text
HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Steam Client Service
```

## Relevant logs

Inspect both of these files inside the Wine prefix:

```text
drive_c/Program Files (x86)/Steam/logs/service_log.txt
drive_c/Program Files (x86)/Common Files/Steam/service_log.txt
```

The failing installation produced messages similar to:

```text
Failed to create Service pipe (GLE 2)
Failed to connect to Steam Service (GLE 183)
Failed to load Steam Service (GLE 126)
ERROR: Failed to load C:\Program Files (x86)\Common Files\Steam\SteamService.dll
```

Wine's process log also showed two different module-loading results:

```text
steam.exe: Steam\bin\steamservice.dll failed with c000007b
SteamService.exe: Common Files\Steam\SteamService.dll failed with c0000135
```

These errors come from different processes and must not be interpreted as the same failure.

## Root cause

GameVerse previously generated this DLL override for every process in the bottle:

```text
WINEDLLOVERRIDES="mscoree=;steamservice=d;SteamService=d"
```

The `d` value tells Wine to disable that DLL. Since environment variables are inherited, this override affected both Steam and every process Steam launched.

The current Windows Steam client uses this sequence:

1. The 64-bit `steam.exe` probes the 32-bit `Steam/bin/steamservice.dll` in-process.
2. Wine rejects that architecture mismatch with `c000007b` (`STATUS_INVALID_IMAGE_FORMAT`).
3. Steam falls back to launching the matching 32-bit `SteamService.exe` out of process.
4. The service executable attempts to load its matching 32-bit `SteamService.dll`.

Step 2 is an expected, non-fatal probe. The real failure occurred at step 4: the child service inherited `steamservice=d`, so Wine deliberately refused to load the correct DLL and returned error 126/module-not-found. The service could not create its IPC pipe, and Steam repeatedly requested installation.

Clicking **Install Service** could copy and register the service, but it could never overcome a DLL that GameVerse disabled at process startup. This is why the installation interface appeared stuck.

## Fix

Do not disable `steamservice.dll` globally. GameVerse now disables only the unrelated optional Mono bridge by default:

```swift
var dllOverrides = ["mscoree="]
if dxvk {
    dllOverrides.append("dxgi,d3d9,d3d10core,d3d11=n,b")
}
wineEnv.updateValue(
    dllOverrides.joined(separator: ";"),
    forKey: "WINEDLLOVERRIDES"
)
```

The implementation is in:

```text
GVEngine/Sources/Core/BottleSettings.swift
```

For a shell-based Wine launcher, follow the same rule:

```bash
# Steam Client Service is allowed to load.
export WINEDLLOVERRIDES="mscoree=;dxgi=b;d3d11=b;d3d10core=b"

# Do not use either of these:
# steamservice=d
# SteamService=d
```

## Applying the fix

1. Remove `steamservice=d` and `SteamService=d` from the generated Wine environment.
2. Rebuild GameVerse.
3. Completely stop Steam and the affected bottle's Wine server.
4. Launch Steam again through GameVerse.
5. Do not click **Install Service** again if it was already installed; it should start after the clean prefix restart.

A complete Wine-prefix restart is important. Closing only the visible Steam window can leave the Wine service process tree alive with the old inherited environment.

## Verification

Confirm all of the following:

- The effective `WINEDLLOVERRIDES` contains no case variation of `steamservice`.
- Steam reaches its home page without displaying the service warning.
- The service logs stop repeating `GLE 126` and pipe connection failures.
- Games can be installed and launched normally.

An isolated `c000007b` line from the 64-bit Steam client's probe is not itself a regression. Judge the operational service using the 32-bit service log and Steam's visible behavior.

## Regression coverage

GameVerse includes a test that constructs the default Wine environment and asserts that `WINEDLLOVERRIDES` does not contain `steamservice`:

```text
GVEngine/Tests/GVEngineTests/BottleSettingsTests.swift
```

This prevents the broken global override from being introduced again.
