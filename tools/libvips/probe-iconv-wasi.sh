#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBICONV_VERSION:-1.18}"
WORK="${LIBICONV_PROBE_DIR:-$ROOT/.wasmify/iconv-probe}"
SRC="$WORK/libiconv-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libiconv.tar.gz" "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/libiconv.tar.gz"
fi

cd "$SRC"
if [[ ! -f Makefile ]]; then
  CC="$WASI_SDK_PATH/bin/clang --target=wasm32-wasip1" \
  AR="$WASI_SDK_PATH/bin/llvm-ar" \
  RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  ./configure \
    --host=wasm32-wasi \
    --prefix="$PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-nls
fi

make -C libcharset/lib all
make -C libcharset/lib install-lib libdir="$SRC/lib" includedir="$SRC/lib"
cp libcharset/include/localcharset.h "$SRC/lib/localcharset.h"
make -C lib all

mkdir -p "$PREFIX/include" "$PREFIX/lib/pkgconfig"
cp include/iconv.h "$PREFIX/include/iconv.h"
cp lib/.libs/libiconv.a "$PREFIX/lib/libiconv.a"
cat > "$PREFIX/lib/pkgconfig/iconv.pc" <<PC
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: iconv
Description: GNU libiconv for WASI
Version: $VERSION
Libs: -L\${libdir} -liconv
Cflags: -I\${includedir}
PC

echo "$PREFIX"
