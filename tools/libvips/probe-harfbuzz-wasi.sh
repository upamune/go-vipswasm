#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${HARFBUZZ_VERSION:-12.1.0}"
WORK="${HARFBUZZ_PROBE_DIR:-$ROOT/.wasmify/harfbuzz-probe}"
SRC="$WORK/harfbuzz-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
FREETYPE_PREFIX="${FREETYPE_PREFIX:-$ROOT/.wasmify/freetype-probe/prefix}"
GLIB_BUILD="${GLIB_BUILD:-$ROOT/.wasmify/glib-probe/build}"
GLIB_STUB_INCLUDE="${GLIB_STUB_INCLUDE:-$ROOT/.wasmify/glib-probe/wasi-stubs/include}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"
PCRE2_PREFIX="${PCRE2_PREFIX:-$ROOT/.wasmify/pcre2-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

if [[ ! -f "$FREETYPE_PREFIX/lib/pkgconfig/freetype2.pc" ]]; then
  echo "missing freetype WASI prefix at $FREETYPE_PREFIX; run: make probe-freetype-wasi" >&2
  exit 2
fi
if [[ ! -d "$GLIB_BUILD/meson-uninstalled" ]]; then
  echo "missing GLib WASI build at $GLIB_BUILD; run: make probe-glib-wasi" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/harfbuzz.tar.xz" "https://github.com/harfbuzz/harfbuzz/releases/download/$VERSION/harfbuzz-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/harfbuzz.tar.xz"
fi

cross="$WORK/wasi-cross.ini"
sed \
  -e "s|@WASI_SDK@|$WASI_SDK_PATH|g" \
  -e "s|@ROOT@|$ROOT|g" \
  "$ROOT/tools/libvips/wasi-cross.ini" > "$cross"
GLIB_STUB_INCLUDE="$GLIB_STUB_INCLUDE" perl -0pi -e 'my $inc = $ENV{"GLIB_STUB_INCLUDE"}; s#c_args = \[([^\]]*)\]#c_args = [$1, '\''-I$inc'\'']#' "$cross"
GLIB_STUB_INCLUDE="$GLIB_STUB_INCLUDE" perl -0pi -e 'my $inc = $ENV{"GLIB_STUB_INCLUDE"}; s#cpp_args = \[([^\]]*)\]#cpp_args = [$1, '\''-I$inc'\'']#' "$cross"

export PKG_CONFIG_PATH="$FREETYPE_PREFIX/lib/pkgconfig:$GLIB_BUILD/meson-uninstalled:$GLIB_BUILD/meson-private:$PCRE2_PREFIX/lib/pkgconfig:$ICONV_PREFIX/lib/pkgconfig:$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
rm -rf "$WORK/build"
meson setup "$WORK/build" "$SRC" \
  --cross-file "$cross" \
  --default-library=static \
  --buildtype=release \
  --prefix "$PREFIX" \
  --wrap-mode=nofallback \
  -Dglib=enabled \
  -Dgobject=enabled \
  -Dfreetype=enabled \
  -Dcairo=disabled \
  -Dchafa=disabled \
  -Dicu=disabled \
  -Dgraphite=disabled \
  -Ddocs=disabled \
  -Dtests=disabled \
  -Dutilities=disabled \
  -Dbenchmark=disabled \
  -Dintrospection=disabled

meson compile -C "$WORK/build"
meson install -C "$WORK/build"

echo "$PREFIX"
