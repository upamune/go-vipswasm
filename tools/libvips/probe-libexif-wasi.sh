#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBEXIF_VERSION:-0.6.26}"
WORK="${LIBEXIF_PROBE_DIR:-$ROOT/.wasmify/libexif-probe}"
SRC="$WORK/libexif-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L --retry 3 -o "$WORK/libexif.tar.gz" \
    "https://github.com/libexif/libexif/archive/refs/tags/v$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/libexif.tar.gz"
fi

cd "$SRC"
if [[ ! -x configure ]]; then
  autoreconf -fi
fi

CC="$WASI_SDK_PATH/bin/clang" \
AR="$WASI_SDK_PATH/bin/llvm-ar" \
RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
STRIP="$WASI_SDK_PATH/bin/llvm-strip" \
CFLAGS="--target=wasm32-wasip1 -O3 ${CFLAGS:-}" \
LDFLAGS="--target=wasm32-wasip1 ${LDFLAGS:-}" \
./configure \
  --host=wasm32-wasi \
  --prefix="$PREFIX" \
  --disable-shared \
  --enable-static \
  --disable-nls \
  --disable-internal-docs \
  --disable-docs \
  --disable-ship-binaries

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install

perl -0pi -e 's#Cflags: -I\$\{includedir\}#Cflags: -I\${includedir}/libexif -I\${includedir}#' \
  "$PREFIX/lib/pkgconfig/libexif.pc"

echo "$PREFIX"
