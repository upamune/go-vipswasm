WASMIFY ?= wasmify
WASMIFY_VERSION ?= v0.1.5
WASI_SDK_PATH ?= $(HOME)/.config/wasmify/bin/wasi-sdk
WASI_CLANG ?= $(WASI_SDK_PATH)/bin/clang++
WASM_OPT ?= wasm-opt

.PHONY: help
help: ## Show available targets.
	@awk 'BEGIN { FS = ":.*##" } /^[a-zA-Z0-9_.-]+:.*##/ { printf "%-18s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: tools
tools: ## Install wasmify and protoc-gen-wasmify-go.
	go install github.com/goccy/wasmify/cmd/wasmify@$(WASMIFY_VERSION)
	go install github.com/goccy/wasmify/protoc-plugins/protoc-gen-wasmify-go@$(WASMIFY_VERSION)

.PHONY: wasi-sdk
wasi-sdk: ## Install wasmify's pinned WASI SDK.
	$(WASMIFY) install-sdk

.PHONY: wasm
wasm: wasm-libvips ## Build the full-format embedded WASI core linked against the libvips WASI probe.

.PHONY: docker-wasm
docker-wasm: ## Build the embedded WASM artifact in Docker and export it under .wasm-artifacts/out/.
	docker buildx build --progress=plain --file Dockerfile.wasm --target artifact --output type=local,dest=.wasm-artifacts .

.PHONY: wasm-scaffold
wasm-scaffold: ## Build the lightweight embedded WASI scaffold core.
	$(WASI_CLANG) -O3 -fno-exceptions -mexec-model=reactor -I. -Itools/wasm \
		-Wl,--no-entry -Wl,--export-all -Wl,--allow-undefined \
		-o internal/vipswasm.wasm tools/wasm/vipswasm.cc bridge/api_bridge.cc
	$(WASM_OPT) internal/vipswasm.wasm -Oz --strip-debug --strip-producers -o internal/vipswasm.wasm

.PHONY: wasm-libvips
wasm-libvips: probe-libvips-full-wasi ## Build the full-format embedded wasmify core linked against the libvips WASI probe.
	LIBVIPS_BUILD=.wasmify/libvips-full-probe/build \
		VIPSWASM_CORE_BUILD_DIR=.wasmify/wasmify-core-full \
		VIPSWASM_OUTPUT=internal/vipswasm.wasm \
		tools/libvips/build-wasmify-core.sh

.PHONY: generate
generate: ## Regenerate wasmify API spec, proto, and bridge sources.
	$(WASMIFY) parse-headers --force --header tools/wasm/vipswasm.h
	$(WASMIFY) gen-proto --package vipswasm

.PHONY: probe-libvips-wasi
probe-libvips-wasi: probe-expat-wasi probe-libpng-wasi probe-glib-wasi ## Probe a minimal libvips WASI cross build.
	tools/libvips/probe-wasi.sh

.PHONY: probe-libvips-full-wasi
probe-libvips-full-wasi: probe-expat-wasi probe-libpng-wasi probe-libarchive-wasi probe-fftw-wasi probe-imagemagick-wasi probe-cfitsio-wasi probe-libimagequant-wasi probe-cgif-wasi probe-libexif-wasi probe-libjpeg-wasi probe-libuhdr-wasi probe-libwebp-wasi probe-libtiff-wasi probe-pango-wasi probe-librsvg-wasi probe-openslide-wasi probe-matio-wasi probe-nifti-wasi probe-lcms-wasi probe-openexr-wasi probe-libraw-wasi probe-highway-wasi probe-poppler-wasi probe-libjxl-wasi probe-libheif-wasi probe-glib-wasi ## Probe a full libvips WASI cross build.
	VIPSWASM_LIBVIPS_PRESET=full \
		LIBVIPS_PROBE_DIR=.wasmify/libvips-full-probe \
		tools/libvips/probe-wasi.sh

.PHONY: probe-libvips-link-wasi
probe-libvips-link-wasi: probe-libvips-wasi ## Probe linking the static libvips archive into a WASI reactor.
	tools/libvips/probe-link-wasi.sh

.PHONY: probe-libvips-run-wazero
probe-libvips-run-wazero: probe-libvips-link-wasi ## Probe the linked libvips reactor under wazero.
	tools/libvips/probe-run-wazero.sh

.PHONY: probe-libvips-init-wazero
probe-libvips-init-wazero: probe-libvips-link-wasi ## Probe vips_init in the linked libvips reactor under wazero.
	PROBE_VIPS_INIT=1 tools/libvips/probe-run-wazero.sh

.PHONY: probe-libvips-gobject-wazero
probe-libvips-gobject-wazero: probe-libvips-link-wasi ## Probe minimal GObject instance construction under wazero.
	PROBE_GOBJECT_NEW=1 tools/libvips/probe-run-wazero.sh

.PHONY: probe-libvips-image-type-wazero
probe-libvips-image-type-wazero: probe-libvips-link-wasi ## Probe VipsImage type registration under wazero.
	PROBE_VIPS_IMAGE_TYPE=1 tools/libvips/probe-run-wazero.sh

.PHONY: probe-libvips-image-new-wazero
probe-libvips-image-new-wazero: probe-libvips-link-wasi ## Probe empty VipsImage construction under wazero.
	PROBE_VIPS_IMAGE_NEW=1 tools/libvips/probe-run-wazero.sh

.PHONY: probe-libvips-memory-wazero
probe-libvips-memory-wazero: probe-libvips-link-wasi ## Probe a direct libvips memory image API without vips_init.
	PROBE_VIPS_MEMORY=1 tools/libvips/probe-run-wazero.sh

.PHONY: probe-libvips-diagnose-wazero
probe-libvips-diagnose-wazero: probe-libvips-link-wasi ## Capture wazero diagnostics for the linked libvips reactor.
	tools/libvips/probe-diagnose-wazero.sh

.PHONY: probe-glib-wasi
probe-glib-wasi: probe-iconv-wasi probe-pcre2-wasi probe-zlib-wasi ## Probe a minimal GLib WASI cross build.
	tools/libvips/probe-glib-wasi.sh

.PHONY: probe-libffi-wasi
probe-libffi-wasi: ## Probe a static libffi WASI build.
	tools/libvips/probe-libffi-wasi.sh

.PHONY: probe-glib-link-wasi
probe-glib-link-wasi: probe-glib-wasi ## Probe linking GLib into a tiny WASI reactor.
	tools/libvips/probe-glib-link-wasi.sh

.PHONY: probe-glib-run-wazero
probe-glib-run-wazero: probe-glib-link-wasi ## Probe the linked GLib reactor under wazero.
	tools/libvips/probe-glib-run-wazero.sh

.PHONY: probe-zlib-wasi
probe-zlib-wasi: ## Probe a static zlib WASI build.
	tools/libvips/probe-zlib-wasi.sh

.PHONY: probe-libpng-wasi
probe-libpng-wasi: probe-zlib-wasi ## Probe a static libpng WASI build.
	tools/libvips/probe-libpng-wasi.sh

.PHONY: probe-libjpeg-wasi
probe-libjpeg-wasi: ## Probe a static libjpeg-turbo WASI build.
	tools/libvips/probe-libjpeg-wasi.sh

.PHONY: probe-libwebp-wasi
probe-libwebp-wasi: ## Probe a static libwebp WASI build.
	tools/libvips/probe-libwebp-wasi.sh

.PHONY: probe-brotli-wasi
probe-brotli-wasi: ## Probe a static Brotli WASI build.
	tools/libvips/probe-brotli-wasi.sh

.PHONY: probe-libjxl-wasi
probe-libjxl-wasi: probe-brotli-wasi probe-highway-wasi probe-lcms-wasi probe-zlib-wasi probe-libpng-wasi ## Probe a static JPEG XL WASI build.
	tools/libvips/probe-libjxl-wasi.sh

.PHONY: probe-libtiff-wasi
probe-libtiff-wasi: probe-zlib-wasi probe-libwebp-wasi ## Probe a static libtiff WASI build.
	tools/libvips/probe-libtiff-wasi.sh

.PHONY: probe-libde265-wasi
probe-libde265-wasi: ## Probe a static libde265 WASI build.
	tools/libvips/probe-libde265-wasi.sh

.PHONY: probe-libheif-wasi
probe-libheif-wasi: probe-libde265-wasi ## Probe a static libheif WASI build.
	tools/libvips/probe-libheif-wasi.sh

.PHONY: probe-libarchive-wasi
probe-libarchive-wasi: probe-zlib-wasi ## Probe a static libarchive WASI build.
	tools/libvips/probe-libarchive-wasi.sh

.PHONY: probe-fftw-wasi
probe-fftw-wasi: ## Probe a static FFTW WASI build.
	tools/libvips/probe-fftw-wasi.sh

.PHONY: probe-imagemagick-wasi
probe-imagemagick-wasi: ## Probe a static ImageMagick MagickCore WASI build.
	tools/libvips/probe-imagemagick-wasi.sh

.PHONY: probe-cfitsio-wasi
probe-cfitsio-wasi: probe-zlib-wasi ## Probe a static CFITSIO WASI build.
	tools/libvips/probe-cfitsio-wasi.sh

.PHONY: probe-libimagequant-wasi
probe-libimagequant-wasi: ## Probe a static libimagequant WASI build.
	tools/libvips/probe-libimagequant-wasi.sh

.PHONY: probe-cgif-wasi
probe-cgif-wasi: ## Probe a static cgif WASI build.
	tools/libvips/probe-cgif-wasi.sh

.PHONY: probe-libexif-wasi
probe-libexif-wasi: ## Probe a static libexif WASI build.
	tools/libvips/probe-libexif-wasi.sh

.PHONY: probe-libuhdr-wasi
probe-libuhdr-wasi: probe-libjpeg-wasi ## Probe a static libultrahdr WASI build.
	tools/libvips/probe-libuhdr-wasi.sh

.PHONY: probe-freetype-wasi
probe-freetype-wasi: probe-zlib-wasi ## Probe a static FreeType WASI build.
	tools/libvips/probe-freetype-wasi.sh

.PHONY: probe-fribidi-wasi
probe-fribidi-wasi: ## Probe a static FriBidi WASI build.
	tools/libvips/probe-fribidi-wasi.sh

.PHONY: probe-pixman-wasi
probe-pixman-wasi: ## Probe a static Pixman WASI build.
	tools/libvips/probe-pixman-wasi.sh

.PHONY: probe-fontconfig-wasi
probe-fontconfig-wasi: probe-expat-wasi probe-freetype-wasi ## Probe a static Fontconfig WASI build.
	tools/libvips/probe-fontconfig-wasi.sh

.PHONY: probe-harfbuzz-wasi
probe-harfbuzz-wasi: probe-freetype-wasi probe-glib-wasi ## Probe a static HarfBuzz WASI build.
	tools/libvips/probe-harfbuzz-wasi.sh

.PHONY: probe-cairo-wasi
probe-cairo-wasi: probe-expat-wasi probe-fontconfig-wasi probe-freetype-wasi probe-libpng-wasi probe-pixman-wasi probe-glib-wasi ## Probe a static Cairo WASI build.
	tools/libvips/probe-cairo-wasi.sh

.PHONY: probe-pango-wasi
probe-pango-wasi: probe-cairo-wasi probe-fontconfig-wasi probe-freetype-wasi probe-fribidi-wasi probe-harfbuzz-wasi probe-glib-wasi ## Probe a static Pango/PangoCairo WASI build.
	tools/libvips/probe-pango-wasi.sh

.PHONY: probe-libxml2-wasi
probe-libxml2-wasi: probe-iconv-wasi probe-zlib-wasi ## Probe a static libxml2 WASI build.
	tools/libvips/probe-libxml2-wasi.sh

.PHONY: probe-libcroco-wasi
probe-libcroco-wasi: probe-libxml2-wasi probe-glib-wasi ## Probe a static libcroco WASI build.
	tools/libvips/probe-libcroco-wasi.sh

.PHONY: probe-gdk-pixbuf-wasi
probe-gdk-pixbuf-wasi: probe-libjpeg-wasi probe-libpng-wasi probe-libtiff-wasi probe-glib-wasi ## Probe a static gdk-pixbuf WASI build.
	tools/libvips/probe-gdk-pixbuf-wasi.sh

.PHONY: probe-librsvg-wasi
probe-librsvg-wasi: probe-gdk-pixbuf-wasi probe-libcroco-wasi probe-libxml2-wasi probe-pango-wasi probe-cairo-wasi probe-glib-wasi ## Probe a static librsvg WASI build.
	tools/libvips/probe-librsvg-wasi.sh

.PHONY: probe-openjpeg-wasi
probe-openjpeg-wasi: probe-zlib-wasi probe-libpng-wasi probe-libtiff-wasi probe-libjpeg-wasi ## Probe a static OpenJPEG WASI build.
	tools/libvips/probe-openjpeg-wasi.sh

.PHONY: probe-sqlite-wasi
probe-sqlite-wasi: ## Probe a static SQLite WASI build.
	tools/libvips/probe-sqlite-wasi.sh

.PHONY: probe-openslide-wasi
probe-openslide-wasi: probe-openjpeg-wasi probe-sqlite-wasi probe-gdk-pixbuf-wasi probe-libxml2-wasi probe-cairo-wasi probe-glib-wasi ## Probe a static OpenSlide WASI build.
	tools/libvips/probe-openslide-wasi.sh

.PHONY: probe-matio-wasi
probe-matio-wasi: probe-zlib-wasi ## Probe a static MATIO WASI build.
	tools/libvips/probe-matio-wasi.sh

.PHONY: probe-nifti-wasi
probe-nifti-wasi: probe-zlib-wasi ## Probe a static NIfTI WASI build.
	tools/libvips/probe-nifti-wasi.sh

.PHONY: probe-lcms-wasi
probe-lcms-wasi: ## Probe a static LittleCMS WASI build.
	tools/libvips/probe-lcms-wasi.sh

.PHONY: probe-openexr-wasi
probe-openexr-wasi: probe-zlib-wasi ## Probe a static OpenEXR WASI build.
	tools/libvips/probe-openexr-wasi.sh

.PHONY: probe-libraw-wasi
probe-libraw-wasi: probe-zlib-wasi probe-lcms-wasi probe-libjpeg-wasi ## Probe a static LibRaw WASI build.
	tools/libvips/probe-libraw-wasi.sh

.PHONY: probe-highway-wasi
probe-highway-wasi: ## Probe a static Highway WASI build.
	tools/libvips/probe-highway-wasi.sh

.PHONY: probe-poppler-wasi
probe-poppler-wasi: probe-cairo-wasi probe-fontconfig-wasi probe-freetype-wasi probe-libjpeg-wasi probe-libpng-wasi probe-openjpeg-wasi probe-lcms-wasi probe-glib-wasi ## Probe a static Poppler GLib WASI build.
	tools/libvips/probe-poppler-wasi.sh

.PHONY: probe-expat-wasi
probe-expat-wasi: ## Probe a static Expat WASI build.
	tools/libvips/probe-expat-wasi.sh

.PHONY: probe-pcre2-wasi
probe-pcre2-wasi: ## Probe a static PCRE2 WASI build.
	tools/libvips/probe-pcre2-wasi.sh

.PHONY: probe-iconv-wasi
probe-iconv-wasi: ## Probe a static GNU libiconv WASI build.
	tools/libvips/probe-iconv-wasi.sh

.PHONY: probe-reset
probe-reset: ## Remove cached WASI/libvips probe builds for a clean reproduction.
	rm -rf .wasmify

.PHONY: test
test: ## Run all Go tests.
	go test ./...

.PHONY: vet
vet: ## Run go vet.
	go vet ./...

.PHONY: verify-cgo
verify-cgo: ## Verify the public package builds without cgo.
	CGO_ENABLED=0 go test ./...
	@test -z "$$(CGO_ENABLED=0 go list -deps -f '{{if .CgoFiles}}{{.ImportPath}}{{end}}' ./... | sed '/^$$/d')"

.PHONY: verify-wasm
verify-wasm: ## Verify the embedded wasm only imports WASI and wasmify callbacks.
	@test -z "$$(wasm-dis internal/vipswasm.wasm | grep '(import ' | grep -v 'wasi_snapshot_preview1' | grep -Fv '"wasmify" "callback_invoke"' | grep -Fv '"env" "__cxa_begin_catch"' | grep -Fv '"env" "__cxa_allocate_exception"' | grep -Fv '"env" "__cxa_throw"' || true)"

.PHONY: verify-no-dynamic
verify-no-dynamic: ## Verify the package does not use host dynamic library loading.
	@test -z "$$(rg -n 'dlopen|dlsym|LoadLibrary|plugin\\.Open|#cgo|import \"C\"|libvips\\.so|libvips\\.dylib|vips\\.dll' --glob '*.go' --glob '*.cc' --glob '*.h' . || true)"

.PHONY: audit-production
audit-production: probe-glib-link-wasi probe-libvips-link-wasi ## Audit whether this is the requested production libvips package.
	tools/libvips/production-audit.sh

.PHONY: verify
verify: wasm test vet verify-cgo verify-wasm verify-no-dynamic ## Rebuild wasm and run all checks.
