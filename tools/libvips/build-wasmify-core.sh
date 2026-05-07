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
LIBJPEG_PREFIX="${LIBJPEG_PREFIX:-$ROOT/.wasmify/libjpeg-probe/prefix}"
LIBWEBP_PREFIX="${LIBWEBP_PREFIX:-$ROOT/.wasmify/libwebp-probe/prefix}"
LIBTIFF_PREFIX="${LIBTIFF_PREFIX:-$ROOT/.wasmify/libtiff-probe/prefix}"
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
#include <pthread.h>
#include <stddef.h>

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

}
C

pkg_config_paths=(
  "$LIBVIPS_BUILD/meson-uninstalled"
  "$LIBVIPS_BUILD/meson-private"
  "$GLIB_BUILD/meson-uninstalled"
  "$GLIB_BUILD/meson-private"
  "$ZLIB_PREFIX/lib/pkgconfig"
  "$LIBPNG_PREFIX/lib/pkgconfig"
  "$LIBJPEG_PREFIX/lib/pkgconfig"
  "$LIBWEBP_PREFIX/lib/pkgconfig"
  "$LIBTIFF_PREFIX/lib/pkgconfig"
  "$LIBDE265_PREFIX/lib/pkgconfig"
  "$LIBHEIF_PREFIX/lib/pkgconfig"
  "$PCRE2_PREFIX/lib/pkgconfig"
  "$ICONV_PREFIX/lib/pkgconfig"
  "$EXPAT_PREFIX/lib/pkgconfig"
)
export PKG_CONFIG_PATH="$(IFS=:; echo "${pkg_config_paths[*]}"):${PKG_CONFIG_PATH:-}"

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
  -mexec-model=reactor \
  -DVIPSWASM_USE_LIBVIPS \
  -D_WASI_EMULATED_PROCESS_CLOCKS \
  -D_WASI_EMULATED_SIGNAL \
  -D_WASI_EMULATED_MMAN \
  -I"$ROOT" \
  -I"$ROOT/tools/wasm" \
  -I"$GLIB_STUB_INCLUDE" \
  "${cflags[@]}" \
  "$ROOT/tools/wasm/vipswasm.cc" \
  "$ROOT/bridge/api_bridge.cc" \
  "$WORK/wasi-link-stubs.cc" \
  "${libs[@]}" \
  -lwasi-emulated-process-clocks \
  -lwasi-emulated-signal \
  -lwasi-emulated-mman \
  -lwasi-emulated-getpid \
  -Wl,--no-entry \
  -Wl,--export-all \
  -Wl,--allow-undefined \
  -o "$VIPSWASM_OUTPUT"

if [[ "${VIPSWASM_SKIP_OPT:-0}" != "1" ]]; then
  wasm-opt "$VIPSWASM_OUTPUT" -Oz --strip-debug --strip-producers -o "$VIPSWASM_OUTPUT"
fi
echo "$VIPSWASM_OUTPUT"
