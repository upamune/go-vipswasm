#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
TAG="${GLIB_TAG:-2.86.5}"
WORK="${GLIB_PROBE_DIR:-$ROOT/.wasmify/glib-probe}"
SRC="${GLIB_SRC:-$WORK/glib}"
BUILD="$WORK/build"
STUB_INCLUDE="$WORK/wasi-stubs/include"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
ICONV_PREFIX="${ICONV_PREFIX:-$ROOT/.wasmify/iconv-probe/prefix}"
PCRE2_PREFIX="${PCRE2_PREFIX:-$ROOT/.wasmify/pcre2-probe/prefix}"
LIBFFI_PREFIX="${LIBFFI_PREFIX:-$ROOT/.wasmify/libffi-probe/prefix}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"
GLIB_WRAP_MODE="${GLIB_WRAP_MODE:-default}"
GLIB_USE_LIBFFI="${GLIB_USE_LIBFFI:-0}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC/.git" ]]; then
  git clone --depth 1 --branch "$TAG" https://github.com/GNOME/glib.git "$SRC"
fi

mkdir -p "$STUB_INCLUDE/sys" "$STUB_INCLUDE/netinet" "$STUB_INCLUDE/arpa" "$STUB_INCLUDE/net"
cat > "$STUB_INCLUDE/pwd.h" <<'H'
#ifndef GO_VIPSWASM_WASI_PWD_H
#define GO_VIPSWASM_WASI_PWD_H
#include <errno.h>
#include <stddef.h>
#include <sys/types.h>
struct passwd {
  char *pw_name;
  char *pw_passwd;
  uid_t pw_uid;
  gid_t pw_gid;
  char *pw_gecos;
  char *pw_dir;
  char *pw_shell;
};
static inline struct passwd *getpwuid(uid_t uid) { (void)uid; errno = ENOSYS; return (struct passwd *)0; }
static inline struct passwd *getpwnam(const char *name) { (void)name; errno = ENOSYS; return (struct passwd *)0; }
static inline int getpwuid_r(uid_t uid, struct passwd *pwd, char *buf, size_t buflen, struct passwd **result) { (void)uid; (void)pwd; (void)buf; (void)buflen; if (result) *result = (struct passwd *)0; return ENOSYS; }
static inline int getpwnam_r(const char *name, struct passwd *pwd, char *buf, size_t buflen, struct passwd **result) { (void)name; (void)pwd; (void)buf; (void)buflen; if (result) *result = (struct passwd *)0; return ENOSYS; }
#endif
H
cat > "$STUB_INCLUDE/grp.h" <<'H'
#ifndef GO_VIPSWASM_WASI_GRP_H
#define GO_VIPSWASM_WASI_GRP_H
#include <errno.h>
#include <stddef.h>
#include <sys/types.h>
struct group {
  char *gr_name;
  char *gr_passwd;
  gid_t gr_gid;
  char **gr_mem;
};
static inline struct group *getgrgid(gid_t gid) { (void)gid; errno = ENOSYS; return (struct group *)0; }
static inline int getgrgid_r(gid_t gid, struct group *grp, char *buf, size_t buflen, struct group **result) { (void)gid; (void)grp; (void)buf; (void)buflen; if (result) *result = (struct group *)0; return ENOSYS; }
#endif
H
cat > "$STUB_INCLUDE/unistd.h" <<'H'
#ifndef GO_VIPSWASM_WASI_UNISTD_H
#define GO_VIPSWASM_WASI_UNISTD_H
#include_next <unistd.h>
#include <errno.h>
static inline int dup(int fd) { (void)fd; errno = ENOSYS; return -1; }
static inline uid_t getuid(void) { return 1; }
static inline uid_t geteuid(void) { return 1; }
static inline gid_t getgid(void) { return 1; }
static inline gid_t getegid(void) { return 1; }
static inline int chown(const char *path, uid_t owner, gid_t group) { (void)path; (void)owner; (void)group; errno = ENOSYS; return -1; }
static inline int lchown(const char *path, uid_t owner, gid_t group) { (void)path; (void)owner; (void)group; errno = ENOSYS; return -1; }
static inline int fchown(int fd, uid_t owner, gid_t group) { (void)fd; (void)owner; (void)group; errno = ENOSYS; return -1; }
#endif
H
cat > "$STUB_INCLUDE/sys/wait.h" <<'H'
#ifndef GO_VIPSWASM_WASI_SYS_WAIT_H
#define GO_VIPSWASM_WASI_SYS_WAIT_H
#include <errno.h>
#include <sys/types.h>
#define WNOHANG 1
#define WUNTRACED 2
#define WCONTINUED 8
#define WEXITED 4
#define WIFEXITED(status) 0
#define WEXITSTATUS(status) (status)
#define WIFSIGNALED(status) 0
#define WTERMSIG(status) 0
#define WIFSTOPPED(status) 0
#define WSTOPSIG(status) 0
#define WIFCONTINUED(status) 0
static inline pid_t waitpid(pid_t pid, int *status, int options) { (void)pid; (void)status; (void)options; errno = ENOSYS; return -1; }
#endif
H
cat > "$STUB_INCLUDE/sys/socket.h" <<'H'
#ifndef GO_VIPSWASM_WASI_SYS_SOCKET_H
#define GO_VIPSWASM_WASI_SYS_SOCKET_H
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/uio.h>
typedef uint16_t sa_family_t;
typedef uint32_t socklen_t;
struct sockaddr { sa_family_t sa_family; char sa_data[14]; };
struct sockaddr_storage { sa_family_t ss_family; char __ss_padding[126]; };
struct linger { int l_onoff; int l_linger; };
struct cmsghdr { socklen_t cmsg_len; int cmsg_level; int cmsg_type; };
struct msghdr {
  void *msg_name;
  socklen_t msg_namelen;
  struct iovec *msg_iov;
  size_t msg_iovlen;
  void *msg_control;
  size_t msg_controllen;
  int msg_flags;
};
#define AF_UNSPEC 0
#define AF_INET 1
#define AF_INET6 2
#define AF_UNIX 3
#define PF_UNSPEC AF_UNSPEC
#define PF_INET AF_INET
#define PF_INET6 AF_INET6
#define PF_UNIX AF_UNIX
#define SOCK_STREAM 1
#define SOCK_DGRAM 2
#define SOCK_RAW 3
#define SOCK_SEQPACKET 5
#define SOCK_NONBLOCK 0x4000
#define SOCK_CLOEXEC 0x80000
#define SOMAXCONN 128
#define SOL_SOCKET 1
#define SO_TYPE 3
#define SO_ERROR 4
#define SO_KEEPALIVE 9
#define SO_BROADCAST 6
#define SO_REUSEADDR 2
#define SO_REUSEPORT 15
#define SO_SNDBUF 7
#define SO_RCVBUF 8
#define SO_OOBINLINE 10
#define SO_PEERCRED 17
#define SHUT_RD 0
#define SHUT_WR 1
#define SHUT_RDWR 2
#define MSG_OOB 0x1
#define MSG_PEEK 0x2
#define MSG_DONTROUTE 0x4
#define MSG_CTRUNC 0x8
#define MSG_TRUNC 0x10
#define MSG_DONTWAIT 0x40
#define MSG_NOSIGNAL 0x4000
#define SCM_RIGHTS 1
#define CMSG_DATA(cmsg) ((unsigned char *) ((struct cmsghdr *)(cmsg) + 1))
#define CMSG_FIRSTHDR(mhdr) ((mhdr)->msg_controllen >= sizeof(struct cmsghdr) ? (struct cmsghdr *)(mhdr)->msg_control : (struct cmsghdr *)0)
#define CMSG_NXTHDR(mhdr, cmsg) ((struct cmsghdr *)0)
#define CMSG_ALIGN(len) (((len) + sizeof(size_t) - 1) & ~(sizeof(size_t) - 1))
#define CMSG_SPACE(len) (CMSG_ALIGN(sizeof(struct cmsghdr)) + CMSG_ALIGN(len))
#define CMSG_LEN(len) (CMSG_ALIGN(sizeof(struct cmsghdr)) + (len))
static inline int socket(int domain, int type, int protocol) { (void)domain; (void)type; (void)protocol; errno = ENOSYS; return -1; }
static inline int bind(int fd, const struct sockaddr *addr, socklen_t len) { (void)fd; (void)addr; (void)len; errno = ENOSYS; return -1; }
static inline int connect(int fd, const struct sockaddr *addr, socklen_t len) { (void)fd; (void)addr; (void)len; errno = ENOSYS; return -1; }
static inline int listen(int fd, int backlog) { (void)fd; (void)backlog; errno = ENOSYS; return -1; }
static inline int accept(int fd, struct sockaddr *addr, socklen_t *len) { (void)fd; (void)addr; (void)len; errno = ENOSYS; return -1; }
static inline int accept4(int fd, struct sockaddr *addr, socklen_t *len, int flags) { (void)flags; return accept(fd, addr, len); }
static inline int shutdown(int fd, int how) { (void)fd; (void)how; errno = ENOSYS; return -1; }
static inline int getsockopt(int fd, int level, int optname, void *optval, socklen_t *optlen) { (void)fd; (void)level; (void)optname; (void)optval; (void)optlen; errno = ENOSYS; return -1; }
static inline int setsockopt(int fd, int level, int optname, const void *optval, socklen_t optlen) { (void)fd; (void)level; (void)optname; (void)optval; (void)optlen; errno = ENOSYS; return -1; }
static inline ssize_t recv(int fd, void *buf, size_t len, int flags) { (void)fd; (void)buf; (void)len; (void)flags; errno = ENOSYS; return -1; }
static inline ssize_t send(int fd, const void *buf, size_t len, int flags) { (void)fd; (void)buf; (void)len; (void)flags; errno = ENOSYS; return -1; }
static inline ssize_t recvfrom(int fd, void *buf, size_t len, int flags, struct sockaddr *addr, socklen_t *addrlen) { (void)fd; (void)buf; (void)len; (void)flags; (void)addr; (void)addrlen; errno = ENOSYS; return -1; }
static inline ssize_t sendto(int fd, const void *buf, size_t len, int flags, const struct sockaddr *addr, socklen_t addrlen) { (void)fd; (void)buf; (void)len; (void)flags; (void)addr; (void)addrlen; errno = ENOSYS; return -1; }
static inline ssize_t recvmsg(int fd, struct msghdr *msg, int flags) { (void)fd; (void)msg; (void)flags; errno = ENOSYS; return -1; }
static inline ssize_t sendmsg(int fd, const struct msghdr *msg, int flags) { (void)fd; (void)msg; (void)flags; errno = ENOSYS; return -1; }
static inline int getsockname(int fd, struct sockaddr *addr, socklen_t *len) { (void)fd; (void)addr; (void)len; errno = ENOSYS; return -1; }
static inline int getpeername(int fd, struct sockaddr *addr, socklen_t *len) { (void)fd; (void)addr; (void)len; errno = ENOSYS; return -1; }
#endif
H
cat > "$STUB_INCLUDE/netinet/in.h" <<'H'
#ifndef GO_VIPSWASM_WASI_NETINET_IN_H
#define GO_VIPSWASM_WASI_NETINET_IN_H
#include <stdint.h>
#include <sys/socket.h>
typedef uint16_t in_port_t;
typedef uint32_t in_addr_t;
struct in_addr { in_addr_t s_addr; };
struct in6_addr { uint8_t s6_addr[16]; };
struct sockaddr_in { sa_family_t sin_family; in_port_t sin_port; struct in_addr sin_addr; unsigned char sin_zero[8]; };
struct sockaddr_in6 { sa_family_t sin6_family; in_port_t sin6_port; uint32_t sin6_flowinfo; struct in6_addr sin6_addr; uint32_t sin6_scope_id; };
struct ip_mreq { struct in_addr imr_multiaddr; struct in_addr imr_interface; };
struct ipv6_mreq { struct in6_addr ipv6mr_multiaddr; unsigned int ipv6mr_interface; };
#define IPPROTO_IP 0
#define IPPROTO_TCP 6
#define IPPROTO_UDP 17
#define IPPROTO_IPV6 41
#define IP_TTL 2
#define INADDR_ANY ((in_addr_t)0x00000000)
#define INADDR_LOOPBACK ((in_addr_t)0x7f000001)
#define INADDR_BROADCAST ((in_addr_t)0xffffffff)
#define IN6ADDR_ANY_INIT {{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}}
#define IN6ADDR_LOOPBACK_INIT {{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1}}
static const struct in6_addr in6addr_any = IN6ADDR_ANY_INIT;
static const struct in6_addr in6addr_loopback = IN6ADDR_LOOPBACK_INIT;
#define IPV6_V6ONLY 26
#define IPV6_UNICAST_HOPS 16
#define IPV6_MULTICAST_LOOP 19
#define IPV6_MULTICAST_HOPS 18
#define IPV6_JOIN_GROUP 20
#define IPV6_LEAVE_GROUP 21
#define IP_MULTICAST_LOOP 34
#define IP_MULTICAST_TTL 33
#define IP_ADD_MEMBERSHIP 35
#define IP_DROP_MEMBERSHIP 36
#define IN_MULTICAST(a) ((((uint32_t)(a)) & 0xf0000000U) == 0xe0000000U)
#define IN6_IS_ADDR_UNSPECIFIED(a) ((a)->s6_addr[0] == 0 && (a)->s6_addr[1] == 0 && (a)->s6_addr[2] == 0 && (a)->s6_addr[3] == 0 && (a)->s6_addr[4] == 0 && (a)->s6_addr[5] == 0 && (a)->s6_addr[6] == 0 && (a)->s6_addr[7] == 0 && (a)->s6_addr[8] == 0 && (a)->s6_addr[9] == 0 && (a)->s6_addr[10] == 0 && (a)->s6_addr[11] == 0 && (a)->s6_addr[12] == 0 && (a)->s6_addr[13] == 0 && (a)->s6_addr[14] == 0 && (a)->s6_addr[15] == 0)
#define IN6_IS_ADDR_LOOPBACK(a) ((a)->s6_addr[0] == 0 && (a)->s6_addr[1] == 0 && (a)->s6_addr[2] == 0 && (a)->s6_addr[3] == 0 && (a)->s6_addr[4] == 0 && (a)->s6_addr[5] == 0 && (a)->s6_addr[6] == 0 && (a)->s6_addr[7] == 0 && (a)->s6_addr[8] == 0 && (a)->s6_addr[9] == 0 && (a)->s6_addr[10] == 0 && (a)->s6_addr[11] == 0 && (a)->s6_addr[12] == 0 && (a)->s6_addr[13] == 0 && (a)->s6_addr[14] == 0 && (a)->s6_addr[15] == 1)
#define IN6_IS_ADDR_LINKLOCAL(a) ((a)->s6_addr[0] == 0xfe && (((a)->s6_addr[1] & 0xc0) == 0x80))
#define IN6_IS_ADDR_SITELOCAL(a) ((a)->s6_addr[0] == 0xfe && (((a)->s6_addr[1] & 0xc0) == 0xc0))
#define IN6_IS_ADDR_MULTICAST(a) ((a)->s6_addr[0] == 0xff)
#define IN6_IS_ADDR_MC_GLOBAL(a) (IN6_IS_ADDR_MULTICAST(a) && (((a)->s6_addr[1] & 0x0f) == 0x0e))
#define IN6_IS_ADDR_MC_LINKLOCAL(a) (IN6_IS_ADDR_MULTICAST(a) && (((a)->s6_addr[1] & 0x0f) == 0x02))
#define IN6_IS_ADDR_MC_NODELOCAL(a) (IN6_IS_ADDR_MULTICAST(a) && (((a)->s6_addr[1] & 0x0f) == 0x01))
#define IN6_IS_ADDR_MC_ORGLOCAL(a) (IN6_IS_ADDR_MULTICAST(a) && (((a)->s6_addr[1] & 0x0f) == 0x08))
#define IN6_IS_ADDR_MC_SITELOCAL(a) (IN6_IS_ADDR_MULTICAST(a) && (((a)->s6_addr[1] & 0x0f) == 0x05))
#define IN6_IS_ADDR_V4MAPPED(a) ((a)->s6_addr[0] == 0 && (a)->s6_addr[1] == 0 && (a)->s6_addr[2] == 0 && (a)->s6_addr[3] == 0 && (a)->s6_addr[4] == 0 && (a)->s6_addr[5] == 0 && (a)->s6_addr[6] == 0 && (a)->s6_addr[7] == 0 && (a)->s6_addr[8] == 0 && (a)->s6_addr[9] == 0 && (a)->s6_addr[10] == 0xff && (a)->s6_addr[11] == 0xff)
static inline uint16_t htons(uint16_t x) { return (uint16_t)((x << 8) | (x >> 8)); }
static inline uint16_t ntohs(uint16_t x) { return htons(x); }
static inline uint32_t htonl(uint32_t x) { return ((x & 0xffU) << 24) | ((x & 0xff00U) << 8) | ((x & 0xff0000U) >> 8) | ((x >> 24) & 0xffU); }
static inline uint32_t ntohl(uint32_t x) { return htonl(x); }
#endif
H
cat > "$STUB_INCLUDE/netinet/tcp.h" <<'H'
#ifndef GO_VIPSWASM_WASI_NETINET_TCP_H
#define GO_VIPSWASM_WASI_NETINET_TCP_H
#define TCP_NODELAY 1
#endif
H
cat > "$STUB_INCLUDE/arpa/inet.h" <<'H'
#ifndef GO_VIPSWASM_WASI_ARPA_INET_H
#define GO_VIPSWASM_WASI_ARPA_INET_H
#include <errno.h>
#include <stddef.h>
#include <netinet/in.h>
#define INET_ADDRSTRLEN 16
#define INET6_ADDRSTRLEN 46
static inline int inet_pton(int af, const char *src, void *dst) { (void)af; (void)src; (void)dst; errno = EAFNOSUPPORT; return -1; }
static inline const char *inet_ntop(int af, const void *src, char *dst, socklen_t size) { (void)af; (void)src; (void)dst; (void)size; errno = EAFNOSUPPORT; return (const char *)0; }
static inline int inet_aton(const char *src, struct in_addr *dst) { (void)src; (void)dst; errno = EAFNOSUPPORT; return 0; }
#endif
H
cat > "$STUB_INCLUDE/netdb.h" <<'H'
#ifndef GO_VIPSWASM_WASI_NETDB_H
#define GO_VIPSWASM_WASI_NETDB_H
#include <errno.h>
#include <stddef.h>
#include <sys/socket.h>
struct addrinfo { int ai_flags; int ai_family; int ai_socktype; int ai_protocol; socklen_t ai_addrlen; struct sockaddr *ai_addr; char *ai_canonname; struct addrinfo *ai_next; };
struct servent { char *s_name; char **s_aliases; int s_port; char *s_proto; };
#define AI_PASSIVE 0x1
#define AI_CANONNAME 0x2
#define AI_NUMERICHOST 0x4
#define AI_NUMERICSERV 0x400
#define NI_NUMERICHOST 0x1
#define NI_NUMERICSERV 0x2
#define NI_NAMEREQD 0x8
#define NI_MAXHOST 1025
#define EAI_FAIL -4
#define EAI_MEMORY -10
#define EAI_NONAME -2
#define EAI_AGAIN -3
#define HOST_NOT_FOUND 1
#define TRY_AGAIN 2
#define NO_RECOVERY 3
#define NO_DATA 4
static int h_errno;
static inline int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) { (void)node; (void)service; (void)hints; if (res) *res = (struct addrinfo *)0; return EAI_FAIL; }
static inline void freeaddrinfo(struct addrinfo *res) { (void)res; }
static inline const char *gai_strerror(int errcode) { (void)errcode; return "WASI networking unsupported"; }
static inline int getnameinfo(const struct sockaddr *sa, socklen_t salen, char *host, socklen_t hostlen, char *serv, socklen_t servlen, int flags) { (void)sa; (void)salen; (void)host; (void)hostlen; (void)serv; (void)servlen; (void)flags; return EAI_FAIL; }
static inline struct servent *getservbyname(const char *name, const char *proto) { (void)name; (void)proto; errno = ENOSYS; return (struct servent *)0; }
#endif
H
cat > "$STUB_INCLUDE/resolv.h" <<'H'
#ifndef GO_VIPSWASM_WASI_RESOLV_H
#define GO_VIPSWASM_WASI_RESOLV_H
#define _PATH_RESCONF "/etc/resolv.conf"
struct __res_state { int retrans; };
static inline int res_query(const char *dname, int cls, int type, unsigned char *answer, int anslen) { (void)dname; (void)cls; (void)type; (void)answer; (void)anslen; return -1; }
static inline int dn_expand(const unsigned char *msg, const unsigned char *eomorig, const unsigned char *comp_dn, char *exp_dn, int length) { (void)msg; (void)eomorig; (void)comp_dn; (void)exp_dn; (void)length; return -1; }
#endif
H
cat > "$STUB_INCLUDE/arpa/nameser.h" <<'H'
#ifndef GO_VIPSWASM_WASI_ARPA_NAMESER_H
#define GO_VIPSWASM_WASI_ARPA_NAMESER_H
#include <stdint.h>
#define C_IN 1
#define T_A 1
#define T_NS 2
#define T_CNAME 5
#define T_SOA 6
#define T_PTR 12
#define T_MX 15
#define T_TXT 16
#define T_SRV 33
typedef struct { uint16_t id; uint16_t flags; uint16_t qdcount; uint16_t ancount; uint16_t nscount; uint16_t arcount; } HEADER;
#define GETSHORT(s, cp) do { const unsigned char *__p = (const unsigned char *)(cp); (s) = (uint16_t)((__p[0] << 8) | __p[1]); (cp) += 2; } while (0)
#define GETLONG(l, cp) do { const unsigned char *__p = (const unsigned char *)(cp); (l) = (uint32_t)((uint32_t)__p[0] << 24 | (uint32_t)__p[1] << 16 | (uint32_t)__p[2] << 8 | (uint32_t)__p[3]); (cp) += 4; } while (0)
#endif
H
cat > "$STUB_INCLUDE/sys/un.h" <<'H'
#ifndef GO_VIPSWASM_WASI_SYS_UN_H
#define GO_VIPSWASM_WASI_SYS_UN_H
#include <sys/socket.h>
struct sockaddr_un { sa_family_t sun_family; char sun_path[108]; };
#endif
H
cat > "$STUB_INCLUDE/net/if.h" <<'H'
#ifndef GO_VIPSWASM_WASI_NET_IF_H
#define GO_VIPSWASM_WASI_NET_IF_H
#include <errno.h>
#include <stddef.h>
#define IFNAMSIZ 16
struct ifreq { char ifr_name[IFNAMSIZ]; };
static inline unsigned int if_nametoindex(const char *ifname) { (void)ifname; errno = ENOSYS; return 0; }
static inline char *if_indextoname(unsigned int ifindex, char *ifname) { (void)ifindex; (void)ifname; errno = ENOSYS; return (char *)0; }
#endif
H

cross="$WORK/wasi-cross.ini"
ffi_c_args=""
ffi_link_args=""
ffi_pkg_config_path=""
if [[ "$GLIB_USE_LIBFFI" == "1" ]]; then
  ffi_c_args=", '-I$LIBFFI_PREFIX/include'"
  ffi_link_args=", '-L$LIBFFI_PREFIX/lib', '-lffi'"
  ffi_pkg_config_path=":$LIBFFI_PREFIX/lib/pkgconfig"
fi
cat > "$cross" <<INI
[binaries]
c = '$ROOT/tools/libvips/wasi-clang-filter.sh'
cpp = '$ROOT/tools/libvips/wasi-clang-filter.sh'
ar = '$WASI_SDK_PATH/bin/llvm-ar'
strip = '$WASI_SDK_PATH/bin/llvm-strip'
pkg-config = 'pkg-config'

[built-in options]
c_args = ['--target=wasm32-wasip1', '-mno-atomics', '-I$STUB_INCLUDE', '-I$ICONV_PREFIX/include', '-I$PCRE2_PREFIX/include'$ffi_c_args, '-I$ZLIB_PREFIX/include', '-D_WASI_EMULATED_PROCESS_CLOCKS', '-D_WASI_EMULATED_SIGNAL', '-D_WASI_EMULATED_GETPID']
cpp_args = ['--target=wasm32-wasip1', '-mno-atomics', '-I$STUB_INCLUDE', '-I$ICONV_PREFIX/include', '-I$PCRE2_PREFIX/include'$ffi_c_args, '-I$ZLIB_PREFIX/include', '-D_WASI_EMULATED_PROCESS_CLOCKS', '-D_WASI_EMULATED_SIGNAL', '-D_WASI_EMULATED_GETPID']
c_link_args = ['--target=wasm32-wasip1', '-L$ICONV_PREFIX/lib', '-L$PCRE2_PREFIX/lib'$ffi_link_args, '-L$ZLIB_PREFIX/lib', '-liconv', '-lpcre2-8', '-lz', '-lwasi-emulated-process-clocks', '-lwasi-emulated-signal', '-lwasi-emulated-getpid']
cpp_link_args = ['--target=wasm32-wasip1', '-L$ICONV_PREFIX/lib', '-L$PCRE2_PREFIX/lib'$ffi_link_args, '-L$ZLIB_PREFIX/lib', '-liconv', '-lpcre2-8', '-lz', '-lwasi-emulated-process-clocks', '-lwasi-emulated-signal', '-lwasi-emulated-getpid']

[host_machine]
system = 'wasi'
cpu_family = 'wasm32'
cpu = 'wasm32'
endian = 'little'
INI

export PKG_CONFIG_PATH="$ICONV_PREFIX/lib/pkgconfig:$PCRE2_PREFIX/lib/pkgconfig$ffi_pkg_config_path:$ZLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

patch_marker="$WORK/.source-patched-v2"
if [[ ! -f "$patch_marker" ]]; then
if ! grep -q "libiconv = declare_dependency" "$SRC/meson.build"; then
  iconv_lib="${ICONV_PREFIX}/lib"
  perl -0pi -e "s#libiconv = (?:dependency\\('iconv'\\)|cc\\.find_library\\('iconv', dirs: \\['[^']+'\\]\\))#libiconv = declare_dependency(link_args: ['$iconv_lib/libiconv.a'])#" "$SRC/meson.build"
fi

if grep -q "if host_system != 'windows'" "$SRC/gio/meson.build"; then
  perl -0pi -e "s#if host_system != 'windows'#if host_system not in ['windows', 'wasi']#" "$SRC/gio/meson.build"
fi
perl -0pi -e "s#if host_system not in \['windows', 'wasi'\]\n  unix_sources = files#if host_system != 'windows'\n  unix_sources = files#" "$SRC/gio/meson.build"

if grep -q "gio_launch_desktop = executable" "$SRC/gio/meson.build"; then
  perl -0pi -e "s#\\n    launch_desktop_sources = files\\('gio-launch-desktop\\.c'\\).*?\\n    gio_launch_desktop = executable\\('gio-launch-desktop'.*?\\n      link_args : noseh_link_args\\)##s" "$SRC/gio/meson.build"
fi

if grep -q "# Several installed executables" "$SRC/gio/meson.build"; then
  perl -0pi -e "s@\\n# Several installed executables.*?\\nif enable_systemtap@\\nif enable_systemtap@s" "$SRC/gio/meson.build"
fi
perl -0pi -e "s/#else \\/\\* !G_OS_WIN32 \\*\\/\n\n#include <sys\\/types\\.h>/#elif defined(G_PLATFORM_WASM)\\n\\n#include <sys\\/types.h>\\n#include <netdb.h>\\n#include <netinet\\/in.h>\\n#include <netinet\\/tcp.h>\\n#include <resolv.h>\\n#include <sys\\/socket.h>\\n#include <sys\\/un.h>\\n#include <net\\/if.h>\\n#include <arpa\\/inet.h>\\n#include <arpa\\/nameser.h>\\n\\n#else \\/\\* !G_OS_WIN32 \\&\\& !G_PLATFORM_WASM \\*\\/\\n\\n#include <sys\\/types.h>/" "$SRC/gio/gnetworking.h.in"
perl -0pi -e "s/#ifdef G_OS_UNIX\n#include \"glib-unix\\.h\"/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n#include \"glib-unix.h\"/" "$SRC/gio/gfile.c"
perl -0pi -e "s/#include \"glib-unix\\.h\"/#ifndef G_PLATFORM_WASM\\n#include \"glib-unix.h\"\\n#else\\nstatic gboolean g_unix_set_fd_nonblocking (gint fd, gboolean nonblock, GError **error) { (void) fd; (void) nonblock; (void) error; return TRUE; }\\n#endif/" "$SRC/gio/gsocket.c"
perl -0pi -e "s/#include \"glib-unix\\.h\"/#ifndef G_PLATFORM_WASM\\n#include \"glib-unix.h\"\\n#endif/" "$SRC/gio/gsubprocess.c"
perl -0pi -e "s/#include <glib-unix\\.h>/#ifndef G_PLATFORM_WASM\\n#include <glib-unix.h>\\n#endif/" "$SRC/gio/gsubprocess.c"
perl -0pi -e "s/#ifndef G_PLATFORM_WASM\n#include <glib-unix\\.h>\n#endif\n#include <fcntl\\.h>/#ifndef G_PLATFORM_WASM\\n#include <glib-unix.h>\\n#else\\n#define WIFEXITED(status) 0\\n#define WEXITSTATUS(status) (status)\\n#define WIFSIGNALED(status) 0\\n#define WTERMSIG(status) 0\\nstatic int kill (GPid pid, int sig) { (void) pid; (void) sig; errno = ENOSYS; return -1; }\\nstatic gboolean g_unix_set_fd_nonblocking (gint fd, gboolean nonblock, GError **error) { (void) fd; (void) nonblock; (void) error; return TRUE; }\\n#endif\\n#include <fcntl.h>/" "$SRC/gio/gsubprocess.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n#include \"glib-unix\\.h\"\n#include \"glib-unixprivate\\.h\"\n#endif/#ifdef G_OS_UNIX\\n#ifdef G_PLATFORM_WASM\\n#include <errno.h>\\n#include <signal.h>\\nstatic int pipe (int fds[2]) { (void) fds; errno = ENOSYS; return -1; }\\nstatic pid_t fork (void) { errno = ENOSYS; return -1; }\\nstatic int kill (pid_t pid, int sig) { (void) pid; (void) sig; errno = ENOSYS; return -1; }\\n#endif\\n#include \"glib-unix.h\"\\n#include \"glib-unixprivate.h\"\\n#endif/" "$SRC/gio/gtestdbus.c"
perl -0pi -e "s/#if defined\\(USE_STATFS\\) \\&\\& !defined\\(HAVE_STRUCT_STATFS_F_FSTYPENAME\\)/#if (defined(USE_STATFS) \\&\\& !defined(HAVE_STRUCT_STATFS_F_FSTYPENAME)) || (defined(USE_STATVFS) \\&\\& defined(HAVE_STRUCT_STATVFS_F_TYPE))/" "$SRC/gio/glocalfile.c"
perl -0pi -e "s|/\\* Common code \\{\\{\\{2 \\*/\\n#else\\n#error No _g_get_unix_mounts\\(\\) implementation for system|/\\* Common code {{{2 \\*/\\n#elif defined(G_PLATFORM_WASM)\\nstatic char *\\nget_mtab_monitor_file (void)\\n{\\n  return NULL;\\n}\\n\\nstatic GUnixMountEntry **\\n_g_unix_mounts_get_from_file (const char *table_path,\\n                              uint64_t   *time_read_out,\\n                              size_t     *n_entries_out)\\n{\\n  (void) table_path;\\n  if (time_read_out != NULL)\\n    *time_read_out = 0;\\n  if (n_entries_out != NULL)\\n    *n_entries_out = 0;\\n  return NULL;\\n}\\n\\nstatic GList *\\n_g_get_unix_mounts (void)\\n{\\n  return NULL;\\n}\\n#else\\n#error No _g_get_unix_mounts() implementation for system|" "$SRC/gio/gunixmounts.c"
perl -0pi -e "s|/\\* Common code \\{\\{\\{2 \\*/\\n#else\\n#error No g_get_mount_table\\(\\) implementation for system|/\\* Common code {{{2 \\*/\\n#elif defined(G_PLATFORM_WASM)\\nstatic GUnixMountPoint **\\n_g_unix_mount_points_get_from_file (const char *table_path,\\n                                    uint64_t   *time_read_out,\\n                                    size_t     *n_points_out)\\n{\\n  (void) table_path;\\n  if (time_read_out != NULL)\\n    *time_read_out = 0;\\n  if (n_points_out != NULL)\\n    *n_points_out = 0;\\n  return NULL;\\n}\\n\\nstatic GList *\\n_g_get_unix_mount_points (void)\\n{\\n  return NULL;\\n}\\n#else\\n#error No g_get_mount_table() implementation for system|" "$SRC/gio/gunixmounts.c"

perl -0pi -e "s/else\n  glib_sources \\+= files\\('glib-unix\\.c', 'gspawn-posix\\.c', 'giounix\\.c'\\)\n  platform_deps = \\[\\]\nendif/elif host_system == 'wasi'\\n  glib_sources += files('gspawn-posix.c')\\n  platform_deps = []\\nelse\\n  glib_sources += files('glib-unix.c', 'gspawn-posix.c', 'giounix.c')\\n  platform_deps = []\\nendif/" "$SRC/glib/meson.build"
perl -0pi -e "s/else\n  glib_os = '#define G_OS_UNIX'\nendif/elif host_system == 'wasi'\\n  glib_os = '''#define G_OS_UNIX\\n#define G_PLATFORM_WASM'''\\nelse\\n  glib_os = '#define G_OS_UNIX'\\nendif/" "$SRC/meson.build"
perl -0pi -e "s/if cc\\.has_function\\('posix_spawn', prefix : '#include <spawn\\.h>'\\)/if host_system != 'wasi' and cc.has_function('posix_spawn', prefix : '#include <spawn.h>')/" "$SRC/meson.build"
perl -0pi -e "s/else\n  g_module_suffix = 'so'\nendif/elif host_system == 'wasi'\\n  g_module_suffix = 'wasm'\\nelse\\n  g_module_suffix = 'so'\\nendif/" "$SRC/meson.build"

cat > "$SRC/glib/gbacktrace.c" <<'C'
#include "config.h"
#include "glibconfig.h"
#include "gbacktrace.h"
#include "gtypes.h"

GLIB_AVAILABLE_IN_ALL volatile gboolean glib_on_error_halt;
volatile gboolean glib_on_error_halt = TRUE;

void
g_on_error_query (const gchar *prg_name)
{
  (void) prg_name;
}

void
g_on_error_stack_trace (const gchar *prg_name)
{
  (void) prg_name;
}
C

cat > "$SRC/glib/gwakeup.c" <<'C'
#include "config.h"

#ifdef GLIB_COMPILATION
#include "gtypes.h"
#include "gmain.h"
#include "gpoll.h"
#include "gmem.h"
#else
#include <glib.h>
#endif

#include "gwakeup.h"

struct _GWakeup
{
  gint signalled;
};

GWakeup *
g_wakeup_new (void)
{
  return g_new0 (GWakeup, 1);
}

void
g_wakeup_get_pollfd (GWakeup *wakeup, GPollFD *poll_fd)
{
  (void) wakeup;
  poll_fd->fd = -1;
  poll_fd->events = G_IO_IN;
  poll_fd->revents = 0;
}

void
g_wakeup_acknowledge (GWakeup *wakeup)
{
  if (wakeup)
    wakeup->signalled = 0;
}

void
g_wakeup_signal (GWakeup *wakeup)
{
  if (wakeup)
    wakeup->signalled = 1;
}

void
g_wakeup_free (GWakeup *wakeup)
{
  g_free (wakeup);
}
C

cat > "$SRC/glib/gspawn-posix.c" <<'C'
#include "config.h"

#include "gspawn.h"
#include "gspawn-private.h"
#include "glibintl.h"

G_DEFINE_QUARK (g-exec-error-quark, g_spawn_error)
G_DEFINE_QUARK (g-spawn-exit-error-quark, g_spawn_exit_error)

gboolean
g_spawn_sync_impl (const gchar           *working_directory,
                   gchar                **argv,
                   gchar                **envp,
                   GSpawnFlags            flags,
                   GSpawnChildSetupFunc   child_setup,
                   gpointer               user_data,
                   gchar                **standard_output,
                   gchar                **standard_error,
                   gint                  *wait_status,
                   GError               **error)
{
  (void) working_directory;
  (void) argv;
  (void) envp;
  (void) flags;
  (void) child_setup;
  (void) user_data;
  (void) standard_output;
  (void) standard_error;
  (void) wait_status;
  g_set_error_literal (error, G_SPAWN_ERROR, G_SPAWN_ERROR_FAILED,
                       _("Process spawning is unsupported on WASI"));
  return FALSE;
}

gboolean
g_spawn_async_with_pipes_and_fds_impl (const gchar           *working_directory,
                                       const gchar * const   *argv,
                                       const gchar * const   *envp,
                                       GSpawnFlags            flags,
                                       GSpawnChildSetupFunc   child_setup,
                                       gpointer               user_data,
                                       gint                   stdin_fd,
                                       gint                   stdout_fd,
                                       gint                   stderr_fd,
                                       const gint            *source_fds,
                                       const gint            *target_fds,
                                       gsize                  n_fds,
                                       GPid                  *child_pid_out,
                                       gint                  *stdin_pipe_out,
                                       gint                  *stdout_pipe_out,
                                       gint                  *stderr_pipe_out,
                                       GError               **error)
{
  (void) working_directory;
  (void) argv;
  (void) envp;
  (void) flags;
  (void) child_setup;
  (void) user_data;
  (void) stdin_fd;
  (void) stdout_fd;
  (void) stderr_fd;
  (void) source_fds;
  (void) target_fds;
  (void) n_fds;
  (void) child_pid_out;
  (void) stdin_pipe_out;
  (void) stdout_pipe_out;
  (void) stderr_pipe_out;
  g_set_error_literal (error, G_SPAWN_ERROR, G_SPAWN_ERROR_FAILED,
                       _("Process spawning is unsupported on WASI"));
  return FALSE;
}

gboolean
g_spawn_check_wait_status_impl (gint wait_status, GError **error)
{
  (void) wait_status;
  g_set_error_literal (error, G_SPAWN_ERROR, G_SPAWN_ERROR_FAILED,
                       _("Process wait status is unsupported on WASI"));
  return FALSE;
}

void
g_spawn_close_pid_impl (GPid pid)
{
  (void) pid;
}
C

perl -0pi -e "s/  tzset \\(\\);/  #ifndef __wasi__\\n  tzset ();\\n  #endif/" "$SRC/glib/gdate.c"
perl -0pi -e "s/getuid \\(\\) != 0/1/" "$SRC/glib/gfileutils.c"
perl -0pi -e "s/seed\\[3\\] = getppid \\(\\);/seed[3] = 0;/" "$SRC/glib/grand.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n#include <sys\\/wait\\.h>/#ifdef G_OS_UNIX\\n#ifndef G_PLATFORM_WASM\\n#include <sys\\/wait.h>\\n#endif/" "$SRC/glib/gtestutils.c"
perl -0pi -e "s/#include <errno\\.h>/#include <errno.h>\\n#ifdef G_PLATFORM_WASM\\n#define WIFEXITED(status) 0\\n#define WEXITSTATUS(status) (status)\\n#define WIFSIGNALED(status) 0\\n#define WTERMSIG(status) 0\\nstatic int pipe (int fds[2]) { (void) fds; errno = ENOSYS; return -1; }\\nstatic int fork (void) { errno = ENOSYS; return -1; }\\nstatic int dup2 (int fd1, int fd2) { (void) fd1; (void) fd2; errno = ENOSYS; return -1; }\\nstatic int kill (pid_t pid, int sig) { (void) pid; (void) sig; errno = ENOSYS; return -1; }\\n#endif/" "$SRC/glib/gtestutils.c"
perl -0pi -e "s/#ifdef HAVE_SYS_RESOURCE_H\n  struct rlimit limit = \\{ 0, 0 \\};\n\n  \\(void\\) setrlimit \\(RLIMIT_CORE, \\&limit\\);\n#endif/#if defined(HAVE_SYS_RESOURCE_H) \\&\\& !defined(G_PLATFORM_WASM)\\n  struct rlimit limit = { 0, 0 };\\n\\n  (void) setrlimit (RLIMIT_CORE, \\&limit);\\n#endif/" "$SRC/glib/gtestutils.c"

if ! grep -q "G_OS_UNIX) && !defined(G_PLATFORM_WASM).*glib-unix.h" "$SRC/glib/gmain.c"; then
  perl -0pi -e "s/#ifdef G_OS_UNIX\n#include \"glib-unix.h\"\n#include <pthread.h>/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n#include \"glib-unix.h\"\\n#include <pthread.h>/" "$SRC/glib/gmain.c"
fi
perl -0pi -e "s/#ifndef G_OS_WIN32\nstatic void unref_unix_signal_handler_unlocked/#if !defined(G_OS_WIN32) \\&\\& !defined(G_PLATFORM_WASM)\\nstatic void unref_unix_signal_handler_unlocked/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\nstatic void g_unix_signal_handler/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\nstatic void g_unix_signal_handler/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifndef G_OS_WIN32\n\n\n\\/\\* UNIX signals work/#if !defined(G_OS_WIN32) \\&\\& !defined(G_PLATFORM_WASM)\\n\\n\\n\\/\\* UNIX signals work/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n\\/\\*\\*/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n\\/\\*\\*/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifdef G_OS_WIN32\n  return FALSE;/#if defined(G_OS_WIN32) || defined(G_PLATFORM_WASM)\\n  return FALSE;/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifdef G_OS_WIN32\n  child_exited = !!\\(child_watch_source->poll\\.revents \\& G_IO_IN\\);/#if defined(G_OS_WIN32) || defined(G_PLATFORM_WASM)\\n  child_exited = !!(child_watch_source->poll.revents \\& G_IO_IN);/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifndef G_OS_WIN32\n  GChildWatchSource \\*child_watch_source = \\(GChildWatchSource \\*\\) source;/#if !defined(G_OS_WIN32) \\&\\& !defined(G_PLATFORM_WASM)\\n  GChildWatchSource *child_watch_source = (GChildWatchSource *) source;/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifndef G_OS_WIN32\n\nstatic void\nwake_source/#if !defined(G_OS_WIN32) \\&\\& !defined(G_PLATFORM_WASM)\\n\\nstatic void\\nwake_source/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#else \\/\\* G_OS_WIN32 \\*\\/\n  \\{\n    gboolean child_exited = FALSE;/#elif defined(G_PLATFORM_WASM)\\n  wait_status = -1;\\n#else \\/\\* !G_OS_WIN32 \\&\\& !G_PLATFORM_WASM \\*\\/\\n  {\\n    gboolean child_exited = FALSE;/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifndef G_OS_WIN32\n\nstatic void\ng_unix_signal_handler/#if !defined(G_OS_WIN32) \\&\\& !defined(G_PLATFORM_WASM)\\n\\nstatic void\\ng_unix_signal_handler/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifndef G_OS_WIN32\n  g_return_val_if_fail \\(pid > 0, NULL\\);/#if !defined(G_OS_WIN32) \\&\\& !defined(G_PLATFORM_WASM)\\n  g_return_val_if_fail (pid > 0, NULL);/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifdef G_OS_WIN32\n  child_watch_source->poll\\.fd = \\(gintptr\\) pid;/#if defined(G_OS_WIN32) || defined(G_PLATFORM_WASM)\\n  child_watch_source->poll.fd = (gintptr) pid;/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n      if \\(g_atomic_int_get \\(&any_unix_signal_pending\\)\\)/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n      if (g_atomic_int_get (\\&any_unix_signal_pending))/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n      sigset_t prev_mask;/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n      sigset_t prev_mask;/" "$SRC/glib/gmain.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n      pthread_sigmask \\(SIG_SETMASK, \\&prev_mask, NULL\\);/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n      pthread_sigmask (SIG_SETMASK, \\&prev_mask, NULL);/" "$SRC/glib/gmain.c"
perl -0pi -e "s/guint\ng_get_num_processors \\(void\\)\n\\{\n#ifdef G_OS_WIN32/guint\\ng_get_num_processors (void)\\n{\\n#ifdef G_PLATFORM_WASM\\n  return 1;\\n#elif defined(G_OS_WIN32)/" "$SRC/glib/gthread.c"
perl -0pi -e "s/#elif defined\\(_SC_NPROCESSORS_ONLN\\) \\&\\& defined\\(THREADS_POSIX\\) \\&\\& defined\\(HAVE_PTHREAD_GETAFFINITY_NP\\)/#elif defined(_SC_NPROCESSORS_ONLN) \\&\\& defined(THREADS_POSIX) \\&\\& defined(HAVE_PTHREAD_GETAFFINITY_NP) \\&\\& !defined(G_PLATFORM_WASM)/" "$SRC/glib/gthread.c"
perl -0pi -e "s/void\ng_system_thread_exit \\(void\\)\n\\{\n  pthread_exit \\(NULL\\);/void\\ng_system_thread_exit (void)\\n{\\n#ifdef G_PLATFORM_WASM\\n  abort ();\\n#else\\n  pthread_exit (NULL);\\n#endif/" "$SRC/glib/gthread-posix.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n#include <pwd\\.h>\n#include <sys\\/utsname\\.h>/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n#include <pwd.h>\\n#include <sys\\/utsname.h>/" "$SRC/glib/gutils.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n      \\{\n        struct passwd \\*pw = NULL;/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n      {\\n        struct passwd *pw = NULL;/" "$SRC/glib/gutils.c"
perl -0pi -e "s/#if defined \\(G_OS_UNIX\\) \\&\\& !defined \\(__APPLE__\\)/#if defined (G_OS_UNIX) \\&\\& !defined (__APPLE__) \\&\\& !defined (G_PLATFORM_WASM)/" "$SRC/glib/gutils.c"
perl -0pi -e "s/#elif defined \\(G_OS_UNIX\\)\n  const gchar \\* const os_release_files\\[\\] = \\{ \"\\/etc\\/os-release\", \"\\/usr\\/lib\\/os-release\" \\};/#elif defined (G_PLATFORM_WASM)\\n  if (g_strcmp0 (key_name, G_OS_INFO_KEY_NAME) == 0)\\n    return g_strdup (\"WebAssembly\");\\n  if (g_strcmp0 (key_name, G_OS_INFO_KEY_ID) == 0)\\n    return g_strdup (\"wasm\");\\n  return NULL;\\n#elif defined (G_OS_UNIX)\\n  const gchar * const os_release_files[] = { \"\\/etc\\/os-release\", \"\\/usr\\/lib\\/os-release\" };/" "$SRC/glib/gutils.c"
perl -0pi -e "s/      tmp = g_malloc \\(size\\);\n      failed = \\(gethostname \\(tmp, size\\) == -1\\);/      tmp = g_malloc (size);\\n#ifdef G_PLATFORM_WASM\\n      g_strlcpy (tmp, \"wasi\", size);\\n      failed = FALSE;\\n#else\\n      failed = (gethostname (tmp, size) == -1);/" "$SRC/glib/gutils.c"
perl -0pi -e "s/      if \\(failed\\)\n        g_clear_pointer \\(\\&tmp, g_free\\);/      if (failed)\\n        g_clear_pointer (\\&tmp, g_free);\\n#endif/" "$SRC/glib/gutils.c"
perl -0pi -e "s/#elif defined\\(G_OS_UNIX\\)\n  uid_t ruid, euid, suid;/#elif defined(G_PLATFORM_WASM)\\n  return FALSE;\\n#elif defined(G_OS_UNIX)\\n  uid_t ruid, euid, suid;/" "$SRC/glib/gutils.c"
perl -0pi -e 's/quark_ht = g_hash_table_new \(g_str_hash, g_str_equal\);/#ifndef G_PLATFORM_WASM\n  quark_ht = g_hash_table_new (g_str_hash, g_str_equal);\n#endif/' "$SRC/glib/gquark.c"
perl -0pi -e 's/(quark_seq_id = 1;\n})/$1\n\n#ifdef G_PLATFORM_WASM\nstatic inline GQuark\nquark_find_locked (const gchar *string)\n{\n  for (GQuark quark = 1; quark < (GQuark) quark_seq_id; quark++)\n    if (quarks[quark] != NULL && strcmp (quarks[quark], string) == 0)\n      return quark;\n\n  return 0;\n}\n#endif/' "$SRC/glib/gquark.c"
perl -0pi -e 's/quark = GPOINTER_TO_UINT \(g_hash_table_lookup \(quark_ht, string\)\);/#ifdef G_PLATFORM_WASM\n  quark = quark_find_locked (string);\n#else\n  quark = GPOINTER_TO_UINT (g_hash_table_lookup (quark_ht, string));\n#endif/g' "$SRC/glib/gquark.c"
perl -0pi -e 's/  g_hash_table_insert \(quark_ht, string, GUINT_TO_POINTER \(quark\)\);/#ifndef G_PLATFORM_WASM\n  g_hash_table_insert (quark_ht, string, GUINT_TO_POINTER (quark));\n#endif/' "$SRC/glib/gquark.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n#include \"glib-unix\\.h\"/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n#include \"glib-unix.h\"/" "$SRC/gobject/gsourceclosure.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\nstatic gboolean\ng_unix_fd_source_closure_callback/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\nstatic gboolean\\ng_unix_fd_source_closure_callback/" "$SRC/gobject/gsourceclosure.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n  g_value_init \\(\\&params\\[0\\], G_TYPE_ULONG\\);/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n  g_value_init (\\&params[0], G_TYPE_ULONG);/" "$SRC/gobject/gsourceclosure.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n      else if \\(source->source_funcs == \\&g_unix_fd_source_funcs\\)/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n      else if (source->source_funcs == \\&g_unix_fd_source_funcs)/" "$SRC/gobject/gsourceclosure.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n               source->source_funcs == \\&g_unix_signal_funcs/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n               source->source_funcs == \\&g_unix_signal_funcs/" "$SRC/gobject/gsourceclosure.c"
perl -0pi -e "s/#ifdef G_OS_UNIX\n      source->source_funcs != \\&g_unix_fd_source_funcs/#if defined(G_OS_UNIX) \\&\\& !defined(G_PLATFORM_WASM)\\n      source->source_funcs != \\&g_unix_fd_source_funcs/" "$SRC/gobject/gsourceclosure.c"
perl -0pi -e 's/(gint\s+\(\*values_cmp\)\s+\(GParamSpec\s+\*pspec,\n\s+const GValue\s+\*value1,\n\s+const GValue\s+\*value2\);\n)/$1#ifdef G_PLATFORM_WASM\n  void          (*instance_init)        (GParamSpec   *pspec);\n#endif\n/' "$SRC/gobject/gparam.c"
perl -0pi -e 's/(  class->values_cmp = info->values_cmp;\n)/$1#ifdef G_PLATFORM_WASM\n  class->dummy[0] = info->instance_init;\n#endif\n/' "$SRC/gobject/gparam.c"
perl -0pi -e 's/(static void\ndefault_value_set_default \(GParamSpec \*pspec,\n\t\t\t   GValue     \*value\)\n)/#ifdef G_PLATFORM_WASM\nstatic void\nparam_spec_instance_init_wasm (GTypeInstance *instance,\n\t\t\t       gpointer       klass)\n{\n  GParamSpecClass *class = G_PARAM_SPEC_CLASS (klass);\n  void (*instance_init) (GParamSpec *pspec) = class->dummy[0];\n\n  if (instance_init)\n    instance_init ((GParamSpec *) instance);\n}\n#endif\n\n$1/' "$SRC/gobject/gparam.c"
perl -0pi -e 's/(  cinfo->value_type = pspec_info->value_type;\n)/$1#ifdef G_PLATFORM_WASM\n  cinfo->instance_init = pspec_info->instance_init;\n#endif\n/' "$SRC/gobject/gparam.c"
perl -0pi -e 's/info\.instance_init = \(GInstanceInitFunc\) pspec_info->instance_init;/#ifdef G_PLATFORM_WASM\n  info.instance_init = pspec_info->instance_init ? param_spec_instance_init_wasm : NULL;\n#else\n  info.instance_init = (GInstanceInitFunc) pspec_info->instance_init;\n#endif/' "$SRC/gobject/gparam.c"
perl -0pi -e 's/static void\s+type_name##_class_intern_init \(gpointer klass\) \\\n\{ \\/static void     type_name##_class_intern_init (gpointer klass, gpointer class_data) \\\n{ \\\n  (void) class_data; \\/g' "$SRC/gobject/gtype.h"
perl -0pi -e 's/static void     type_name##_class_init        \(TypeName##Class \*klass\); \\/static void     type_name##_class_init        (TypeName##Class *klass); \\\nstatic void     type_name##_instance_intern_init (GTypeInstance *instance, gpointer klass); \\/' "$SRC/gobject/gtype.h"
perl -0pi -e 's/_G_DEFINE_TYPE_EXTENDED_CLASS_INIT\(TypeName, type_name\) \\\n\\/_G_DEFINE_TYPE_EXTENDED_CLASS_INIT(TypeName, type_name) \\\n\\\nstatic void \\\ntype_name##_instance_intern_init (GTypeInstance *instance, gpointer klass) \\\n{ \\\n  (void) klass; \\\n  type_name##_init ((TypeName *) instance); \\\n} \\\n\\/' "$SRC/gobject/gtype.h"
perl -0pi -e 's/\(GInstanceInitFunc\)\(void \(\*\)\(void\)\) type_name##_init, \\/(GInstanceInitFunc)(void (*)(void)) type_name##_instance_intern_init, \\/' "$SRC/gobject/gtype.h"
perl -0pi -e 's/(#define _G_DEFINE_INTERFACE_EXTENDED_BEGIN\(TypeName, type_name, TYPE_PREREQ\) \\\n\\\nstatic void     type_name##_default_init        \(TypeName##Interface \*klass\); \\\n)/$1static void     type_name##_default_intern_init (gpointer klass, gpointer class_data); \\\n\\\nstatic void \\\ntype_name##_default_intern_init (gpointer klass, gpointer class_data) \\\n{ \\\n  (void) class_data; \\\n  type_name##_default_init ((TypeName##Interface *) klass); \\\n} \\\n\\\n/' "$SRC/gobject/gtype.h"
perl -0pi -e 's/\(GClassInitFunc\)\(void \(\*\)\(void\)\) type_name##_default_init, \\/(GClassInitFunc)(void (*)(void)) type_name##_default_intern_init, \\/' "$SRC/gobject/gtype.h"
perl -0pi -e 's/static void\s+g_object_do_class_init\s+\(GObjectClass\s+\*class\);/static void\tg_object_do_class_init\t\t\t(GObjectClass\t*class);\n#ifdef G_PLATFORM_WASM\nstatic void\tg_object_do_class_init_wasm\t\t(gpointer\t g_class,\n\t\t\t\t\t\t\t gpointer\t class_data);\n#endif/' "$SRC/gobject/gobject.c"
perl -0pi -e 's/static void\ng_object_do_class_init \(GObjectClass \*class\)/#ifdef G_PLATFORM_WASM\nstatic void\ng_object_do_class_init_wasm (gpointer g_class,\n\t\t\t  gpointer class_data)\n{\n  (void) class_data;\n  g_object_do_class_init ((GObjectClass *) g_class);\n}\n#endif\n\nstatic void\ng_object_do_class_init (GObjectClass *class)/' "$SRC/gobject/gobject.c"
perl -0pi -e 's/\(GClassInitFunc\) g_object_do_class_init,/#ifdef G_PLATFORM_WASM\n    g_object_do_class_init_wasm,\n#else\n    (GClassInitFunc) g_object_do_class_init,\n#endif/' "$SRC/gobject/gobject.c"
touch "$patch_marker"
fi

noffi_patch_marker="$WORK/.source-patched-noffi"
if [[ "$GLIB_USE_LIBFFI" != "1" && ! -f "$noffi_patch_marker" ]]; then
  perl -0pi -e "s/libffi_dep = dependency\\('libffi', version : '>= 3\\.0\\.0'\\)/libffi_dep = dependency('libffi', version : '>= 3.0.0', required : false)\\nif not libffi_dep.found()\\n  libffi_dep = declare_dependency()\\nendif/" "$SRC/meson.build"
  perl -0pi -e 's/#include <ffi\.h>/#ifndef __wasi__\n#include <ffi.h>\n#endif/g' "$SRC/gobject/gclosure.c"
  perl -0pi -e 's/#ifndef __wasi__\n#include <ffi\.h>\n#endif\nstatic ffi_type \*\nvalue_to_ffi_type.*\z/void\ng_cclosure_marshal_generic (GClosure     *closure,\n                            GValue       *return_gvalue,\n                            guint         n_param_values,\n                            const GValue *param_values,\n                            gpointer      invocation_hint,\n                            gpointer      marshal_data)\n{\n  (void) closure;\n  (void) return_gvalue;\n  (void) n_param_values;\n  (void) param_values;\n  (void) invocation_hint;\n  (void) marshal_data;\n  g_critical ("g_cclosure_marshal_generic is unsupported on WASI without libffi");\n}\n\nvoid\ng_cclosure_marshal_generic_va (GClosure *closure,\n                               GValue   *return_value,\n                               gpointer  instance,\n                               va_list   args_list,\n                               gpointer  marshal_data,\n                               int       n_params,\n                               GType    *param_types)\n{\n  (void) closure;\n  (void) return_value;\n  (void) instance;\n  (void) args_list;\n  (void) marshal_data;\n  (void) n_params;\n  (void) param_types;\n  g_critical ("g_cclosure_marshal_generic_va is unsupported on WASI without libffi");\n}\n/s' "$SRC/gobject/gclosure.c"
  touch "$noffi_patch_marker"
fi

rm -rf "$BUILD"
meson setup "$BUILD" "$SRC" \
  --cross-file "$cross" \
  --default-library=static \
  --buildtype=release \
  --wrap-mode="$GLIB_WRAP_MODE" \
  -Dtests=false \
  -Dinstalled_tests=false \
  -Ddocumentation=false \
  -Dintrospection=disabled \
  -Dnls=disabled \
  -Dselinux=disabled \
  -Dlibmount=disabled \
  -Dlibelf=disabled \
  -Dsysprof=disabled \
  -Dxattr=false \
  -Dglib_debug=disabled \
  -Dglib_assert=false \
  -Dglib_checks=false

ninja -C "$BUILD" \
  subprojects/proxy-libintl/libintl.a \
  glib/libglib-2.0.a \
  gobject/libgobject-2.0.a \
  gmodule/libgmodule-2.0.a \
  gio/libgio-2.0.a \
  gthread/libgthread-2.0.a

echo "$BUILD"
