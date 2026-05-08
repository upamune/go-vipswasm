#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${NIFTI_VERSION:-3.0.1}"
WORK="${NIFTI_PROBE_DIR:-$ROOT/.wasmify/nifti-probe}"
SRC="$WORK/nifti_clib-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/nifti.tar.gz" "https://github.com/NIFTI-Imaging/nifti_clib/archive/refs/tags/v$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/nifti.tar.gz"
fi

cmake -S "$SRC" -B "$WORK/build" \
  -DCMAKE_SYSTEM_NAME=WASI \
  -DCMAKE_SYSTEM_PROCESSOR=wasm32 \
  -DCMAKE_C_COMPILER="$WASI_SDK_PATH/bin/clang" \
  -DCMAKE_C_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_AR="$WASI_SDK_PATH/bin/llvm-ar" \
  -DCMAKE_RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-I$ZLIB_PREFIX/include" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DNIFTI_BUILD_TESTING=OFF \
  -DNIFTI_BUILD_APPLICATIONS=OFF \
  -DNIFTI_INSTALL_NO_DOCS=ON \
  -DUSE_NIFTICDF_CODE=OFF \
  -DUSE_NIFTI2_CODE=OFF \
  -DUSE_FSL_CODE=OFF \
  -DNIFTI_SYSTEM_MATH_LIB=m \
  -DNIFTI_ZLIB_LIBRARIES="$ZLIB_PREFIX/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$ZLIB_PREFIX/include" \
  -DZLIB_LIBRARY="$ZLIB_PREFIX/lib/libz.a"

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

mkdir -p "$PREFIX/lib/pkgconfig"
cat >"$PREFIX/lib/pkgconfig/niftiio.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include/nifti

Name: niftiio
Description: Core i/o routines for reading and writing nifti-1 format files
Version: $VERSION
Requires.private: zlib
Libs: -L\${libdir} -lniftiio -lznz
Cflags: -I\${includedir}
EOF

echo "$PREFIX"
