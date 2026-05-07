# go-vipswasm

`go-vipswasm` is a CGO-free Go package that runs an embedded libvips-backed WebAssembly image core through `wazero`.

The package exposes runtime ownership, a typed operation catalog, and libvips-backed image operations (`ResizeNearest`, `ExtractArea`) behind a Go API. Public operations call the `wasmify` generated `w_0_*` bridge exports, and the wasm core is checked in as `internal/vipswasm.wasm`.

## Development

Use the repo flake:

```sh
direnv allow
make tools
make generate
make verify
```

`make tools` installs `wasmify` and `protoc-gen-wasmify-go` at the pinned
`WASMIFY_VERSION` from the Makefile. Override it only when intentionally
upgrading the generated bridge.

`make wasm` builds the embedded artifact through the current libvips WASI
probe. `make wasm-scaffold` is available only for the old lightweight RGBA
scaffold build.

`make verify` rebuilds the libvips-linked wasm artifact, runs `go test ./...`, repeats the
tests with `CGO_ENABLED=0`, checks that no dependency reports `CgoFiles`,
verifies that the wasm module imports only WASI, and scans the package for host
dynamic-library loading hooks.

If the pinned WASI SDK has not been installed yet:

```sh
make wasi-sdk
```

On macOS, the current `wasi-sdk-31.0-arm64-macos` archive may contain an absolute `libedit` install name. If `clang++` fails to load `libedit.0.dylib`, repair the local SDK once:

```sh
install_name_tool -change /Users/runner/work/wasi-sdk/wasi-sdk/build/toolchain/install/lib/libedit.0.dylib @rpath/libedit.0.dylib ~/.config/wasmify/bin/wasi-sdk/lib/libLLVM.dylib
install_name_tool -add_rpath ~/.config/wasmify/bin/wasi-sdk/lib ~/.config/wasmify/bin/wasi-sdk/bin/clang++
```

## Status

The embedded wasm artifact is linked against the static WASI libvips probe and
the public image operations execute through libvips. The package also keeps a
vipsgen-style `GeneratedOperations` catalog for the typed surface, including
foreign JPEG/PNG operation entries. The byte-oriented `Decode`, `EncodePNG`,
and `EncodeJPEG` helpers intentionally use Go's standard image packages at the
package edge. `Engine.DecodePNG` additionally exercises libvips' PNG foreign
loader inside the wasm runtime.

The current WASI libvips probe is reproducible:

```sh
direnv exec . make probe-reset
direnv exec . make probe-glib-wasi
direnv exec . make probe-libvips-wasi
direnv exec . make probe-libvips-link-wasi
direnv exec . make probe-libvips-run-wazero
direnv exec . make probe-libvips-init-wazero
direnv exec . make probe-libvips-gobject-wazero
direnv exec . make probe-libvips-image-type-wazero
direnv exec . make probe-libvips-image-new-wazero
direnv exec . make probe-libvips-memory-wazero
direnv exec . make probe-libvips-diagnose-wazero
direnv exec . make wasm-libvips
```

`probe-glib-wasi` builds GLib/GObject/GIO as static WASI archives without
libffi. The probe patches GLib's generic closure marshaller to fail explicitly
on WASI instead of linking a fake FFI layer; the libvips paths used by this
package use typed marshallers and do not require generic `ffi_call()`.

The linked libvips reactor imports only `wasi_snapshot_preview1` and can call
`vips_version(0)`, `vips_init()`, `g_object_new(G_TYPE_OBJECT)`,
`VIPS_TYPE_IMAGE`, `vips_image_new()`, and
`vips_image_new_from_memory_copy()` under the normal wazero runtime.

To check whether the repository has crossed from scaffold to the requested
production libvips package, run:

```sh
direnv exec . make audit-production
```

This target is the production gate for the current package surface.

See `PRODUCTION_AUDIT.md` for the prompt-to-artifact checklist.

`make probe-reset` deletes `.wasmify/` so exploratory local dependency patches
cannot accidentally change the probe outcome.
`make probe-libvips-diagnose-wazero` writes the current version, init,
GObject, VipsImage, and memory probe outputs to
`.wasmify/libvips-link-probe/wazero-diagnostics.txt`.

## Example

```go
engine, err := vipswasm.New(context.Background())
if err != nil {
    return err
}
defer engine.Close()

img, _, err := vipswasm.Decode(input)
if err != nil {
    return err
}
thumb, err := engine.ResizeNearest(img, 320, 240)
if err != nil {
    return err
}
return thumb.EncodePNG(output)
```
