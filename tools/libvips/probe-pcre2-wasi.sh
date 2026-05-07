#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${PCRE2_VERSION:-10.47}"
WORK="${PCRE2_PROBE_DIR:-$ROOT/.wasmify/pcre2-probe}"
SRC="$WORK/pcre2-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/pcre2.tar.gz" "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$VERSION/pcre2-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/pcre2.tar.gz"
fi

cd "$SRC"
if [[ ! -f Makefile ]]; then
  CC="$WASI_SDK_PATH/bin/clang --target=wasm32-wasip1" \
  AR="$WASI_SDK_PATH/bin/llvm-ar" \
  RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  ./configure \
    --host=wasm32-wasi \
    --prefix="$PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-jit \
    --disable-pcre2grep-callout \
    --disable-pcre2grep-callout-fork \
    --enable-pcre2-8 \
    --disable-pcre2-16 \
    --disable-pcre2-32
fi

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" libpcre2-8.la libpcre2-8.pc

mkdir -p "$PREFIX/include" "$PREFIX/lib/pkgconfig"
cp src/pcre2.h "$PREFIX/include/pcre2.h"
cp .libs/libpcre2-8.a "$PREFIX/lib/libpcre2-8.a"
cp libpcre2-8.pc "$PREFIX/lib/pkgconfig/libpcre2-8.pc"

echo "$PREFIX"
