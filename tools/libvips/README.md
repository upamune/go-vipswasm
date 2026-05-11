# libvips WASI Probe

This directory contains the reproducible probe for the real libvips path.

```sh
make probe-reset
make probe-iconv-wasi
make probe-pcre2-wasi
make probe-zlib-wasi
make probe-libpng-wasi
make probe-expat-wasi
make probe-glib-wasi
make probe-glib-run-wazero
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

Use `make probe-reset` before a clean reproduction. The `.wasmify/` tree is a
scratch cache and may contain local dependency experiments while debugging.
`make probe-libvips-diagnose-wazero` captures the linked reactor's version,
init, GObject/VipsImage, direct-memory, section, and import diagnostics in
`.wasmify/libvips-link-probe/wazero-diagnostics.txt`.

## Current Path

The probe builds static WASI archives for:

- GNU libiconv 1.18
- PCRE2 10.47
- zlib 1.3.2
- libpng 1.6.50 with `PNG_SETJMP_NOT_SUPPORTED`
- Expat 2.8.0
- GLib/GObject/GIO 2.86.5
- libvips 8.18.2

GLib is built without libffi. `probe-glib-wasi.sh` patches GLib's generic
closure marshaller to fail explicitly on WASI instead of linking an FFI layer.
The libvips operation paths used by this package use typed marshallers and run
under wazero without generic `ffi_call()`.

The GLib-only reactor isolates GLib from libvips:

```text
make probe-glib-run-wazero
g_hash_table=1
g_quark=1
```

`g_hash_table=1` means a minimal `GHashTable` insert/lookup path works under
wazero. `g_quark=1` means a minimal `g_quark_from_static_string()` /
`g_quark_try_string()` / `g_quark_to_string()` path also works after the runner
calls the WASI reactor `_initialize` export and the probe calls GLib's
idempotent `glib_init()`.

The libvips link/run probes verify the static archive behind a tiny WASI
reactor:

```text
make probe-libvips-run-wazero
vips_version(0)=8
```

```text
make probe-libvips-init-wazero
vips_version(0)=8
vips_init()=0
```

```text
make probe-libvips-gobject-wazero
vips_version(0)=8
g_object_new(G_TYPE_OBJECT)=1
```

```text
make probe-libvips-image-type-wazero
vips_version(0)=8
VIPS_TYPE_IMAGE=1
```

```text
make probe-libvips-image-new-wazero
vips_version(0)=8
vips_image_new()=1
```

```text
make probe-libvips-memory-wazero
vips_version(0)=8
vips_image_new_from_memory_copy width=1
```

`make wasm-libvips` links the wasmify bridge against the same static libvips
archive. The Go package tests pass against that artifact, and the embedded
WASM imports only `wasi_snapshot_preview1` plus the wasmify callback import.

## Patch Scope

The GLib probe routes WASI compiler calls through `wasi-clang-filter.sh` so
Meson's GNU ld group flags and `-pthread` do not produce false negatives with
`wasm-ld`.

The GLib source patches adapt the Emscripten-oriented `wasm-vips` approach to
plain WASI/wazero: skip unsupported GIO tools and resolver checks, no-op the
debugger backtrace path, avoid POSIX timezone refresh, bypass executable
permission checks, stub unsupported subprocess helpers, add `G_PLATFORM_WASM`
guards around Unix signal, child-watch, user database, host-info, wakeup,
spawn, GFile, socket, resolver, and Unix mount paths, and adapt common
GObject/GParamSpec class and instance initialization signatures.

The libvips source patches use WASI's `posix_memalign` path, pass the GLib
WASI stub headers into Meson, compile the PNG path against the no-setjmp
libpng build, enable zlib/libpng/JPEG, and make `vips_threadpool_run()`
execute synchronously on WASI. The final reactor link intentionally avoids
LLVM WebAssembly SJLJ tag sections so wazero can load the artifact. Fatal
codec longjmp paths become wasm traps; the Go `Engine` reports `ErrWasmTrap`
and reinstantiates a clean runtime for subsequent calls.

## Remaining Work

The current package surface has real libvips resize, extract, image-memory,
PNG/JPEG/WebP encode coverage, and broad format registration checks. Future
hardening can add more invalid-input codec paths and generated executable
bindings beyond `ResizeNearest` and `ExtractArea`.
