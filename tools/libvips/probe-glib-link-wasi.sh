#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
WORK="${GLIB_LINK_PROBE_DIR:-$ROOT/.wasmify/glib-link-probe}"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
GLIB_BUILD="${GLIB_BUILD:-$ROOT/.wasmify/glib-probe/build}"
GLIB_STUB_INCLUDE="${GLIB_STUB_INCLUDE:-$ROOT/.wasmify/glib-probe/wasi-stubs/include}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"
PCRE2_PREFIX="${PCRE2_PREFIX:-$ROOT/.wasmify/pcre2-probe/prefix}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

if [[ ! -f "$GLIB_BUILD/glib/libglib-2.0.a" ]]; then
  echo "missing $GLIB_BUILD/glib/libglib-2.0.a; run: make probe-glib-wasi" >&2
  exit 2
fi

mkdir -p "$WORK"
cat > "$WORK/probe.c" <<'C'
#include <glib.h>

extern void glib_init(void);

__attribute__((export_name("glibwasm_hash_table_probe")))
int glibwasm_hash_table_probe(void) {
  GHashTable *table = g_hash_table_new(g_str_hash, g_str_equal);
  if (table == NULL) {
    return -1;
  }

  g_hash_table_insert(table, "key", "value");
  const char *value = (const char *) g_hash_table_lookup(table, "key");
  int ok = value != NULL && g_strcmp0(value, "value") == 0;
  g_hash_table_unref(table);
  return ok ? 1 : 0;
}

__attribute__((export_name("glibwasm_quark_probe")))
int glibwasm_quark_probe(void) {
  glib_init();

  GQuark a = g_quark_from_static_string("go-vipswasm-probe");
  GQuark b = g_quark_try_string("go-vipswasm-probe");
  const char *value = g_quark_to_string(a);
  if (a == 0) {
    return -1;
  }
  if (b == 0) {
    return -2;
  }
  if (a != b) {
    return -3;
  }
  if (g_strcmp0(value, "go-vipswasm-probe") != 0) {
    return -4;
  }
  return 1;
}
C

pkg_config_paths=(
  "$GLIB_BUILD/meson-uninstalled"
  "$GLIB_BUILD/meson-private"
  "$ZLIB_PREFIX/lib/pkgconfig"
  "$PCRE2_PREFIX/lib/pkgconfig"
  "$ICONV_PREFIX/lib/pkgconfig"
)
export PKG_CONFIG_PATH="$(IFS=:; echo "${pkg_config_paths[*]}"):${PKG_CONFIG_PATH:-}"

filter_link_flags() {
  tr ' ' '\n' |
    sed '/^$/d' |
    grep -Ev '^-pthread$|^-Wl,--start-group$|^-Wl,--end-group$|^-Wl,--as-needed$|^-Wl,--no-as-needed$'
}

cflags=()
while IFS= read -r flag; do
  cflags+=("$flag")
done < <(pkg-config --cflags glib-2.0 | filter_link_flags)

libs=()
while IFS= read -r flag; do
  libs+=("$flag")
done < <(pkg-config --libs --static glib-2.0 | filter_link_flags)

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
  "${libs[@]}" \
  -lwasi-emulated-process-clocks \
  -lwasi-emulated-signal \
  -lwasi-emulated-mman \
  -lwasi-emulated-getpid \
  -Wl,--no-entry \
  -Wl,--export=glibwasm_hash_table_probe \
  -Wl,--export=glibwasm_quark_probe \
  -o "$WORK/glib-link-probe.wasm"

echo "$WORK/glib-link-probe.wasm"
