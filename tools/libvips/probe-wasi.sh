#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
TAG="${LIBVIPS_TAG:-v8.18.2}"
WORK="${LIBVIPS_PROBE_DIR:-$ROOT/.wasmify/libvips-probe}"
SRC="${LIBVIPS_SRC:-$WORK/libvips}"
BUILD="$WORK/build"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
EXPAT_PREFIX="${EXPAT_PREFIX:-$ROOT/.wasmify/expat-probe/prefix}"
GLIB_BUILD="${GLIB_BUILD:-$ROOT/.wasmify/glib-probe/build}"
GLIB_STUB_INCLUDE="${GLIB_STUB_INCLUDE:-$ROOT/.wasmify/glib-probe/wasi-stubs/include}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"
PCRE2_PREFIX="${PCRE2_PREFIX:-$ROOT/.wasmify/pcre2-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"
LIBPNG_PREFIX="${LIBPNG_PREFIX:-$ROOT/.wasmify/libpng-probe/prefix}"
LIBJPEG_PREFIX="${LIBJPEG_PREFIX:-$ROOT/.wasmify/libjpeg-probe/prefix}"
LIBWEBP_PREFIX="${LIBWEBP_PREFIX:-$ROOT/.wasmify/libwebp-probe/prefix}"
LIBTIFF_PREFIX="${LIBTIFF_PREFIX:-$ROOT/.wasmify/libtiff-probe/prefix}"
LIBDE265_PREFIX="${LIBDE265_PREFIX:-$ROOT/.wasmify/libde265-probe/prefix}"
LIBHEIF_PREFIX="${LIBHEIF_PREFIX:-$ROOT/.wasmify/libheif-probe/prefix}"
VIPSWASM_LIBVIPS_PRESET="${VIPSWASM_LIBVIPS_PRESET:-minimal}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC/.git" ]]; then
  git clone --depth 1 --branch "$TAG" https://github.com/libvips/libvips "$SRC"
fi

# libvips always compiles the foreign source list, even when individual
# external codec features are disabled. Keep disabled JPEG sources away from
# WASI setjmp.h; enabling JPEG for production will need a real SJLJ strategy.
perl -0pi -e 's/#include <setjmp\.h>\n\n#include <vips\/vips\.h>/#ifdef HAVE_JPEG\n#include <setjmp.h>\n#endif\n\n#include <vips\/vips.h>/' \
  "$SRC/libvips/foreign/jpegload.c" \
  "$SRC/libvips/foreign/jpegsave.c"

# libpng is built for WASI without setjmp support. Keep the normal libvips PNG
# error handling on native targets, but avoid png_jmpbuf() references under WASI
# so valid PNG load/save paths can use libpng without requiring SJLJ support.
if ! grep -q "VIPS_WASI_PNG_SETJMP_FAILED" "$SRC/libvips/foreign/vipspng.c"; then
  perl -0pi -e 's/#include <png\.h>/#include <png.h>\n\n#ifdef __wasi__\n#define VIPS_WASI_PNG_SETJMP_FAILED(png_ptr) 0\n#define VIPS_WASI_PNG_SETJMP_OK(png_ptr) 1\n#else\n#define VIPS_WASI_PNG_SETJMP_FAILED(png_ptr) setjmp(png_jmpbuf(png_ptr))\n#define VIPS_WASI_PNG_SETJMP_OK(png_ptr) !setjmp(png_jmpbuf(png_ptr))\n#endif/' \
    "$SRC/libvips/foreign/vipspng.c"
  perl -0pi -e 's/longjmp\(png_jmpbuf\(png_ptr\), -1\);/#ifdef __wasi__\n\tfprintf(stderr, "libpng fatal error: %s\\n", error_msg);\n\tabort();\n#else\n\tlongjmp(png_jmpbuf(png_ptr), -1);\n#endif/' \
    "$SRC/libvips/foreign/vipspng.c"
  perl -0pi -e 's/!setjmp\(png_jmpbuf\(([^)]+)\)\)/VIPS_WASI_PNG_SETJMP_OK($1)/g; s/setjmp\(png_jmpbuf\(([^)]+)\)\)/VIPS_WASI_PNG_SETJMP_FAILED($1)/g' \
    "$SRC/libvips/foreign/vipspng.c"
fi
if ! grep -q "defined(HAVE_POSIX_MEMALIGN) || defined(__wasi__)" "$SRC/libvips/conversion/composite.cpp"; then
  perl -0pi -e 's/defined\(HAVE_POSIX_MEMALIGN\)/defined(HAVE_POSIX_MEMALIGN) || defined(__wasi__)/g' \
    "$SRC/libvips/conversion/composite.cpp" \
    "$SRC/libvips/iofuncs/memory.c"
fi
if ! grep -q "vips_threadpool_run_wasi_inline" "$SRC/libvips/iofuncs/threadpool.c"; then
  perl -0pi -e 's/(\tpool->a = a;\n)/$1\n#ifdef __wasi__\n\t{\n\t\tVipsWorker worker = { pool, NULL, FALSE };\n\n\t\tg_private_set(&worker_key, &worker);\n\t\twhile (!pool->stop &&\n\t\t\t!worker.stop &&\n\t\t\t!pool->error) {\n\t\t\tVIPS_GATE_START("vips_threadpool_run_wasi_inline");\n\t\t\tvips_worker_work_unit(&worker);\n\t\t\tVIPS_GATE_STOP("vips_threadpool_run_wasi_inline");\n\n\t\t\tif (pool->stop ||\n\t\t\t\tworker.stop ||\n\t\t\t\tpool->error)\n\t\t\t\tbreak;\n\n\t\t\tif (progress &&\n\t\t\t\tprogress(pool->a))\n\t\t\t\tpool->error = TRUE;\n\t\t}\n\n\t\tg_mutex_lock(&pool->allocate_lock);\n\t\tVIPS_FREEF(g_object_unref, worker.state);\n\t\tg_mutex_unlock(&pool->allocate_lock);\n\t\tg_private_set(&worker_key, NULL);\n\n\t\tresult = pool->error ? -1 : 0;\n\t\tvips_threadpool_free(pool);\n\n\t\tif (!vips_image_get_typeof(im, "vips-no-minimise"))\n\t\t\tvips_image_minimise_all(im);\n\n\t\treturn result;\n\t}\n#endif\n/' "$SRC/libvips/iofuncs/threadpool.c"
fi

cross="$WORK/wasi-cross.ini"
sed \
  -e "s|@WASI_SDK@|$WASI_SDK_PATH|g" \
  -e "s|@ROOT@|$ROOT|g" \
  "$ROOT/tools/libvips/wasi-cross.ini" > "$cross"
GLIB_STUB_INCLUDE="$GLIB_STUB_INCLUDE" perl -0pi -e 'my $inc = $ENV{"GLIB_STUB_INCLUDE"}; s#c_args = \[([^\]]*)\]#c_args = [$1, '\''-I$inc'\'']#' "$cross"
GLIB_STUB_INCLUDE="$GLIB_STUB_INCLUDE" perl -0pi -e 'my $inc = $ENV{"GLIB_STUB_INCLUDE"}; s#cpp_args = \[([^\]]*)\]#cpp_args = [$1, '\''-I$inc'\'']#' "$cross"

pkg_config_paths=("$EXPAT_PREFIX/lib/pkgconfig")
if [[ -d "$GLIB_BUILD/meson-uninstalled" ]]; then
  pkg_config_paths=(
    "$GLIB_BUILD/meson-uninstalled"
    "$GLIB_BUILD/meson-private"
    "$ZLIB_PREFIX/lib/pkgconfig"
    "$LIBPNG_PREFIX/lib/pkgconfig"
    "$LIBJPEG_PREFIX/lib/pkgconfig"
    "$LIBWEBP_PREFIX/lib/pkgconfig"
    "$LIBTIFF_PREFIX/lib/pkgconfig"
    "$LIBDE265_PREFIX/lib/pkgconfig"
    "$LIBHEIF_PREFIX/lib/pkgconfig"
    "$PCRE2_PREFIX/lib/pkgconfig"
    "$ICONV_PREFIX/lib/pkgconfig"
    "${pkg_config_paths[@]}"
  )
fi

export PKG_CONFIG_PATH="$(IFS=:; echo "${pkg_config_paths[*]}"):${PKG_CONFIG_PATH:-}"
export CFLAGS="-I$EXPAT_PREFIX/include -I$LIBPNG_PREFIX/include -I$LIBJPEG_PREFIX/include -I$LIBWEBP_PREFIX/include -I$LIBTIFF_PREFIX/include -I$LIBDE265_PREFIX/include -I$LIBHEIF_PREFIX/include -I$GLIB_STUB_INCLUDE ${CFLAGS:-}"
export CXXFLAGS="-I$EXPAT_PREFIX/include -I$LIBPNG_PREFIX/include -I$LIBJPEG_PREFIX/include -I$LIBWEBP_PREFIX/include -I$LIBTIFF_PREFIX/include -I$LIBDE265_PREFIX/include -I$LIBHEIF_PREFIX/include -I$GLIB_STUB_INCLUDE ${CXXFLAGS:-}"
export LDFLAGS="-L$EXPAT_PREFIX/lib -L$LIBPNG_PREFIX/lib -L$LIBJPEG_PREFIX/lib -L$LIBWEBP_PREFIX/lib -L$LIBTIFF_PREFIX/lib -L$LIBDE265_PREFIX/lib -L$LIBHEIF_PREFIX/lib -L$ZLIB_PREFIX/lib -L$PCRE2_PREFIX/lib -L$ICONV_PREFIX/lib ${LDFLAGS:-}"

feature_args=(
  -Dpng=enabled
  -Dzlib=enabled
)

case "$VIPSWASM_LIBVIPS_PRESET" in
  minimal)
    feature_args+=(
      -Djpeg=disabled
      -Dwebp=disabled
      -Dtiff=disabled
    )
    ;;
  default)
    feature_args+=(
      -Dheif=enabled
      -Djpeg=disabled
      -Dtiff=enabled
      -Dwebp=enabled
    )
    ;;
  full)
    feature_args+=(
      -Darchive=enabled
      -Dcfitsio=enabled
      -Dcgif=enabled
      -Dexif=enabled
      -Dfftw=enabled
      -Dfontconfig=enabled
      -Dheif=enabled
      -Dhighway=enabled
      -Dimagequant=enabled
      -Djpeg=enabled
      -Djpeg-xl=enabled
      -Dlcms=enabled
      -Dmagick=enabled
      -Dmatio=enabled
      -Dnifti=enabled
      -Dopenexr=enabled
      -Dopenjpeg=enabled
      -Dopenslide=enabled
      -Dorc=enabled
      -Dpangocairo=enabled
      -Dpdfium=enabled
      -Dpoppler=enabled
      -Dquantizr=enabled
      -Draw=enabled
      -Drsvg=enabled
      -Dspng=enabled
      -Dtiff=enabled
      -Duhdr=enabled
      -Dwebp=enabled
    )
    ;;
  *)
    echo "unknown VIPSWASM_LIBVIPS_PRESET=$VIPSWASM_LIBVIPS_PRESET; expected minimal, default, or full" >&2
    exit 2
    ;;
esac

rm -rf "$BUILD"
meson setup "$BUILD" "$SRC" \
  --cross-file "$cross" \
  --default-library=static \
  --buildtype=release \
  --wrap-mode=nofallback \
  --auto-features=disabled \
  -Dmodules=disabled \
  -Dintrospection=disabled \
  -Dcplusplus=false \
  -Ddeprecated=false \
  -Dexamples=false \
  -Ddocs=false \
  -Dcpp-docs=false \
  -Dvapi=false \
  "${feature_args[@]}"

ninja -C "$BUILD" libvips/libvips.a

echo "$BUILD/libvips/libvips.a"
