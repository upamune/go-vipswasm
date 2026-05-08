#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBIMAGEQUANT_VERSION:-2.18.0}"
WORK="${LIBIMAGEQUANT_PROBE_DIR:-$ROOT/.wasmify/libimagequant-probe}"
SRC="$WORK/libimagequant-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L --retry 3 -o "$WORK/libimagequant.tar.gz" \
    "https://github.com/ImageOptim/libimagequant/archive/refs/tags/$VERSION.tar.gz"
  mkdir -p "$SRC"
  tar -C "$SRC" --strip-components=1 -xf "$WORK/libimagequant.tar.gz"
fi

cd "$SRC"

OSTYPE=linux-gnu ./configure \
  "CC=$WASI_SDK_PATH/bin/clang" \
  --prefix="$PREFIX" \
  --disable-sse \
  --extra-cflags="--target=wasm32-wasip1 -O3" \
  --extra-ldflags="--target=wasm32-wasip1"

make static imagequant.pc -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

mkdir -p "$PREFIX/include" "$PREFIX/lib/pkgconfig"
cp -f libimagequant.h "$PREFIX/include/"
cp -f libimagequant.a "$PREFIX/lib/"
"$WASI_SDK_PATH/bin/llvm-ranlib" "$PREFIX/lib/libimagequant.a"
cp -f imagequant.pc "$PREFIX/lib/pkgconfig/"

echo "$PREFIX"
