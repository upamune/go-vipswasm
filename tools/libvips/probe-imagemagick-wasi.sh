#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${IMAGEMAGICK_VERSION:-7.1.2-9}"
WORK="${IMAGEMAGICK_PROBE_DIR:-$ROOT/.wasmify/imagemagick-probe}"
SRC="$WORK/ImageMagick-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L --retry 3 -o "$WORK/imagemagick.tar.gz" \
    "https://github.com/ImageMagick/ImageMagick/archive/refs/tags/$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/imagemagick.tar.gz"
fi

cd "$SRC"

export CC="$WASI_SDK_PATH/bin/clang --target=wasm32-wasip1"
export AR="$WASI_SDK_PATH/bin/llvm-ar"
export RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib"
export STRIP="$WASI_SDK_PATH/bin/llvm-strip"
export CFLAGS="-O3 -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_GETPID ${CFLAGS:-}"
export LDFLAGS="-lwasi-emulated-mman -lwasi-emulated-process-clocks -lwasi-emulated-signal -lwasi-emulated-getpid ${LDFLAGS:-}"

./configure \
  --host=wasm32-wasi \
  --prefix="$PREFIX" \
  --enable-static \
  --disable-shared \
  --disable-openmp \
  --disable-docs \
  --disable-dependency-tracking \
  --disable-installed \
  --disable-largefile \
  --disable-opencl \
  --disable-hdri \
  --disable-cipher \
  --without-modules \
  --without-utilities \
  --without-magick-plus-plus \
  --without-perl \
  --without-threads \
  --without-x \
  --without-autotrace \
  --without-bzlib \
  --without-djvu \
  --without-dps \
  --without-fftw \
  --without-flif \
  --without-fontconfig \
  --without-fpx \
  --without-freetype \
  --without-gslib \
  --without-gvc \
  --without-heic \
  --without-jbig \
  --without-jpeg \
  --without-jxl \
  --without-lcms \
  --without-lqr \
  --without-lzma \
  --without-openexr \
  --without-openjp2 \
  --without-pango \
  --without-png \
  --without-raqm \
  --without-raw \
  --without-rsvg \
  --without-tiff \
  --without-webp \
  --without-wmf \
  --without-xml \
  --without-zlib \
  --without-zstd \
  --with-quantum-depth=8

# ImageMagick unconditionally includes sys/wait.h for POSIX builds even when
# configure has already detected that the target sysroot does not provide it.
perl -0pi -e 's/#  include <sys\/wait\.h>/#  if defined(MAGICKCORE_HAVE_SYS_WAIT_H)\n#   include <sys\/wait.h>\n#  endif/g' \
  MagickCore/studio.h \
  MagickWand/studio.h
perl -0pi -e 's/#  include <pwd\.h>/#  if defined(MAGICKCORE_HAVE_PWD_H)\n#   include <pwd.h>\n#  endif/g' \
  MagickCore/studio.h \
  MagickWand/studio.h
perl -0pi -e 's/defined\(MAGICKCORE_POSIX_SUPPORT\) && !defined\(__OS2__\)/defined(MAGICKCORE_POSIX_SUPPORT) \&\& !defined(__OS2__) \&\& defined(MAGICKCORE_HAVE_PWD_H)/g' \
  MagickCore/utility.c
perl -0pi -e 's/#if !defined\(MAGICKCORE_WINDOWS_SUPPORT\) \|\| defined\(__CYGWIN__\)\n  return\(popen\(command,type\)\);/#if defined(MAGICKCORE_HAVE_POPEN) \&\& (!defined(MAGICKCORE_WINDOWS_SUPPORT) || defined(__CYGWIN__))\n  return(popen(command,type));\n#elif !defined(MAGICKCORE_WINDOWS_SUPPORT) || defined(__CYGWIN__)\n  errno=ENOSYS;\n  return((FILE *) NULL);/g' \
  MagickCore/utility-private.h

make MagickCore/libMagickCore-7.Q8.la -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install-pkgconfigDATA install-MagickCoreincHEADERS install-MagickCoreincarchHEADERS
mkdir -p "$PREFIX/lib"
cp -f MagickCore/.libs/libMagickCore-7.Q8.a "$PREFIX/lib/"
"$RANLIB" "$PREFIX/lib/libMagickCore-7.Q8.a"

echo "$PREFIX"
