/*
 * NURL nolibc — unikernel/nolibc/stdio.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Buffered streams and the printf subset, over the six syscalls.
 *
 * The format subset is not a guess: `stdlib/runtime_core.c` contains
 * exactly seven format strings, using `%s`, `%lld` and `%llu` and no
 * width, precision or flags. `%g` used to be the eighth and is why this
 * file would have needed a dtoa — the shortest-digit generator in
 * runtime_core §2b removed that requirement, so nothing here has to
 * know what a double is. `%c`, `%d`, `%u`, `%x`, `%p` and `%%` are here
 * anyway because they cost three lines each and a diagnostic that
 * silently prints the wrong thing is worse than one that does not
 * build; anything else in a format string is copied through verbatim so
 * the text still reaches the reader.
 */
#include "nolibc.h"

extern nl_ssize_t nl_write(int fd, const void *buf, nl_size_t n);
extern int nl_format_double(char *out, double v, char conv, int prec, int alt);
extern nl_ssize_t nl_read(int fd, void *buf, nl_size_t n);
extern int  nl_open(const char *path, int flags, int mode);
extern int  nl_close(int fd);
extern nl_off_t nl_lseek(int fd, nl_off_t off, int whence);

/* ── the three standard streams ─────────────────────────────────── */
static FILE nl_stdin  = { 0, NL_F_READ,  -1, 0, 0, { 0 } };
static FILE nl_stdout = { 1, NL_F_WRITE, -1, 0, 0, { 0 } };
static FILE nl_stderr = { 2, NL_F_WRITE | NL_F_UNBUF, -1, 0, 0, { 0 } };

FILE *stdin  = &nl_stdin;
FILE *stdout = &nl_stdout;
FILE *stderr = &nl_stderr;

/* A short write is not an error and not a rarity — a pipe with a slow
 * reader gives one every time. Loop until the buffer is out or the
 * kernel says no. */
static int nl_write_all(int fd, const unsigned char *p, nl_size_t n) {
    while (n) {
        nl_ssize_t w = nl_write(fd, p, n);
        if (w <= 0) {
            if (w < 0 && errno == 4 /* EINTR */) continue;
            return -1;
        }
        p += w; n -= (nl_size_t)w;
    }
    return 0;
}

int fflush(FILE *f) {
    if (!f) {                          /* fflush(NULL): every stream */
        int a = fflush(&nl_stdout), b = fflush(&nl_stderr);
        return (a || b) ? -1 : 0;
    }
    if (!(f->flags & NL_F_WRITE) || f->bufpos == 0) return 0;
    if (nl_write_all(f->fd, f->buf, f->bufpos) < 0) {
        f->flags |= NL_F_ERR;
        f->bufpos = 0;
        return -1;
    }
    f->bufpos = 0;
    return 0;
}

/* Drop read-ahead before writing: the kernel offset is ahead of the
 * caller's position by whatever we prefetched, and writing there would
 * land the bytes in the wrong place. */
static void nl_drop_readahead(FILE *f) {
    if (f->buflen > f->bufpos)
        nl_lseek(f->fd, -(nl_off_t)(f->buflen - f->bufpos), 1 /* SEEK_CUR */);
    f->bufpos = f->buflen = 0;
    f->ungot = -1;
}

static int nl_putb(FILE *f, unsigned char c) {
    if (!(f->flags & NL_F_WRITE)) { f->flags |= NL_F_ERR; return -1; }
    if (f->buflen) nl_drop_readahead(f);
    f->buf[f->bufpos++] = c;
    if (f->bufpos == NL_BUFSZ || (f->flags & NL_F_UNBUF) ||
        ((f->flags & NL_F_LINEBUF) && c == '\n'))
        return fflush(f);
    return 0;
}

int fputc(int c, FILE *f) { return nl_putb(f, (unsigned char)c) < 0 ? -1 : (unsigned char)c; }

int fputs(const char *s, FILE *f) {
    nl_size_t n = strlen(s), i;
    /* Big strings go straight out: the runtime prints whole IR lines
     * through here, and copying them through a 4 KB buffer one byte at
     * a time is the single hottest thing this file could do wrong. */
    if (n >= NL_BUFSZ) {
        if (fflush(f) < 0) return -1;
        return nl_write_all(f->fd, (const unsigned char *)s, n) < 0 ? -1 : 0;
    }
    if (f->bufpos + n > NL_BUFSZ && fflush(f) < 0) return -1;
    for (i = 0; i < n; i++) f->buf[f->bufpos + i] = (unsigned char)s[i];
    f->bufpos += n;
    if ((f->flags & NL_F_UNBUF) ||
        ((f->flags & NL_F_LINEBUF) && n && s[n - 1] == '\n'))
        return fflush(f);
    return 0;
}

int puts(const char *s) {
    if (fputs(s, stdout) < 0) return -1;
    return fputc('\n', stdout) < 0 ? -1 : 0;
}

nl_size_t fwrite(const void *p, nl_size_t sz, nl_size_t n, FILE *f) {
    nl_size_t total = sz * n, i;
    const unsigned char *b = (const unsigned char *)p;
    if (sz == 0 || n == 0) return 0;
    if (total >= NL_BUFSZ) {
        if (fflush(f) < 0) return 0;
        return nl_write_all(f->fd, b, total) < 0 ? 0 : n;
    }
    if (f->bufpos + total > NL_BUFSZ && fflush(f) < 0) return 0;
    for (i = 0; i < total; i++) f->buf[f->bufpos + i] = b[i];
    f->bufpos += total;
    if (f->flags & NL_F_UNBUF) fflush(f);
    return n;
}

/* ── formatting ─────────────────────────────────────────────────── */

/* Unsigned in any base up to 16, written backwards into a scratch and
 * copied out — the same shape as nurl_str_int, for the same reason. */
static int nl_fmt_u(FILE *f, unsigned long long v, int base, int upper) {
    char tmp[24];
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    int n = 0, i;
    do { tmp[n++] = digits[v % (unsigned)base]; v /= (unsigned)base; } while (v);
    for (i = n - 1; i >= 0; i--) if (nl_putb(f, (unsigned char)tmp[i]) < 0) return -1;
    return n;
}

static int nl_fmt_s(FILE *f, long long v) {
    unsigned long long m = v < 0 ? 0ULL - (unsigned long long)v : (unsigned long long)v;
    int extra = 0;
    if (v < 0) { if (nl_putb(f, '-') < 0) return -1; extra = 1; }
    { int r = nl_fmt_u(f, m, 10, 0); return r < 0 ? -1 : r + extra; }
}

/* va_list without <stdarg.h>: clang provides __builtin_va_* in
 * freestanding mode, and stdarg.h is one of the five headers a
 * freestanding compiler must ship, so using it is not a libc
 * dependency. */
#include <stdarg.h>

static int nl_vfprintf(FILE *f, const char *fmt, va_list ap) {
    int written = 0;
    const char *p = fmt;
    while (*p) {
        int longs = 0, prec = -1, alt = 0;
        if (*p != '%') {
            if (nl_putb(f, (unsigned char)*p++) < 0) return -1;
            written++;
            continue;
        }
        p++;
        /* Flags and width are parsed so a conversion that carries them
         * still prints its VALUE rather than its format string. Width is
         * accepted and ignored: nothing in the runtime or the corpus
         * pads a field, and silently mis-padding would be worse than
         * not padding. Precision is honoured, because %.*f without it
         * is a different number. */
        while (*p == '-' || *p == '+' || *p == ' ' || *p == '0' || *p == '#') {
            if (*p == '#') alt = 1;
            p++;
        }
        while (*p >= '0' && *p <= '9') p++;
        if (*p == '.') {
            p++;
            prec = 0;
            if (*p == '*') { prec = va_arg(ap, int); p++; }
            else while (*p >= '0' && *p <= '9') prec = prec * 10 + (*p++ - '0');
            if (prec < 0) prec = -1;
        }
        while (*p == 'l' || *p == 'h' || *p == 'z' || *p == 'j' || *p == 't') {
            if (*p == 'l') longs++;
            p++;
        }
        switch (*p) {
        case 's': {
            const char *s = va_arg(ap, const char *);
            if (!s) s = "(null)";
            if (fputs(s, f) < 0) return -1;
            written += (int)strlen(s);
            break;
        }
        case 'c': {
            int c = va_arg(ap, int);
            if (nl_putb(f, (unsigned char)c) < 0) return -1;
            written++;
            break;
        }
        case 'd': case 'i': {
            long long v = longs >= 2 ? va_arg(ap, long long)
                        : longs == 1 ? (long long)va_arg(ap, long)
                                     : (long long)va_arg(ap, int);
            int r = nl_fmt_s(f, v);
            if (r < 0) return -1;
            written += r;
            break;
        }
        case 'u': {
            unsigned long long v = longs >= 2 ? va_arg(ap, unsigned long long)
                                 : longs == 1 ? (unsigned long long)va_arg(ap, unsigned long)
                                              : (unsigned long long)va_arg(ap, unsigned int);
            int r = nl_fmt_u(f, v, 10, 0);
            if (r < 0) return -1;
            written += r;
            break;
        }
        case 'x': case 'X': {
            unsigned long long v = longs >= 2 ? va_arg(ap, unsigned long long)
                                 : longs == 1 ? (unsigned long long)va_arg(ap, unsigned long)
                                              : (unsigned long long)va_arg(ap, unsigned int);
            int r = nl_fmt_u(f, v, 16, *p == 'X');
            if (r < 0) return -1;
            written += r;
            break;
        }
        case 'p': {
            void *v = va_arg(ap, void *);
            int r;
            if (nl_putb(f, '0') < 0 || nl_putb(f, 'x') < 0) return -1;
            r = nl_fmt_u(f, (unsigned long long)(unsigned long)v, 16, 0);
            if (r < 0) return -1;
            written += r + 2;
            break;
        }
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': {
            /* dtoa.c does the conversion exactly; this only has to hand
             * it the precision C says applies when none was written. */
            char fbuf[1200];
            double d = va_arg(ap, double);
            int n = nl_format_double(fbuf, d, (*p | 32), prec < 0 ? 6 : prec, alt);
            int q;
            for (q = 0; q < n; q++) if (nl_putb(f, (unsigned char)fbuf[q]) < 0) return -1;
            written += n;
            break;
        }
        case '%':
            if (nl_putb(f, '%') < 0) return -1;
            written++;
            break;
        default:
            /* An unsupported conversion prints itself rather than
             * vanishing: a diagnostic that lies about its own text is
             * how you lose an afternoon. */
            if (nl_putb(f, '%') < 0) return -1;
            if (*p && nl_putb(f, (unsigned char)*p) < 0) return -1;
            written += 2;
            break;
        }
        if (*p) p++;
    }
    return written;
}

int fprintf(FILE *f, const char *fmt, ...) {
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = nl_vfprintf(f, fmt, ap);
    va_end(ap);
    return r;
}

int printf(const char *fmt, ...) {
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = nl_vfprintf(stdout, fmt, ap);
    va_end(ap);
    return r;
}

/* ── reading ────────────────────────────────────────────────────── */

int fileno(FILE *f) { return f ? f->fd : -1; }

int fgetc(FILE *f) {
    if (f->ungot >= 0) { int c = f->ungot; f->ungot = -1; return c; }
    if (!(f->flags & NL_F_READ)) return -1;
    /* An update stream shares one buffer between the directions, so a
     * pending write has to reach the file before a read can see past
     * it. buflen == 0 with bufpos > 0 is what "write-buffered" looks
     * like here. */
    if (f->buflen == 0 && f->bufpos > 0) fflush(f);
    if (f->bufpos >= f->buflen) {
        nl_ssize_t r = nl_read(f->fd, f->buf, NL_BUFSZ);
        if (r <= 0) { f->flags |= (r == 0) ? NL_F_EOF : NL_F_ERR; return -1; }
        f->buflen = (nl_size_t)r;
        f->bufpos = 0;
    }
    return f->buf[f->bufpos++];
}

int getc(FILE *f) { return fgetc(f); }

int ungetc(int c, FILE *f) {
    if (c < 0) return -1;
    f->ungot = c & 0xff;
    f->flags &= ~NL_F_EOF;
    return c & 0xff;
}

nl_size_t fread(void *p, nl_size_t sz, nl_size_t n, FILE *f) {
    unsigned char *b = (unsigned char *)p;
    nl_size_t want = sz * n, got = 0;
    if (sz == 0 || n == 0) return 0;
    while (got < want) {
        int c;
        /* Serve from the buffer in bulk where we can — a byte-at-a-time
         * fread of a source file is the difference between a compile
         * and a coffee break. */
        if (f->ungot < 0 && f->bufpos < f->buflen) {
            nl_size_t have = f->buflen - f->bufpos;
            nl_size_t take = (want - got < have) ? want - got : have;
            memcpy(b + got, f->buf + f->bufpos, take);
            f->bufpos += take;
            got += take;
            continue;
        }
        c = fgetc(f);
        if (c < 0) break;
        b[got++] = (unsigned char)c;
    }
    return sz ? got / sz : 0;
}

/* ── files ──────────────────────────────────────────────────────── */
#define NL_O_RDONLY 0
#define NL_O_WRONLY 1
#define NL_O_RDWR   2
#define NL_O_CREAT  0100
#define NL_O_TRUNC  01000
#define NL_O_APPEND 02000

FILE *fopen(const char *path, const char *mode) {
    /* "+" anywhere after the first letter means update, and 'b' may sit
     * on either side of it ("r+b" and "rb+" are the same stream). A
     * mode parser that only looks at mode[1] gets "rb+" wrong, which
     * shows up much later as a read returning nothing. */
    int flags, sflags, plus = 0, i;
    FILE *f;
    int fd;
    for (i = 1; mode[i]; i++) if (mode[i] == '+') plus = 1;
    switch (mode[0]) {
    case 'w': flags = (plus ? NL_O_RDWR : NL_O_WRONLY) | NL_O_CREAT | NL_O_TRUNC;
              sflags = plus ? (NL_F_READ | NL_F_WRITE) : NL_F_WRITE; break;
    case 'a': flags = (plus ? NL_O_RDWR : NL_O_WRONLY) | NL_O_CREAT | NL_O_APPEND;
              sflags = plus ? (NL_F_READ | NL_F_WRITE) : NL_F_WRITE; break;
    default:  flags = plus ? NL_O_RDWR : NL_O_RDONLY;
              sflags = plus ? (NL_F_READ | NL_F_WRITE) : NL_F_READ; break;
    }
    fd = nl_open(path, flags, 0666);
    if (fd < 0) return 0;
    f = (FILE *)malloc(sizeof(FILE));
    if (!f) { nl_close(fd); return 0; }
    memset(f, 0, sizeof(FILE));
    f->fd = fd;
    f->ungot = -1;
    f->flags = sflags | NL_F_ALLOC;
    return f;
}

int fclose(FILE *f) {
    int r;
    if (!f) return -1;
    fflush(f);
    r = nl_close(f->fd);
    if (f->flags & NL_F_ALLOC) free(f);
    return r;
}

int fseek(FILE *f, long off, int whence) {
    /* Whatever is buffered describes the old position. Drop it, both
     * directions, or the next read returns bytes from before the seek.
     *
     * SEEK_CUR needs more than dropping: the kernel's offset is ahead
     * of the caller's by every byte we read ahead and have not handed
     * out, so a relative seek must subtract them first. Without that,
     * "read 11 bytes, then seek +9" lands at 4105 instead of 20 —
     * which is exactly how fs_write_handle failed the moment the rest
     * of nolibc was complete enough for it to link. */
    if (f->flags & NL_F_WRITE) fflush(f);
    if (whence == 1 /* SEEK_CUR */) {
        off -= (long)(f->buflen - f->bufpos);
        if (f->ungot >= 0) off -= 1;
    }
    f->bufpos = f->buflen = 0;
    f->ungot = -1;
    f->flags &= ~NL_F_EOF;
    return nl_lseek(f->fd, off, whence) < 0 ? -1 : 0;
}

long ftell(FILE *f) {
    nl_off_t pos = nl_lseek(f->fd, 0, 1 /* SEEK_CUR */);
    if (pos < 0) return -1;
    /* The kernel's offset counts bytes we have read into the buffer but
     * not yet handed out; ftell must not. */
    if (f->flags & NL_F_READ) pos -= (nl_off_t)(f->buflen - f->bufpos);
    if (f->flags & NL_F_WRITE) pos += (nl_off_t)f->bufpos;
    if (f->ungot >= 0) pos -= 1;
    return (long)pos;
}

/* ── the stdio names a program reaches that the runtime does not ── */
int putchar(int c) { return fputc(c, stdout); }
int feof(FILE *f)   { return (f->flags & NL_F_EOF) ? 1 : 0; }
int ferror(FILE *f) { return (f->flags & NL_F_ERR) ? 1 : 0; }
int remove(const char *path) { extern int unlink(const char *); return unlink(path); }
