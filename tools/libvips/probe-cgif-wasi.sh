#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${CGIF_VERSION:-0.5.3}"
WORK="${CGIF_PROBE_DIR:-$ROOT/.wasmify/cgif-probe}"
SRC="$WORK/cgif-$VERSION"
BUILD="$WORK/build"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L --retry 3 -o "$WORK/cgif.tar.gz" \
    "https://github.com/dloebl/cgif/archive/refs/tags/v$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/cgif.tar.gz"
fi

cross="$WORK/wasi-cross.ini"
sed \
  -e "s|@WASI_SDK@|$WASI_SDK_PATH|g" \
  -e "s|@ROOT@|$ROOT|g" \
  "$ROOT/tools/libvips/wasi-cross.ini" > "$cross"

rm -rf "$BUILD"
meson setup "$BUILD" "$SRC" \
  --cross-file "$cross" \
  --prefix "$PREFIX" \
  --default-library=static \
  --buildtype=release \
  -Dexamples=false \
  -Dfuzzer=false \
  -Dtests=false

ninja -C "$BUILD" install

echo "$PREFIX"
