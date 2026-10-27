#!/bin/bash
# Build Wine from CodeWeavers' published LGPL source as an x86_64 cellar runtime on an arm64 Mac.
#
# No x86_64 Homebrew needed: host code is cross-compiled with `clang -arch x86_64`,
# third-party x86_64 dylibs (gnutls, freetype, SDL2, vulkan...) are borrowed from the
# Gcenx staging runtime, and the matching headers come from arm64 Homebrew.
#
# Usage: build-wine.sh [source-version] [runtime-name]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

CX_VERSION="${1:-26.1.0}"
NAME="${2:-cx}"
CELLAR_HOME="${CELLAR_HOME:-$HOME/Library/Application Support/Cellar}"
# Autoconf/make can't cope with spaces ("Application Support"), so source, build and
# staging install live in a space-free work dir; the finished, relocatable tree is copied over.
WORK="${CELLAR_BUILD:-$HOME/.cache/cellar-build}"
SRC="$WORK/src"
BUILD="$WORK/$NAME"
STAGE="$BUILD/install"
DEST="$CELLAR_HOME/runtimes/$NAME/wine"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
BREW="${BREW:-/opt/homebrew}"

log() { echo "==> $*"; }
die() { echo "build-wine: $*" >&2; exit 1; }

# x86_64 dylibs to link against and ship with the runtime.
STAGING_LIBS=$(find "$CELLAR_HOME/runtimes/staging" -path '*/wine/lib' -type d 2>/dev/null | head -1)
[ -n "$STAGING_LIBS" ] || die "staging runtime missing; run: cellar runtime install staging"
case "$WORK" in *" "*) die "CELLAR_BUILD must not contain spaces: $WORK" ;; esac
mkdir -p "$BUILD"
# The staging dylibs carry bare install names ("libSDL2.dylib"), which Wine's configure
# can't turn into sonames. Copy them and give each real file an @rpath/<filename> id.
DEPLIBS="$BUILD/deplibs"
if [ ! -f "$DEPLIBS/.ids-fixed" ]; then
  rm -rf "$DEPLIBS"; mkdir -p "$DEPLIBS"
  cp -a "$STAGING_LIBS"/*.dylib "$DEPLIBS/"
  for f in "$DEPLIBS"/*.dylib; do
    [ -L "$f" ] && continue
    install_name_tool -id "@rpath/$(basename "$f")" "$f" 2>/dev/null
    codesign -f -s - "$f" 2>/dev/null
  done
  touch "$DEPLIBS/.ids-fixed"
fi

for t in "$BREW/opt/bison/bin/bison" "$BREW/bin/x86_64-w64-mingw32-gcc" "$BREW/bin/i686-w64-mingw32-gcc" \
         "$BREW/include/gnutls/gnutls.h" "$BREW/include/freetype2/ft2build.h" "$BREW/include/SDL2/SDL.h"; do
  [ -e "$t" ] || die "missing $t (brew install bison mingw-w64 gnutls freetype sdl2)"
done

# --- source -----------------------------------------------------------------
mkdir -p "$SRC"
tarball="$SRC/crossover-sources-$CX_VERSION.tar.gz"
WINESRC="$SRC/wine-cx-$CX_VERSION"
if [ ! -f "$WINESRC/configure" ]; then
  if [ ! -f "$tarball" ]; then
    log "Downloading CodeWeavers $CX_VERSION Wine sources"
    curl -fL --progress-bar -o "$tarball.part" \
      "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$CX_VERSION.tar.gz"
    mv "$tarball.part" "$tarball"
  fi
  log "Extracting wine source"
  rm -rf "$WINESRC" "$SRC/sources"
  tar -xzf "$tarball" -C "$SRC" sources/wine
  mv "$SRC/sources/wine" "$WINESRC"; rmdir "$SRC/sources"
fi

# --- cellar patches -----------------------------------------------------------
for p in "$ROOT"/patches/*.patch; do
  [ -f "$p" ] || continue
  if patch -d "$WINESRC" -p1 -R --dry-run -s -f <"$p" >/dev/null 2>&1; then
    continue  # already applied
  fi
  log "Applying $(basename "$p")"
  patch -d "$WINESRC" -p1 -s -f <"$p" || die "patch $(basename "$p") failed"
done

# --- headers ----------------------------------------------------------------
# Only expose the headers we need, not all of arm64 Homebrew.
INC="$BUILD/include"
mkdir -p "$INC"
ln -sfn "$BREW/include/gnutls" "$INC/gnutls"
ln -sfn "$BREW/include/SDL2" "$INC/SDL2"

# --- configure --------------------------------------------------------------
export PATH="$BREW/opt/bison/bin:$BREW/bin:$PATH"
export CC="clang -arch x86_64"
export CXX="clang++ -arch x86_64"
export CFLAGS="-O2 -I$INC"
# ../../external lets D3DMetal's dlopen("@rpath/D3DMetal.framework") resolve from ntdll.so;
# the build-dir rpath lets build tools such as sfnt2fon find freetype while compiling.
export LDFLAGS="-L$DEPLIBS -Wl,-rpath,@loader_path/../../ -Wl,-rpath,@loader_path/../../external -Wl,-rpath,@executable_path/../lib -Wl,-rpath,$DEPLIBS"
export MACOSX_DEPLOYMENT_TARGET=11.0
export GNUTLS_CFLAGS="-I$INC" GNUTLS_LIBS="-L$DEPLIBS -lgnutls"
export FREETYPE_CFLAGS="-I$BREW/include/freetype2" FREETYPE_LIBS="-L$DEPLIBS -lfreetype"
export SDL2_CFLAGS="-I$INC/SDL2" SDL2_LIBS="-L$DEPLIBS -lSDL2"

mkdir -p "$BUILD/obj"
cd "$BUILD/obj"
if [ ! -f Makefile ]; then
  log "Configuring (log: $BUILD/configure.log)"
  "$WINESRC/configure" \
    --prefix="$STAGE" \
    --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
    --enable-archs=i386,x86_64 \
    --disable-tests \
    --with-mingw \
    --with-coreaudio --with-opencl --with-vulkan \
    --with-freetype --with-gnutls --with-sdl --with-pcap --with-unwind \
    --without-alsa --without-capi --without-cups --without-dbus --without-fontconfig \
    --without-gettext --without-gettextpo --without-gphoto --without-gssapi \
    --without-gstreamer --without-inotify --without-krb5 --without-netapi \
    --without-oss --without-pulse --without-sane --without-udev --without-usb \
    --without-v4l2 --without-wayland --without-x \
    >"$BUILD/configure.log" 2>&1 || { tail -30 "$BUILD/configure.log"; die "configure failed"; }
  grep -A40 'configure: Finished' "$BUILD/configure.log" | grep -i -E 'warning|won.t' || true
fi

# --- build & install --------------------------------------------------------
log "Building with $JOBS jobs (log: $BUILD/make.log)"
make -j"$JOBS" >"$BUILD/make.log" 2>&1 || { grep -E 'error|Error' "$BUILD/make.log" | tail -20; die "build failed"; }

log "Installing to $DEST"
rm -rf "$STAGE"
make install-lib >"$BUILD/install.log" 2>&1 || { tail -20 "$BUILD/install.log"; die "install failed"; }
cp -a "$DEPLIBS"/*.dylib "$STAGE/lib/"
# Replacing the tree drops D3DMetal; remember whether it was on so it can be put back.
d3dmetal=0; [ -d "$DEST/lib/wine/.wined3d-backup" ] && d3dmetal=1
rm -rf "$DEST"; mkdir -p "$(dirname "$DEST")"
cp -a "$STAGE" "$DEST"
echo "codeweavers-$CX_VERSION" > "$CELLAR_HOME/runtimes/$NAME/VERSION"
if [ $d3dmetal = 1 ]; then
  log "Re-enabling D3DMetal"
  CELLAR_HOME="$CELLAR_HOME" "$ROOT/cellar" runtime d3dmetal "$NAME" on
fi
log "Done: $("$DEST/bin/wine" --version)"
