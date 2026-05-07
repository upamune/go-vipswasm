#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
WORK="${LIBVIPS_LINK_PROBE_DIR:-$ROOT/.wasmify/libvips-link-probe}"
WASM="$WORK/libvips-link-probe.wasm"
RUNNER="$WORK/run-wazero.go"

if [[ ! -f "$WASM" ]]; then
  echo "missing $WASM; run: make probe-libvips-link-wasi" >&2
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
	wasm, err := os.ReadFile(".wasmify/libvips-link-probe/libvips-link-probe.wasm")
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
	ret, err := mod.ExportedFunction("vipswasm_version_major").Call(ctx)
	if err != nil {
		panic(err)
	}
	fmt.Printf("vips_version(0)=%d\n", ret[0])

	if os.Getenv("PROBE_VIPS_INIT") == "1" {
		ret, err := mod.ExportedFunction("vipswasm_init").Call(ctx)
		if err != nil {
			panic(err)
		}
		fmt.Printf("vips_init()=%d\n", ret[0])
	}
	if os.Getenv("PROBE_GOBJECT_NEW") == "1" {
		ret, err := mod.ExportedFunction("vipswasm_gobject_new").Call(ctx)
		if err != nil {
			panic(err)
		}
		fmt.Printf("g_object_new(G_TYPE_OBJECT)=%d\n", ret[0])
	}
	if os.Getenv("PROBE_VIPS_IMAGE_TYPE") == "1" {
		ret, err := mod.ExportedFunction("vipswasm_vips_image_type").Call(ctx)
		if err != nil {
			panic(err)
		}
		fmt.Printf("VIPS_TYPE_IMAGE=%d\n", ret[0])
	}
	if os.Getenv("PROBE_VIPS_IMAGE_NEW") == "1" {
		ret, err := mod.ExportedFunction("vipswasm_vips_image_new_empty").Call(ctx)
		if err != nil {
			panic(err)
		}
		fmt.Printf("vips_image_new()=%d\n", ret[0])
	}
	if os.Getenv("PROBE_VIPS_MEMORY") == "1" {
		ret, err := mod.ExportedFunction("vipswasm_memory_width_noinit").Call(ctx)
		if err != nil {
			panic(err)
		}
		fmt.Printf("vips_image_new_from_memory_copy width=%d\n", ret[0])
	}
}
GO

go run "$RUNNER"
