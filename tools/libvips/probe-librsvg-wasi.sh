#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBRSVG_VERSION:-2.40.21}"
WORK="${LIBRSVG_PROBE_DIR:-$ROOT/.wasmify/librsvg-probe}"
SRC="$WORK/librsvg-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
CAIRO_PREFIX="${CAIRO_PREFIX:-$ROOT/.wasmify/cairo-probe/prefix}"
EXPAT_PREFIX="${EXPAT_PREFIX:-$ROOT/.wasmify/expat-probe/prefix}"
FONTCONFIG_PREFIX="${FONTCONFIG_PREFIX:-$ROOT/.wasmify/fontconfig-probe/prefix}"
FREETYPE_PREFIX="${FREETYPE_PREFIX:-$ROOT/.wasmify/freetype-probe/prefix}"
FRIBIDI_PREFIX="${FRIBIDI_PREFIX:-$ROOT/.wasmify/fribidi-probe/prefix}"
GDK_PIXBUF_PREFIX="${GDK_PIXBUF_PREFIX:-$ROOT/.wasmify/gdk-pixbuf-probe/prefix}"
GLIB_BUILD="${GLIB_BUILD:-$ROOT/.wasmify/glib-probe/build}"
GLIB_STUB_INCLUDE="${GLIB_STUB_INCLUDE:-$ROOT/.wasmify/glib-probe/wasi-stubs/include}"
HARFBUZZ_PREFIX="${HARFBUZZ_PREFIX:-$ROOT/.wasmify/harfbuzz-probe/prefix}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"
LIBCROCO_PREFIX="${LIBCROCO_PREFIX:-$ROOT/.wasmify/libcroco-probe/prefix}"
LIBJPEG_PREFIX="${LIBJPEG_PREFIX:-$ROOT/.wasmify/libjpeg-probe/prefix}"
LIBPNG_PREFIX="${LIBPNG_PREFIX:-$ROOT/.wasmify/libpng-probe/prefix}"
LIBTIFF_PREFIX="${LIBTIFF_PREFIX:-$ROOT/.wasmify/libtiff-probe/prefix}"
LIBWEBP_PREFIX="${LIBWEBP_PREFIX:-$ROOT/.wasmify/libwebp-probe/prefix}"
LIBXML2_PREFIX="${LIBXML2_PREFIX:-$ROOT/.wasmify/libxml2-probe/prefix}"
PANGO_PREFIX="${PANGO_PREFIX:-$ROOT/.wasmify/pango-probe/prefix}"
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

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/librsvg.tar.xz" "https://download.gnome.org/sources/librsvg/${VERSION%.*}/librsvg-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/librsvg.tar.xz"
fi

cd "$SRC"
if ! grep -q 'VIPSWASM_LIBXML2_CONST_STRUCTURED_ERROR' rsvg-css.c; then
  perl -0pi -e 's/static void\nrsvg_xml_noerror \(void \*data, xmlErrorPtr error\)/static void\nrsvg_xml_noerror (void *data, const xmlError *error) \/* VIPSWASM_LIBXML2_CONST_STRUCTURED_ERROR *\//g' rsvg-css.c
fi
if ! grep -q 'VIPSWASM_WASI_NO_RSVG_CONVERT' Makefile.in; then
  perl -0pi -e 's/bin_PROGRAMS = rsvg-convert\$\(EXEEXT\) \$\(am__EXEEXT_1\)/bin_PROGRAMS = \$\(am__EXEEXT_1\) # VIPSWASM_WASI_NO_RSVG_CONVERT/g' Makefile.in
fi
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$GDK_PIXBUF_PREFIX/lib/pkgconfig:$LIBCROCO_PREFIX/lib/pkgconfig:$LIBXML2_PREFIX/lib/pkgconfig:$PANGO_PREFIX/lib/pkgconfig:$CAIRO_PREFIX/lib/pkgconfig:$HARFBUZZ_PREFIX/lib/pkgconfig:$FONTCONFIG_PREFIX/lib/pkgconfig:$EXPAT_PREFIX/lib/pkgconfig:$FRIBIDI_PREFIX/lib/pkgconfig:$PIXMAN_PREFIX/lib/pkgconfig:$FREETYPE_PREFIX/lib/pkgconfig:$LIBTIFF_PREFIX/lib/pkgconfig:$LIBJPEG_PREFIX/lib/pkgconfig:$LIBWEBP_PREFIX/lib/pkgconfig:$LIBPNG_PREFIX/lib/pkgconfig:$GLIB_BUILD/meson-uninstalled:$GLIB_BUILD/meson-private:$PCRE2_PREFIX/lib/pkgconfig:$ICONV_PREFIX/lib/pkgconfig:$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CC="$ROOT/tools/libvips/wasi-clang-filter.sh --target=wasm32-wasip1"
export CXX="$WASI_SDK_PATH/bin/clang++ --target=wasm32-wasip1"
export AR="$WASI_SDK_PATH/bin/ar"
export RANLIB="$WASI_SDK_PATH/bin/ranlib"
export CFLAGS="-mno-atomics -mllvm -wasm-enable-sjlj -I$GLIB_STUB_INCLUDE -I$GDK_PIXBUF_PREFIX/include/gdk-pixbuf-2.0 -I$LIBXML2_PREFIX/include/libxml2 -I$LIBTIFF_PREFIX/include -I$LIBJPEG_PREFIX/include -I$LIBWEBP_PREFIX/include -I$LIBPNG_PREFIX/include -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_GETPID ${CFLAGS:-}"
export LDFLAGS="-mllvm -wasm-enable-sjlj -L$GDK_PIXBUF_PREFIX/lib -L$LIBCROCO_PREFIX/lib -L$LIBXML2_PREFIX/lib -L$PANGO_PREFIX/lib -L$CAIRO_PREFIX/lib -L$HARFBUZZ_PREFIX/lib -L$FONTCONFIG_PREFIX/lib -L$EXPAT_PREFIX/lib -L$FRIBIDI_PREFIX/lib -L$PIXMAN_PREFIX/lib -L$FREETYPE_PREFIX/lib -L$LIBTIFF_PREFIX/lib -L$LIBJPEG_PREFIX/lib -L$LIBWEBP_PREFIX/lib -L$LIBPNG_PREFIX/lib -L$ICONV_PREFIX/lib -L$ZLIB_PREFIX/lib -lwasi-emulated-process-clocks -lwasi-emulated-signal -lwasi-emulated-mman -lwasi-emulated-getpid -lsetjmp ${LDFLAGS:-}"

./configure \
  --host=wasm32-unknown-none \
  --prefix="$PREFIX" \
  --disable-shared \
  --enable-static \
  --disable-Bsymbolic \
  --disable-tools \
  --disable-pixbuf-loader \
  --disable-introspection \
  --disable-vala \
  --disable-gtk-doc \
  --disable-gtk-doc-html \
  --disable-gtk-doc-pdf

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install

perl -0pi -e 's/Requires\.private:[^\n]*/Requires.private: libcroco-0.6 libxml-2.0/;
               s/Libs:([^\n]*)/Libs:$1 -lcroco-0.6 -lxml2 -liconv/' \
  "$PREFIX/lib/pkgconfig/librsvg-2.0.pc"

echo "$PREFIX"
