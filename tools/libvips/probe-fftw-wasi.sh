#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${FFTW_VERSION:-3.3.10}"
WORK="${FFTW_PROBE_DIR:-$ROOT/.wasmify/fftw-probe}"
SRC="$WORK/fftw-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl --retry 5 --retry-delay 2 -L -o "$WORK/fftw.tar.gz" "http://www.fftw.org/fftw-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/fftw.tar.gz"
fi

cd "$SRC"
if [[ ! -f Makefile ]]; then
  CC="$WASI_SDK_PATH/bin/clang --target=wasm32-wasip1" \
  AR="$WASI_SDK_PATH/bin/llvm-ar" \
  RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  ./configure \
    --host=wasm32-unknown-none \
    --prefix="$PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-fortran \
    --disable-threads \
    --disable-openmp \
    --disable-doc \
    --with-our-malloc16
fi

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install

echo "$PREFIX"
