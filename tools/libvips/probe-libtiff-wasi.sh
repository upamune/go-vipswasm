#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBTIFF_VERSION:-4.7.1}"
WORK="${LIBTIFF_PROBE_DIR:-$ROOT/.wasmify/libtiff-probe}"
SRC="$WORK/tiff-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"
LIBJPEG_PREFIX="${LIBJPEG_PREFIX:-$ROOT/.wasmify/libjpeg-probe/prefix}"
LIBWEBP_PREFIX="${LIBWEBP_PREFIX:-$ROOT/.wasmify/libwebp-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libtiff.tar.gz" "https://download.osgeo.org/libtiff/tiff-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/libtiff.tar.gz"
fi

export PKG_CONFIG_PATH="$ZLIB_PREFIX/lib/pkgconfig:$LIBJPEG_PREFIX/lib/pkgconfig:$LIBWEBP_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
cmake -S "$SRC" -B "$WORK/build" \
  -DCMAKE_SYSTEM_NAME=WASI \
  -DCMAKE_SYSTEM_PROCESSOR=wasm32 \
  -DCMAKE_C_COMPILER="$WASI_SDK_PATH/bin/clang" \
  -DCMAKE_C_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_AR="$WASI_SDK_PATH/bin/llvm-ar" \
  -DCMAKE_RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$ZLIB_PREFIX;$LIBJPEG_PREFIX;$LIBWEBP_PREFIX" \
  -DBUILD_SHARED_LIBS=OFF \
  -Dtiff-tools=OFF \
  -Dtiff-tests=OFF \
  -Dtiff-contrib=OFF \
  -Dtiff-docs=OFF \
  -Djbig=OFF \
  -Djpeg=OFF \
  -Dlerc=OFF \
  -Dlzma=OFF \
  -Dwebp=ON \
  -Dzlib=ON \
  -Dzstd=OFF

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "$PREFIX"
