/*
 * NURL nolibc — unikernel/nolibc/misc.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Process exit, environment, and the shims for the four things the
 * runtime asks a hosted libc for that a freestanding target does not
 * have: directory listing, terminal control, thread-local keys, and
 * glibc's backtrace.
 *
 * They FAIL rather than pretend. `opendir` returning NULL makes the
 * runtime's fs_* report "cannot open"; `isatty` answering 0 makes the
 * REPL use its non-tty path; `backtrace` finding no frames prints a
 * panic without one. The one thing none of them does is succeed
 * silently while doing nothing — that is how a stub becomes a bug
 * report from someone else, months later.
 */
#include "nolibc.h"

extern nl_ssize_t nl_write(int fd, const void *buf, nl_size_t n);
extern void nl_exit_group(int code);
extern int  nl_open(const char *path, int flags, int mode);
extern int  nl_close(int fd);
extern long nl_ret(long r);

char **environ;                     /* nl_environ is a macro for this */

void exit(int code) {
    fflush(stdout);
    fflush(stderr);
    nl_exit_group(code);
    for (;;) { }
}

/* Ownership and auto-drop both assume a panic path terminates — the
 * plan lists "the nolibc abort must not return" as a known trap. It
 * does not return. */
void abort(void) {
    static const char msg[] = "nurl: abort\n";
    fflush(stdout);
    nl_write(2, msg, sizeof msg - 1);
    nl_exit_group(134);                 /* 128 + SIGABRT, as a shell sees it */
    for (;;) { }
}

/* A freestanding target delivers no signals, so a handler can never be
 * installed. Reporting failure makes the runtime's guard-page memory
 * treat this like any other host without the plumbing (nurl_vmem_reserve
 * already answers 0 there) and keep its bounds-checked path — the same
 * capability-probe contract as the executable-page allocator. The
 * struct layout is irrelevant to a call that only fails, so the
 * prototype takes opaque pointers rather than dragging in signal.h. */
int sigaction(int sig, const void *act, void *oldact) {
    (void)sig; (void)act; (void)oldact;
    return -1;
}

char *getenv(const char *name) {
    nl_size_t n = strlen(name);
    char **e = nl_environ;
    if (!e) return 0;
    for (; *e; e++) {
        nl_size_t i;
        for (i = 0; i < n; i++) if ((*e)[i] != name[i]) break;
        if (i == n && (*e)[n] == '=') return *e + n + 1;
    }
    return 0;
}

/* ── thread-local keys, for a world with one thread ─────────────── */
/* The runtime uses one key (the panic journal's per-thread state).
 * A freestanding NURL has one vCPU and cooperative fibers, so "thread
 * local" and "global" are the same storage — but fibers that migrate
 * between real threads would need this to become fiber-local, which is
 * exactly what runtime_bare's scheduler will own. */
#define NL_KEYS 8
static void *nl_key_val[NL_KEYS];
static int nl_keys_used;

int pthread_key_create(unsigned int *key, void (*dtor)(void *)) {
    (void)dtor;
    if (nl_keys_used >= NL_KEYS) return 11 /* EAGAIN */;
    *key = (unsigned int)nl_keys_used++;
    return 0;
}
int pthread_setspecific(unsigned int key, const void *val) {
    if (key >= NL_KEYS) return 22 /* EINVAL */;
    nl_key_val[key] = (void *)val;
    return 0;
}
void *pthread_getspecific(unsigned int key) {
    return key < NL_KEYS ? nl_key_val[key] : 0;
}
int pthread_once(int *ctl, void (*fn)(void)) {
    if (*ctl == 0) { *ctl = 1; fn(); }
    return 0;
}

/* ── terminal ───────────────────────────────────────────────────── */
int isatty(int fd) { (void)fd; return 0; }
int tcgetattr(int fd, void *t) { (void)fd; (void)t; return -1; }
int tcsetattr(int fd, int act, const void *t) { (void)fd; (void)act; (void)t; return -1; }

/* ── directories and stat ───────────────────────────────────────
 * Real, over getdents64 and the stat syscalls, because the stubs that
 * "refused honestly" turned out to refuse a test the corpus expects to
 * work: fs_dir_list linked as soon as open/read existed and then
 * reported "not found" for a directory that was right there. A stub is
 * the right answer when the capability does not exist on the target;
 * on Linux it does, and the freestanding version of this file is where
 * the baked-in image reader will go (plan B7).
 *
 * The kernel's linux_dirent64 IS glibc's `struct dirent` field for
 * field — d_ino, d_off, d_reclen, d_type, d_name — which is how glibc
 * gets away with handing the raw buffer back, and why readdir can
 * return a pointer into it here. Same for `struct stat`: on x86_64 the
 * kernel's layout is the one the headers declare. runtime_core.o was
 * compiled against those headers, so anything else would be silent
 * corruption rather than a compile error. */
#define NL_SYS_getdents64 217
#define NL_SYS_stat        4
#define NL_SYS_fstat       5
#define NL_SYS_lstat       6
#define NL_O_RDONLY_DIR   (0 | 0200000)   /* O_RDONLY | O_DIRECTORY */

struct nl_dir {
    int fd;
    int pos;
    int len;
    char buf[8192];
};

void *opendir(const char *path) {
    struct nl_dir *d;
    int fd = nl_open(path, NL_O_RDONLY_DIR, 0);
    if (fd < 0) return 0;
    d = (struct nl_dir *)malloc(sizeof(struct nl_dir));
    if (!d) { nl_close(fd); return 0; }
    d->fd = fd; d->pos = 0; d->len = 0;
    return d;
}

void *readdir(void *dp) {
    struct nl_dir *d = (struct nl_dir *)dp;
    if (!d) return 0;
    if (d->pos >= d->len) {
        long r = nl_syscall6(NL_SYS_getdents64, d->fd, (long)d->buf,
                             (long)sizeof d->buf, 0, 0, 0);
        if (r <= 0) return 0;                  /* end of directory, or error */
        d->len = (int)r;
        d->pos = 0;
    }
    {
        char *ent = d->buf + d->pos;
        unsigned short reclen;
        memcpy(&reclen, ent + 16, sizeof reclen);   /* d_reclen */
        if (reclen == 0) return 0;                  /* malformed: stop, do not spin */
        d->pos += reclen;
        return ent;
    }
}

int closedir(void *dp) {
    struct nl_dir *d = (struct nl_dir *)dp;
    int r;
    if (!d) return -1;
    r = nl_close(d->fd);
    free(d);
    return r;
}

int lstat(const char *path, void *st) {
    return (int)nl_ret(nl_syscall6(NL_SYS_lstat, (long)path, (long)st, 0, 0, 0, 0));
}
int stat(const char *path, void *st) {
    return (int)nl_ret(nl_syscall6(NL_SYS_stat, (long)path, (long)st, 0, 0, 0, 0));
}
int fstat(int fd, void *st) {
    return (int)nl_ret(nl_syscall6(NL_SYS_fstat, fd, (long)st, 0, 0, 0, 0));
}

/* utimensat(2) — what `touch` needs to set a timestamp. The syscall is
 * there on Linux; on the guest, nl_syscall6 answers -ENOSYS and the
 * caller reports it, which is the truth about a machine whose filesystem
 * may be a read-only image in its own text segment. */
#define NL_SYS_utimensat 280

int utimensat(int dirfd, const char *path, const void *times, int flags) {
    return (int)nl_ret(nl_syscall6(NL_SYS_utimensat, dirfd, (long)path,
                                   (long)times, flags, 0, 0));
}

extern char *getcwd(char *buf, unsigned long size);
extern long  readlink(const char *path, char *buf, unsigned long size);
extern int   access(const char *path, int mode);

/* The filesystem and credential calls this file BUILDS ON — chmod,
 * link, symlink, readlink, getcwd, the uid/gid quartet, getgroups,
 * uname and sysconf — are the bottom edge, and the bottom edge is
 * per-target: `syscall_linux.c` makes them syscalls, and the guest's
 * `boot/nosys.c` answers them for a machine with one address space and
 * no user database. Everything below is written against those and is
 * the same code on both.
 */

/* realpath(3) — libc's, not a syscall, so it is written out here.
 *
 * Absolutise against the working directory, then consume the path one
 * component at a time: `.` is dropped, `..` pops the resolved prefix,
 * and anything that turns out to be a symlink is replaced by its target
 * followed by whatever of the path is still unconsumed. The link budget
 * is 40, matching Linux's own ELOOP threshold, because a symlink cycle
 * must terminate as an error rather than as a hang.
 *
 * On the guest there are no symlinks, so this reduces to the lexical
 * normalisation — which is the right answer there, not an approximation
 * of one.
 */
#define NL_PATH_MAX 4096

static int nl_rp_push(char *out, int *len, const char *seg, int seglen) {
    if (*len + seglen + 2 >= NL_PATH_MAX) return -1;
    out[(*len)++] = '/';
    memcpy(out + *len, seg, (nl_size_t)seglen);
    *len += seglen;
    out[*len] = 0;
    return 0;
}

char *realpath(const char *path, char *resolved) {
    static char left[2][NL_PATH_MAX];   /* the path still to consume */
    static char out[NL_PATH_MAX];       /* the resolved prefix */
    static char link_buf[NL_PATH_MAX];
    int which = 0, li = 0, llen = 0, olen = 0, links = 0;

    if (!path || !*path) { errno = 2 /* ENOENT */; return 0; }

    if (path[0] == '/') {
        nl_size_t n = strlen(path);
        if (n >= NL_PATH_MAX) { errno = 36 /* ENAMETOOLONG */; return 0; }
        memcpy(left[0], path, n + 1);
        llen = (int)n;
    } else {
        nl_size_t n;
        if (!getcwd(left[0], NL_PATH_MAX)) return 0;
        llen = (int)strlen(left[0]);
        if (llen == 1 && left[0][0] == '/') llen = 0;
        n = strlen(path);
        if (llen + 1 + (int)n >= NL_PATH_MAX) { errno = 36; return 0; }
        left[0][llen++] = '/';
        memcpy(left[0] + llen, path, n + 1);
        llen += (int)n;
    }

    out[0] = 0;
    for (;;) {
        char *cur = left[which];
        int start, seglen;
        while (li < llen && cur[li] == '/') li++;
        if (li >= llen) break;
        start = li;
        while (li < llen && cur[li] != '/') li++;
        seglen = li - start;

        if (seglen == 1 && cur[start] == '.') continue;
        if (seglen == 2 && cur[start] == '.' && cur[start + 1] == '.') {
            while (olen > 0 && out[olen - 1] != '/') olen--;
            if (olen > 0) olen--;               /* drop the '/' as well */
            out[olen] = 0;
            continue;
        }
        if (nl_rp_push(out, &olen, cur + start, seglen) != 0) {
            errno = 36;
            return 0;
        }
        {
            long n = readlink(out, link_buf, NL_PATH_MAX - 1);
            if (n > 0) {
                char *next = left[which ^ 1];
                int rest = llen - li;
                int nlen = 0;
                if (++links > 40) { errno = 40 /* ELOOP */; return 0; }
                link_buf[n] = 0;
                if ((int)n + rest + 2 >= NL_PATH_MAX) { errno = 36; return 0; }
                /* The link's target, then whatever of the path we have
                 * not walked yet, becomes the new work list. */
                memcpy(next, link_buf, (nl_size_t)n);
                nlen = (int)n;
                if (rest > 0) {
                    next[nlen++] = '/';
                    memcpy(next + nlen, cur + li, (nl_size_t)rest);
                    nlen += rest;
                }
                next[nlen] = 0;
                /* An absolute target restarts from the root; a relative
                 * one is resolved against the link's own directory, so
                 * the last component pops off first. */
                while (olen > 0 && out[olen - 1] != '/') olen--;
                if (olen > 0) olen--;
                out[olen] = 0;
                if (link_buf[0] == '/') { olen = 0; out[0] = 0; }
                which ^= 1;
                llen = nlen;
                li = 0;
            }
        }
    }
    if (olen == 0) { out[olen++] = '/'; out[olen] = 0; }
    /* POSIX: every component must exist, and a caller distinguishes
     * "this is where that path would be" from "this is where it IS" by
     * whether realpath answered at all. The lexical result of a missing
     * path is a plausible string, which is worse than no answer —
     * `path_canonical` is specified to say None. */
    if (access(out, 0 /* F_OK */) != 0) {
        errno = 2 /* ENOENT */;
        return 0;
    }
    if (resolved) {
        memcpy(resolved, out, (nl_size_t)olen + 1);
        return resolved;
    }
    {
        char *heap = (char *)malloc((nl_size_t)olen + 1);
        if (!heap) return 0;
        memcpy(heap, out, (nl_size_t)olen + 1);
        return heap;
    }
}

/* localtime_r(3) — there is no zone database on a machine whose whole
 * filesystem may be its own text segment, and a -nostdlib Linux build
 * has no /etc/localtime reader either. The honest answer is "no local
 * time", and runtime_core.c's nurl_tz_offset turns that into 0, i.e.
 * UTC. Reporting a fabricated offset would put every timestamp an hour
 * off, twice a year, silently. */
void *localtime_r(const void *t, void *tm) { (void)t; (void)tm; return 0; }

/* ── the user database ──────────────────────────────────────────
 * There isn't one. A machine with no /etc/passwd has no name for a uid,
 * and saying so is what makes `ls -l` print the number instead of
 * inventing `root`. runtime_core.c's nurl_user_name / nurl_group_name
 * treat NULL exactly that way. */
void *getpwuid(unsigned int uid) { (void)uid; return 0; }
void *getgrgid(unsigned int gid) { (void)gid; return 0; }

/* ── backtrace ──────────────────────────────────────────────────── */
/* glibc's backtrace walks .eh_frame; a -nostdlib link has no unwinder,
 * so the honest answer is "no frames", which the runtime prints as a
 * panic with an empty trace rather than crashing inside the printer. */
int backtrace(void **buf, int size) { (void)buf; (void)size; return 0; }
void backtrace_symbols_fd(void *const *buf, int size, int fd) {
    (void)buf; (void)size; (void)fd;
}

/* ── environment ────────────────────────────────────────────────
 * setenv/unsetenv rewrite the vector `_start` captured. The strings
 * are heap copies and the vector is reallocated, so the kernel's
 * original block is never written to — that block is above the stack
 * and shared with argv, and growing it in place is how a nolibc
 * corrupts its own arguments. */
static char **nl_env_owned;      /* our copy, once we have made one */
static int nl_env_n, nl_env_cap;

static int nl_env_adopt(void) {
    int n = 0, i;
    char **e;
    if (nl_env_owned) return 1;
    for (e = nl_environ; e && *e; e++) n++;
    nl_env_cap = n + 8;
    nl_env_owned = (char **)malloc((nl_size_t)(nl_env_cap + 1) * sizeof(char *));
    if (!nl_env_owned) return 0;
    for (i = 0; i < n; i++) nl_env_owned[i] = nl_environ[i];
    nl_env_owned[n] = 0;
    nl_env_n = n;
    nl_environ = nl_env_owned;
    return 1;
}

static int nl_env_find(const char *name, nl_size_t len) {
    int i;
    for (i = 0; i < nl_env_n; i++) {
        nl_size_t j;
        for (j = 0; j < len; j++) if (nl_env_owned[i][j] != name[j]) break;
        if (j == len && nl_env_owned[i][len] == '=') return i;
    }
    return -1;
}

int setenv(const char *name, const char *value, int overwrite) {
    nl_size_t nlen = strlen(name), vlen = strlen(value);
    char *entry;
    int at;
    if (!nl_env_adopt()) return -1;
    at = nl_env_find(name, nlen);
    if (at >= 0 && !overwrite) return 0;
    entry = (char *)malloc(nlen + vlen + 2);
    if (!entry) return -1;
    memcpy(entry, name, nlen);
    entry[nlen] = '=';
    memcpy(entry + nlen + 1, value, vlen);
    entry[nlen + vlen + 1] = 0;
    if (at >= 0) { nl_env_owned[at] = entry; return 0; }
    if (nl_env_n + 1 >= nl_env_cap) {
        int newcap = nl_env_cap * 2 + 8;
        char **grown = (char **)realloc(nl_env_owned,
                                        (nl_size_t)(newcap + 1) * sizeof(char *));
        if (!grown) return -1;
        nl_env_owned = grown;
        nl_env_cap = newcap;
        nl_environ = nl_env_owned;
    }
    nl_env_owned[nl_env_n++] = entry;
    nl_env_owned[nl_env_n] = 0;
    return 0;
}

int unsetenv(const char *name) {
    int at;
    if (!nl_env_adopt()) return -1;
    at = nl_env_find(name, strlen(name));
    if (at < 0) return 0;
    for (; at < nl_env_n - 1; at++) nl_env_owned[at] = nl_env_owned[at + 1];
    nl_env_owned[--nl_env_n] = 0;
    return 0;
}
