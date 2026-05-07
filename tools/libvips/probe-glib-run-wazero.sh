#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
WORK="${GLIB_LINK_PROBE_DIR:-$ROOT/.wasmify/glib-link-probe}"
WASM="$WORK/glib-link-probe.wasm"
RUNNER="$WORK/run-wazero.go"

if [[ ! -f "$WASM" ]]; then
  echo "missing $WASM; run: make probe-glib-link-wasi" >&2
  exit 2
fi

cat > "$RUNNER" <<'GO'
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/imports/wasi_snapshot_preview1"
)

func main() {
	ctx := context.Background()
	wasm, err := os.ReadFile(".wasmify/glib-link-probe/glib-link-probe.wasm")
	if err != nil {
		panic(err)
	}

	rt := wazero.NewRuntime(ctx)
	defer rt.Close(ctx)

	if _, err := wasi_snapshot_preview1.Instantiate(ctx, rt); err != nil {
		panic(err)
	}
	mod, err := rt.Instantiate(ctx, wasm)
	if err != nil {
		panic(err)
	}
	if init := mod.ExportedFunction("_initialize"); init != nil {
		if _, err := init.Call(ctx); err != nil {
			panic(err)
		}
	}
	hash, err := mod.ExportedFunction("glibwasm_hash_table_probe").Call(ctx)
	if err != nil {
		panic(err)
	}
	quark, err := mod.ExportedFunction("glibwasm_quark_probe").Call(ctx)
	if err != nil {
		panic(err)
	}
	fmt.Printf("g_hash_table=%d\n", hash[0])
	fmt.Printf("g_quark=%d\n", quark[0])
}
GO

go run "$RUNNER"
