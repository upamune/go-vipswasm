#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${GDK_PIXBUF_VERSION:-2.42.12}"
WORK="${GDK_PIXBUF_PROBE_DIR:-$ROOT/.wasmify/gdk-pixbuf-probe}"
SRC="$WORK/gdk-pixbuf-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
GLIB_BUILD="${GLIB_BUILD:-$ROOT/.wasmify/glib-probe/build}"
GLIB_STUB_INCLUDE="${GLIB_STUB_INCLUDE:-$ROOT/.wasmify/glib-probe/wasi-stubs/include}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"
LIBJPEG_PREFIX="${LIBJPEG_PREFIX:-$ROOT/.wasmify/libjpeg-probe/prefix}"
LIBPNG_PREFIX="${LIBPNG_PREFIX:-$ROOT/.wasmify/libpng-probe/prefix}"
LIBTIFF_PREFIX="${LIBTIFF_PREFIX:-$ROOT/.wasmify/libtiff-probe/prefix}"
PCRE2_PREFIX="${PCRE2_PREFIX:-$ROOT/.wasmify/pcre2-probe/prefix}"
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
  curl -L -o "$WORK/gdk-pixbuf.tar.xz" "https://download.gnome.org/sources/gdk-pixbuf/${VERSION%.*}/gdk-pixbuf-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/gdk-pixbuf.tar.xz"
fi

if ! grep -q "VIPSWASM_WASI_NO_GDK_PIXBUF_BINS" "$SRC/gdk-pixbuf/meson.build"; then
  perl -0pi -e "s/foreach bin: gdkpixbuf_bin/if host_system != 'wasi' # VIPSWASM_WASI_NO_GDK_PIXBUF_BINS\\nforeach bin: gdkpixbuf_bin/" "$SRC/gdk-pixbuf/meson.build"
  perl -0pi -e "s/set_variable\\(bin_name\\.underscorify\\(\\), bin\\)\\nendforeach/set_variable(bin_name.underscorify(), bin)\\nendforeach\\nendif/" "$SRC/gdk-pixbuf/meson.build"
fi
if ! grep -q "VIPSWASM_WASI_NO_PIXOPS_TIMESCALE" "$SRC/gdk-pixbuf/pixops/meson.build"; then
  perl -0pi -e "s/executable\\('timescale', 'timescale\\.c', dependencies: pixops_dep\\)/if host_system != 'wasi' # VIPSWASM_WASI_NO_PIXOPS_TIMESCALE\\nexecutable('timescale', 'timescale.c', dependencies: pixops_dep)\\nendif/" "$SRC/gdk-pixbuf/pixops/meson.build"
fi
if ! grep -q "VIPSWASM_WASI_NO_GMODULE_LOADERS" "$SRC/meson.build"; then
  perl -0pi -e "s/if gmodule_dep\\.type_name\\(\\) == 'pkgconfig'\\n  build_modules = gmodule_dep\\.get_variable\\(pkgconfig: 'gmodule_supported'\\) == 'true'\\nelse\\n  build_modules = subproject\\('glib'\\)\\.get_variable\\('g_module_impl'\\) != '0'\\nendif/if host_system == 'wasi' # VIPSWASM_WASI_NO_GMODULE_LOADERS\\n  build_modules = false\\nelif gmodule_dep.type_name() == 'pkgconfig'\\n  build_modules = gmodule_dep.get_variable(pkgconfig: 'gmodule_supported') == 'true'\\nelse\\n  build_modules = subproject('glib').get_variable('g_module_impl') != '0'\\nendif/" "$SRC/meson.build"
fi
if ! grep -q "GDK_PIXBUF_WASI_PNG_SETJMP" "$SRC/gdk-pixbuf/io-png.c"; then
  perl -0pi -e 's/#include <png\.h>/#include <png.h>\n\n#ifdef __wasi__\n#define GDK_PIXBUF_WASI_PNG_SETJMP(png_ptr) 0\n#define GDK_PIXBUF_WASI_PNG_LONGJMP(png_ptr) abort()\n#else\n#define GDK_PIXBUF_WASI_PNG_SETJMP(png_ptr) setjmp(png_jmpbuf(png_ptr))\n#define GDK_PIXBUF_WASI_PNG_LONGJMP(png_ptr) longjmp(png_jmpbuf(png_ptr), 1)\n#endif/' "$SRC/gdk-pixbuf/io-png.c"
  perl -0pi -e 's/setjmp\s*\(\s*png_jmpbuf\s*\(\s*([^)]+?)\s*\)\s*\)/GDK_PIXBUF_WASI_PNG_SETJMP($1)/g; s/longjmp\s*\(\s*png_jmpbuf\s*\(\s*([^)]+?)\s*\)\s*,\s*1\s*\)/GDK_PIXBUF_WASI_PNG_LONGJMP($1)/g' "$SRC/gdk-pixbuf/io-png.c"
fi

cross="$WORK/wasi-cross.ini"
sed \
  -e "s|@WASI_SDK@|$WASI_SDK_PATH|g" \
  -e "s|@ROOT@|$ROOT|g" \
  "$ROOT/tools/libvips/wasi-cross.ini" > "$cross"
perl -0pi -e "s/, '-mllvm', '-wasm-enable-sjlj'//g; s/, '-lsetjmp'//g" "$cross"
GLIB_STUB_INCLUDE="$GLIB_STUB_INCLUDE" perl -0pi -e 'my $inc = $ENV{"GLIB_STUB_INCLUDE"}; s#c_args = \[([^\]]*)\]#c_args = [$1, '\''-I$inc'\'']#' "$cross"
GLIB_STUB_INCLUDE="$GLIB_STUB_INCLUDE" perl -0pi -e 'my $inc = $ENV{"GLIB_STUB_INCLUDE"}; s#cpp_args = \[([^\]]*)\]#cpp_args = [$1, '\''-I$inc'\'']#' "$cross"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$LIBTIFF_PREFIX/lib/pkgconfig:$LIBJPEG_PREFIX/lib/pkgconfig:$LIBPNG_PREFIX/lib/pkgconfig:$GLIB_BUILD/meson-uninstalled:$GLIB_BUILD/meson-private:$PCRE2_PREFIX/lib/pkgconfig:$ICONV_PREFIX/lib/pkgconfig:$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
rm -rf "$WORK/build"
meson setup "$WORK/build" "$SRC" \
  --cross-file "$cross" \
  --default-library=static \
  --buildtype=release \
  --prefix "$PREFIX" \
  --wrap-mode=nofallback \
  -Dpng=enabled \
  -Djpeg=disabled \
  -Dtiff=enabled \
  -Dgif=enabled \
  -Dothers=disabled \
  -Dbuiltin_loaders=png,gif,tiff \
  -Dgio_sniffing=false \
  -Dintrospection=disabled \
  -Dgtk_doc=false \
  -Ddocs=false \
  -Dman=false \
  -Dtests=false \
  -Dinstalled_tests=false

meson compile -C "$WORK/build"
meson install -C "$WORK/build"

echo "$PREFIX"
