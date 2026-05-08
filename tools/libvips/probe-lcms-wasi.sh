#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LCMS_VERSION:-2.17}"
WORK="${LCMS_PROBE_DIR:-$ROOT/.wasmify/lcms-probe}"
SRC="$WORK/lcms2-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/lcms.tar.gz" "https://github.com/mm2/Little-CMS/releases/download/lcms$VERSION/lcms2-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/lcms.tar.gz"
fi

cd "$SRC"

export CC="$ROOT/tools/libvips/wasi-clang-filter.sh --target=wasm32-wasip1"
export AR="$WASI_SDK_PATH/bin/ar"
export RANLIB="$WASI_SDK_PATH/bin/ranlib"
export CFLAGS="-mno-atomics ${CFLAGS:-}"

./configure \
  --host=wasm32-unknown-none \
  --prefix="$PREFIX" \
  --disable-shared \
  --enable-static \
  --without-jpeg \
  --without-tiff \
  --without-zlib

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install

echo "$PREFIX"
