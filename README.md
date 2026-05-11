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

`make wasm` builds the default embedded artifact through the current libvips
WASI probe. `make wasm-libvips-full` builds `internal/vipswasm_full.wasm`, a
larger static WASI reactor with the extended libvips external-format preset.
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
the public image operations execute through libvips. The package also keeps a
vipsgen-style `GeneratedOperations` catalog for the typed surface, including
foreign codec operation entries. The byte-oriented `Decode`, `EncodePNG`, and
`EncodeJPEG` helpers intentionally use Go's standard image packages at the
package edge. `Engine.DecodeImage` exercises libvips' foreign loaders inside
the wasm runtime; `NewFull` selects the larger full-format core when a caller
needs codecs that are not in the default artifact.
Foreign loaders are exposed through the generic `Engine.DecodeImage` entry
point. Public encoding and the CLI support PNG/JPEG output plus the libvips
foreign savers that run under the embedded WASI runtime today: WebP, TIFF, raw
RGBA, GIF, and JPEG 2000.

The default checked-in runtime is `internal/vipswasm.wasm`. The repository also
includes `internal/vipswasm_full.wasm`, built by `make wasm-libvips-full`, for
validating the extended static WASI libvips dependency graph. The extended
preset enables the static external packages that are both linkable and loadable
under wazero today, including archive, CFITSIO, CGIF, EXIF, FFTW, HEIF/AVIF,
highway, imagequant, JPEG XL, LCMS, ImageMagick, MATIO, NIfTI, OpenEXR,
OpenJPEG, TIFF, and WebP. JPEG, UHDR, fontconfig/Pango/Cairo, OpenSlide,
Poppler/PDF, RAW camera formats, and librsvg/SVG are disabled in the checked-in
full artifact because their current WASI builds pull in exception/SJLJ or other
runtime paths that do not load cleanly in wazero.

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
make wasm-libvips-full
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

## CLI Example

`examples/convert_cli` is a complete command-line example built on the public
Go API. It reads PNG/JPEG input through `vipswasm.Decode` by default, uses the
embedded libvips foreign loader for non-standard input such as HEIC/HEIF/AVIF,
WebP, TIFF, GIF, JPEG XL, JPEG 2000, OpenEXR, FITS, MAT, and NIfTI, can force
libvips decode with `-libvips-input`, applies `ExtractArea` before
`ResizeNearest`, and writes PNG/JPEG/WebP/TIFF/raw/GIF/JPEG 2000 output.

```sh
go run ./examples/convert_cli input.png output.jpg
go run ./examples/convert_cli input.heic output.jpg
go run ./examples/convert_cli input.png output.webp
go run ./examples/convert_cli input.heic output.jp2
go run ./examples/convert_cli -resize 320x240 input.png thumb.png
go run ./examples/convert_cli -extract 10,10,200,120 -format jpeg input.png - > crop.jpg
cat input.heic | go run ./examples/convert_cli -libvips-input -format png - - > roundtrip.png
```

Flags:

- `-format png|jpeg|webp|tiff|raw|gif|jp2`: output format. This is required when output is `-`.
- `-resize WIDTHxHEIGHT`: resize with libvips nearest-neighbor sampling.
- `-extract X,Y,WIDTH,HEIGHT`: crop before resizing.
- `-quality 1..100`: JPEG/WebP quality, default `90`.
- `-libvips-input`: decode input through the embedded libvips foreign loader.
- `-libvips-png-input`: decode PNG input through the embedded libvips loader.

File outputs are written atomically so a failed conversion does not replace an
existing destination. Use `-` for stdin or stdout.
