#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${SQLITE_VERSION:-3460100}"
DISPLAY_VERSION="${SQLITE_DISPLAY_VERSION:-3.46.1}"
WORK="${SQLITE_PROBE_DIR:-$ROOT/.wasmify/sqlite-probe}"
SRC="$WORK/sqlite-autoconf-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/sqlite.tar.gz" "https://www.sqlite.org/2024/sqlite-autoconf-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/sqlite.tar.gz"
fi

cd "$SRC"

export CC="$ROOT/tools/libvips/wasi-clang-filter.sh --target=wasm32-wasip1"
export AR="$WASI_SDK_PATH/bin/ar"
export RANLIB="$WASI_SDK_PATH/bin/ranlib"
export CFLAGS="-mno-atomics -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_WAL -DSQLITE_OMIT_SHARED_CACHE -D_WASI_EMULATED_GETPID ${CFLAGS:-}"
export LDFLAGS="-lwasi-emulated-getpid ${LDFLAGS:-}"

./configure \
  --host=wasm32-unknown-none \
  --prefix="$PREFIX" \
  --disable-shared \
  --enable-static \
  --disable-readline \
  --disable-threadsafe

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" libsqlite3.la
make install-libLTLIBRARIES install-pkgconfigDATA install-includeHEADERS

pc="$PREFIX/lib/pkgconfig/sqlite3.pc"
if [[ -f "$pc" ]]; then
  perl -0pi -e "s/^Version:.*/Version: $DISPLAY_VERSION/m" "$pc"
fi

echo "$PREFIX"
