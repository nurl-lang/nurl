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

char **nl_environ;

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

/* ── directories and stat ───────────────────────────────────────── */
void *opendir(const char *path) { (void)path; return 0; }
void *readdir(void *d) { (void)d; return 0; }
int   closedir(void *d) { (void)d; return -1; }
int   lstat(const char *path, void *st) { (void)path; (void)st; return -1; }

/* ── backtrace ──────────────────────────────────────────────────── */
/* glibc's backtrace walks .eh_frame; a -nostdlib link has no unwinder,
 * so the honest answer is "no frames", which the runtime prints as a
 * panic with an empty trace rather than crashing inside the printer. */
int backtrace(void **buf, int size) { (void)buf; (void)size; return 0; }
void backtrace_symbols_fd(void *const *buf, int size, int fd) {
    (void)buf; (void)size; (void)fd;
}
