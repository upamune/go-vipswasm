# Full WASI libvips Preset

## Context

`full` is intended to enable every libvips external image format and optional
package that can reasonably be linked into the static WASI reactor.

The initial `VIPSWASM_LIBVIPS_PRESET=full` probe enables:

- `archive`
- `cfitsio`
- `cgif`
- `exif`
- `fftw`
- `fontconfig`
- `heif`
- `highway`
- `imagequant`
- `jpeg`
- `jpeg-xl`
- `lcms`
- `magick`
- `matio`
- `nifti`
- `openexr`
- `openjpeg`
- `openslide`
- `orc`
- `pangocairo`
- `pdfium`
- `poppler`
- `quantizr`
- `raw`
- `rsvg`
- `spng`
- `tiff`
- `uhdr`
- `webp`

## Status

The `full` preset now configures, builds `libvips.a`, and links
`internal/vipswasm_full.wasm` as a static WASI reactor.

The resulting full Meson configuration enables the expected external packages:

- `archive`
- `cfitsio`
- `cgif`
- `exif`
- `fftw`
- `fontconfig`
- `heif`
- `highway`
- `imagequant`
- `jpeg`
- `jpeg-xl`
- `lcms`
- `magick`
- `matio`
- `nifti`
- `openexr`
- `openjpeg`
- `openslide`
- `orc`
- `pangocairo`
- `poppler`
- `quantizr`
- `raw`
- `rsvg`
- `spng`
- `tiff`
- `uhdr`
- `webp`

`pdfium` is intentionally disabled. The available upstream binary distribution
is a standalone `pdfium.wasm` plus JavaScript glue, not a static `libpdfium.a`
that can be linked into this reactor. PDF support is provided through the
static Poppler/Poppler-GLib backend instead.

## Verification

The full artifact has been checked so that its imports are limited to
`wasi_snapshot_preview1`; libvips and codec symbols are linked into the module
rather than left as host imports.
