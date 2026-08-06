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
 * WHERE IT PLUGS IN. nolibc's `fopen`/`fread`/`fseek` are already
 * written against `nl_open`/`nl_read`/`nl_lseek`/`nl_close` — the same
 * four functions the Linux build implements with syscalls. Implementing
 * those four here means every reader above them works unchanged, from
 * `fread` to `fs_read_file` to whatever the TLS code does to load a
 * PEM. Nothing above knows the file came out of the binary.
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

/* Find `name` in the archive. Returns its bytes and size, or 0. */
static const unsigned char *fs_lookup(const char *name, fs_size_t *size_out) {
    const unsigned char *p = nurl_initfs_start;
    const unsigned char *end = nurl_initfs_end;
    const char *want = fs_norm(name);

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

int nl_open(const char *path, int flags, int mode) {
    (void)mode;
    /* Read-only, and it says so: a write to a filesystem that lives in
     * the text segment cannot be honoured, and a caller that opened
     * for writing and got a descriptor would discover that later, at
     * the write, with the data already gone. */
    if ((flags & 3) != 0) { nl_errno_slot = 30 /* EROFS */; return -1; }

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

int fs_is_file_fd(int fd) { return fs_file(fd) != 0; }

fs_ssize_t fs_read_fd(int fd, void *buf, fs_size_t n) {
    FsFile *f = fs_file(fd);
    unsigned char *out = (unsigned char *)buf;
    if (!f) { nl_errno_slot = 9 /* EBADF */; return -1; }
    fs_size_t left = f->size - f->pos;
    fs_size_t take = n < left ? n : left;
    for (fs_size_t i = 0; i < take; i++) out[i] = f->data[f->pos + i];
    f->pos += take;
    return (fs_ssize_t)take;
}

long long fs_lseek_fd(int fd, long long off, int whence) {
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

int fs_close_fd(int fd) {
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
const unsigned char *fs_map_fd(int fd, fs_size_t off) {
    FsFile *f = fs_file(fd);
    if (!f || off > f->size) return 0;
    return f->data + off;
}

/* Is this path a file in the image? `access(2)` is how a program asks —
 * `std/fs.nu`'s `file_exists` is exactly that call — and answering "no"
 * for a file the image demonstrably contains is the kind of stub that
 * becomes somebody's bug report: swarm-mcp asked whether its baked-in
 * certificate was there, was told no, and tried to generate one onto a
 * read-only filesystem. */
int fs_exists(const char *path) {
    fs_size_t size = 0;
    return fs_lookup(path, &size) != 0;
}

/* Does the image contain anything at all? The boot banner uses it, and
 * so does the decision not to look for a certificate that cannot be
 * there. */
long long nurl_initfs_size(void) {
    return (long long)(nurl_initfs_end - nurl_initfs_start);
}
