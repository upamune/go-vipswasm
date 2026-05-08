#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${OPENEXR_VERSION:-3.2.4}"
WORK="${OPENEXR_PROBE_DIR:-$ROOT/.wasmify/openexr-probe}"
SRC="$WORK/openexr-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/openexr.tar.gz" "https://github.com/AcademySoftwareFoundation/openexr/archive/refs/tags/v$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/openexr.tar.gz"
fi

if ! grep -q "VIPSWASM_WASI_NO_WEBSITE_SRC" "$SRC/CMakeLists.txt"; then
  perl -0pi -e 's/if \(OPENEXR_BUILD_LIBS AND NOT OPENEXR_IS_SUBPROJECT\)\n  # Even if not building the website, still make sure the website example code compiles\.\n  add_subdirectory\(website\/src\)\nendif\(\)/if (OPENEXR_BUILD_LIBS AND NOT OPENEXR_IS_SUBPROJECT)\n  # VIPSWASM_WASI_NO_WEBSITE_SRC: website examples require mmap and are not part of the installed libraries.\nendif()/g' \
    "$SRC/CMakeLists.txt"
fi

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
  -DCMAKE_PREFIX_PATH="$ZLIB_PREFIX" \
  -DCMAKE_C_FLAGS="-mno-atomics -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_GETPID" \
  -DCMAKE_CXX_FLAGS="-mno-atomics -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_GETPID" \
  -DCMAKE_EXE_LINKER_FLAGS="-lwasi-emulated-signal -lwasi-emulated-getpid" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DOPENEXR_BUILD_TOOLS=OFF \
  -DOPENEXR_INSTALL_TOOLS=OFF \
  -DOPENEXR_BUILD_EXAMPLES=OFF \
  -DOPENEXR_BUILD_PYTHON=OFF \
  -DOPENEXR_INSTALL_DOCS=OFF \
  -DOPENEXR_TEST_LIBRARIES=OFF \
  -DOPENEXR_TEST_TOOLS=OFF \
  -DOPENEXR_TEST_PYTHON=OFF \
  -DOPENEXR_ENABLE_THREADING=OFF \
  -DOPENEXR_FORCE_INTERNAL_IMATH=ON \
  -DOPENEXR_FORCE_INTERNAL_DEFLATE=OFF

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

perl -0pi -e 's/Libs:([^\n]*)\nCflags:/Libs:$1\nLibs.private: -lc++ -lc++abi -lwasi-emulated-signal -lwasi-emulated-getpid\nCflags:/' \
  "$PREFIX/lib/pkgconfig/OpenEXR.pc"

echo "$PREFIX"
