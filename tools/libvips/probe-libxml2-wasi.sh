#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBXML2_VERSION:-2.13.9}"
WORK="${LIBXML2_PROBE_DIR:-$ROOT/.wasmify/libxml2-probe}"
SRC="$WORK/libxml2-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libxml2.tar.xz" "https://download.gnome.org/sources/libxml2/${VERSION%.*}/libxml2-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/libxml2.tar.xz"
fi
cat > "$WORK/vipswasm-libxml2-wasi.h" <<'STUB'
#include <errno.h>

static inline int
vipswasm_libxml2_dup(int fd)
{
  (void) fd;
  errno = ENOSYS;
  return -1;
}

#define dup(fd) vipswasm_libxml2_dup(fd)
STUB

cross="$WORK/wasi-cross.ini"
sed \
  -e "s|@WASI_SDK@|$WASI_SDK_PATH|g" \
  -e "s|@ROOT@|$ROOT|g" \
  "$ROOT/tools/libvips/wasi-cross.ini" > "$cross"
STUB_INCLUDE="$WORK/vipswasm-libxml2-wasi.h" perl -0pi -e 'my $inc = $ENV{"STUB_INCLUDE"}; s#c_args = \[([^\]]*)\]#c_args = [$1, '\''-include'\'', '\''$inc'\'']#' "$cross"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$ICONV_PREFIX/lib/pkgconfig:$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
rm -rf "$WORK/build"
meson setup "$WORK/build" "$SRC" \
  --cross-file "$cross" \
  --default-library=static \
  --buildtype=release \
  --prefix "$PREFIX" \
  --wrap-mode=nofallback \
  -Dftp=false \
  -Dhttp=false \
  -Diconv=enabled \
  -Dicu=disabled \
  -Dlzma=disabled \
  -Dmodules=disabled \
  -Dpython=false \
  -Dreadline=false \
  -Dthreads=disabled \
  -Dzlib=enabled

meson compile -C "$WORK/build"
meson install -C "$WORK/build"

echo "$PREFIX"
