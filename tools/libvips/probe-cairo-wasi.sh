#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${CAIRO_VERSION:-1.18.4}"
WORK="${CAIRO_PROBE_DIR:-$ROOT/.wasmify/cairo-probe}"
SRC="$WORK/cairo-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
EXPAT_PREFIX="${EXPAT_PREFIX:-$ROOT/.wasmify/expat-probe/prefix}"
FONTCONFIG_PREFIX="${FONTCONFIG_PREFIX:-$ROOT/.wasmify/fontconfig-probe/prefix}"
FREETYPE_PREFIX="${FREETYPE_PREFIX:-$ROOT/.wasmify/freetype-probe/prefix}"
GLIB_BUILD="${GLIB_BUILD:-$ROOT/.wasmify/glib-probe/build}"
GLIB_STUB_INCLUDE="${GLIB_STUB_INCLUDE:-$ROOT/.wasmify/glib-probe/wasi-stubs/include}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"
LIBPNG_PREFIX="${LIBPNG_PREFIX:-$ROOT/.wasmify/libpng-probe/prefix}"
PCRE2_PREFIX="${PCRE2_PREFIX:-$ROOT/.wasmify/pcre2-probe/prefix}"
PIXMAN_PREFIX="${PIXMAN_PREFIX:-$ROOT/.wasmify/pixman-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

for pc in \
  "$EXPAT_PREFIX/lib/pkgconfig/expat.pc" \
  "$FONTCONFIG_PREFIX/lib/pkgconfig/fontconfig.pc" \
  "$FREETYPE_PREFIX/lib/pkgconfig/freetype2.pc" \
  "$LIBPNG_PREFIX/lib/pkgconfig/libpng.pc" \
  "$PIXMAN_PREFIX/lib/pkgconfig/pixman-1.pc" \
  "$ZLIB_PREFIX/lib/pkgconfig/zlib.pc"; do
  if [[ ! -f "$pc" ]]; then
    echo "missing dependency pkg-config file $pc; run the corresponding probe target first" >&2
    exit 2
  fi
done
if [[ ! -d "$GLIB_BUILD/meson-uninstalled" ]]; then
  echo "missing GLib WASI build at $GLIB_BUILD; run: make probe-glib-wasi" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/cairo.tar.xz" "https://www.cairographics.org/releases/cairo-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/cairo.tar.xz"
fi
if ! grep -q "VIPSWASM_WASI_NO_CAIRO_SCRIPT_INTERPRETER" "$SRC/meson.build"; then
  perl -0pi -e "s/if zlib_dep\\.found\\(\\)\\n  conf\\.set\\('CAIRO_HAS_INTERPRETER', 1\\)\\nendif/if zlib_dep.found() and host_machine.system() != 'wasi' # VIPSWASM_WASI_NO_CAIRO_SCRIPT_INTERPRETER\\n  conf.set('CAIRO_HAS_INTERPRETER', 1)\\nendif/" "$SRC/meson.build"
fi

cross="$WORK/wasi-cross.ini"
sed \
  -e "s|@WASI_SDK@|$WASI_SDK_PATH|g" \
  -e "s|@ROOT@|$ROOT|g" \
  "$ROOT/tools/libvips/wasi-cross.ini" > "$cross"
GLIB_STUB_INCLUDE="$GLIB_STUB_INCLUDE" perl -0pi -e 'my $inc = $ENV{"GLIB_STUB_INCLUDE"}; s#c_args = \[([^\]]*)\]#c_args = [$1, '\''-I$inc'\'']#' "$cross"
GLIB_STUB_INCLUDE="$GLIB_STUB_INCLUDE" perl -0pi -e 'my $inc = $ENV{"GLIB_STUB_INCLUDE"}; s#cpp_args = \[([^\]]*)\]#cpp_args = [$1, '\''-I$inc'\'']#' "$cross"

export PKG_CONFIG_PATH="$FONTCONFIG_PREFIX/lib/pkgconfig:$FREETYPE_PREFIX/lib/pkgconfig:$LIBPNG_PREFIX/lib/pkgconfig:$PIXMAN_PREFIX/lib/pkgconfig:$EXPAT_PREFIX/lib/pkgconfig:$GLIB_BUILD/meson-uninstalled:$GLIB_BUILD/meson-private:$PCRE2_PREFIX/lib/pkgconfig:$ICONV_PREFIX/lib/pkgconfig:$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
rm -rf "$WORK/build"
meson setup "$WORK/build" "$SRC" \
  --cross-file "$cross" \
  --default-library=static \
  --buildtype=release \
  --prefix "$PREFIX" \
  --wrap-mode=nofallback \
  -Dfontconfig=enabled \
  -Dfreetype=enabled \
  -Dglib=enabled \
  -Dpng=enabled \
  -Dzlib=enabled \
  -Dtests=disabled \
  -Dspectre=disabled \
  -Dsymbol-lookup=disabled \
  -Dxlib=disabled \
  -Dxcb=disabled \
  -Dgtk_doc=false

meson compile -C "$WORK/build"
meson install -C "$WORK/build"

echo "$PREFIX"
