#!/bin/bash

set -euo pipefail

CROSSOVER_VERSION="26.3.0"
CROSSOVER_SOURCE_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CROSSOVER_VERSION}.tar.gz"
GPTK_ROOT=""
DXMT_ROOT=""
DXVK_ROOT=""
SOURCE_ARCHIVE=""
OUTPUT_PATH="dist/GameVerseRuntime-CX26-GPTK3.tar.gz"
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"

usage() {
    echo "Usage: $0 --gptk-root PATH --dxmt-root PATH --dxvk-root PATH [options]"
    echo
    echo "Required renderer inputs:"
    echo "  --gptk-root PATH       Extracted, licensed Apple GPTK D3DMetal runtime"
    echo "  --dxmt-root PATH       Extracted DXMT builtin release"
    echo "  --dxvk-root PATH       Extracted DXVK release containing x64/ and x32/"
    echo
    echo "Options:"
    echo "  --source-archive PATH  Existing CrossOver source archive (skips download)"
    echo "  --output PATH          Output archive (default: ${OUTPUT_PATH})"
    echo "  --jobs COUNT           Parallel build jobs (default: ${JOBS})"
    echo "  --help                 Show this help"
}

fail() {
    echo "error: $*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --gptk-root)
            [ "$#" -ge 2 ] || fail "--gptk-root requires a path"
            GPTK_ROOT="$2"
            shift 2
            ;;
        --dxmt-root)
            [ "$#" -ge 2 ] || fail "--dxmt-root requires a path"
            DXMT_ROOT="$2"
            shift 2
            ;;
        --dxvk-root)
            [ "$#" -ge 2 ] || fail "--dxvk-root requires a path"
            DXVK_ROOT="$2"
            shift 2
            ;;
        --source-archive)
            [ "$#" -ge 2 ] || fail "--source-archive requires a path"
            SOURCE_ARCHIVE="$2"
            shift 2
            ;;
        --output)
            [ "$#" -ge 2 ] || fail "--output requires a path"
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --jobs)
            [ "$#" -ge 2 ] || fail "--jobs requires a count"
            JOBS="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

[ -d "$GPTK_ROOT" ] || fail "pass an extracted GPTK directory with --gptk-root"
[ -d "$DXMT_ROOT" ] || fail "pass an extracted DXMT directory with --dxmt-root"
[ -d "$DXVK_ROOT/x64" ] || fail "DXVK root must contain x64/"
[ -d "$DXVK_ROOT/x32" ] || fail "DXVK root must contain x32/"
case "$JOBS" in
    ''|*[!0-9]*) fail "--jobs must be a positive integer" ;;
    0) fail "--jobs must be greater than zero" ;;
esac
[ ! -e "$OUTPUT_PATH" ] || fail "output already exists: $OUTPUT_PATH"

for tool in arch curl make tar clang pkg-config i686-w64-mingw32-gcc x86_64-w64-mingw32-gcc; do
    command -v "$tool" >/dev/null 2>&1 || fail "required build tool is missing: $tool"
done

BISON_BIN="$(command -v bison || true)"
if [ -x /usr/local/opt/bison/bin/bison ]; then
    BISON_BIN=/usr/local/opt/bison/bin/bison
fi
[ -n "$BISON_BIN" ] || fail "bison is required"
BISON_VERSION="$($BISON_BIN --version | head -n 1 | awk '{print $4}')"
case "$BISON_VERSION" in
    1.*|2.*) fail "Wine requires modern bison; install bison with Intel Homebrew" ;;
esac

for required in dxgi.dll d3d11.dll; do
    [ -f "$DXVK_ROOT/x64/$required" ] || fail "DXVK x64 is missing $required"
done
for required in dxgi.dll d3d11.dll; do
    [ -f "$DXVK_ROOT/x32/$required" ] || fail "DXVK x32 is missing $required"
done

GPTK_DLL_ROOT=""
for candidate in \
    "$GPTK_ROOT/wine/x86_64-windows" \
    "$GPTK_ROOT/lib/wine/x86_64-windows" \
    "$GPTK_ROOT/x86_64-windows"; do
    if [ -f "$candidate/dxgi.dll" ] && [ -f "$candidate/d3d11.dll" ] && [ -f "$candidate/d3d12.dll" ]; then
        GPTK_DLL_ROOT="$candidate"
        break
    fi
done
[ -n "$GPTK_DLL_ROOT" ] || fail "could not locate GPTK's x86_64 D3DMetal DLLs"

GPTK_EXTERNAL_ROOT=""
for candidate in "$GPTK_ROOT/external" "$GPTK_ROOT/lib/external" "$GPTK_ROOT"; do
    if [ -f "$candidate/libd3dshared.dylib" ] && [ -d "$candidate/D3DMetal.framework" ]; then
        GPTK_EXTERNAL_ROOT="$candidate"
        break
    fi
done
[ -n "$GPTK_EXTERNAL_ROOT" ] || fail "could not locate libd3dshared.dylib and D3DMetal.framework"

DXMT_X64_ROOT=""
DXMT_X32_ROOT=""
DXMT_UNIX_ROOT=""
for candidate in "$DXMT_ROOT/x64" "$DXMT_ROOT/x86_64-windows"; do
    if [ -f "$candidate/dxgi.dll" ] && [ -f "$candidate/d3d11.dll" ] && [ -f "$candidate/winemetal.dll" ]; then
        DXMT_X64_ROOT="$candidate"
        break
    fi
done
if [ -z "$DXMT_X64_ROOT" ]; then
    DXMT_X64_ROOT="$(find "$DXMT_ROOT" -type d -name x86_64-windows -print -quit)"
fi
[ -n "$DXMT_X64_ROOT" ] || fail "could not locate DXMT's x86_64-windows directory"
for required in dxgi.dll d3d11.dll winemetal.dll; do
    [ -f "$DXMT_X64_ROOT/$required" ] || fail "DXMT x86_64 is missing $required"
done

for candidate in "$DXMT_ROOT/x32" "$DXMT_ROOT/i386-windows"; do
    if [ -d "$candidate" ]; then
        DXMT_X32_ROOT="$candidate"
        break
    fi
done
if [ -z "$DXMT_X32_ROOT" ]; then
    DXMT_X32_ROOT="$(find "$DXMT_ROOT" -type d -name i386-windows -print -quit)"
fi
DXMT_UNIX_ROOT="$(find "$DXMT_ROOT" -type f -path '*/x86_64-unix/winemetal.so' -print -quit)"
[ -n "$DXMT_UNIX_ROOT" ] || fail "DXMT builtin release is missing x86_64-unix/winemetal.so"

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gameverse-runtime.XXXXXX")"
cleanup() {
    case "$WORK_ROOT" in
        "${TMPDIR:-/tmp}"/gameverse-runtime.*) rm -rf "$WORK_ROOT" ;;
    esac
}
trap cleanup EXIT INT TERM

if [ -z "$SOURCE_ARCHIVE" ]; then
    SOURCE_ARCHIVE="$WORK_ROOT/crossover-sources-${CROSSOVER_VERSION}.tar.gz"
    echo "Downloading CrossOver ${CROSSOVER_VERSION} FOSS source..."
    curl --fail --location --proto '=https' --tlsv1.2 \
        "$CROSSOVER_SOURCE_URL" --output "$SOURCE_ARCHIVE"
else
    [ -f "$SOURCE_ARCHIVE" ] || fail "source archive does not exist: $SOURCE_ARCHIVE"
fi

SOURCE_ROOT="$WORK_ROOT/source"
BUILD_ROOT="$WORK_ROOT/build"
INSTALL_ROOT="$WORK_ROOT/install"
STAGE_ROOT="$WORK_ROOT/stage"
mkdir -p "$SOURCE_ROOT" "$BUILD_ROOT" "$INSTALL_ROOT" "$STAGE_ROOT/Libraries"
tar -xzf "$SOURCE_ARCHIVE" -C "$SOURCE_ROOT"
WINE_SOURCE="$(find "$SOURCE_ROOT" -type d -path '*/sources/wine' -print -quit)"
[ -n "$WINE_SOURCE" ] || fail "the archive does not contain sources/wine"

BISON_DIR="$(dirname "$BISON_BIN")"
BUILD_PATH="$BISON_DIR:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
GNUTLS_PKGCONFIG="/usr/local/opt/gnutls/lib/pkgconfig"

echo "Configuring CrossOver ${CROSSOVER_VERSION} Wine for Intel/Rosetta WoW64..."
(
    cd "$BUILD_ROOT"
    arch -x86_64 env \
        PATH="$BUILD_PATH" \
        PKG_CONFIG_PATH="$GNUTLS_PKGCONFIG" \
        CC=clang CXX=clang++ \
        "$WINE_SOURCE/configure" \
        --prefix="$INSTALL_ROOT" \
        --enable-archs=i386,x86_64 \
        --without-x \
        --without-gstreamer
    arch -x86_64 env PATH="$BUILD_PATH" make -j"$JOBS"
    arch -x86_64 env PATH="$BUILD_PATH" make install
)

mkdir -p "$STAGE_ROOT/Libraries/Wine"
for directory in bin lib share; do
    cp -R "$INSTALL_ROOT/$directory" "$STAGE_ROOT/Libraries/Wine/$directory"
done
# Keep compatibility with older GameVerse builds while Wine 11 new-WoW64 uses `wine`.
if [ ! -e "$STAGE_ROOT/Libraries/Wine/bin/wine64" ]; then
    ln -s wine "$STAGE_ROOT/Libraries/Wine/bin/wine64"
fi

mkdir -p "$STAGE_ROOT/Libraries/D3DMetal/x64" "$STAGE_ROOT/Libraries/D3DMetal/external"
find "$GPTK_DLL_ROOT" -maxdepth 1 -type f -name '*.dll' -exec cp {} "$STAGE_ROOT/Libraries/D3DMetal/x64/" \;
cp "$GPTK_EXTERNAL_ROOT/libd3dshared.dylib" "$STAGE_ROOT/Libraries/D3DMetal/external/"
cp -R "$GPTK_EXTERNAL_ROOT/D3DMetal.framework" "$STAGE_ROOT/Libraries/D3DMetal/external/"

mkdir -p "$STAGE_ROOT/Libraries/DXMT" "$STAGE_ROOT/Libraries/DXVK"
cp -R "$DXMT_X64_ROOT" "$STAGE_ROOT/Libraries/DXMT/x64"
if [ -n "$DXMT_X32_ROOT" ]; then
    cp -R "$DXMT_X32_ROOT" "$STAGE_ROOT/Libraries/DXMT/x32"
fi
cp "$DXMT_UNIX_ROOT" "$STAGE_ROOT/Libraries/Wine/lib/wine/x86_64-unix/winemetal.so"
cp -R "$DXVK_ROOT/x64" "$STAGE_ROOT/Libraries/DXVK/x64"
cp -R "$DXVK_ROOT/x32" "$STAGE_ROOT/Libraries/DXVK/x32"

cat > "$STAGE_ROOT/Libraries/WhiskyWineVersion.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>version</key>
    <dict>
        <key>major</key><integer>11</integer>
        <key>minor</key><integer>0</integer>
        <key>patch</key><integer>0</integer>
        <key>preRelease</key><string></string>
        <key>build</key><string>0</string>
    </dict>
</dict>
</plist>
PLIST

arch -x86_64 "$STAGE_ROOT/Libraries/Wine/bin/wine" --version
mkdir -p "$(dirname "$OUTPUT_PATH")"
COPYFILE_DISABLE=1 tar -czf "$OUTPUT_PATH" -C "$STAGE_ROOT" Libraries
shasum -a 256 "$OUTPUT_PATH" > "${OUTPUT_PATH}.sha256"

echo
echo "Runtime created: $OUTPUT_PATH"
echo "Checksum: ${OUTPUT_PATH}.sha256"
echo "Do not commit the generated archive; review every component's license before distribution."
