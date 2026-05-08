#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${MATIO_VERSION:-1.5.28}"
WORK="${MATIO_PROBE_DIR:-$ROOT/.wasmify/matio-probe}"
SRC="$WORK/matio-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/matio.tar.gz" "https://github.com/tbeu/matio/releases/download/v$VERSION/matio-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/matio.tar.gz"
fi

cd "$SRC"

stub="$WORK/vipswasm-matio-wasi.h"
cat > "$stub" <<'STUB'
#include <errno.h>
static inline char *
vipswasm_matio_mkdtemp(char *template)
{
  (void) template;
  errno = ENOSYS;
  return 0;
}
#define mkdtemp vipswasm_matio_mkdtemp
STUB

export PKG_CONFIG_PATH="$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CC="$ROOT/tools/libvips/wasi-clang-filter.sh --target=wasm32-wasip1"
export AR="$WASI_SDK_PATH/bin/ar"
export RANLIB="$WASI_SDK_PATH/bin/ranlib"
export CFLAGS="-mno-atomics -include $stub -I$ZLIB_PREFIX/include ${CFLAGS:-}"
export LDFLAGS="-L$ZLIB_PREFIX/lib ${LDFLAGS:-}"
export ac_cv_va_copy=C99

./configure \
  --host=wasm32-unknown-none \
  --prefix="$PREFIX" \
  --disable-shared \
  --enable-static \
  --disable-mat73 \
  --with-zlib="$ZLIB_PREFIX"

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install

echo "$PREFIX"
