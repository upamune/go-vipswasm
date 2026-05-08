#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
WORK="${VIPSWASM_CORE_BUILD_DIR:-$ROOT/.wasmify/wasmify-core}"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
LIBVIPS_BUILD="${LIBVIPS_BUILD:-$ROOT/.wasmify/libvips-probe/build}"
GLIB_BUILD="${GLIB_BUILD:-$ROOT/.wasmify/glib-probe/build}"
GLIB_STUB_INCLUDE="${GLIB_STUB_INCLUDE:-$ROOT/.wasmify/glib-probe/wasi-stubs/include}"
EXPAT_PREFIX="${EXPAT_PREFIX:-$ROOT/.wasmify/expat-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"
LIBPNG_PREFIX="${LIBPNG_PREFIX:-$ROOT/.wasmify/libpng-probe/prefix}"
LIBARCHIVE_PREFIX="${LIBARCHIVE_PREFIX:-$ROOT/.wasmify/libarchive-probe/prefix}"
FFTW_PREFIX="${FFTW_PREFIX:-$ROOT/.wasmify/fftw-probe/prefix}"
IMAGEMAGICK_PREFIX="${IMAGEMAGICK_PREFIX:-$ROOT/.wasmify/imagemagick-probe/prefix}"
CFITSIO_PREFIX="${CFITSIO_PREFIX:-$ROOT/.wasmify/cfitsio-probe/prefix}"
LIBIMAGEQUANT_PREFIX="${LIBIMAGEQUANT_PREFIX:-$ROOT/.wasmify/libimagequant-probe/prefix}"
CGIF_PREFIX="${CGIF_PREFIX:-$ROOT/.wasmify/cgif-probe/prefix}"
LIBEXIF_PREFIX="${LIBEXIF_PREFIX:-$ROOT/.wasmify/libexif-probe/prefix}"
LIBJPEG_PREFIX="${LIBJPEG_PREFIX:-$ROOT/.wasmify/libjpeg-probe/prefix}"
LIBUHDR_PREFIX="${LIBUHDR_PREFIX:-$ROOT/.wasmify/libuhdr-probe/prefix}"
LIBWEBP_PREFIX="${LIBWEBP_PREFIX:-$ROOT/.wasmify/libwebp-probe/prefix}"
FREETYPE_PREFIX="${FREETYPE_PREFIX:-$ROOT/.wasmify/freetype-probe/prefix}"
FRIBIDI_PREFIX="${FRIBIDI_PREFIX:-$ROOT/.wasmify/fribidi-probe/prefix}"
PIXMAN_PREFIX="${PIXMAN_PREFIX:-$ROOT/.wasmify/pixman-probe/prefix}"
FONTCONFIG_PREFIX="${FONTCONFIG_PREFIX:-$ROOT/.wasmify/fontconfig-probe/prefix}"
HARFBUZZ_PREFIX="${HARFBUZZ_PREFIX:-$ROOT/.wasmify/harfbuzz-probe/prefix}"
CAIRO_PREFIX="${CAIRO_PREFIX:-$ROOT/.wasmify/cairo-probe/prefix}"
PANGO_PREFIX="${PANGO_PREFIX:-$ROOT/.wasmify/pango-probe/prefix}"
LIBTIFF_PREFIX="${LIBTIFF_PREFIX:-$ROOT/.wasmify/libtiff-probe/prefix}"
GDK_PIXBUF_PREFIX="${GDK_PIXBUF_PREFIX:-$ROOT/.wasmify/gdk-pixbuf-probe/prefix}"
LIBXML2_PREFIX="${LIBXML2_PREFIX:-$ROOT/.wasmify/libxml2-probe/prefix}"
LIBCROCO_PREFIX="${LIBCROCO_PREFIX:-$ROOT/.wasmify/libcroco-probe/prefix}"
LIBRSVG_PREFIX="${LIBRSVG_PREFIX:-$ROOT/.wasmify/librsvg-probe/prefix}"
OPENJPEG_PREFIX="${OPENJPEG_PREFIX:-$ROOT/.wasmify/openjpeg-probe/prefix}"
SQLITE_PREFIX="${SQLITE_PREFIX:-$ROOT/.wasmify/sqlite-probe/prefix}"
OPENSLIDE_PREFIX="${OPENSLIDE_PREFIX:-$ROOT/.wasmify/openslide-probe/prefix}"
MATIO_PREFIX="${MATIO_PREFIX:-$ROOT/.wasmify/matio-probe/prefix}"
NIFTI_PREFIX="${NIFTI_PREFIX:-$ROOT/.wasmify/nifti-probe/prefix}"
LCMS_PREFIX="${LCMS_PREFIX:-$ROOT/.wasmify/lcms-probe/prefix}"
OPENEXR_PREFIX="${OPENEXR_PREFIX:-$ROOT/.wasmify/openexr-probe/prefix}"
LIBRAW_PREFIX="${LIBRAW_PREFIX:-$ROOT/.wasmify/libraw-probe/prefix}"
HIGHWAY_PREFIX="${HIGHWAY_PREFIX:-$ROOT/.wasmify/highway-probe/prefix}"
BROTLI_PREFIX="${BROTLI_PREFIX:-$ROOT/.wasmify/brotli-probe/prefix}"
LIBJXL_PREFIX="${LIBJXL_PREFIX:-$ROOT/.wasmify/libjxl-probe/prefix}"
POPPLER_PREFIX="${POPPLER_PREFIX:-$ROOT/.wasmify/poppler-probe/prefix}"
LIBDE265_PREFIX="${LIBDE265_PREFIX:-$ROOT/.wasmify/libde265-probe/prefix}"
LIBHEIF_PREFIX="${LIBHEIF_PREFIX:-$ROOT/.wasmify/libheif-probe/prefix}"
PCRE2_PREFIX="${PCRE2_PREFIX:-$ROOT/.wasmify/pcre2-probe/prefix}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"
VIPSWASM_OUTPUT="${VIPSWASM_OUTPUT:-$ROOT/internal/vipswasm.wasm}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang++" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

if [[ ! -f "$LIBVIPS_BUILD/libvips/libvips.a" ]]; then
  echo "missing $LIBVIPS_BUILD/libvips/libvips.a; run: make probe-libvips-wasi" >&2
  exit 2
fi

mkdir -p "$WORK"
cat > "$WORK/wasi-link-stubs.cc" <<'C'
#include <errno.h>
#include <stdio.h>
#include <pthread.h>
#include <stddef.h>
#include <stdlib.h>

extern "C" {

int pthread_attr_setinheritsched(pthread_attr_t *attr, int inheritsched) {
  (void) attr;
  (void) inheritsched;
  return 0;
}

int pthread_getname_np(pthread_t thread, char *name, size_t len) {
  (void) thread;
  if (name && len > 0) {
    name[0] = '\0';
  }
  return ENOSYS;
}

void *g_unix_fd_source_new(int fd, int condition) {
  (void) fd;
  (void) condition;
  return nullptr;
}

void *g_source_add_unix_fd(void *source, int fd, int events) {
  (void) source;
  (void) fd;
  (void) events;
  return nullptr;
}

void g_source_remove_unix_fd(void *source, void *tag) {
  (void) source;
  (void) tag;
}

int g_source_query_unix_fd(void *source, void *tag) {
  (void) source;
  (void) tag;
  return 0;
}

void *g_unix_get_passwd_entry(const char *user_name, void *error) {
  (void) user_name;
  (void) error;
  errno = ENOSYS;
  return nullptr;
}

void *g_io_channel_unix_new(int fd) {
  (void) fd;
  errno = ENOSYS;
  return nullptr;
}

int system(const char *command) {
  (void) command;
  errno = ENOSYS;
  return -1;
}

void *__cxa_allocate_exception(size_t thrown_size) {
  return malloc(thrown_size);
}

void __cxa_throw(void *thrown_exception, void *tinfo, void (*dest)(void *)) {
  if (dest != nullptr) {
    dest(thrown_exception);
  }
  free(thrown_exception);
  abort();
}

void *__cxa_begin_catch(void *exception_object) {
  return exception_object;
}

FILE *tmpfile(void) {
  errno = ENOSYS;
  return nullptr;
}

void *g_io_watch_funcs = nullptr;
void *g_unix_signal_funcs = nullptr;

}
C

pkg_config_paths=(
  "$LIBVIPS_BUILD/meson-uninstalled"
  "$LIBVIPS_BUILD/meson-private"
  "$GLIB_BUILD/meson-uninstalled"
  "$GLIB_BUILD/meson-private"
  "$ZLIB_PREFIX/lib/pkgconfig"
  "$LIBPNG_PREFIX/lib/pkgconfig"
  "$LIBARCHIVE_PREFIX/lib/pkgconfig"
  "$FFTW_PREFIX/lib/pkgconfig"
  "$IMAGEMAGICK_PREFIX/lib/pkgconfig"
  "$CFITSIO_PREFIX/lib/pkgconfig"
  "$LIBIMAGEQUANT_PREFIX/lib/pkgconfig"
  "$CGIF_PREFIX/lib/pkgconfig"
  "$LIBEXIF_PREFIX/lib/pkgconfig"
  "$LIBJPEG_PREFIX/lib/pkgconfig"
  "$LIBUHDR_PREFIX/lib/pkgconfig"
  "$LIBWEBP_PREFIX/lib/pkgconfig"
  "$PANGO_PREFIX/lib/pkgconfig"
  "$CAIRO_PREFIX/lib/pkgconfig"
  "$HARFBUZZ_PREFIX/lib/pkgconfig"
  "$FONTCONFIG_PREFIX/lib/pkgconfig"
  "$PIXMAN_PREFIX/lib/pkgconfig"
  "$FRIBIDI_PREFIX/lib/pkgconfig"
  "$FREETYPE_PREFIX/lib/pkgconfig"
  "$LIBTIFF_PREFIX/lib/pkgconfig"
  "$LIBRSVG_PREFIX/lib/pkgconfig"
  "$OPENSLIDE_PREFIX/lib/pkgconfig"
  "$MATIO_PREFIX/lib/pkgconfig"
  "$NIFTI_PREFIX/lib/pkgconfig"
  "$LCMS_PREFIX/lib/pkgconfig"
  "$OPENEXR_PREFIX/lib/pkgconfig"
  "$LIBRAW_PREFIX/lib/pkgconfig"
  "$HIGHWAY_PREFIX/lib/pkgconfig"
  "$BROTLI_PREFIX/lib/pkgconfig"
  "$LIBJXL_PREFIX/lib/pkgconfig"
  "$POPPLER_PREFIX/lib/pkgconfig"
  "$OPENJPEG_PREFIX/lib/pkgconfig"
  "$SQLITE_PREFIX/lib/pkgconfig"
  "$GDK_PIXBUF_PREFIX/lib/pkgconfig"
  "$LIBCROCO_PREFIX/lib/pkgconfig"
  "$LIBXML2_PREFIX/lib/pkgconfig"
  "$LIBDE265_PREFIX/lib/pkgconfig"
  "$LIBHEIF_PREFIX/lib/pkgconfig"
  "$PCRE2_PREFIX/lib/pkgconfig"
  "$ICONV_PREFIX/lib/pkgconfig"
  "$EXPAT_PREFIX/lib/pkgconfig"
)
export PKG_CONFIG_PATH="$(IFS=:; echo "${pkg_config_paths[*]}"):${PKG_CONFIG_PATH:-}"

link_search_dirs=(
  "$EXPAT_PREFIX/lib"
  "$ZLIB_PREFIX/lib"
  "$LIBPNG_PREFIX/lib"
  "$LIBARCHIVE_PREFIX/lib"
  "$FFTW_PREFIX/lib"
  "$IMAGEMAGICK_PREFIX/lib"
  "$CFITSIO_PREFIX/lib"
  "$LIBIMAGEQUANT_PREFIX/lib"
  "$CGIF_PREFIX/lib"
  "$LIBEXIF_PREFIX/lib"
  "$LIBJPEG_PREFIX/lib"
  "$LIBUHDR_PREFIX/lib"
  "$LIBWEBP_PREFIX/lib"
  "$PANGO_PREFIX/lib"
  "$CAIRO_PREFIX/lib"
  "$HARFBUZZ_PREFIX/lib"
  "$FONTCONFIG_PREFIX/lib"
  "$PIXMAN_PREFIX/lib"
  "$FRIBIDI_PREFIX/lib"
  "$FREETYPE_PREFIX/lib"
  "$LIBTIFF_PREFIX/lib"
  "$LIBRSVG_PREFIX/lib"
  "$OPENSLIDE_PREFIX/lib"
  "$MATIO_PREFIX/lib"
  "$NIFTI_PREFIX/lib"
  "$LCMS_PREFIX/lib"
  "$OPENEXR_PREFIX/lib"
  "$LIBRAW_PREFIX/lib"
  "$HIGHWAY_PREFIX/lib"
  "$BROTLI_PREFIX/lib"
  "$LIBJXL_PREFIX/lib"
  "$POPPLER_PREFIX/lib"
  "$OPENJPEG_PREFIX/lib"
  "$SQLITE_PREFIX/lib"
  "$GDK_PIXBUF_PREFIX/lib"
  "$LIBCROCO_PREFIX/lib"
  "$LIBXML2_PREFIX/lib"
  "$LIBDE265_PREFIX/lib"
  "$LIBHEIF_PREFIX/lib"
  "$PCRE2_PREFIX/lib"
  "$ICONV_PREFIX/lib"
)

filter_link_flags() {
  tr ' ' '\n' |
    sed '/^$/d' |
    grep -Ev '^-pthread$|^-Wl,--start-group$|^-Wl,--end-group$|^-Wl,--as-needed$|^-Wl,--no-as-needed$'
}

mapfile -t cflags < <(pkg-config --cflags vips glib-2.0 gio-2.0 gobject-2.0 | filter_link_flags)
mapfile -t libs < <(pkg-config --libs --static vips glib-2.0 gio-2.0 gobject-2.0 | filter_link_flags)

"$WASI_SDK_PATH/bin/clang++" \
  --target=wasm32-wasip1 \
  -O3 \
  -fno-exceptions \
  -mno-atomics \
  -mllvm -wasm-enable-sjlj \
  -mexec-model=reactor \
  -DVIPSWASM_USE_LIBVIPS \
  -D_WASI_EMULATED_PROCESS_CLOCKS \
  -D_WASI_EMULATED_SIGNAL \
  -D_WASI_EMULATED_MMAN \
  -D_WASI_EMULATED_GETPID \
  -I"$ROOT" \
  -I"$ROOT/tools/wasm" \
  -I"$GLIB_STUB_INCLUDE" \
  "${cflags[@]}" \
  "$ROOT/tools/wasm/vipswasm.cc" \
  "$ROOT/bridge/api_bridge.cc" \
  "$WORK/wasi-link-stubs.cc" \
  "${link_search_dirs[@]/#/-L}" \
  "${libs[@]}" \
  -lwasi-emulated-process-clocks \
  -lwasi-emulated-signal \
  -lwasi-emulated-mman \
  -lwasi-emulated-getpid \
  -Wl,--no-entry \
  -Wl,--export-all \
  -o "$VIPSWASM_OUTPUT"

if [[ "${VIPSWASM_SKIP_OPT:-0}" != "1" ]]; then
  wasm-opt "$VIPSWASM_OUTPUT" -Oz --strip-debug --strip-producers -o "$VIPSWASM_OUTPUT"
fi
echo "$VIPSWASM_OUTPUT"
