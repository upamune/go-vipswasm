#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${POPPLER_VERSION:-24.12.0}"
WORK="${POPPLER_PROBE_DIR:-$ROOT/.wasmify/poppler-probe}"
SRC="$WORK/poppler-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
EXPAT_PREFIX="${EXPAT_PREFIX:-$ROOT/.wasmify/expat-probe/prefix}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"
LIBJPEG_PREFIX="${LIBJPEG_PREFIX:-$ROOT/.wasmify/libjpeg-probe/prefix}"
LIBPNG_PREFIX="${LIBPNG_PREFIX:-$ROOT/.wasmify/libpng-probe/prefix}"
OPENJPEG_PREFIX="${OPENJPEG_PREFIX:-$ROOT/.wasmify/openjpeg-probe/prefix}"
LCMS_PREFIX="${LCMS_PREFIX:-$ROOT/.wasmify/lcms-probe/prefix}"
FREETYPE_PREFIX="${FREETYPE_PREFIX:-$ROOT/.wasmify/freetype-probe/prefix}"
FONTCONFIG_PREFIX="${FONTCONFIG_PREFIX:-$ROOT/.wasmify/fontconfig-probe/prefix}"
PIXMAN_PREFIX="${PIXMAN_PREFIX:-$ROOT/.wasmify/pixman-probe/prefix}"
CAIRO_PREFIX="${CAIRO_PREFIX:-$ROOT/.wasmify/cairo-probe/prefix}"
GLIB_BUILD="${GLIB_BUILD:-$ROOT/.wasmify/glib-probe/build}"
PCRE2_PREFIX="${PCRE2_PREFIX:-$ROOT/.wasmify/pcre2-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/poppler.tar.xz" "https://poppler.freedesktop.org/poppler-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/poppler.tar.xz"
fi

if ! grep -q "VIPSWASM_WASI_NO_PWD_H" "$SRC/goo/gfile.cc"; then
  perl -0pi -e 's/#    include <pwd\.h>/#    ifndef __wasi__\n#        include <pwd.h>\n#    endif\n\/\/ VIPSWASM_WASI_NO_PWD_H/' \
    "$SRC/goo/gfile.cc"
fi
if ! grep -q "#define VIPSWASM_WASI_PNG_SETJMP_FAILED" "$SRC/goo/PNGWriter.cc"; then
  perl -0pi -e 's/#\s*include <png\.h>/#    include <png.h>\n\n#if defined(__wasi__) && !defined(PNG_SETJMP_SUPPORTED)\n#define VIPSWASM_WASI_PNG_SETJMP_FAILED(png_ptr) 0\n#else\n#define VIPSWASM_WASI_PNG_SETJMP_FAILED(png_ptr) setjmp(png_jmpbuf(png_ptr))\n#endif/' \
    "$SRC/goo/PNGWriter.cc"
fi
if grep -q "setjmp(png_jmpbuf" "$SRC/goo/PNGWriter.cc"; then
  perl -0pi -e 's/setjmp\(png_jmpbuf\(([^)]+)\)\)/VIPSWASM_WASI_PNG_SETJMP_FAILED($1)/g' \
    "$SRC/goo/PNGWriter.cc"
fi
if ! grep -q "#define VIPSWASM_WASI_PNG_SETJMP_FAILED" "$SRC/poppler/ImageEmbeddingUtils.cc"; then
  perl -0pi -e 's/#\s*include <png\.h>/#    include <png.h>\n\n#if defined(__wasi__) && !defined(PNG_SETJMP_SUPPORTED)\n#define VIPSWASM_WASI_PNG_SETJMP_FAILED(png_ptr) 0\n#else\n#define VIPSWASM_WASI_PNG_SETJMP_FAILED(png_ptr) setjmp(png_jmpbuf(png_ptr))\n#endif/' \
    "$SRC/poppler/ImageEmbeddingUtils.cc"
fi
if grep -q "setjmp(png_jmpbuf" "$SRC/poppler/ImageEmbeddingUtils.cc"; then
  perl -0pi -e 's/setjmp\(png_jmpbuf\(([^)]+)\)\)/VIPSWASM_WASI_PNG_SETJMP_FAILED($1)/g' \
    "$SRC/poppler/ImageEmbeddingUtils.cc"
fi

mkdir -p "$GLIB_BUILD/lib/glib-2.0"
if [[ ! -e "$GLIB_BUILD/lib/glib-2.0/include" ]]; then
  ln -s "$GLIB_BUILD/glib" "$GLIB_BUILD/lib/glib-2.0/include"
fi

pkg_config_paths=(
  "$GLIB_BUILD/meson-uninstalled"
  "$GLIB_BUILD/meson-private"
  "$CAIRO_PREFIX/lib/pkgconfig"
  "$FONTCONFIG_PREFIX/lib/pkgconfig"
  "$FREETYPE_PREFIX/lib/pkgconfig"
  "$PIXMAN_PREFIX/lib/pkgconfig"
  "$LIBPNG_PREFIX/lib/pkgconfig"
  "$LIBJPEG_PREFIX/lib/pkgconfig"
  "$OPENJPEG_PREFIX/lib/pkgconfig"
  "$LCMS_PREFIX/lib/pkgconfig"
  "$ZLIB_PREFIX/lib/pkgconfig"
  "$EXPAT_PREFIX/lib/pkgconfig"
  "$PCRE2_PREFIX/lib/pkgconfig"
  "$ICONV_PREFIX/lib/pkgconfig"
)

export PKG_CONFIG_PATH="$(IFS=:; echo "${pkg_config_paths[*]}"):${PKG_CONFIG_PATH:-}"

cmake -S "$SRC" -B "$WORK/build" \
  -DCMAKE_SYSTEM_NAME=WASI \
  -DCMAKE_SYSTEM_PROCESSOR=wasm32 \
  -DCMAKE_C_COMPILER="$ROOT/tools/libvips/wasi-clang-filter.sh" \
  -DCMAKE_C_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_CXX_COMPILER="$ROOT/tools/libvips/wasi-clang-filter.sh" \
  -DCMAKE_CXX_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_AR="$WASI_SDK_PATH/bin/llvm-ar" \
  -DCMAKE_RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$CAIRO_PREFIX;$FONTCONFIG_PREFIX;$FREETYPE_PREFIX;$LIBJPEG_PREFIX;$LIBPNG_PREFIX;$OPENJPEG_PREFIX;$LCMS_PREFIX;$ZLIB_PREFIX;$EXPAT_PREFIX;$ICONV_PREFIX" \
  -DCMAKE_C_FLAGS="-mno-atomics -mllvm -wasm-enable-sjlj -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID -D_WASI_EMULATED_SIGNAL" \
  -DCMAKE_CXX_FLAGS="-mno-atomics -mllvm -wasm-enable-sjlj -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID -D_WASI_EMULATED_SIGNAL" \
  -DCMAKE_EXE_LINKER_FLAGS="-mllvm -wasm-enable-sjlj -lwasi-emulated-process-clocks -lwasi-emulated-getpid -lwasi-emulated-signal -lsetjmp" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_GTK_TESTS=OFF \
  -DBUILD_QT5_TESTS=OFF \
  -DBUILD_QT6_TESTS=OFF \
  -DBUILD_CPP_TESTS=OFF \
  -DBUILD_MANUAL_TESTS=OFF \
  -DENABLE_BOOST=OFF \
  -DENABLE_UTILS=OFF \
  -DENABLE_CPP=OFF \
  -DENABLE_GLIB=ON \
  -DENABLE_GOBJECT_INTROSPECTION=OFF \
  -DENABLE_GTK_DOC=OFF \
  -DENABLE_QT5=OFF \
  -DENABLE_QT6=OFF \
  -DENABLE_LIBOPENJPEG=openjpeg2 \
  -DENABLE_DCTDECODER=libjpeg \
  -DENABLE_LCMS=ON \
  -DENABLE_LIBCURL=OFF \
  -DENABLE_LIBTIFF=OFF \
  -DENABLE_NSS3=OFF \
  -DENABLE_GPGME=OFF \
  -DENABLE_ZLIB_UNCOMPRESS=ON \
  -DRUN_GPERF_IF_PRESENT=OFF \
  -DINSTALL_GLIB_DEMO=OFF

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

  perl -0pi -e 's/Libs:([^\n]*)\n/Libs:$1\nLibs.private: -lc++ -lc++abi -lwasi-emulated-process-clocks -lwasi-emulated-getpid -lwasi-emulated-signal -lsetjmp\n/' \
  "$PREFIX/lib/pkgconfig/poppler.pc" \
  "$PREFIX/lib/pkgconfig/poppler-glib.pc"

echo "$PREFIX"
