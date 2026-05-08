#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${FONTCONFIG_VERSION:-2.17.1}"
WORK="${FONTCONFIG_PROBE_DIR:-$ROOT/.wasmify/fontconfig-probe}"
SRC="$WORK/fontconfig-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
EXPAT_PREFIX="${EXPAT_PREFIX:-$ROOT/.wasmify/expat-probe/prefix}"
FREETYPE_PREFIX="${FREETYPE_PREFIX:-$ROOT/.wasmify/freetype-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

for pc in "$EXPAT_PREFIX/lib/pkgconfig/expat.pc" "$FREETYPE_PREFIX/lib/pkgconfig/freetype2.pc" "$ZLIB_PREFIX/lib/pkgconfig/zlib.pc"; do
  if [[ ! -f "$pc" ]]; then
    echo "missing dependency pkg-config file $pc; run: make probe-expat-wasi probe-freetype-wasi" >&2
    exit 2
  fi
done

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/fontconfig.tar.xz" "https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/$VERSION/fontconfig-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/fontconfig.tar.xz"
fi

if ! grep -q "VIPSWASM_WASI_NO_FCNTL_LOCKS" "$SRC/src/fccache.c"; then
  perl -0pi -e 's/#else\n\t    struct flock fl;/#elif !defined(__wasi__) \/* VIPSWASM_WASI_NO_FCNTL_LOCKS *\/\n\t    struct flock fl;\n#endif\n#if defined(__wasi__) \/* VIPSWASM_WASI_NO_FCNTL_LOCKS *\/\n\t    (void) fd;\n#else/' "$SRC/src/fccache.c"
  perl -0pi -e 's/\t    if \(fcntl \(fd, F_SETLKW, &fl\) == -1\)\n\t\tgoto bail;\n#endif/\t    if (fcntl (fd, F_SETLKW, \&fl) == -1)\n\t\tgoto bail;\n#endif/' "$SRC/src/fccache.c"
  perl -0pi -e 's/#else\n\tstruct flock fl;/#elif !defined(__wasi__) \/* VIPSWASM_WASI_NO_FCNTL_LOCKS *\/\n\tstruct flock fl;\n#endif\n#if defined(__wasi__) \/* VIPSWASM_WASI_NO_FCNTL_LOCKS *\/\n\t(void) fd;\n#else/' "$SRC/src/fccache.c"
  perl -0pi -e 's/\tfcntl \(fd, F_SETLK, &fl\);\n#endif/\tfcntl (fd, F_SETLK, \&fl);\n#endif/' "$SRC/src/fccache.c"
fi

cross="$WORK/wasi-cross.ini"
sed \
  -e "s|@WASI_SDK@|$WASI_SDK_PATH|g" \
  -e "s|@ROOT@|$ROOT|g" \
  "$ROOT/tools/libvips/wasi-cross.ini" > "$cross"

export PKG_CONFIG_PATH="$FREETYPE_PREFIX/lib/pkgconfig:$EXPAT_PREFIX/lib/pkgconfig:$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
rm -rf "$WORK/build"
meson setup "$WORK/build" "$SRC" \
  --cross-file "$cross" \
  --default-library=static \
  --buildtype=release \
  --prefix "$PREFIX" \
  --wrap-mode=nofallback \
  -Ddoc=disabled \
  -Dtests=disabled \
  -Dtools=disabled \
  -Dcache-build=disabled \
  -Dnls=disabled \
  -Dxml-backend=expat

meson compile -C "$WORK/build"
meson install -C "$WORK/build"

echo "$PREFIX"
