// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// nurl-sandbox — run one playground build tool confined by Landlock
// (Agora #207).
//
//   nurl-sandbox [--require] [--ro=PATH]... [--rw=PATH]... -- TOOL [ARG]...
//   nurl-sandbox --probe
//
// nurlapi compiles other people's code. Every tool it starts for a build
// (nurlc, clang, wasm-opt, zig, mingw gcc, the unikernel scripts, qemu)
// runs under this wrapper, which restricts the tool, before exec, to:
//   * read and execute: the system and toolchain trees (DEFAULT_RO below)
//     and each --ro=PATH;
//   * read and write: each --rw=PATH — the request's own build directory,
//     and the zig cache; TMPDIR points at the first one;
//   * no TCP bind or connect (Landlock ABI 4+), and no signals or abstract
//     unix sockets outside the sandbox (ABI 6+).
// Everything else is invisible to it: the server binary and static tree
// under /app, other builds' directories, /tmp, /home. The restriction is
// inherited by every process the tool starts and cannot be lifted.
//
// Landlock needs no privilege, but the kernel may lack it. Then the tool
// runs unconfined, unless --require is given: then nothing runs (exit
// 125). --probe prints `landlock <abi>` or `unavailable: <reason>` and
// exits 0; nurlapi reports it on /health.
//
// The constants are spelled out here so the build does not depend on the
// installed kernel headers knowing the newer ABIs.

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef __NR_landlock_create_ruleset
#define __NR_landlock_create_ruleset 444
#define __NR_landlock_add_rule 445
#define __NR_landlock_restrict_self 446
#endif

#define LL_CREATE_RULESET_VERSION (1U << 0)
#define LL_RULE_PATH_BENEATH 1

#define FS_EXECUTE (1ULL << 0)
#define FS_WRITE_FILE (1ULL << 1)
#define FS_READ_FILE (1ULL << 2)
#define FS_READ_DIR (1ULL << 3)
#define FS_REMOVE_DIR (1ULL << 4)
#define FS_REMOVE_FILE (1ULL << 5)
#define FS_MAKE_CHAR (1ULL << 6)
#define FS_MAKE_DIR (1ULL << 7)
#define FS_MAKE_REG (1ULL << 8)
#define FS_MAKE_SOCK (1ULL << 9)
#define FS_MAKE_FIFO (1ULL << 10)
#define FS_MAKE_BLOCK (1ULL << 11)
#define FS_MAKE_SYM (1ULL << 12)
#define FS_REFER (1ULL << 13)    // ABI 2
#define FS_TRUNCATE (1ULL << 14) // ABI 3
#define NET_BIND_TCP (1ULL << 0) // ABI 4
#define NET_CONNECT_TCP (1ULL << 1)
#define SCOPE_ABSTRACT_UNIX_SOCKET (1ULL << 0) // ABI 6
#define SCOPE_SIGNAL (1ULL << 1)

#define FS_V1 (FS_EXECUTE | FS_WRITE_FILE | FS_READ_FILE | FS_READ_DIR | \
               FS_REMOVE_DIR | FS_REMOVE_FILE | FS_MAKE_CHAR | FS_MAKE_DIR | \
               FS_MAKE_REG | FS_MAKE_SOCK | FS_MAKE_FIFO | FS_MAKE_BLOCK | \
               FS_MAKE_SYM)
#define FS_RO (FS_EXECUTE | FS_READ_FILE | FS_READ_DIR)
// What Landlock allows on a path that is not a directory.
#define FS_FILE (FS_EXECUTE | FS_WRITE_FILE | FS_READ_FILE | FS_TRUNCATE)

struct ruleset_attr {
    uint64_t handled_access_fs;
    uint64_t handled_access_net;
    uint64_t scoped;
};

struct path_beneath_attr {
    uint64_t allowed_access;
    int32_t parent_fd;
} __attribute__((packed));

// The system and toolchain trees a build reads. /opt holds the NURL tree,
// wasi-sdk, zig, the mingw curl and the unikernel caches in the image.
static const char *const DEFAULT_RO[] = {
    "/usr", "/lib", "/lib32", "/lib64", "/libx32", "/bin", "/sbin",
    "/etc", "/opt", "/proc", "/sys", "/dev",
};

#define MAX_PATHS 64

static int landlock_abi(void) {
    long abi = syscall(__NR_landlock_create_ruleset, NULL, 0,
                       LL_CREATE_RULESET_VERSION);
    return abi < 0 ? -errno : (int)abi;
}

// Allow `access` beneath `path`. A path that does not exist is skipped:
// the default list names directories some systems do not have.
static int allow(int ruleset, const char *path, uint64_t access,
                 uint64_t handled) {
    int fd = open(path, O_PATH | O_CLOEXEC);
    if (fd < 0) return errno == ENOENT ? 0 : -1;
    struct stat st;
    if (fstat(fd, &st) == 0 && !S_ISDIR(st.st_mode)) access &= FS_FILE;
    struct path_beneath_attr pb = {
        .allowed_access = access & handled,
        .parent_fd = fd,
    };
    int rc = 0;
    if (pb.allowed_access != 0 &&
        syscall(__NR_landlock_add_rule, ruleset, LL_RULE_PATH_BENEATH, &pb, 0))
        rc = -1;
    int saved = errno;
    close(fd);
    errno = saved;
    return rc;
}

static int confine(int abi, const char *const *ro, int nro,
                   const char *const *rw, int nrw) {
    struct ruleset_attr attr = {0};
    attr.handled_access_fs = FS_V1;
    if (abi >= 2) attr.handled_access_fs |= FS_REFER;
    if (abi >= 3) attr.handled_access_fs |= FS_TRUNCATE;
    if (abi >= 4) attr.handled_access_net = NET_BIND_TCP | NET_CONNECT_TCP;
    if (abi >= 6) attr.scoped = SCOPE_ABSTRACT_UNIX_SOCKET | SCOPE_SIGNAL;
    uint64_t handled = attr.handled_access_fs;

    int ruleset = (int)syscall(__NR_landlock_create_ruleset, &attr,
                               sizeof attr, 0);
    if (ruleset < 0) return -1;
    size_t i;
    for (i = 0; i < sizeof DEFAULT_RO / sizeof DEFAULT_RO[0]; i++)
        if (allow(ruleset, DEFAULT_RO[i], FS_RO, handled)) goto fail;
    for (int k = 0; k < nro; k++)
        if (allow(ruleset, ro[k], FS_RO, handled)) goto fail;
    for (int k = 0; k < nrw; k++)
        if (allow(ruleset, rw[k], handled, handled)) goto fail;
    // Tools write to /dev/null; the rest of /dev stays read-only.
    if (allow(ruleset, "/dev/null", FS_READ_FILE | FS_WRITE_FILE | FS_TRUNCATE,
              handled))
        goto fail;
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) goto fail;
    if (syscall(__NR_landlock_restrict_self, ruleset, 0)) goto fail;
    close(ruleset);
    return 0;
fail:;
    int saved = errno;
    close(ruleset);
    errno = saved;
    return -1;
}

static int usage(void) {
    fprintf(stderr,
            "usage: nurl-sandbox [--require] [--ro=PATH]... [--rw=PATH]... "
            "-- TOOL [ARG]...\n"
            "       nurl-sandbox --probe\n");
    return 2;
}

int main(int argc, char **argv) {
    const char *ro[MAX_PATHS], *rw[MAX_PATHS];
    int nro = 0, nrw = 0, require = 0, i;

    if (argc == 2 && strcmp(argv[1], "--probe") == 0) {
        int abi = landlock_abi();
        if (abi > 0) printf("landlock %d\n", abi);
        else printf("unavailable: %s\n", strerror(-abi));
        return 0;
    }
    for (i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "--") == 0) { i++; break; }
        if (strcmp(a, "--require") == 0) { require = 1; continue; }
        if (strncmp(a, "--ro=", 5) == 0 && a[5] && nro < MAX_PATHS) {
            ro[nro++] = a + 5;
            continue;
        }
        if (strncmp(a, "--rw=", 5) == 0 && a[5] && nrw < MAX_PATHS) {
            rw[nrw++] = a + 5;
            continue;
        }
        return usage();
    }
    if (i >= argc) return usage();

    int abi = landlock_abi();
    if (abi > 0) {
        if (confine(abi, ro, nro, rw, nrw)) {
            fprintf(stderr, "nurl-sandbox: could not confine %s: %s\n",
                    argv[i], strerror(errno));
            return 125;
        }
    } else if (require) {
        fprintf(stderr,
                "nurl-sandbox: Landlock is unavailable (%s); refusing to run "
                "%s unconfined\n",
                strerror(-abi), argv[i]);
        return 125;
    }
    if (nrw > 0 && setenv("TMPDIR", rw[0], 1)) {
        fprintf(stderr, "nurl-sandbox: setenv: %s\n", strerror(errno));
        return 125;
    }
    execvp(argv[i], argv + i);
    fprintf(stderr, "nurl-sandbox: %s: %s\n", argv[i], strerror(errno));
    return 127;
}
