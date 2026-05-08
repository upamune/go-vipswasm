#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBCROCO_VERSION:-0.6.13}"
WORK="${LIBCROCO_PROBE_DIR:-$ROOT/.wasmify/libcroco-probe}"
SRC="$WORK/libcroco-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
GLIB_BUILD="${GLIB_BUILD:-$ROOT/.wasmify/glib-probe/build}"
GLIB_STUB_INCLUDE="${GLIB_STUB_INCLUDE:-$ROOT/.wasmify/glib-probe/wasi-stubs/include}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"
LIBXML2_PREFIX="${LIBXML2_PREFIX:-$ROOT/.wasmify/libxml2-probe/prefix}"
PCRE2_PREFIX="${PCRE2_PREFIX:-$ROOT/.wasmify/pcre2-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi
if [[ ! -d "$GLIB_BUILD/meson-uninstalled" ]]; then
  echo "missing GLib WASI build at $GLIB_BUILD; run: make probe-glib-wasi" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libcroco.tar.xz" "https://download.gnome.org/sources/libcroco/0.6/libcroco-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/libcroco.tar.xz"
fi

cd "$SRC"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$LIBXML2_PREFIX/lib/pkgconfig:$GLIB_BUILD/meson-uninstalled:$GLIB_BUILD/meson-private:$PCRE2_PREFIX/lib/pkgconfig:$ICONV_PREFIX/lib/pkgconfig:$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CC="$ROOT/tools/libvips/wasi-clang-filter.sh --target=wasm32-wasip1"
export AR="$WASI_SDK_PATH/bin/ar"
export RANLIB="$WASI_SDK_PATH/bin/ranlib"
export CFLAGS="-mno-atomics -mllvm -wasm-enable-sjlj -I$GLIB_STUB_INCLUDE -I$LIBXML2_PREFIX/include/libxml2 -I$ICONV_PREFIX/include -I$ZLIB_PREFIX/include -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_GETPID ${CFLAGS:-}"
export LDFLAGS="-mllvm -wasm-enable-sjlj -L$LIBXML2_PREFIX/lib -L$ICONV_PREFIX/lib -L$ZLIB_PREFIX/lib -lwasi-emulated-process-clocks -lwasi-emulated-signal -lwasi-emulated-getpid -lsetjmp ${LDFLAGS:-}"

./configure \
  --host=wasm32-unknown-none \
  --prefix="$PREFIX" \
  --disable-shared \
  --enable-static \
  --disable-Bsymbolic \
  --disable-gtk-doc \
  --disable-gtk-doc-html \
  --disable-gtk-doc-pdf

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install

echo "$PREFIX"
