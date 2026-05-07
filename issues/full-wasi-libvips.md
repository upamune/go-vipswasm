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

## Current Blocker

`direnv exec . make wasm-libvips-full` currently stops during Meson configure
because `libarchive` is not available for the WASI pkg-config path.

A direct static WASI build probe of libarchive 3.8.2 with zlib enabled also
failed. The compile errors come from POSIX APIs that are not available in the
current WASI SDK/sysroot path:

- `fchdir`
- `dup`
- `getpwuid`
- `getgrgid`
- incomplete `struct passwd`
- incomplete `struct group`

## Notes

This means `full` is not just a matter of adding pkg-config paths. Several
dependencies will need WASI-specific configuration or patches before the full
preset can produce a usable `internal/vipswasm_full.wasm`.

The pragmatic path is to finish a smaller `default` preset first:

- PNG
- WebP
- TIFF
- HEIC/HEIF

JPEG is not in `default` yet. libvips' JPEG loader/saver includes `setjmp.h`,
and the WASI SDK requires `-mllvm -wasm-enable-sjlj` plus an engine that
supports WebAssembly exception handling for `setjmp/longjmp`. That should be
treated as part of the later expanded/full work rather than silently changing
the runtime requirement for the default artifact.

Then grow `full` one dependency family at a time.
