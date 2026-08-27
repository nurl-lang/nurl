/*
 * NURL nolibc — unikernel/nolibc/nolibc.h
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The freestanding libc subset the NURL runtime needs, and nothing else.
 * "Nothing else" is a design rule, not modesty: the list below is the
 * measured undefined-symbol set of `clang -c stdlib/runtime_core.c`
 * (49 symbols), so anything not in it is a symbol the runtime does not
 * call, and adding it would be speculation.
 *
 * These are the REAL libc names — memcpy, printf, malloc — because the
 * runtime calls them by those names. On Linux the whole set links with
 * `-nostdlib`, which is how it is tested: a NURL program built against
 * this libc has glibc nowhere in its link line, so a missing piece is a
 * link error rather than a surprise at boot.
 *
 * Platform split: everything here is portable C except syscall.h (the
 * Linux/x86_64 entry sequence), setjmp_x86_64.S and start_x86_64.S.
 * The unikernel target replaces syscall.h with MMIO/boot-shim
 * equivalents and keeps the rest verbatim.
 */
#ifndef NURL_NOLIBC_H
#define NURL_NOLIBC_H

typedef unsigned long  nl_size_t;
typedef long           nl_ssize_t;
typedef long           nl_off_t;

/* ── the FILE the runtime sees ──────────────────────────────────
 * The runtime only ever holds `FILE *`, so the layout is ours. Three
 * static streams plus whatever fopen returns; a single buffer that is
 * either a write buffer or a read buffer, never both, because no caller
 * in the runtime reads and writes the same stream. */
#define NL_BUFSZ 4096

struct nl_file {
    int  fd;
    int  flags;          /* NL_F_* below */
    int  ungot;          /* pushed-back byte, or -1 */
    nl_size_t bufpos;    /* bytes held in buf */
    nl_size_t buflen;    /* bytes valid in buf (read mode) */
    unsigned char buf[NL_BUFSZ];
};

#define NL_F_READ    0x01
#define NL_F_WRITE   0x02
#define NL_F_EOF     0x04
#define NL_F_ERR     0x08
#define NL_F_UNBUF   0x10   /* stderr: never hold a byte back */
#define NL_F_LINEBUF 0x20   /* a tty stdout: flush on newline */
#define NL_F_ALLOC   0x40   /* came from fopen, so fclose frees it */

typedef struct nl_file FILE;

extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

/* ── memory and strings ─────────────────────────────────────────── */
void *memcpy(void *d, const void *s, nl_size_t n);
void *memmove(void *d, const void *s, nl_size_t n);
void *memset(void *d, int c, nl_size_t n);
void *memchr(const void *s, int c, nl_size_t n);
int   memcmp(const void *a, const void *b, nl_size_t n);
int   bcmp(const void *a, const void *b, nl_size_t n);
nl_size_t strlen(const char *s);
int   strcmp(const char *a, const char *b);

/* ── allocator ──────────────────────────────────────────────────── */
void *malloc(nl_size_t n);
void *calloc(nl_size_t n, nl_size_t sz);
void *realloc(void *p, nl_size_t n);
void  free(void *p);
nl_size_t malloc_usable_size(void *p);

/* ── stdio ──────────────────────────────────────────────────────── */
int   fflush(FILE *f);
int   fputc(int c, FILE *f);
int   fputs(const char *s, FILE *f);
int   puts(const char *s);
int   printf(const char *fmt, ...);
int   fprintf(FILE *f, const char *fmt, ...);
int   fileno(FILE *f);
int   fgetc(FILE *f);
int   getc(FILE *f);
int   ungetc(int c, FILE *f);
FILE *fopen(const char *path, const char *mode);
FILE *fdopen(int fd, const char *mode);
int   fclose(FILE *f);
nl_size_t fread(void *p, nl_size_t sz, nl_size_t n, FILE *f);
nl_size_t fwrite(const void *p, nl_size_t sz, nl_size_t n, FILE *f);
int   fseek(FILE *f, long off, int whence);
long  ftell(FILE *f);

/* ── process ────────────────────────────────────────────────────── */
void  exit(int code);
void  abort(void);
char *getenv(const char *name);
int  *__errno_location(void);
#define errno (*__errno_location())

/* Set by _start from the process stack; getenv reads it and the runtime
 * never sees it. */
/* libc's spelling of the environment vector. It is ONE variable under
 * two names: runtime_core.c enumerates `environ` (nurl_env_at, so `env`
 * and `printenv` can list it), while everything in nolibc was written
 * against `nl_environ`. Two variables would drift the moment setenv
 * reallocated one of them. */
extern char **environ;
#define nl_environ environ

/* ── the pieces with no portable form ───────────────────────────── */
long nl_syscall6(long n, long a, long b, long c, long d, long e, long f);

#endif /* NURL_NOLIBC_H */
