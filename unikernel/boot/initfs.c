/*
 * NURL unikernel — unikernel/boot/initfs.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * A read-only filesystem, baked into the image at link time.
 *
 * B10 needs this for one reason and it is a good one: a TLS server
 * needs its certificate and its key, and a machine with no disk and no
 * network filesystem has exactly one place to keep them — inside
 * itself. The plan's scope for v1 is precise: read-only, no writes, no
 * directories to speak of, and no block device.
 *
 * The archive is a POSIX tar, because `tar cf` is on every machine that
 * will ever build one of these images and a custom format would be one
 * more thing to write a tool for. Only what a lookup needs is parsed:
 * the name, the size, and the file type. 512-byte header, payload
 * rounded up to 512, repeat.
 *
 * WHERE IT PLUGS IN. nolibc's `fopen`/`fread`/`fseek` are written
 * against `nl_open`/`nl_read`/`nl_lseek`/`nl_close` — the same four
 * functions the Linux build implements with syscalls. Those four live
 * one layer up, in `boot/vfs.c`, which asks THIS file first and the
 * disk (when there is one) second. Everything here is named `ifs_*`
 * and answers only about the archive: a lookup that misses is a miss,
 * not a decision about the machine.
 */

typedef unsigned long fs_size_t;
typedef long          fs_ssize_t;

/* The image, supplied by the linker. `build_unikernel.sh --fs <dir>`
 * turns a directory into a tar and that tar into an object; with no
 * --fs it emits an empty one, so these symbols always exist and the
 * "no files" case is a zero-length archive rather than a #ifdef. */
extern const unsigned char nurl_initfs_start[];
extern const unsigned char nurl_initfs_end[];

void pf_panic(const char *msg);
extern int nl_errno_slot;

#define FS_MAX_OPEN 16
#define FS_FD_BASE  64          /* above stdin/stdout/stderr and clear of them */

typedef struct {
    const unsigned char *data;
    fs_size_t            size;
    fs_size_t            pos;
    int                  used;
} FsFile;

static FsFile fs_open_files[FS_MAX_OPEN];

static fs_size_t tar_octal(const char *p, int n) {
    fs_size_t v = 0;
    for (int i = 0; i < n; i++) {
        if (p[i] < '0' || p[i] > '7') break;
        v = v * 8 + (fs_size_t)(p[i] - '0');
    }
    return v;
}

/* Name comparison, with the archive side BOUNDED: a tar name field
 * is 100 bytes and is only NUL-terminated when the name is shorter than
 * that. A plain `strcmp` against a full-width name walks out of the
 * field and into the mode digits, so a 100-character name would be
 * compared against something that is not a name at all. */
static int fs_streq_n(const char *hdr, int n, const char *want) {
    int i = 0;
    for (; i < n && hdr[i] && want[i] && hdr[i] == want[i]; i++) { }
    if (i == n) return want[i] == 0;             /* the field ran out */
    return hdr[i] == want[i];
}

/* Leading "./" and a leading "/" are the same file: `tar cf` writes
 * "./certs/key.pem" and a program asks for "certs/key.pem" or
 * "/certs/key.pem". Normalising here rather than at every caller is
 * what keeps the program identical to its Linux self. */
static const char *fs_norm(const char *p) {
    if (p[0] == '.' && p[1] == '/') return p + 2;
    if (p[0] == '/') return p + 1;
    return p;
}

static int fs_norm_dir(const char *path, char *out, int cap);

/* Find `name` in the archive. Returns its bytes and size, or 0. */
static const unsigned char *fs_lookup(const char *name, fs_size_t *size_out) {
    const unsigned char *p = nurl_initfs_start;
    const unsigned char *end = nurl_initfs_end;
    /* Fold `.` / `..` here as well: a program that opens `etc/../etc/x`
     * gets the same file it would on any other machine. */
    static char folded[256];
    const char *want = name;
    if (fs_norm_dir(name, folded, (int)sizeof folded) >= 0) want = folded;

    while (p + 512 <= end) {
        const char *hdr = (const char *)p;
        if (hdr[0] == 0) break;                 /* end-of-archive padding */
        fs_size_t size = tar_octal(hdr + 124, 12);
        char type = hdr[156];
        const unsigned char *body = p + 512;
        fs_size_t stride;

        /* A size field is twelve octal digits and can name a number no
         * archive this size could hold. Rounding it up would then wrap,
         * `p += stride` would move BACKWARDS, and the walk would never
         * end. The archive is built by our own build script, so this is
         * a corrupt-image check rather than a hostile-input one — and a
         * corrupt image is exactly when a loop that never ends is the
         * worst possible behaviour. */
        if (size > (fs_size_t)(end - body)) return 0;
        stride = 512 + ((size + 511) & ~(fs_size_t)511);

        /* '0' and '\0' are both "regular file"; anything else (a
         * directory, a symlink) is skipped rather than served, because
         * serving a directory's zero bytes as a file is how a missing
         * certificate becomes an empty one. */
        if ((type == '0' || type == 0) &&
            fs_streq_n(fs_norm(hdr), 100 - (int)(fs_norm(hdr) - hdr), want)) {
            if (body + size > end) return 0;    /* truncated archive */
            if (size_out) *size_out = size;
            return body;
        }
        p += stride;
    }
    return 0;
}

/* ── the four functions nolibc's stdio is written against ───────── */

/* O_DIRECTORY, the Linux value — nolibc's opendir passes it and this
 * file is the only thing that reads it. */
#define NL_O_DIRECTORY 0200000

int ifs_open(const char *path, int flags, int mode) {
    (void)mode;
    /* Read-only, and it says so: a write to a filesystem that lives in
     * the text segment cannot be honoured, and a caller that opened
     * for writing and got a descriptor would discover that later, at
     * the write, with the data already gone. */
    if ((flags & 3) != 0) { nl_errno_slot = 30 /* EROFS */; return -1; }

    /* An archive is not a directory tree you can walk: there is no
     * getdents here, so `opendir` must FAIL, which is what it does on
     * the Linux nolibc build and what the README has always claimed.
     * Ignoring this flag made it SUCCEED on a regular file — and a
     * successful opendir that then lists nothing is the worst possible
     * answer, because every "is this a directory?" predicate written
     * the obvious way (open it as one; if that works, it is one) then
     * says yes about a file. That is not hypothetical: the wasm
     * runtime's path_open asks exactly that question, decided that a
     * NURL source file was a directory, handed the compiler an empty
     * directory fd, and nurlc.wasm dutifully compiled an empty
     * program — 21939 bytes of preamble instead of the program's own
     * 6624, with no error anywhere in the chain. */
    if ((flags & NL_O_DIRECTORY) != 0) { nl_errno_slot = 20 /* ENOTDIR */; return -1; }

    fs_size_t size = 0;
    const unsigned char *data = fs_lookup(path, &size);
    if (!data) { nl_errno_slot = 2 /* ENOENT */; return -1; }

    for (int i = 0; i < FS_MAX_OPEN; i++) {
        if (fs_open_files[i].used) continue;
        fs_open_files[i].data = data;
        fs_open_files[i].size = size;
        fs_open_files[i].pos  = 0;
        fs_open_files[i].used = 1;
        return FS_FD_BASE + i;
    }
    nl_errno_slot = 24 /* EMFILE */;
    return -1;
}

static FsFile *fs_file(int fd) {
    int i = fd - FS_FD_BASE;
    if (i < 0 || i >= FS_MAX_OPEN) return 0;
    if (!fs_open_files[i].used) return 0;
    return &fs_open_files[i];
}

int ifs_is_fd(int fd) { return fs_file(fd) != 0; }

fs_ssize_t ifs_read(int fd, void *buf, fs_size_t n) {
    FsFile *f = fs_file(fd);
    unsigned char *out = (unsigned char *)buf;
    if (!f) { nl_errno_slot = 9 /* EBADF */; return -1; }
    fs_size_t left = f->size - f->pos;
    fs_size_t take = n < left ? n : left;
    for (fs_size_t i = 0; i < take; i++) out[i] = f->data[f->pos + i];
    f->pos += take;
    return (fs_ssize_t)take;
}

long long ifs_lseek(int fd, long long off, int whence) {
    FsFile *f = fs_file(fd);
    long long base;
    if (!f) { nl_errno_slot = 9; return -1; }
    if (whence == 0) base = 0;
    else if (whence == 1) base = (long long)f->pos;
    else base = (long long)f->size;
    long long pos = base + off;
    if (pos < 0) { nl_errno_slot = 22 /* EINVAL */; return -1; }
    if (pos > (long long)f->size) pos = (long long)f->size;
    f->pos = (fs_size_t)pos;
    return pos;
}

int ifs_close(int fd) {
    FsFile *f = fs_file(fd);
    if (!f) { nl_errno_slot = 9; return -1; }
    f->used = 0;
    return 0;
}

/* The bytes of an open file, in place. A file-backed `mmap` of an
 * image that is already in memory is a pointer into it: read-only,
 * shared with the archive, and free. `std/fs.nu`'s POSIX read path
 * maps rather than reads, so without this every `read_file` on this
 * machine returns whatever the bump allocator handed back. */
const unsigned char *ifs_map(int fd, fs_size_t off) {
    FsFile *f = fs_file(fd);
    if (!f || off > f->size) return 0;
    return f->data + off;
}

/* ── the archive as a DIRECTORY TREE ─────────────────────────────
 *
 * A tar is a flat list of paths, but the paths spell a tree, and a
 * userland needs that tree: `ls`, `find`, `du`, `test -d` and every
 * `stat` on a directory are otherwise answered "I/O error" on a machine
 * whose image demonstrably contains the files.
 *
 * Nothing is indexed up front — the archive is small, in memory, and
 * walking it is a few hundred instructions. Directories are derived
 * from the paths rather than requiring `tar` to have written explicit
 * '5' entries, because `tar cf` does not always emit them and a
 * directory that exists only as a prefix of its children is still a
 * directory.
 */

/* Copy the header's name field into `out` (bounded, NUL-terminated),
 * normalised the same way a lookup normalises the caller's path.
 * Returns the length. */
static int fs_hdr_name(const char *hdr, char *out, int cap) {
    const char *n = fs_norm(hdr);
    int room = 100 - (int)(n - hdr);
    int i = 0;
    while (i < room && i < cap - 1 && n[i]) { out[i] = n[i]; i++; }
    out[i] = 0;
    return i;
}

/* Does `name` sit inside directory `dir`, and if so where does its next
 * component end? `dir` is normalised and may be "" for the root.
 * Returns the component's length, or -1 when `name` is not under `dir`.
 * `*is_dir` says whether the component has anything after it. */
static int fs_child_of(const char *dir, int dirlen, const char *name, int *is_dir) {
    int i = 0;
    if (dirlen > 0) {
        for (i = 0; i < dirlen; i++) if (name[i] != dir[i]) return -1;
        if (name[dirlen] != '/') return -1;
        i = dirlen + 1;
    }
    if (name[i] == 0) return -1;                 /* the directory itself */
    {
        int start = i;
        while (name[i] && name[i] != '/') i++;
        *is_dir = (name[i] == '/');
        return i - start;
    }
}

/* Normalise a caller's directory path into `out`: drop the leading
 * "./" or "/", fold every "." and ".." component, and drop trailing
 * slashes. Returns the length.
 *
 * The folding is not cosmetic. On a hosted system the KERNEL resolves
 * `etc/.` and `etc/..`; here nothing does, so `ls -a` — which stats
 * exactly those two names — asked the archive about paths it could
 * never contain and was told they did not exist. A listing whose first
 * two entries are reported as neither file nor directory is the shape
 * of that bug. */
static int fs_norm_dir(const char *path, char *out, int cap) {
    const char *p = fs_norm(path);
    int i = 0, n = 0;
    for (;;) {
        int start, seglen;
        while (p[i] == '/') i++;
        if (!p[i]) break;
        start = i;
        while (p[i] && p[i] != '/') i++;
        seglen = i - start;
        if (seglen == 1 && p[start] == '.') continue;
        if (seglen == 2 && p[start] == '.' && p[start + 1] == '.') {
            while (n > 0 && out[n - 1] != '/') n--;
            if (n > 0) n--;                       /* the separator too */
            out[n] = 0;
            continue;
        }
        if (n > 0) { if (n < cap - 1) out[n++] = '/'; }
        {
            int k = 0;
            while (k < seglen && n < cap - 1) out[n++] = p[start + k++];
        }
        out[n] = 0;
    }
    return n;
}

/* 0 = missing, 1 = regular file, 2 = directory. Sets *size for a file. */
int ifs_kind(const char *path, fs_size_t *size_out) {
    char dir[256];
    char name[256];
    int dirlen = fs_norm_dir(path, dir, sizeof dir);
    const unsigned char *p = nurl_initfs_start;
    const unsigned char *end = nurl_initfs_end;

    if (dirlen == 0) return 2;                   /* the archive's root */

    while (p + 512 <= end) {
        const char *hdr = (const char *)p;
        fs_size_t size, stride;
        char type;
        int nlen, is_dir;
        if (hdr[0] == 0) break;
        size = tar_octal(hdr + 124, 12);
        type = hdr[156];
        if (size > (fs_size_t)(end - (p + 512))) break;
        stride = 512 + ((size + 511) & ~(fs_size_t)511);
        nlen = fs_hdr_name(hdr, name, sizeof name);
        /* Trailing slash on a '5' entry: `etc/` names `etc`. */
        while (nlen > 0 && name[nlen - 1] == '/') name[--nlen] = 0;
        if (nlen == dirlen) {
            int i = 0;
            while (i < nlen && name[i] == dir[i]) i++;
            if (i == nlen) {
                if (type == '5') return 2;
                if (size_out) *size_out = size;
                return 1;
            }
        }
        /* Anything under it makes it a directory, explicit entry or not. */
        if (fs_child_of(dir, dirlen, name, &is_dir) > 0) return 2;
        p += stride;
    }
    return 0;
}

/* The `index`-th immediate child of `path`, deduplicated. Returns 1 and
 * fills `out` / `*is_dir`, or 0 past the end. O(entries) per call, which
 * an archive of a few dozen files does not notice. */
int ifs_dirent(const char *path, int index, char *out, int cap, int *is_dir) {
    char dir[256];
    char name[256];
    char seen[256];
    int dirlen = fs_norm_dir(path, dir, sizeof dir);
    const unsigned char *p = nurl_initfs_start;
    const unsigned char *end = nurl_initfs_end;
    int found = 0;

    while (p + 512 <= end) {
        const char *hdr = (const char *)p;
        fs_size_t size, stride;
        int nlen, child_is_dir = 0, clen;
        if (hdr[0] == 0) break;
        size = tar_octal(hdr + 124, 12);
        if (size > (fs_size_t)(end - (p + 512))) break;
        stride = 512 + ((size + 511) & ~(fs_size_t)511);
        nlen = fs_hdr_name(hdr, name, sizeof name);
        while (nlen > 0 && name[nlen - 1] == '/') name[--nlen] = 0;
        clen = fs_child_of(dir, dirlen, name, &child_is_dir);
        if (clen > 0 && clen < (int)sizeof seen) {
            int start = dirlen == 0 ? 0 : dirlen + 1;
            int dup = 0;
            const unsigned char *q = nurl_initfs_start;
            int i;
            for (i = 0; i < clen; i++) seen[i] = name[start + i];
            seen[clen] = 0;
            /* Emitted already? A directory appears once per file under
             * it, and a listing must name it once. */
            while (q < p && q + 512 <= end) {
                const char *h2 = (const char *)q;
                char n2[256];
                fs_size_t s2, st2;
                int l2, d2 = 0, c2;
                if (h2[0] == 0) break;
                s2 = tar_octal(h2 + 124, 12);
                if (s2 > (fs_size_t)(end - (q + 512))) break;
                st2 = 512 + ((s2 + 511) & ~(fs_size_t)511);
                l2 = fs_hdr_name(h2, n2, sizeof n2);
                while (l2 > 0 && n2[l2 - 1] == '/') n2[--l2] = 0;
                c2 = fs_child_of(dir, dirlen, n2, &d2);
                if (c2 == clen) {
                    int j = 0;
                    while (j < clen && n2[start + j] == seen[j]) j++;
                    if (j == clen) { dup = 1; break; }
                }
                q += st2;
            }
            if (!dup) {
                if (found == index) {
                    for (i = 0; i < clen && i < cap - 1; i++) out[i] = seen[i];
                    out[i] = 0;
                    if (is_dir) *is_dir = child_is_dir;
                    return 1;
                }
                found++;
            }
        }
        p += stride;
    }
    return 0;
}

/* Is this path a file in the image? `access(2)` is how a program asks —
 * `std/fs.nu`'s `file_exists` is exactly that call — and answering "no"
 * for a file the image demonstrably contains is the kind of stub that
 * becomes somebody's bug report: swarm-mcp asked whether its baked-in
 * certificate was there, was told no, and tried to generate one onto a
 * read-only filesystem. */
int ifs_exists(const char *path) {
    fs_size_t size = 0;
    return fs_lookup(path, &size) != 0;
}

/* Does the image contain anything at all? The boot banner uses it, and
 * so does the decision not to look for a certificate that cannot be
 * there. */
long long nurl_initfs_size(void) {
    return (long long)(nurl_initfs_end - nurl_initfs_start);
}
