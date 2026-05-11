#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail=0

check() {
  local name="$1"
  shift
  if "$@"; then
    printf "ok   %s\n" "$name"
  else
    printf "FAIL %s\n" "$name"
    fail=1
  fi
}

has_libvips_shim() {
  rg -q '#include <vips/|vips_init|VipsImage|vips_image_new_from' tools/wasm bridge internal vipswasm.go
}

has_no_placeholder_core() {
  ! rg -q 'rgba_resize_nearest|rgba_extract_area|vipswasm_rgba_resize_nearest|vipswasm_rgba_extract_area' tools/wasm bridge vipswasm.go
}

has_libvips_codecs() {
  ! rg -q -- '-Dpng=disabled' tools/libvips/probe-wasi.sh &&
    rg -q 'vips__png_read_source|vips_pngload|vips_foreign_load_png' tools/wasm vipswasm.go vipswasm_test.go &&
    rg -q 'DecodePNG|TestLibvipsDecodeAndEncodePNG' vipswasm.go vipswasm_test.go
}

has_generated_surface() {
  rg -q 'VipsOperation|vipsgen|thumbnail|autorot|jpegload|jpegsave|pngload|pngsave|webpload|webpsave' proto api-spec.json bridge vipswasm.go
}

has_no_unsafe_libffi_stub() {
  ! rg -q 'libffi-stub|unsafe libffi|ffi_call.*abort|Description: unsafe libffi' \
    Makefile tools README.md PRODUCTION_AUDIT.md \
    --glob '!tools/libvips/production-audit.sh'
}

has_real_operation_runtime() {
  rg -q 'vips_resize|vips_extract_area|vips_image_write_to_memory' tools/wasm &&
    go test ./... >/dev/null
}

has_init_probe() {
  rg -q 'probe-libvips-init-wazero|PROBE_VIPS_INIT|vipswasm_init' Makefile tools README.md PRODUCTION_AUDIT.md
}

has_memory_probe() {
  rg -q 'probe-libvips-memory-wazero|PROBE_VIPS_MEMORY|vips_image_new_from_memory_copy' Makefile tools README.md PRODUCTION_AUDIT.md
}

has_gobject_probe() {
  rg -q 'probe-libvips-gobject-wazero|PROBE_GOBJECT_NEW|g_object_new' Makefile tools README.md PRODUCTION_AUDIT.md
}

has_image_type_probe() {
  rg -q 'probe-libvips-image-type-wazero|PROBE_VIPS_IMAGE_TYPE|VIPS_TYPE_IMAGE' Makefile tools README.md PRODUCTION_AUDIT.md
}

has_image_new_probe() {
  rg -q 'probe-libvips-image-new-wazero|PROBE_VIPS_IMAGE_NEW|vips_image_new' Makefile tools README.md PRODUCTION_AUDIT.md
}

has_glib_probe() {
  rg -q 'probe-glib-run-wazero|glibwasm_hash_table_probe|glibwasm_quark_probe|g_quark_from_static_string' Makefile tools README.md PRODUCTION_AUDIT.md
}

has_glib_probe_runtime() {
  local out
  out="$(tools/libvips/probe-glib-run-wazero.sh 2>&1)" &&
    grep -q 'g_hash_table=1' <<<"$out" &&
    grep -q 'g_quark=1' <<<"$out"
}

has_init_probe_runtime() {
  local out
  out="$(PROBE_VIPS_INIT=1 tools/libvips/probe-run-wazero.sh 2>&1)" &&
    grep -q 'vips_init()=0' <<<"$out"
}

has_gobject_probe_runtime() {
  local out
  out="$(PROBE_GOBJECT_NEW=1 tools/libvips/probe-run-wazero.sh 2>&1)" &&
    grep -q 'g_object_new(G_TYPE_OBJECT)=1' <<<"$out"
}

has_image_type_probe_runtime() {
  local out
  out="$(PROBE_VIPS_IMAGE_TYPE=1 tools/libvips/probe-run-wazero.sh 2>&1)" &&
    grep -q 'VIPS_TYPE_IMAGE=1' <<<"$out"
}

has_image_new_probe_runtime() {
  local out
  out="$(PROBE_VIPS_IMAGE_NEW=1 tools/libvips/probe-run-wazero.sh 2>&1)" &&
    grep -q 'vips_image_new()=1' <<<"$out"
}

has_memory_probe_runtime() {
  local out
  out="$(PROBE_VIPS_MEMORY=1 tools/libvips/probe-run-wazero.sh 2>&1)" &&
    grep -q 'vips_image_new_from_memory_copy width=1' <<<"$out"
}

has_no_host_dynamic_loading() {
  test -z "$(rg -n 'dlopen|dlsym|LoadLibrary|plugin\.Open|#cgo|import "C"|libvips\.so|libvips\.dylib|vips\.dll' --glob '*.go' --glob '*.cc' --glob '*.h' . || true)"
}

has_wasm_runtime_only() {
  test -z "$(wasm-dis internal/vipswasm.wasm | grep '(import ' | grep -v 'wasi_snapshot_preview1' | grep -Fv '"wasmify" "callback_invoke"' || true)"
}

has_cgo_free_tests() {
  CGO_ENABLED=0 go test ./... >/dev/null
}

printf "Production audit for go-vipswasm\n"
printf "Objective: expose real libvips as a Go package via wasmify, with no CGO, no host dynamic loading, and production tests.\n\n"

check "embedded WASM is backed by libvips symbols/shim" has_libvips_shim
check "placeholder RGBA-only core has been removed" has_no_placeholder_core
check "runtime operations execute real libvips operations" has_real_operation_runtime
check "real libvips PNG foreign loader is covered" has_libvips_codecs
check "typed operation surface is generated beyond the demo ops" has_generated_surface
check "production build does not depend on unsafe libffi stubs" has_no_unsafe_libffi_stub
check "GLib hash/quark baseline probe exists" has_glib_probe
check "GLib hash/quark baseline runs under wazero" has_glib_probe_runtime
check "real libvips initialization probe exists" has_init_probe
check "real libvips initialization runs under wazero" has_init_probe_runtime
check "minimal GObject construction probe exists" has_gobject_probe
check "minimal GObject construction runs under wazero" has_gobject_probe_runtime
check "VipsImage type registration probe exists" has_image_type_probe
check "VipsImage type registration runs under wazero" has_image_type_probe_runtime
check "empty VipsImage construction probe exists" has_image_new_probe
check "empty VipsImage construction runs under wazero" has_image_new_probe_runtime
check "real libvips image creation probe exists" has_memory_probe
check "real libvips image creation runs under wazero" has_memory_probe_runtime
check "no host dynamic library loading or CGO hooks are present" has_no_host_dynamic_loading
check "embedded WASM imports only WASI/wasmify callbacks" has_wasm_runtime_only
check "package tests pass with CGO disabled" has_cgo_free_tests

if [[ "$fail" -ne 0 ]]; then
	cat <<'MSG'

Production audit failed.

	The current package failed one or more production checks for the current
	wasmify/wazero libvips package surface. See the failed checks above and
	tools/libvips/README.md for the current probe results.
MSG
  exit 1
fi
