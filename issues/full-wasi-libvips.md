# Full WASI libvips Preset

## Context

`full` is intended to enable every libvips external image format and optional
package that can reasonably be linked into the static WASI reactor.

The initial `VIPSWASM_LIBVIPS_PRESET=full` target was intended to enable:

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
`internal/vipswasm.wasm` as a static WASI reactor.

The resulting full Meson configuration enables the external packages that are
both linkable and loadable under wazero today:

- `archive`
- `cfitsio`
- `cgif`
- `exif`
- `fftw`
- `heif`
- `highway`
- `imagequant`
- `jpeg-xl`
- `lcms`
- `magick`
- `matio`
- `nifti`
- `openexr`
- `openjpeg`
- `orc`
- `quantizr`
- `spng`
- `tiff`
- `webp`

`pdfium` is intentionally disabled. JPEG, UHDR, fontconfig/Pango/Cairo,
OpenSlide, Poppler/PDF, RAW camera formats, and librsvg/SVG are also disabled
in the checked-in full artifact because their current WASI builds pull in
exception/SJLJ or other runtime paths that do not load cleanly in wazero.

## Verification

The full artifact has been checked so that its imports are limited to
`wasi_snapshot_preview1`; libvips and codec symbols are linked into the module
rather than left as host imports.
