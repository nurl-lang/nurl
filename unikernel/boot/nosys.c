/*
 * NURL unikernel — unikernel/boot/nosys.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The calls this machine does not have, said out loud.
 *
 * A unikernel is ONE program in ONE address space: there is nothing to
 * fork, nothing to exec, no signals to deliver and no writable
 * filesystem to make a temporary file in. The plan lists all of that
 * under non-goals and the whole directory agrees with it.
 *
 * But "the machine has no processes" and "a program that mentions
 * processes cannot be built for it" are different statements, and only
 * the first one is true. A real program — swarm-mcp is the case that
 * forced this file — is a compute node that also knows how to compile a
 * kernel by running the toolchain. Nothing about the node needs a
 * subprocess; one leaf of one feature does. Without these symbols the
 * whole image fails to LINK, and the answer "then port fork to a
 * unikernel" is the wrong one.
 *
 * So each of these refuses the way its callers already handle:
 *
 *   pipe/fork/execvp/waitpid/dup2/fcntl/poll   -1, which is what
 *       std/process.nu's POSIX path checks first — a failed `pipe` is
 *       reported as ProcessIo before a fork is ever attempted.
 *   nurl_proc_run                              a zero handle, which
 *       std/process.nu maps to ProcessOther (its `raw == 0` branch).
 *   signal                                     SIG_ERR.
 *   mkstemp/rename/rmdir                       -1: the filesystem is
 *       the tar inside the image and it is read-only, which `unlink`
 *       and `mkdir` in platform_x86.c already answer the same way.
 *
 * NONE of them succeeds while doing nothing. That is the rule this
 * directory is built on, and it is what makes the failure a caller's
 * ordinary error path instead of a mystery: swarm-mcp asked to build a
 * wasm kernel in the guest reports that it could not run the compiler,
 * which is exactly what happened.
 *
 * LINKED ONLY INTO GUEST IMAGES (build_unikernel.sh), never into the
 * Linux -nostdlib build. That build's corpus runner buckets a test by
 * the symbols it cannot resolve, so defining these there would turn 21
 * honest NEEDS-BARE results — processes and signals, which that build
 * genuinely does not have either — into 21 failures.
 */

#include "../../stdlib/nurl_version_gen.h"

typedef unsigned long ns_size_t;

extern int nl_errno_slot;

#define NS_ENOSYS 38
#define NS_EROFS  30

static int ns_refuse(int err) { nl_errno_slot = err; return -1; }

/* ── the filesystem calls this machine does not have ─────────────
 *
 * The image's filesystem is a tar in the text segment plus, when there
 * is one, a FAT volume on a virtio disk. Neither carries POSIX
 * permission bits or symlinks, so `chmod` and the link calls refuse
 * rather than pretend: a script that believes it just made a key file
 * unreadable, on a machine where it did nothing of the sort, is the
 * failure this whole file exists to prevent. */
int chmod(const char *p, int mode)   { (void)p; (void)mode; return ns_refuse(NS_EROFS); }
int link(const char *a, const char *b) { (void)a; (void)b; return ns_refuse(NS_ENOSYS); }
int symlink(const char *t, const char *l) { (void)t; (void)l; return ns_refuse(NS_ENOSYS); }
long readlink(const char *p, char *b, unsigned long n) {
    (void)p; (void)b; (void)n;
    /* EINVAL, not ENOSYS: "that is not a symlink" is the true answer on
     * a filesystem that has none, and it is the answer `readlink` and
     * `ls -l` already know how to handle. */
    return ns_refuse(22);
}

/* ── the working directory ───────────────────────────────────────
 * There is exactly one namespace and the program starts at its root, so
 * `/` is not a placeholder here — it is the answer. */
char *getcwd(char *buf, unsigned long size) {
    if (!buf || size < 2) { nl_errno_slot = 34 /* ERANGE */; return 0; }
    buf[0] = '/';
    buf[1] = 0;
    return buf;
}

/* ── credentials ─────────────────────────────────────────────────
 * One program, one address space, nothing above it: it is uid 0 in the
 * only sense the word can have here. There is no user database to give
 * that number a name — nurl_user_name answers NULL and every caller
 * prints the number, which is what `ls -l` on an unmapped NFS id does
 * on any machine. */
int getuid(void)  { return 0; }
int getgid(void)  { return 0; }
int geteuid(void) { return 0; }
int getegid(void) { return 0; }

int getgroups(int size, unsigned int *list) {
    (void)size; (void)list;
    return 0;                       /* no supplementary groups, truthfully */
}

/* ── uname(2) ────────────────────────────────────────────────────
 * A guest CAN answer this, and should: `uname -a` is the first thing
 * anyone types to find out where they are, and "unknown" would be a
 * worse answer than the true one. `struct utsname` is six fixed 65-byte
 * fields on Linux, which is the layout runtime_core.c was compiled
 * against. */
static void ns_field(char *base, int idx, const char *text) {
    char *p = base + idx * 65;
    int i = 0;
    while (text[i] && i < 64) { p[i] = text[i]; i++; }
    p[i] = 0;
}

int uname(void *buf) {
    char *b = (char *)buf;
    if (!b) return ns_refuse(14 /* EFAULT */);
    ns_field(b, 0, "NURL");
    ns_field(b, 1, "unikernel");
    ns_field(b, 2, NURL_VERSION);
    ns_field(b, 3, "#1 NURL unikernel");
#if defined(__aarch64__)
    ns_field(b, 4, "aarch64");
#elif defined(__riscv)
    ns_field(b, 4, "riscv64");
#else
    ns_field(b, 4, "x86_64");
#endif
    ns_field(b, 5, "");
    return 0;
}

/* sysconf(3) — one vCPU, which is the machine v1 is. */
long sysconf(int name) { return name == 84 ? 1 : -1; }

/* ── processes ───────────────────────────────────────────────── */

int pipe(int fds[2]) {
    /* The fds are left untouched: std/process.nu reads them only after
     * a non-negative return, and writing -1 into a caller's array on
     * the failure path is one more thing to get wrong. */
    (void)fds;
    return ns_refuse(NS_ENOSYS);
}

int fork(void)                          { return ns_refuse(NS_ENOSYS); }
int execvp(const char *f, char *const a[]) { (void)f; (void)a; return ns_refuse(NS_ENOSYS); }
int waitpid(int pid, int *st, int opt)  { (void)pid; (void)st; (void)opt; return ns_refuse(NS_ENOSYS); }
int dup2(int a, int b)                  { (void)a; (void)b; return ns_refuse(NS_ENOSYS); }
int fcntl(int fd, int cmd, long arg)    { (void)fd; (void)cmd; (void)arg; return ns_refuse(NS_ENOSYS); }

/* poll over pipes to a child. The guest's own readiness lives in
 * unikernel/net/sockets.nu and never comes through here. */
int poll(void *fds, unsigned long n, int timeout_ms) {
    (void)fds; (void)n; (void)timeout_ms;
    return ns_refuse(NS_ENOSYS);
}

/* SIG_ERR is (void*)-1 — "this signal could not be handled", which is
 * the honest answer on a machine that delivers none. */
void *signal(int signum, void *handler) {
    (void)signum; (void)handler;
    nl_errno_slot = NS_ENOSYS;
    return (void *)-1;
}

int kill(int pid, int sig)   { (void)pid; (void)sig; return ns_refuse(NS_ENOSYS); }

/* ── the runtime's process API ───────────────────────────────── */

/* Zero, not a result block with an error in it: std/process.nu's
 * `__process_dispatch` has a `raw == 0` branch that answers
 * ProcessOther, so this needs no allocation on a path that exists
 * because something already went wrong. */
long long nurl_proc_run(const char *cmd, const char *argv_buf,
                        long long argc, const char *stdin_blob) {
    (void)cmd; (void)argv_buf; (void)argc; (void)stdin_blob;
    return 0;
}

long long nurl_proc_exit_code(long long h) { (void)h; return -1; }
long long nurl_proc_err_kind(long long h)  { (void)h; return 4; }  /* OTHER */
const char *nurl_proc_stdout(long long h)  { (void)h; return ""; }
const char *nurl_proc_stderr(long long h)  { (void)h; return ""; }
long long nurl_proc_stdout_len(long long h) { (void)h; return 0; }
long long nurl_proc_stderr_len(long long h) { (void)h; return 0; }
void nurl_proc_free(long long h)           { (void)h; }

/* ── writing to a filesystem ─────────────────────────────────── */
/*
 * `rename`, `rmdir`, `truncate`, `fsync` and `mkstemp` USED to live
 * here, refusing with EROFS, because the only filesystem this machine
 * had was a tar inside its own text segment. They moved to
 * `boot/vfs.c` when the guest grew a block device: the refusal is
 * still what a diskless machine answers, but it is now a fact about
 * the filesystem rather than about the machine, and one file has to
 * hold both answers. Every caller stayed put, which is what that
 * comment always promised would happen.
 */
