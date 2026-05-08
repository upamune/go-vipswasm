#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${CFITSIO_VERSION:-4.6.4}"
TAG="${CFITSIO_TAG:-cfitsio-$VERSION}"
WORK="${CFITSIO_PROBE_DIR:-$ROOT/.wasmify/cfitsio-probe}"
SRC="$WORK/cfitsio-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L --retry 3 -o "$WORK/cfitsio.tar.gz" \
    "https://github.com/HEASARC/cfitsio/archive/refs/tags/$TAG.tar.gz"
  mkdir -p "$SRC"
  tar -C "$SRC" --strip-components=1 -xf "$WORK/cfitsio.tar.gz"
fi

# libvips uses the C API only. The Fortran compatibility wrappers depend on
# cfortran.h platform conventions that do not define a WASI ABI.
perl -0pi -e 's/\s*f77_wrap1\.c f77_wrap2\.c f77_wrap3\.c f77_wrap4\.c//g' \
  "$SRC/CMakeLists.txt"

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
  -DCMAKE_C_FLAGS="-D_WASI_EMULATED_PROCESS_CLOCKS" \
  -DCMAKE_EXE_LINKER_FLAGS="-lwasi-emulated-process-clocks" \
  -DM_LIB="" \
  -DBUILD_SHARED_LIBS=OFF \
  -DUSE_PTHREADS=OFF \
  -DUSE_BZIP2=OFF \
  -DUSE_CURL=OFF \
  -DZLIB_INCLUDE_DIR="$ZLIB_PREFIX/include" \
  -DZLIB_LIBRARY="$ZLIB_PREFIX/lib/libz.a"

cmake --build "$WORK/build" --target cfitsio --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

mkdir -p "$PREFIX/include" "$PREFIX/lib"
cp -f "$WORK/build/libcfitsio.a" "$PREFIX/lib/"
"$WASI_SDK_PATH/bin/llvm-ranlib" "$PREFIX/lib/libcfitsio.a"
cp -f "$SRC"/*.h "$PREFIX/include/"
mkdir -p "$PREFIX/lib/pkgconfig"
cat > "$PREFIX/lib/pkgconfig/cfitsio.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: cfitsio
Description: FITS file subroutine library
Version: $VERSION
Libs: -L\${libdir} -lcfitsio -L$ZLIB_PREFIX/lib -lz -lwasi-emulated-process-clocks
Cflags: -I\${includedir}
EOF

echo "$PREFIX"
