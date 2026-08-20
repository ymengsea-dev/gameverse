# GameVerse Wine 11 + GPTK runtime

GameVerse no longer needs the old Sikarugir Wine 10 runtime. The runtime builder in this repository compiles the published CrossOver 26 Wine source, which is based on stable Wine 11 and contains the macOS integration patches required by D3DMetal. It then stages D3DMetal, DXMT, and DXVK as separate, switchable graphics backends.

No CrossOver application installation is required. CrossOver's proprietary binaries are not copied or redistributed.

## Why this engine

Plain upstream Wine can run Windows applications on macOS, but dropping D3DMetal DLLs into an arbitrary Wine build is not equivalent to GPTK support. D3DMetal also depends on loader, `winemac.drv`, GPU, memory-region, and environment integration patches. CodeWeavers publishes the open-source portion of CrossOver 26, so GameVerse can build that complete Wine-side integration rather than cherry-picking an incomplete patch.

CrossOver 26 uses Wine 11.0, D3DMetal 3.0, and DXMT 0.72. The current 26.3.0 FOSS archive is the default input to the script. See the [CrossOver changelog](https://www.codeweavers.com/crossover/changelog), [published source](https://www.codeweavers.com/crossover/source), and [CrossOver graphics backend descriptions](https://support.codeweavers.com/en_US/advanced-settings-in-crossover-mac-26).

## Renderer policy

The bottle setting defaults to **Auto**. At launch, GameVerse scans the game's PE executables and DLL imports and chooses:

| Detected API | Preferred backend | Fallback |
| --- | --- | --- |
| DirectX 12, 64-bit | D3DMetal | WineD3D |
| DirectX 11, 64-bit | D3DMetal | DXMT, then DXVK |
| DirectX 10 | DXMT | DXVK, then WineD3D |
| DirectX 9 | WineD3D | — |
| Unknown/dynamically loaded | D3DMetal | DXMT, DXVK, then WineD3D |

Manual D3DMetal, DXMT, DXVK, and WineD3D choices remain available per bottle. GameVerse restarts that bottle's Wine server only when the resolved backend changes; this is necessary because an already-running Steam client otherwise retains the old DLLs and environment.

Steam's client UI is always launched with WineD3D and the existing CEF compatibility flags. This keeps D3DMetal/DXVK out of the login and store UI path that previously produced a black window. Launching a game then switches to the game's resolved backend before issuing Steam's `-applaunch` command.

This inspection is a strong default, not a universal compatibility database. A game can load a renderer dynamically or behave better with a non-default backend, so the manual selection is intentional.

## Prerequisites

- Apple silicon Mac with Rosetta 2.
- Xcode command-line tools.
- An Intel (`/usr/local`) Homebrew toolchain with modern Bison, GnuTLS, pkg-config, and MinGW-w64. The Wine Unix loader must be x86_64 because it runs under Rosetta.
- A Game Porting Toolkit distribution obtained from [Apple Developer](https://developer.apple.com/games/game-porting-toolkit/) after accepting Apple's license. Point the script at its extracted D3DMetal runtime; do not commit these files to this repository.
- Extracted [DXMT builtin release](https://github.com/3Shain/dxmt/releases). DXMT 0.80 is the current upstream release when this document was written. Use `dxmt-v0.80-builtin.tar.gz`; GameVerse stages both its Windows DLLs and required `x86_64-unix/winemetal.so`.
- Extracted [DXVK-macOS release](https://github.com/Gcenx/DXVK-macOS/releases) with `x64` and `x32` directories. Upstream DXVK is not a drop-in macOS build; the macOS variant supports DirectX 10/11 and uses the x86_64 MoltenVK library that GVEngine already embeds in its Runtime resources.

Example Intel Homebrew dependencies:

```bash
arch -x86_64 /usr/local/bin/brew install bison gnutls pkg-config mingw-w64
```

## Build

From the repository root:

```bash
scripts/build-gameverse-runtime.sh \
  --gptk-root "/path/to/apple_gptk" \
  --dxmt-root "/path/to/dxmt-release" \
  --dxvk-root "/path/to/dxvk-release"
```

The build is isolated under `mktemp` and creates:

```text
dist/GameVerseRuntime-CX26-GPTK3.tar.gz
dist/GameVerseRuntime-CX26-GPTK3.tar.gz.sha256
```

The archive layout is:

```text
Libraries/
├── Wine/               # CrossOver 26.3 Wine 11 build
├── D3DMetal/
│   ├── x64/            # D3DMetal PE DLLs
│   └── external/       # D3DMetal.framework + libd3dshared.dylib
├── DXMT/{x64,x32}/      # PE DLLs; winemetal.so is staged in Wine/lib/wine
├── DXVK/{x64,x32}/
└── WhiskyWineVersion.plist
```

To use an already downloaded CodeWeavers source archive or select another output path:

```bash
scripts/build-gameverse-runtime.sh \
  --source-archive "/path/to/crossover-sources-26.3.0.tar.gz" \
  --gptk-root "/path/to/apple_gptk" \
  --dxmt-root "/path/to/dxmt-release" \
  --dxvk-root "/path/to/dxvk-release" \
  --output "/path/to/GameVerseRuntime-CX26-GPTK3.tar.gz"
```

## Install for local development

GameVerse looks for the archive in its Application Support directory. Copy it there before opening the setup screen:

```bash
mkdir -p "$HOME/Library/Application Support/com.mrmengsea.GameVerse/WineRuntimeDist"
cp dist/GameVerseRuntime-CX26-GPTK3.tar.gz \
  "$HOME/Library/Application Support/com.mrmengsea.GameVerse/WineRuntimeDist/"
```

Setup extracts only the `Libraries` directory and preserves `WineRuntimeDist`, bottles, and other application data. The setup UI now reports extraction errors instead of silently continuing with a partial install.

## Distribution and licensing

The generated archive is deliberately ignored by Git. CodeWeavers publishes the FOSS source, but D3DMetal and other GPTK components have separate Apple license terms. Supplying a local GPTK path to the builder does not itself grant redistribution rights. Review the license packaged with the exact GPTK release and every included backend before publishing a runtime artifact.

## Current limitations

- The build disables GStreamer because a compatible Intel GStreamer development stack is not bundled. Games may rely on their own media framework, but some videos or codecs can be unavailable until an x86_64 GStreamer runtime is added and Wine is rebuilt against it.
- Renderer detection reads static PE imports. Games that hide, delay-load, or download their renderer later use the fallback policy and may need a manual override.
- D3DMetal is 64-bit only. A 32-bit DirectX game is routed to DXMT/DXVK when supported.
- Anti-cheat or kernel-driver requirements remain outside the scope of a graphics translation layer.
