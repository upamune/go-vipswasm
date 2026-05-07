#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
WORK="${LIBVIPS_LINK_PROBE_DIR:-$ROOT/.wasmify/libvips-link-probe}"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
LIBVIPS_BUILD="${LIBVIPS_BUILD:-$ROOT/.wasmify/libvips-probe/build}"
GLIB_BUILD="${GLIB_BUILD:-$ROOT/.wasmify/glib-probe/build}"
GLIB_STUB_INCLUDE="${GLIB_STUB_INCLUDE:-$ROOT/.wasmify/glib-probe/wasi-stubs/include}"
EXPAT_PREFIX="${EXPAT_PREFIX:-$ROOT/.wasmify/expat-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"
LIBPNG_PREFIX="${LIBPNG_PREFIX:-$ROOT/.wasmify/libpng-probe/prefix}"
PCRE2_PREFIX="${PCRE2_PREFIX:-$ROOT/.wasmify/pcre2-probe/prefix}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

if [[ ! -f "$LIBVIPS_BUILD/libvips/libvips.a" ]]; then
  echo "missing $LIBVIPS_BUILD/libvips/libvips.a; run: make probe-libvips-wasi" >&2
  exit 2
fi

mkdir -p "$WORK"
cat > "$WORK/probe.c" <<'C'
#include <vips/vips.h>

extern void glib_init(void);

__attribute__((export_name("vipswasm_version_major")))
int vipswasm_version_major(void) {
  return vips_version(0);
}

__attribute__((export_name("vipswasm_init")))
int vipswasm_init(void) {
  glib_init();
  return vips_init("go-vipswasm-link-probe");
}

__attribute__((export_name("vipswasm_gobject_new")))
int vipswasm_gobject_new(void) {
  glib_init();
  GObject *object = g_object_new(G_TYPE_OBJECT, NULL);
  if (object == NULL) {
    return -1;
  }
  g_object_unref(object);
  return 1;
}

__attribute__((export_name("vipswasm_vips_image_type")))
int vipswasm_vips_image_type(void) {
  glib_init();
  if (vips_init("go-vipswasm-link-probe") != 0) {
    return -1;
  }
  GType type = VIPS_TYPE_IMAGE;
  if (type == 0) {
    return -2;
  }
  const char *name = g_type_name(type);
  if (name == NULL || g_strcmp0(name, "VipsImage") != 0) {
    return -3;
  }
  return 1;
}

__attribute__((export_name("vipswasm_vips_image_new_empty")))
int vipswasm_vips_image_new_empty(void) {
  glib_init();
  if (vips_init("go-vipswasm-link-probe") != 0) {
    return -1;
  }
  VipsImage *image = vips_image_new();
  if (image == NULL) {
    return -2;
  }
  g_object_unref(image);
  return 1;
}

__attribute__((export_name("vipswasm_memory_width_noinit")))
int vipswasm_memory_width_noinit(void) {
  glib_init();
  const unsigned char pixel[4] = {1, 2, 3, 255};
  VipsImage *image = vips_image_new_from_memory_copy(pixel, sizeof(pixel), 1, 1, 4, VIPS_FORMAT_UCHAR);
  if (image == NULL) {
    return -1;
  }
  int width = vips_image_get_width(image);
  g_object_unref(image);
  return width;
}
C

cat > "$WORK/wasi-link-stubs.c" <<'C'
#include <errno.h>
#include <pthread.h>
#include <stddef.h>

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
C

pkg_config_paths=(
  "$LIBVIPS_BUILD/meson-uninstalled"
  "$LIBVIPS_BUILD/meson-private"
  "$GLIB_BUILD/meson-uninstalled"
  "$GLIB_BUILD/meson-private"
  "$ZLIB_PREFIX/lib/pkgconfig"
  "$LIBPNG_PREFIX/lib/pkgconfig"
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

"$WASI_SDK_PATH/bin/clang" \
  --target=wasm32-wasip1 \
  -O2 \
  -g \
  -mno-atomics \
  -mexec-model=reactor \
  -D_WASI_EMULATED_PROCESS_CLOCKS \
  -D_WASI_EMULATED_SIGNAL \
  -D_WASI_EMULATED_MMAN \
  -I"$GLIB_STUB_INCLUDE" \
  "${cflags[@]}" \
  "$WORK/probe.c" \
  "$WORK/wasi-link-stubs.c" \
  "${libs[@]}" \
  -lwasi-emulated-process-clocks \
  -lwasi-emulated-signal \
  -lwasi-emulated-mman \
  -lwasi-emulated-getpid \
  -Wl,--no-entry \
  -Wl,--export=vipswasm_init \
  -Wl,--export=vipswasm_version_major \
  -Wl,--export=vipswasm_gobject_new \
  -Wl,--export=vipswasm_vips_image_type \
  -Wl,--export=vipswasm_vips_image_new_empty \
  -Wl,--export=vipswasm_memory_width_noinit \
  -o "$WORK/libvips-link-probe.wasm"

echo "$WORK/libvips-link-probe.wasm"
