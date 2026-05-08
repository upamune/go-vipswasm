#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBARCHIVE_VERSION:-3.8.2}"
WORK="${LIBARCHIVE_PROBE_DIR:-$ROOT/.wasmify/libarchive-probe}"
SRC="$WORK/libarchive-$VERSION"
PREFIX="$WORK/prefix"
STUB_INCLUDE="$WORK/wasi-stubs"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

if [[ ! -f "$ZLIB_PREFIX/lib/pkgconfig/zlib.pc" ]]; then
  echo "missing zlib WASI prefix at $ZLIB_PREFIX; run: make probe-zlib-wasi" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libarchive.tar.xz" "https://github.com/libarchive/libarchive/releases/download/v$VERSION/libarchive-$VERSION.tar.xz"
  tar -C "$WORK" -xf "$WORK/libarchive.tar.xz"
fi

mkdir -p "$STUB_INCLUDE"
cat > "$STUB_INCLUDE/vipswasm-libarchive-wasi.h" <<'H'
#ifndef VIPSWASM_LIBARCHIVE_WASI_H
#define VIPSWASM_LIBARCHIVE_WASI_H
#ifdef __wasi__
#include <errno.h>
#include <stddef.h>
#include <sys/types.h>

#define HAVE_FCHDIR 1
#define VIPSWASM_UNUSED __attribute__((unused))

struct passwd {
  char *pw_name;
  char *pw_passwd;
  uid_t pw_uid;
  gid_t pw_gid;
  char *pw_gecos;
  char *pw_dir;
  char *pw_shell;
};

struct group {
  char *gr_name;
  char *gr_passwd;
  gid_t gr_gid;
  char **gr_mem;
};

static VIPSWASM_UNUSED int vipswasm_wasi_fchdir(int fd) { (void) fd; errno = ENOSYS; return -1; }
static VIPSWASM_UNUSED int vipswasm_wasi_dup(int fd) { (void) fd; errno = ENOSYS; return -1; }
static VIPSWASM_UNUSED int vipswasm_wasi_waitpid(pid_t pid, int *status, int options) { (void) pid; (void) status; (void) options; errno = ENOSYS; return -1; }
static VIPSWASM_UNUSED mode_t vipswasm_wasi_umask(mode_t mask) { (void) mask; return 0; }
static VIPSWASM_UNUSED uid_t vipswasm_wasi_getuid(void) { return 0; }
static VIPSWASM_UNUSED gid_t vipswasm_wasi_getgid(void) { return 0; }
static VIPSWASM_UNUSED void vipswasm_wasi_tzset(void) {}
static VIPSWASM_UNUSED struct passwd *vipswasm_wasi_getpwuid(uid_t uid) { (void) uid; return NULL; }
static VIPSWASM_UNUSED struct group *vipswasm_wasi_getgrgid(gid_t gid) { (void) gid; return NULL; }
static VIPSWASM_UNUSED struct passwd *vipswasm_wasi_getpwnam(const char *name) { (void) name; return NULL; }
static VIPSWASM_UNUSED struct group *vipswasm_wasi_getgrnam(const char *name) { (void) name; return NULL; }

#define fchdir vipswasm_wasi_fchdir
#define dup vipswasm_wasi_dup
#define waitpid vipswasm_wasi_waitpid
#define umask vipswasm_wasi_umask
#define getuid vipswasm_wasi_getuid
#define getgid vipswasm_wasi_getgid
#define tzset vipswasm_wasi_tzset
#define getpwuid vipswasm_wasi_getpwuid
#define getgrgid vipswasm_wasi_getgrgid
#define getpwnam vipswasm_wasi_getpwnam
#define getgrnam vipswasm_wasi_getgrnam

#ifndef WIFSIGNALED
#define WIFSIGNALED(status) 0
#endif
#ifndef WTERMSIG
#define WTERMSIG(status) 0
#endif
#ifndef WIFEXITED
#define WIFEXITED(status) 0
#endif
#ifndef WEXITSTATUS
#define WEXITSTATUS(status) 1
#endif
#endif
#endif
H

if ! grep -q "VIPSWASM_WASI_KEEP_CALLER_GID" "$SRC/libarchive/archive_write_disk_set_standard_lookup.c"; then
  perl -0pi -e 's/#else\n\t#error No way to perform gid lookups on this platform/#elif defined(__wasi__)\n\t\/* VIPSWASM_WASI_KEEP_CALLER_GID: user\/group databases are unavailable. *\/\n#else\n\t#error No way to perform gid lookups on this platform/' \
    "$SRC/libarchive/archive_write_disk_set_standard_lookup.c"
  perl -0pi -e 's/#else\n\t#error No way to look up uids on this platform/#elif defined(__wasi__)\n\t\/* VIPSWASM_WASI_KEEP_CALLER_UID: user\/group databases are unavailable. *\/\n#else\n\t#error No way to look up uids on this platform/' \
    "$SRC/libarchive/archive_write_disk_set_standard_lookup.c"
fi

export PKG_CONFIG_PATH="$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
cmake -S "$SRC" -B "$WORK/build" \
  -DCMAKE_SYSTEM_NAME=WASI \
  -DCMAKE_SYSTEM_PROCESSOR=wasm32 \
  -DCMAKE_C_COMPILER="$WASI_SDK_PATH/bin/clang" \
  -DCMAKE_C_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_AR="$WASI_SDK_PATH/bin/llvm-ar" \
  -DCMAKE_RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-include $STUB_INCLUDE/vipswasm-libarchive-wasi.h" \
  -DCMAKE_PREFIX_PATH="$ZLIB_PREFIX" \
  -DZLIB_ROOT="$ZLIB_PREFIX" \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_TEST=OFF \
  -DENABLE_TAR=OFF \
  -DENABLE_CPIO=OFF \
  -DENABLE_CAT=OFF \
  -DENABLE_UNZIP=OFF \
  -DENABLE_ACL=OFF \
  -DENABLE_XATTR=OFF \
  -DENABLE_OPENSSL=OFF \
  -DENABLE_MBEDTLS=OFF \
  -DENABLE_NETTLE=OFF \
  -DENABLE_LIBB2=OFF \
  -DENABLE_LZ4=OFF \
  -DENABLE_LZO=OFF \
  -DENABLE_LZMA=OFF \
  -DENABLE_ZSTD=OFF \
  -DENABLE_BZip2=OFF \
  -DENABLE_LIBXML2=OFF \
  -DENABLE_EXPAT=OFF \
  -DENABLE_PCREPOSIX=OFF \
  -DENABLE_PCRE2POSIX=OFF \
  -DENABLE_ICONV=OFF \
  -DENABLE_ZLIB=ON

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "$PREFIX"
