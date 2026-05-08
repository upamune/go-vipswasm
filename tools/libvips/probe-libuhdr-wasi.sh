#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBUHDR_VERSION:-1.4.0}"
WORK="${LIBUHDR_PROBE_DIR:-$ROOT/.wasmify/libuhdr-probe}"
SRC="$WORK/libultrahdr-$VERSION"
BUILD="$WORK/build"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
LIBJPEG_PREFIX="${LIBJPEG_PREFIX:-$ROOT/.wasmify/libjpeg-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi
if [[ ! -f "$LIBJPEG_PREFIX/lib/pkgconfig/libjpeg.pc" ]]; then
  echo "missing libjpeg WASI prefix at $LIBJPEG_PREFIX; run: make probe-libjpeg-wasi" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L --retry 3 -o "$WORK/libultrahdr.tar.gz" \
    "https://github.com/google/libultrahdr/archive/refs/tags/v$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/libultrahdr.tar.gz"
fi

if [[ ! -f "$WORK/.source-patched-v1" ]]; then
  perl -0pi -e 's/if\(\$\{CMAKE_SYSTEM_NAME\} MATCHES "Linux"\)/if(CMAKE_SYSTEM_NAME MATCHES "Linux")/;
                 s/elseif\(\$\{CMAKE_SYSTEM_NAME\} MATCHES "Emscripten"\)/elseif(CMAKE_SYSTEM_NAME MATCHES "Emscripten")\nelseif(CMAKE_SYSTEM_NAME MATCHES "WASI")/;
                 s/elseif\(\$\{CMAKE_SYSTEM_NAME\} MATCHES "Android"\)/elseif(CMAKE_SYSTEM_NAME MATCHES "Android")/g;
                 s/if\(\$\{CMAKE_SYSTEM_NAME\} MATCHES "Android"\)/if(CMAKE_SYSTEM_NAME MATCHES "Android")/g' \
    "$SRC/CMakeLists.txt"
  perl -0pi -e 's/else\(\)\n  message\(FATAL_ERROR "Architecture: \$\{CMAKE_SYSTEM_PROCESSOR\} not recognized"\)/elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^wasm32")\n  set(ARCH "wasm32")\nelse()\n  message(FATAL_ERROR "Architecture: ${CMAKE_SYSTEM_PROCESSOR} not recognized")/' \
    "$SRC/CMakeLists.txt"
  perl -0pi -e 's/if\(CMAKE_CROSSCOMPILING AND UHDR_ENABLE_INSTALL\)/if(FALSE AND CMAKE_CROSSCOMPILING AND UHDR_ENABLE_INSTALL)/' \
    "$SRC/CMakeLists.txt"
  touch "$WORK/.source-patched-v1"
fi

rm -rf "$BUILD"
cmake -S "$SRC" -B "$BUILD" \
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
  -DCMAKE_C_FLAGS="-mllvm -wasm-enable-sjlj ${CFLAGS:-}" \
  -DCMAKE_CXX_FLAGS="-mllvm -wasm-enable-sjlj ${CXXFLAGS:-}" \
  -DCMAKE_EXE_LINKER_FLAGS="-mllvm -wasm-enable-sjlj -lsetjmp ${LDFLAGS:-}" \
  -DCMAKE_SHARED_LINKER_FLAGS="-mllvm -wasm-enable-sjlj -lsetjmp ${LDFLAGS:-}" \
  -DCMAKE_PREFIX_PATH="$LIBJPEG_PREFIX" \
  -DBUILD_SHARED_LIBS=OFF \
  -DUHDR_BUILD_EXAMPLES=OFF \
  -DUHDR_BUILD_TESTS=OFF \
  -DUHDR_BUILD_BENCHMARK=OFF \
  -DUHDR_BUILD_FUZZERS=OFF \
  -DUHDR_BUILD_DEPS=OFF \
  -DUHDR_BUILD_JAVA=OFF \
  -DUHDR_ENABLE_INSTALL=ON \
  -DUHDR_ENABLE_INTRINSICS=OFF \
  -DUHDR_ENABLE_GLES=OFF

cmake --build "$BUILD" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

perl -0pi -e 's/Requires\.private: libjpeg/Requires.private: libjpeg/;
               s/Libs\.private: (.*)/Libs.private: $1 -lsetjmp -lc++ -lc++abi/' \
  "$PREFIX/lib/pkgconfig/libuhdr.pc"

echo "$PREFIX"
