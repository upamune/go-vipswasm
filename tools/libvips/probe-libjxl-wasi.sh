#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBJXL_VERSION:-0.11.1}"
WORK="${LIBJXL_PROBE_DIR:-$ROOT/.wasmify/libjxl-probe}"
SRC="$WORK/libjxl-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
BROTLI_PREFIX="${BROTLI_PREFIX:-$ROOT/.wasmify/brotli-probe/prefix}"
HIGHWAY_PREFIX="${HIGHWAY_PREFIX:-$ROOT/.wasmify/highway-probe/prefix}"
LCMS_PREFIX="${LCMS_PREFIX:-$ROOT/.wasmify/lcms-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"
LIBPNG_PREFIX="${LIBPNG_PREFIX:-$ROOT/.wasmify/libpng-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libjxl.tar.gz" "https://github.com/libjxl/libjxl/archive/refs/tags/v$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/libjxl.tar.gz"
fi

export PKG_CONFIG_PATH="$BROTLI_PREFIX/lib/pkgconfig:$HIGHWAY_PREFIX/lib/pkgconfig:$LCMS_PREFIX/lib/pkgconfig:$ZLIB_PREFIX/lib/pkgconfig:$LIBPNG_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
cmake -S "$SRC" -B "$WORK/build" \
  -DCMAKE_SYSTEM_NAME=WASI \
  -DCMAKE_SYSTEM_PROCESSOR=wasm32 \
  -DCMAKE_C_COMPILER="$WASI_SDK_PATH/bin/clang" \
  -DCMAKE_C_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_CXX_COMPILER="$WASI_SDK_PATH/bin/clang++" \
  -DCMAKE_CXX_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_AR="$WASI_SDK_PATH/bin/llvm-ar" \
  -DCMAKE_RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$BROTLI_PREFIX;$HIGHWAY_PREFIX;$LCMS_PREFIX;$ZLIB_PREFIX;$LIBPNG_PREFIX" \
  -DLCMS2_INCLUDE_DIR="$LCMS_PREFIX/include" \
  -DLCMS2_LIBRARY="$LCMS_PREFIX/lib/liblcms2.a" \
  -DZLIB_INCLUDE_DIR="$ZLIB_PREFIX/include" \
  -DZLIB_LIBRARY="$ZLIB_PREFIX/lib/libz.a" \
  -DPNG_PNG_INCLUDE_DIR="$LIBPNG_PREFIX/include" \
  -DPNG_LIBRARY="$LIBPNG_PREFIX/lib/libpng16.a" \
  -DCMAKE_C_FLAGS="-D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID" \
  -DCMAKE_CXX_FLAGS="-D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID" \
  -DCMAKE_EXE_LINKER_FLAGS="-lwasi-emulated-process-clocks -lwasi-emulated-getpid" \
  -DBUILD_SHARED_LIBS=OFF \
  -DJPEGXL_STATIC=ON \
  -DJPEGXL_ENABLE_TOOLS=OFF \
  -DJPEGXL_ENABLE_MANPAGES=OFF \
  -DJPEGXL_ENABLE_BENCHMARK=OFF \
  -DJPEGXL_ENABLE_EXAMPLES=OFF \
  -DJPEGXL_ENABLE_PLUGINS=OFF \
  -DJPEGXL_ENABLE_JNI=OFF \
  -DJPEGXL_ENABLE_SJPEG=OFF \
  -DJPEGXL_ENABLE_OPENEXR=OFF \
  -DJPEGXL_ENABLE_SKCMS=OFF \
  -DJPEGXL_ENABLE_VIEWERS=OFF \
  -DJPEGXL_ENABLE_DEVTOOLS=OFF \
  -DJPEGXL_ENABLE_DOXYGEN=OFF \
  -DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
  -DJPEGXL_FORCE_SYSTEM_HWY=ON \
  -DBUILD_TESTING=OFF

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

for pc in "$PREFIX"/lib/pkgconfig/libjxl.pc "$PREFIX"/lib/pkgconfig/libjxl_threads.pc; do
  if [[ -f "$pc" ]]; then
    perl -0pi -e '
      my @private = /Libs\.private:[ \t]*([^\n]*)/g;
      s/^Libs\.private:[^\n]*\n//mg;
      my %seen;
      my @libs = grep { length && !$seen{$_}++ }
        split /\s+/, join(" ", @private, "-lc++ -lc++abi -lwasi-emulated-process-clocks -lwasi-emulated-getpid");
      s/Libs:([^\n]*)\n/Libs:$1\nLibs.private: @libs\n/;
    ' "$pc"
  fi
done

echo "$PREFIX"
