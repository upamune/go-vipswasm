#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBHEIF_VERSION:-1.20.2}"
WORK="${LIBHEIF_PROBE_DIR:-$ROOT/.wasmify/libheif-probe}"
SRC="$WORK/libheif-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
LIBDE265_PREFIX="${LIBDE265_PREFIX:-$ROOT/.wasmify/libde265-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libheif.tar.gz" "https://github.com/strukturag/libheif/releases/download/v$VERSION/libheif-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/libheif.tar.gz"
fi

if ! grep -q "VIPSWASM_WASI_NO_MKSTEMP" "$SRC/libheif/box.cc"; then
  perl -0pi -e 's/void Box_iloc::set_use_tmp_file\(bool flag\)\n\{\n  m_use_tmpfile = flag;\n  if \(flag\) \{/void Box_iloc::set_use_tmp_file(bool flag)\n{\n  m_use_tmpfile = flag;\n  if (flag) {\n#if defined(__wasi__)\n    \/\/ VIPSWASM_WASI_NO_MKSTEMP: HEIF decoding does not need this writing-only tmpfile path.\n    m_use_tmpfile = false;\n    return;\n#endif/' "$SRC/libheif/box.cc"
fi
perl -0pi -e 's/#if !defined\(_WIN32\)\n    strcpy\(m_tmp_filename, "\/tmp\/libheif-XXXXXX"\);\n    m_tmpfile_fd = mkstemp\(m_tmp_filename\);/#if !defined(_WIN32) \&\& !defined(__wasi__)\n    strcpy(m_tmp_filename, "\/tmp\/libheif-XXXXXX");\n    m_tmpfile_fd = mkstemp(m_tmp_filename);/' "$SRC/libheif/box.cc"
if ! grep -q "VIPSWASM_WASI_LIBDE265_SINGLE_THREAD" "$SRC/libheif/plugins/decoder_libde265.cc"; then
  perl -0pi -e 's/#if defined\(__EMSCRIPTEN__\)/#if defined(__EMSCRIPTEN__) || defined(__wasi__)\n  \/\/ VIPSWASM_WASI_LIBDE265_SINGLE_THREAD: worker threads are unavailable in the embedded WASI runtime./' "$SRC/libheif/plugins/decoder_libde265.cc"
fi
if ! grep -q "VIPSWASM_WASI_LIBHEIF_SINGLE_THREAD" "$SRC/libheif/context.h"; then
  perl -0pi -e 's/int m_max_decoding_threads = 4;/\/\/ VIPSWASM_WASI_LIBHEIF_SINGLE_THREAD: decode tiles in the main thread under WASI.\n#if defined(__wasi__)\n  int m_max_decoding_threads = 0;\n#else\n  int m_max_decoding_threads = 4;\n#endif/' "$SRC/libheif/context.h"
fi

export PKG_CONFIG_PATH="$LIBDE265_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
cmake -S "$SRC" -B "$WORK/build" \
  -DCMAKE_SYSTEM_NAME=WASI \
  -DCMAKE_SYSTEM_PROCESSOR=wasm32 \
  -DCMAKE_C_COMPILER="$WASI_SDK_PATH/bin/clang" \
  -DCMAKE_C_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_CXX_COMPILER="$WASI_SDK_PATH/bin/clang++" \
  -DCMAKE_CXX_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_AR="$WASI_SDK_PATH/bin/llvm-ar" \
  -DCMAKE_RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$LIBDE265_PREFIX" \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_PLUGIN_LOADING=OFF \
  -DWITH_LIBDE265=ON \
  -DWITH_AOM_DECODER=OFF \
  -DWITH_AOM_ENCODER=OFF \
  -DWITH_DAV1D=OFF \
  -DWITH_RAV1E=OFF \
  -DWITH_SvtEnc=OFF \
  -DWITH_X265=OFF \
  -DWITH_EXAMPLES=OFF \
  -DWITH_EXAMPLE_HEIF_VIEW=OFF \
  -DWITH_GDK_PIXBUF=OFF \
  -DENABLE_MULTITHREADING_SUPPORT=OFF \
  -DENABLE_PARALLEL_TILE_DECODING=OFF \
  -DBUILD_TESTING=OFF \
  -DBUILD_EXAMPLES=OFF

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "$PREFIX"
