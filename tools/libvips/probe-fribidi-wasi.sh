#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${FRIBIDI_VERSION:-1.0.16}"
WORK="${FRIBIDI_PROBE_DIR:-$ROOT/.wasmify/fribidi-probe}"
SRC="$WORK/fribidi-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/fribidi.tar.xz" "https://github.com/fribidi/fribidi/releases/download/v$VERSION/fribidi-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/fribidi.tar.xz"
fi

cross="$WORK/wasi-cross.ini"
sed \
  -e "s|@WASI_SDK@|$WASI_SDK_PATH|g" \
  -e "s|@ROOT@|$ROOT|g" \
  "$ROOT/tools/libvips/wasi-cross.ini" > "$cross"

rm -rf "$WORK/build"
meson setup "$WORK/build" "$SRC" \
  --cross-file "$cross" \
  --default-library=static \
  --buildtype=release \
  --prefix "$PREFIX" \
  --wrap-mode=nofallback \
  -Ddocs=false \
  -Dtests=false \
  -Dbin=false

meson compile -C "$WORK/build"
meson install -C "$WORK/build"

echo "$PREFIX"
