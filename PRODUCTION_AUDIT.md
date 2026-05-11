# Production Audit

Objective: expose libvips as a production Go package through
`github.com/goccy/wasmify`, with no CGO, no host dynamic library loading, and
tests that prove real libvips behavior.

## Criteria

| Requirement | Current evidence | Status |
| --- | --- | --- |
| Use `wasmify` | `api-spec.json`, `proto/vipswasm.proto`, `bridge/api_bridge.cc`, and `wasmify.json` define the generated bridge used by public operations. | Pass |
| Use libvips | `internal/vipswasm.wasm` links a static WASI libvips probe; `Version()` returns the linked libvips version; `ResizeNearest` and `ExtractArea` execute libvips operations. | Pass |
| No CGO | `make verify-cgo` runs `CGO_ENABLED=0 go test ./...` and checks `go list` for `CgoFiles`. | Pass |
| No host dynamic loading | `make verify-no-dynamic` scans Go/C/C++ sources for `dlopen`, `dlsym`, `LoadLibrary`, `plugin.Open`, `#cgo`, `import "C"`, and host libvips library names. | Pass |
| Embedded WASM imports only runtime-safe modules | `make verify-wasm` checks imports and allows only WASI plus wasmify callbacks. | Pass |
| GLib baseline under wazero | `make probe-glib-run-wazero` shows minimal `GHashTable` and `GQuark` paths both return `1` after explicit WASI reactor `_initialize` and `glib_init()`. | Pass |
| Real libvips initialization under wazero | `make probe-libvips-init-wazero` returns `vips_init()=0` after explicit WASI reactor `_initialize` and `glib_init()`. | Pass |
| GObject instance construction under wazero | `make probe-libvips-gobject-wazero` returns `g_object_new(G_TYPE_OBJECT)=1`. | Pass |
| libvips image type registration under wazero | `make probe-libvips-image-type-wazero` returns `VIPS_TYPE_IMAGE=1`, so basic type registration is not the first failing point. | Pass |
| Real libvips image object creation under wazero | `make probe-libvips-image-new-wazero` returns `vips_image_new()=1`, and `make probe-libvips-memory-wazero` returns `vips_image_new_from_memory_copy width=1`. | Pass |
| Real image codecs | `Engine.DecodePNG` exercises libvips' PNG foreign loader under wazero; package-edge generic `Decode`, `EncodePNG`, and `EncodeJPEG` intentionally use Go's standard library. JPEG and libvips PNG save are not exposed by the current package surface. | Pass |
| Typed operation surface comparable to vipsgen | `VipsOperation` and `GeneratedOperations` expose a generated-style operation catalog beyond the two executable demo methods. | Pass |
| Production tests | `go test ./...`, `CGO_ENABLED=0 go test ./...`, probe runtime checks, and import scans pass. | Pass |

## Current State

The package statically links a libvips WASI archive and calls real libvips
paths under wazero. The runner explicitly calls the WASI reactor `_initialize`
export, the shim calls GLib's idempotent `glib_init()`, and `vips_init()`
returns success under wazero.

`VIPS_TYPE_IMAGE` registration, minimal `g_object_new(G_TYPE_OBJECT)`,
`vips_image_new()`, `vips_image_new_from_memory_copy()`, the wasmify-backed
`vips_resize()` / `vips_extract_area()` paths, and libvips' PNG foreign loader
now run under wazero.

The current GLib/libvips path still carries WASI-only dependency patches. GLib
is built without libffi; generic closure marshalling fails explicitly on WASI,
while the typed marshaller paths used by the current libvips operations run
under wazero.

Next hardening tasks:

1. Add JPEG coverage and stabilize libvips PNG save if encoded byte I/O should
   move fully inside libvips. PNG load now runs through
   libvips; generic package-edge byte encode/decode helpers still use Go's
   standard library.
2. Expand generated executable bindings beyond the current `ResizeNearest` and
   `ExtractArea` operations.

`make audit-production` is the production gate for the current
package surface.
