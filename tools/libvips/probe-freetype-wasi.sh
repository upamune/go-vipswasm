#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${FREETYPE_VERSION:-2.14.1}"
WORK="${FREETYPE_PROBE_DIR:-$ROOT/.wasmify/freetype-probe}"
SRC="$WORK/freetype-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

if [[ ! -f "$ZLIB_PREFIX/lib/pkgconfig/zlib.pc" ]]; then
  echo "missing zlib WASI prefix at $ZLIB_PREFIX; run: make probe-zlib-wasi" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/freetype.tar.xz" "https://download.savannah.gnu.org/releases/freetype/freetype-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/freetype.tar.xz"
fi

cross="$WORK/wasi-cross.ini"
sed \
  -e "s|@WASI_SDK@|$WASI_SDK_PATH|g" \
  -e "s|@ROOT@|$ROOT|g" \
  "$ROOT/tools/libvips/wasi-cross.ini" > "$cross"

export PKG_CONFIG_PATH="$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
rm -rf "$WORK/build"
meson setup "$WORK/build" "$SRC" \
  --cross-file "$cross" \
  --default-library=static \
  --buildtype=release \
  --prefix "$PREFIX" \
  --wrap-mode=nofallback \
  -Dbzip2=disabled \
  -Dbrotli=disabled \
  -Dharfbuzz=disabled \
  -Dpng=disabled \
  -Dzlib=enabled \
  -Dtests=disabled

meson compile -C "$WORK/build"
meson install -C "$WORK/build"

echo "$PREFIX"
