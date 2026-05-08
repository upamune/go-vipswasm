#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBRAW_VERSION:-0.21.4}"
WORK="${LIBRAW_PROBE_DIR:-$ROOT/.wasmify/libraw-probe}"
SRC="$WORK/LibRaw-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"
LCMS_PREFIX="${LCMS_PREFIX:-$ROOT/.wasmify/lcms-probe/prefix}"
LIBJPEG_PREFIX="${LIBJPEG_PREFIX:-$ROOT/.wasmify/libjpeg-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libraw.tar.gz" "https://www.libraw.org/data/LibRaw-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/libraw.tar.gz"
fi

automake_libdir="$(automake --print-libdir 2>/dev/null || true)"
config_sub="$automake_libdir/config.sub"
if [[ -f "$config_sub" ]]; then
  cp "$config_sub" "$SRC/config.sub"
fi

mkdir -p "$WORK/build"
cd "$WORK/build"

PKG_CONFIG_PATH="$ZLIB_PREFIX/lib/pkgconfig:$LCMS_PREFIX/lib/pkgconfig:$LIBJPEG_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
CC="$WASI_SDK_PATH/bin/clang --target=wasm32-wasip1" \
CXX="$WASI_SDK_PATH/bin/clang++ --target=wasm32-wasip1" \
AR="$WASI_SDK_PATH/bin/llvm-ar" \
RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
STRIP="$WASI_SDK_PATH/bin/llvm-strip" \
CFLAGS="-mno-atomics -mllvm -wasm-enable-sjlj -D_WASI_EMULATED_GETPID -I$ZLIB_PREFIX/include -I$LCMS_PREFIX/include -I$LIBJPEG_PREFIX/include ${CFLAGS:-}" \
CXXFLAGS="-mno-atomics -mllvm -wasm-enable-sjlj -D_WASI_EMULATED_GETPID -I$ZLIB_PREFIX/include -I$LCMS_PREFIX/include -I$LIBJPEG_PREFIX/include ${CXXFLAGS:-}" \
LDFLAGS="-mllvm -wasm-enable-sjlj -L$ZLIB_PREFIX/lib -L$LCMS_PREFIX/lib -L$LIBJPEG_PREFIX/lib ${LDFLAGS:-}" \
LIBS="-lsetjmp -lwasi-emulated-getpid ${LIBS:-}" \
ZLIB_CFLAGS="-I$ZLIB_PREFIX/include" \
ZLIB_LIBS="-L$ZLIB_PREFIX/lib -lz" \
LCMS2_CFLAGS="-I$LCMS_PREFIX/include" \
LCMS2_LIBS="-L$LCMS_PREFIX/lib -llcms2" \
"$SRC/configure" \
  --host=wasm32-unknown-wasi \
  --prefix="$PREFIX" \
  --disable-shared \
  --enable-static \
  --disable-openmp \
  --disable-examples \
  --enable-jpeg \
  --disable-jasper \
  --enable-zlib \
  --enable-lcms

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install

for pc in "$PREFIX/lib/pkgconfig/libraw.pc" "$PREFIX/lib/pkgconfig/libraw_r.pc"; do
  perl -0pi -e '
    my @private = /Libs\.private:[ \t]*([^\n]*)/g;
    s/^Libs\.private:[^\n]*\n//mg;
    my %seen;
    my @libs = grep { length && !$seen{$_}++ }
      split /\s+/, join(" ", @private, "-lsetjmp -lc++ -lc++abi -lwasi-emulated-getpid");
    s/Libs:([^\n]*)\n/Libs:$1\nLibs.private: @libs\n/;
  ' "$pc"
done

echo "$PREFIX"
