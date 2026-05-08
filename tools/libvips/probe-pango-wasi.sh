#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${PANGO_VERSION:-1.57.0}"
WORK="${PANGO_PROBE_DIR:-$ROOT/.wasmify/pango-probe}"
SRC="$WORK/pango-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
CAIRO_PREFIX="${CAIRO_PREFIX:-$ROOT/.wasmify/cairo-probe/prefix}"
EXPAT_PREFIX="${EXPAT_PREFIX:-$ROOT/.wasmify/expat-probe/prefix}"
FONTCONFIG_PREFIX="${FONTCONFIG_PREFIX:-$ROOT/.wasmify/fontconfig-probe/prefix}"
FREETYPE_PREFIX="${FREETYPE_PREFIX:-$ROOT/.wasmify/freetype-probe/prefix}"
FRIBIDI_PREFIX="${FRIBIDI_PREFIX:-$ROOT/.wasmify/fribidi-probe/prefix}"
GLIB_BUILD="${GLIB_BUILD:-$ROOT/.wasmify/glib-probe/build}"
GLIB_STUB_INCLUDE="${GLIB_STUB_INCLUDE:-$ROOT/.wasmify/glib-probe/wasi-stubs/include}"
HARFBUZZ_PREFIX="${HARFBUZZ_PREFIX:-$ROOT/.wasmify/harfbuzz-probe/prefix}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"
LIBPNG_PREFIX="${LIBPNG_PREFIX:-$ROOT/.wasmify/libpng-probe/prefix}"
PCRE2_PREFIX="${PCRE2_PREFIX:-$ROOT/.wasmify/pcre2-probe/prefix}"
PIXMAN_PREFIX="${PIXMAN_PREFIX:-$ROOT/.wasmify/pixman-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

if [[ ! -d "$GLIB_BUILD/meson-uninstalled" ]]; then
  echo "missing GLib WASI build at $GLIB_BUILD; run: make probe-glib-wasi" >&2
  exit 2
fi
for pc in \
  "$CAIRO_PREFIX/lib/pkgconfig/cairo.pc" \
  "$CAIRO_PREFIX/lib/pkgconfig/cairo-ft.pc" \
  "$CAIRO_PREFIX/lib/pkgconfig/cairo-gobject.pc" \
  "$FONTCONFIG_PREFIX/lib/pkgconfig/fontconfig.pc" \
  "$FREETYPE_PREFIX/lib/pkgconfig/freetype2.pc" \
  "$FRIBIDI_PREFIX/lib/pkgconfig/fribidi.pc" \
  "$HARFBUZZ_PREFIX/lib/pkgconfig/harfbuzz.pc"; do
  if [[ ! -f "$pc" ]]; then
    echo "missing dependency pkg-config file $pc; run the corresponding probe target first" >&2
    exit 2
  fi
done

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/pango.tar.xz" "https://download.gnome.org/sources/pango/${VERSION%.*}/pango-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/pango.tar.xz"
fi

if ! grep -q "VIPSWASM_WASI_NO_STDIO_LOCKS" "$SRC/pango/pango-utils.c"; then
  perl -0pi -e 's/#include "config\.h"/#include "config.h"\n\n#ifdef __wasi__\n#define flockfile(stream) ((void) (stream)) \/* VIPSWASM_WASI_NO_STDIO_LOCKS *\/\n#define funlockfile(stream) ((void) (stream)) \/* VIPSWASM_WASI_NO_STDIO_LOCKS *\/\n#endif/' "$SRC/pango/pango-utils.c"
fi
if ! grep -q "VIPSWASM_WASI_NO_UTILITIES" "$SRC/meson.build"; then
  perl -0pi -e "s/subdir\\('utils'\\)\\nsubdir\\('tools'\\)/if host_system != 'wasi' # VIPSWASM_WASI_NO_UTILITIES\\n  subdir('utils')\\n  subdir('tools')\\nendif/" "$SRC/meson.build"
fi

cross="$WORK/wasi-cross.ini"
sed \
  -e "s|@WASI_SDK@|$WASI_SDK_PATH|g" \
  -e "s|@ROOT@|$ROOT|g" \
  "$ROOT/tools/libvips/wasi-cross.ini" > "$cross"
GLIB_STUB_INCLUDE="$GLIB_STUB_INCLUDE" perl -0pi -e 'my $inc = $ENV{"GLIB_STUB_INCLUDE"}; s#c_args = \[([^\]]*)\]#c_args = [$1, '\''-I$inc'\'']#' "$cross"
GLIB_STUB_INCLUDE="$GLIB_STUB_INCLUDE" perl -0pi -e 'my $inc = $ENV{"GLIB_STUB_INCLUDE"}; s#cpp_args = \[([^\]]*)\]#cpp_args = [$1, '\''-I$inc'\'']#' "$cross"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$CAIRO_PREFIX/lib/pkgconfig:$FONTCONFIG_PREFIX/lib/pkgconfig:$FREETYPE_PREFIX/lib/pkgconfig:$FRIBIDI_PREFIX/lib/pkgconfig:$HARFBUZZ_PREFIX/lib/pkgconfig:$PIXMAN_PREFIX/lib/pkgconfig:$LIBPNG_PREFIX/lib/pkgconfig:$EXPAT_PREFIX/lib/pkgconfig:$GLIB_BUILD/meson-uninstalled:$GLIB_BUILD/meson-private:$PCRE2_PREFIX/lib/pkgconfig:$ICONV_PREFIX/lib/pkgconfig:$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
rm -rf "$WORK/build"
meson setup "$WORK/build" "$SRC" \
  --cross-file "$cross" \
  --default-library=static \
  --buildtype=release \
  --prefix "$PREFIX" \
  --wrap-mode=nofallback \
  -Dcairo=enabled \
  -Dfontconfig=enabled \
  -Dfreetype=enabled \
  -Ddocumentation=false \
  -Dgtk_doc=false \
  -Dintrospection=disabled \
  -Dlibthai=disabled \
  -Dsysprof=disabled \
  -Dxft=disabled \
  -Dbuild-testsuite=false \
  -Dbuild-examples=false \
  -Dman-pages=false

meson compile -C "$WORK/build"
meson install -C "$WORK/build"

echo "$PREFIX"
