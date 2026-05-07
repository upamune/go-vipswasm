#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
WORK="${LIBVIPS_LINK_PROBE_DIR:-$ROOT/.wasmify/libvips-link-probe}"
WASM="$WORK/libvips-link-probe.wasm"
OUT="$WORK/wazero-diagnostics.txt"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -f "$WASM" ]]; then
  echo "missing $WASM; run: make probe-libvips-link-wasi" >&2
  exit 2
fi

mkdir -p "$WORK"
: > "$OUT"

{
  printf "go-vipswasm wazero diagnostics\n"
  printf "wasm: %s\n" "$WASM"
  shasum -a 256 "$WASM"
  ls -lh "$WASM"
  printf "\n== wasm sections ==\n"
  "$WASI_SDK_PATH/bin/llvm-objdump" -h "$WASM"
  if command -v wasm-dis >/dev/null 2>&1; then
    printf "\n== wasm imports ==\n"
    wasm-dis "$WASM" | grep "(import " || true
  else
    printf "\n== wasm imports ==\n"
    printf "wasm-dis not found; run through direnv so binaryen is on PATH\n"
  fi
} >> "$OUT" 2>&1

run_case() {
  local name="$1"
  shift

  {
    printf "\n== %s ==\n" "$name"
    printf "command:"
    printf " %q" "$@"
    printf "\n"
  } >> "$OUT"

  set +e
  "$@" >> "$OUT" 2>&1
  local status=$?
  set -e

  printf "exit=%d\n" "$status" >> "$OUT"
}

run_case "version only" tools/libvips/probe-run-wazero.sh
run_case "vips_init" env PROBE_VIPS_INIT=1 tools/libvips/probe-run-wazero.sh
run_case "minimal GObject construction" env PROBE_GOBJECT_NEW=1 tools/libvips/probe-run-wazero.sh
run_case "VipsImage type registration" env PROBE_VIPS_IMAGE_TYPE=1 tools/libvips/probe-run-wazero.sh
run_case "empty VipsImage construction" env PROBE_VIPS_IMAGE_NEW=1 tools/libvips/probe-run-wazero.sh
run_case "direct memory image without init" env PROBE_VIPS_MEMORY=1 tools/libvips/probe-run-wazero.sh

cat "$OUT"
