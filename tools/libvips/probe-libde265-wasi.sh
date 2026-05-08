#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBDE265_VERSION:-1.0.16}"
WORK="${LIBDE265_PROBE_DIR:-$ROOT/.wasmify/libde265-probe}"
SRC="$WORK/libde265-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libde265.tar.gz" "https://github.com/strukturag/libde265/releases/download/v$VERSION/libde265-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/libde265.tar.gz"
fi

if ! grep -q "VIPSWASM_WASI_NO_ENCODER_OBJECTS" "$SRC/libde265/CMakeLists.txt"; then
  perl -0pi -e 's/add_subdirectory \(encoder\)/# VIPSWASM_WASI_NO_ENCODER_OBJECTS\nif (NOT CMAKE_SYSTEM_NAME STREQUAL "WASI")\n  add_subdirectory (encoder)\nendif()/' "$SRC/libde265/CMakeLists.txt"
fi
if ! grep -q "VIPSWASM_WASI_NO_PTHREAD_TYPES" "$SRC/libde265/threads.h"; then
  perl -0pi -e 's/#ifndef _WIN32\n#include <pthread.h>\n\n/#if defined(__wasi__)\n\/\/ VIPSWASM_WASI_NO_PTHREAD_TYPES: static HEIC decoding runs single-threaded under WASI.\ntypedef int de265_thread;\ntypedef int de265_mutex;\ntypedef int de265_cond;\n#elif !defined(_WIN32)\n#include <pthread.h>\n\n/' "$SRC/libde265/threads.h"
fi
if ! grep -q "VIPSWASM_WASI_NO_PTHREAD_IMPL" "$SRC/libde265/threads.cc"; then
  perl -0pi -e 's/#ifndef _WIN32\n\/\/ #include <intrin.h>/#if defined(__wasi__)\n\/\/ VIPSWASM_WASI_NO_PTHREAD_IMPL: no-op synchronization for single-threaded WASI decode.\n#define THREAD_RESULT_TYPE  void*\n#define THREAD_PARAM_TYPE   void*\n#define THREAD_CALLING_CONVENTION\n\nint  de265_thread_create(de265_thread* t, void *(*start_routine) (void *), void *arg) { (void)t; (void)start_routine; (void)arg; return -1; }\nvoid de265_thread_join(de265_thread t) { (void)t; }\nvoid de265_thread_destroy(de265_thread* t) { (void)t; }\nvoid de265_mutex_init(de265_mutex* m) { if (m) *m = 0; }\nvoid de265_mutex_destroy(de265_mutex* m) { (void)m; }\nvoid de265_mutex_lock(de265_mutex* m) { (void)m; }\nvoid de265_mutex_unlock(de265_mutex* m) { (void)m; }\nvoid de265_cond_init(de265_cond* c) { if (c) *c = 0; }\nvoid de265_cond_destroy(de265_cond* c) { (void)c; }\nvoid de265_cond_broadcast(de265_cond* c,de265_mutex* m) { (void)c; (void)m; }\nvoid de265_cond_wait(de265_cond* c,de265_mutex* m) { (void)c; (void)m; }\nvoid de265_cond_signal(de265_cond* c) { (void)c; }\n#elif !defined(_WIN32)\n\/\/ #include <intrin.h>/' "$SRC/libde265/threads.cc"
fi
if ! grep -q "VIPSWASM_WASI_PROGRESS_WAIT" "$SRC/libde265/threads.cc"; then
  perl -0pi -e 's/void de265_progress_lock::wait_for_progress\(int progress\)\n\{/void de265_progress_lock::wait_for_progress(int progress)\n{\n#if defined(__wasi__)\n  \/\/ VIPSWASM_WASI_PROGRESS_WAIT: no background workers exist, so do not block.\n  if (mProgress < progress) {\n    mProgress = progress;\n  }\n  return;\n#endif/' "$SRC/libde265/threads.cc"
fi
if ! grep -q "VIPSWASM_WASI_COMPLETION_WAIT" "$SRC/libde265/image.cc"; then
  perl -0pi -e 's/void de265_image::wait_for_completion\(\)\n\{/void de265_image::wait_for_completion()\n{\n#if defined(__wasi__)\n  \/\/ VIPSWASM_WASI_COMPLETION_WAIT: single-threaded decode has no worker completion signal.\n  nThreadsFinished = nThreadsTotal;\n  return;\n#endif/' "$SRC/libde265/image.cc"
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
  -DCMAKE_C_FLAGS="-D_WASI_EMULATED_SIGNAL" \
  -DCMAKE_CXX_FLAGS="-D_WASI_EMULATED_SIGNAL -fno-exceptions" \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_DECODER=OFF \
  -DENABLE_ENCODER=OFF \
  -DENABLE_SDL=OFF

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "$PREFIX"
