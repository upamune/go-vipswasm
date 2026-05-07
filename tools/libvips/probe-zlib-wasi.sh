#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${ZLIB_VERSION:-1.3.2}"
WORK="${ZLIB_PROBE_DIR:-$ROOT/.wasmify/zlib-probe}"
SRC="$WORK/zlib-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/zlib.tar.gz" "https://zlib.net/zlib-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/zlib.tar.gz"
fi

cd "$SRC"
if [[ ! -f zlib.pc ]]; then
  CHOST=wasm32-wasi \
  CC="$WASI_SDK_PATH/bin/clang --target=wasm32-wasip1" \
  AR="$WASI_SDK_PATH/bin/llvm-ar" \
  RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  ./configure \
    --static \
    --prefix="$PREFIX"
fi

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" libz.a

mkdir -p "$PREFIX/include" "$PREFIX/lib/pkgconfig"
cp zconf.h zlib.h "$PREFIX/include/"
cp libz.a "$PREFIX/lib/libz.a"
cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<PC
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: zlib
Description: zlib compression library for WASI
Version: $VERSION
Libs: -L\${libdir} -lz
Cflags: -I\${includedir}
PC

echo "$PREFIX"
