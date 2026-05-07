#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBFFI_VERSION:-3.5.2}"
WORK="${LIBFFI_PROBE_DIR:-$ROOT/.wasmify/libffi-probe}"
SRC="$WORK/libffi-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libffi.tar.gz" "https://github.com/libffi/libffi/releases/download/v$VERSION/libffi-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/libffi.tar.gz"
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
    --disable-raw-api \
    --disable-structs \
    --disable-exec-static-tramp \
    --disable-multi-os-directory \
    --disable-docs
fi

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install

echo "$PREFIX"
