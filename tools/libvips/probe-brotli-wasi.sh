#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${BROTLI_VERSION:-1.1.0}"
WORK="${BROTLI_PROBE_DIR:-$ROOT/.wasmify/brotli-probe}"
SRC="$WORK/brotli-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/brotli.tar.gz" "https://github.com/google/brotli/archive/refs/tags/v$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/brotli.tar.gz"
fi

if ! grep -q "VIPSWASM_WASI_NO_BROTLI_CLI" "$SRC/CMakeLists.txt"; then
  perl -0pi -e 's/# Build the brotli executable\nadd_executable\(brotli c\/tools\/brotli\.c\)\ntarget_link_libraries\(brotli \$\{BROTLI_LIBRARIES\}\)/# VIPSWASM_WASI_NO_BROTLI_CLI\nif(NOT CMAKE_SYSTEM_NAME STREQUAL "WASI")\nadd_executable(brotli c\/tools\/brotli.c)\ntarget_link_libraries(brotli \$\{BROTLI_LIBRARIES\})\nendif()/g' "$SRC/CMakeLists.txt"
  perl -0pi -e 's/  install\(\n    TARGETS brotli\n    RUNTIME DESTINATION "\$\{CMAKE_INSTALL_BINDIR\}"\n  \)/  if(NOT CMAKE_SYSTEM_NAME STREQUAL "WASI")\n  install(\n    TARGETS brotli\n    RUNTIME DESTINATION "\${CMAKE_INSTALL_BINDIR}"\n  )\n  endif()/g' "$SRC/CMakeLists.txt"
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
  -DBUILD_SHARED_LIBS=OFF \
  -DBROTLI_DISABLE_TESTS=ON

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "$PREFIX"
