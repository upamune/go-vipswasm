# go-vipswasm

<p align="center">
  <img src="https://i.gyazo.com/23e9674eac498f92210f201639bf8301.png" alt="go-vipswasm logo" width="420">
</p>

`go-vipswasm` is a CGO-free Go package that runs an embedded libvips-backed WebAssembly image core through `wazero`.

The package exposes runtime ownership, a typed operation catalog, and libvips-backed image operations (`ResizeNearest`, `ExtractArea`) behind a Go API. Public operations call the `wasmify` generated `w_0_*` bridge exports, and the wasm core is checked in as `internal/vipswasm.wasm`.

`go-vipswasm` uses `github.com/goccy/wasmify` for API discovery and bridge generation: `api-spec.json`, `proto/vipswasm.proto`, `proto/wasmify/options.proto`, and `bridge/api_bridge.cc` are generated from `tools/wasm/vipswasm.h`. The final WASI module is linked by this repository's build scripts with wasmify's generated bridge, the project C++ shim, and statically built libvips/GLib/codec libraries. In other words, wasmify provides the Go-to-WASM bridge; the libvips WASI build and final static link are owned here.

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

`make wasm` builds the full-format embedded artifact used by `New`.
`make wasm-scaffold` is available only for the old lightweight RGBA scaffold
build.

`make verify` rebuilds the libvips-linked wasm artifact, runs `go test ./...`, repeats the
tests with `CGO_ENABLED=0`, checks that no dependency reports `CgoFiles`,
verifies that the wasm module imports only WASI, and scans the package for host
dynamic-library loading hooks.

If the pinned WASI SDK has not been installed yet:

```sh
make wasi-sdk
```

### Docker WASM build

Use `Dockerfile.wasm` to regenerate `internal/vipswasm.wasm` without installing
Meson, GLib tools, the WASI SDK, or other probe dependencies on the host:

```sh
# Build the artifact stage and export /out/ to .wasm-artifacts/.
make docker-wasm

# Replace the checked-in embedded artifact after reviewing the result.
cp .wasm-artifacts/internal/vipswasm.wasm internal/vipswasm.wasm
```

Equivalent direct BuildKit command:

```sh
docker buildx build \
  --progress=plain \
  --file Dockerfile.wasm \
  --target artifact \
  --output type=local,dest=.wasm-artifacts \
  .
```

The Docker build installs the host build tools needed by the libvips WASI probe,
including `libglib2.0-dev` so tools such as `glib-mkenums` are available in
`PATH`, then runs `make tools`, `make wasi-sdk`, and `make wasm` inside the
container. The exported artifact is written to
`.wasm-artifacts/internal/vipswasm.wasm`.

On macOS, the current `wasi-sdk-31.0-arm64-macos` archive may contain an absolute `libedit` install name. If `clang++` fails to load `libedit.0.dylib`, repair the local SDK once:

```sh
install_name_tool -change /Users/runner/work/wasi-sdk/wasi-sdk/build/toolchain/install/lib/libedit.0.dylib @rpath/libedit.0.dylib ~/.config/wasmify/bin/wasi-sdk/lib/libLLVM.dylib
install_name_tool -add_rpath ~/.config/wasmify/bin/wasi-sdk/lib ~/.config/wasmify/bin/wasi-sdk/bin/clang++
```

## Status

The embedded wasm artifact is linked against the static WASI libvips probe and
public image operations execute through libvips. The package also keeps a
vipsgen-style `GeneratedOperations` catalog for the typed surface, including
foreign codec operation entries. `Engine.DecodeImage`,
`Engine.DecodeImageWithOptions`, `Engine.DecodeHEICWithOptions`,
`Engine.ResizeNearest`, `Engine.ExtractArea`, and `Engine.EncodeImage` run inside
the wasm runtime. This package is WASM/libvips-only: it does not expose
package-level Go standard-library codec helpers or pure-Go resize fallbacks.
`New` uses the full-format core; there is no separate default/full API split.

### Format support matrix

Use `SupportedFormats()` for the same matrix from Go code.

- PNG: decode yes; encode yes; decode-time resize yes.
- JPEG: decode yes; encode yes; decode-time resize yes.
- WebP: decode yes; encode yes; decode-time resize yes.
- TIFF: decode yes; encode yes; decode-time resize yes.
- GIF: decode yes; encode yes; decode-time resize yes.
- JPEG 2000 (`jp2`): decode yes; encode yes.
- HEIC/HEIF: decode yes through libheif; encode not exposed. For large HEIC/HEIF images, use `DecodeImageWithOptions` or `DecodeHEICWithOptions` with `ResizeWidth` and `ResizeHeight` so libvips can thumbnail during decode instead of allocating the full-resolution RGBA image.

Foreign loaders are exposed through the generic `Engine.DecodeImage` entry
point. Public `Engine.EncodeImage` uses the libvips foreign savers that run
under the embedded WASI runtime today: PNG, WebP, TIFF, raw RGBA, GIF,
JPEG, and JPEG 2000.

The checked-in runtime used by `New` is the full-format `internal/vipswasm.wasm`.
The extended preset enables the static external packages that are both linkable and loadable
under wazero today, including archive, CFITSIO, CGIF, EXIF, FFTW, HEIF/AVIF,
highway, imagequant, JPEG, JPEG XL, LCMS, ImageMagick, MATIO, NIfTI, OpenEXR,
OpenJPEG, TIFF, and WebP. The final reactor intentionally avoids LLVM SJLJ tag
sections so wazero can load the artifact. Fatal codec longjmp paths are converted
to wasm traps; `Engine` returns `ErrWasmTrap` and reinstantiates its runtime so
the next call can continue. UHDR, fontconfig/Pango/Cairo, OpenSlide, Poppler/PDF, RAW camera
formats, and librsvg/SVG are disabled in the checked-in full artifact because
their current WASI builds still pull in runtime paths that do not load cleanly
in wazero.

The current WASI libvips probe is reproducible:

```sh
make probe-reset
make probe-glib-wasi
make probe-libvips-wasi
make probe-libvips-link-wasi
make probe-libvips-run-wazero
make probe-libvips-init-wazero
make probe-libvips-gobject-wazero
make probe-libvips-image-type-wazero
make probe-libvips-image-new-wazero
make probe-libvips-memory-wazero
make probe-libvips-diagnose-wazero
make wasm-libvips
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
make audit-production
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
engine, err := vipswasm.NewWithOptions(context.Background(), vipswasm.Options{
    MaxInputBytes:   64 << 20,
    MaxOutputPixels: 40_000_000,
})
if err != nil {
    return err
}
defer engine.Close()

img, err := engine.DecodeImageWithOptions(inputBytes, &vipswasm.DecodeOptions{
    ResizeWidth:  320,
    ResizeHeight: 240,
})
if err != nil {
    return err
}
encoded, err := engine.EncodeImage(img, "png", nil)
if err != nil {
    return err
}
_, err = output.Write(encoded)
return err
```

## CLI Example

`examples/convert_cli` is a complete command-line example built on the public
Go API. It decodes every input through the embedded libvips foreign loader,
applies `ExtractArea` before `ResizeNearest` when cropping is requested, and
writes PNG/JPEG/WebP/TIFF/raw/GIF/JPEG 2000 output through `Engine.EncodeImage`.
It does not use Go's standard image codecs or pure-Go resize fallbacks.

```sh
go run ./examples/convert_cli input.heic output.webp
go run ./examples/convert_cli input.png output.webp
go run ./examples/convert_cli -resize 320x240 input.png thumb.png
go run ./examples/convert_cli -extract 10,10,200,120 -format webp input.png - > crop.webp
cat input.heic | go run ./examples/convert_cli -resize 320x240 -format png - - > thumb.png
```

Flags:

- `-format png|webp|tiff|raw|gif|jp2`: output format. This is required when output is `-`.
- `-resize WIDTHxHEIGHT`: resize with libvips nearest-neighbor sampling.
- `-extract X,Y,WIDTH,HEIGHT`: crop before resizing.
- `-quality 1..100`: WebP quality, default `90`.

File outputs are written atomically so a failed conversion does not replace an
existing destination. Use `-` for stdin or stdout.
