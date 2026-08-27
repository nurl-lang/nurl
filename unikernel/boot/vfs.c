/*
 * NURL unikernel — unikernel/boot/vfs.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The guest's file surface: one archive that is baked into the image
 * and read-only, and one disk that is neither.
 *
 * WHY A LAYER. Until there was a disk, `initfs.c` WAS the filesystem
 * and could answer every question by itself — including the two it
 * answered by refusing, `O_WRONLY` (EROFS) and `O_DIRECTORY`
 * (ENOTDIR). With a block device attached, both of those refusals stop
 * being facts about the machine and become facts about the archive, so
 * something above has to ask the second question. That is this file:
 * `initfs.c` now answers only about its own bytes (`ifs_*`), and the
 * POSIX names every caller uses live here.
 *
 * PRECEDENCE, and it is deliberate. A read of a path the IMAGE
 * contains is served from the image, even when a disk holds the same
 * name: the image is part of the program, a certificate baked in at
 * build time should not be shadowed by whatever a disk picked up, and
 * a guest that behaved differently depending on the contents of an
 * attached disk would be a guest nobody can reason about. Writes never
 * consult the image at all — it cannot serve them — so they go to the
 * disk, and a machine with no disk gets the archive's honest EROFS.
 *
 * WEAK SYMBOLS are how "there is a disk layer linked in" is asked. The
 * `nurl_disk_*` functions are defined in NURL, in
 * `unikernel/fs/disk.nu`, and that file is linked only into images
 * built with a disk. An image without it links fine and every pointer
 * below is null, which is exactly the question this file needs to ask
 * and the only mechanism that answers it at LINK time rather than by
 * carrying a second copy of the filesystem around.
 *
 * WIDTHS. Every `nurl_disk_*` returns `long long`, never `int`. A C
 * declaration returning `int` has its negative answers read back
 * through a register whose top half a `movl` just zeroed — the bug
 * that made a guest read -1 as 4294967295 and take a refusal for a
 * success. The NURL side returns `i`, which is 64 bits, and these
 * declarations have to agree.
 */

typedef unsigned long vfs_size_t;
typedef long          vfs_ssize_t;

extern int nl_errno_slot;
long long nurl_initfs_size(void);

/* ── the archive, one layer down ─────────────────────────────────── */

int                  ifs_open(const char *path, int flags, int mode);
int                  ifs_is_fd(int fd);
vfs_ssize_t          ifs_read(int fd, void *buf, vfs_size_t n);
long long            ifs_lseek(int fd, long long off, int whence);
int                  ifs_close(int fd);
const unsigned char *ifs_map(int fd, vfs_size_t off);
int                  ifs_exists(const char *path);
int                  ifs_kind(const char *path, vfs_size_t *size_out);
int                  ifs_dirent(const char *path, int index, char *out, int cap, int *is_dir);

/* ── the disk, when one is linked ────────────────────────────────── */

__attribute__((weak)) long long nurl_disk_ready(void);
__attribute__((weak)) long long nurl_disk_writable(void);
__attribute__((weak)) long long nurl_disk_open(const char *path, long long flags);
__attribute__((weak)) long long nurl_disk_read(long long h, void *buf, long long n);
__attribute__((weak)) long long nurl_disk_write(long long h, const void *buf, long long n);
__attribute__((weak)) long long nurl_disk_lseek(long long h, long long off, long long whence);
__attribute__((weak)) long long nurl_disk_close(long long h);
__attribute__((weak)) long long nurl_disk_size(long long h);
__attribute__((weak)) long long nurl_disk_fsync(long long h);
__attribute__((weak)) long long nurl_disk_sync(void);
__attribute__((weak)) long long nurl_disk_exists(const char *path);
__attribute__((weak)) long long nurl_disk_is_dir(const char *path);
__attribute__((weak)) long long nurl_disk_stat_size(const char *path);
__attribute__((weak)) long long nurl_disk_unlink(const char *path);
__attribute__((weak)) long long nurl_disk_rename(const char *a, const char *b);
__attribute__((weak)) long long nurl_disk_mkdir(const char *path);
__attribute__((weak)) long long nurl_disk_rmdir(const char *path);
__attribute__((weak)) long long nurl_disk_truncate(const char *path, long long len);
__attribute__((weak)) long long nurl_disk_opendir(const char *path);
__attribute__((weak)) long long nurl_disk_readdir_name(long long h, char *buf, long long cap);
__attribute__((weak)) long long nurl_disk_dirent_is_dir(void);
__attribute__((weak)) long long nurl_disk_closedir(long long h);

/* Is a disk layer linked in AND did it find a filesystem? Both, in that
 * order: the null check must come first or an image without the layer
 * calls through a null pointer. */
static int disk_live(void) {
    if (!nurl_disk_ready) return 0;
    return nurl_disk_ready() == 1;
}

/* Descriptors. The archive owns 64..79 (initfs.c's own base and
 * count); the disk owns 128 upward, far enough away that a stray
 * descriptor lands in neither range instead of in the wrong one. */
#define VFS_DISK_FD_BASE 128
#define VFS_DISK_FD_MAX  (VFS_DISK_FD_BASE + 64)

static int disk_is_fd(int fd) { return fd >= VFS_DISK_FD_BASE && fd < VFS_DISK_FD_MAX; }

/* Archive directories get their own range above the disk's: an
 * `opendir` on the image is a cursor over tar headers, not a file. */
#define VFS_IFSDIR_FD_BASE 256
#define VFS_IFSDIR_MAX     8

/* A directory handle over the UNION of the two filesystems: the
 * archive's entries first, then the disk's, with a name the archive
 * already supplied skipped so a file that exists in both is listed
 * once. Reads resolve archive-first (see nl_open), and a listing that
 * disagreed with that would show a name whose `open` returns different
 * bytes. */
typedef struct {
    char      path[256];
    int       cursor;      /* next archive entry to emit */
    int       archive_done;
    long long disk_h;      /* the disk's own handle, or -1 */
    int       used;
} VfsIfsDir;

static VfsIfsDir vfs_ifsdirs[VFS_IFSDIR_MAX];

static int ifsdir_is_fd(int fd) {
    int i = fd - VFS_IFSDIR_FD_BASE;
    return i >= 0 && i < VFS_IFSDIR_MAX && vfs_ifsdirs[i].used;
}

static int ifsdir_open(const char *path, int have_archive) {
    int i, n;
    long long h = -1;
    if (disk_live() && nurl_disk_opendir) {
        h = nurl_disk_opendir(path);
        if (h < 0) h = -1;
    }
    /* Neither side has it: that is ENOENT, not an empty directory. */
    if (!have_archive && h < 0) return -1;
    for (i = 0; i < VFS_IFSDIR_MAX; i++) {
        if (vfs_ifsdirs[i].used) continue;
        for (n = 0; path[n] && n < (int)sizeof vfs_ifsdirs[i].path - 1; n++)
            vfs_ifsdirs[i].path[n] = path[n];
        vfs_ifsdirs[i].path[n] = 0;
        vfs_ifsdirs[i].cursor = 0;
        vfs_ifsdirs[i].archive_done = !have_archive;
        vfs_ifsdirs[i].disk_h = h;
        vfs_ifsdirs[i].used = 1;
        return VFS_IFSDIR_FD_BASE + i;
    }
    if (h >= 0 && nurl_disk_closedir) (void)nurl_disk_closedir(h);
    nl_errno_slot = 24 /* EMFILE */;
    return -1;
}

/* A negative errno from NURL becomes -1 plus `errno`, which is the
 * shape every caller of these POSIX names already handles. */
static int posix_ret(long long rc) {
    if (rc < 0) { nl_errno_slot = (int)-rc; return -1; }
    return (int)rc;
}

static long long posix_ret_ll(long long rc) {
    if (rc < 0) { nl_errno_slot = (int)-rc; return -1; }
    return rc;
}

/* Open flags, the Linux numbers — the same ones `stdlib/fs/fatfs.nu`
 * names, because the guest's nolibc and the filesystem under it are
 * both written against this one table. */
#define VFS_O_ACCMODE   3
#define VFS_O_RDWR      2
#define VFS_O_CREAT     0100
#define VFS_O_EXCL      0200
#define VFS_O_DIRECTORY 0200000

/* ── redirecting the standard descriptors ────────────────────────
 *
 * `cmd > file` is not an exotic feature, and a shell that could not do
 * it would not be a shell. On Linux the kernel's descriptor table
 * answers `dup2`; here there is no kernel, so the three standard
 * descriptors get a redirection table of their own and `write` / `read`
 * consult it.
 *
 * Scope, stated rather than discovered: only 0, 1 and 2 may be the
 * TARGET of a `dup2`. That is what a shell redirects, and a general
 * descriptor table would be a second filesystem layer for no caller.
 *
 * Ownership follows the shell's own idiom — `dup2(newfd, 1)` then
 * `close(newfd)` — so a descriptor that has become a redirect target is
 * NOT closed by that `close`; it is closed when the redirect is
 * replaced or undone. Without that, every `>` would close the file it
 * had just opened and the next write would go nowhere.
 */
#define VFS_SAVED_BASE 300
#define VFS_SAVED_MAX  8

static int vfs_std_target[3] = { -1, -1, -1 };
static int vfs_std_alias[3]  = { 0, 0, 0 };   /* 2>&1: shares, does not own */

typedef struct {
    int used;
    int target;
    int alias;
} VfsSaved;

static VfsSaved vfs_saved[VFS_SAVED_MAX];

int fs_is_file_fd(int fd);
int fs_close_fd(int fd);

/* Where should a write to `fd` actually go? -1 means the console. */
int vfs_std_of(int fd) {
    if (fd < 0 || fd > 2) return -1;
    return vfs_std_target[fd];
}

/* Is this descriptor currently standing in for a standard one? Then a
 * `close` on it is the shell tidying up after `dup2`, not a request to
 * drop the redirect. */
int vfs_is_std_target(int fd) {
    int i;
    if (fd < 0) return 0;
    for (i = 0; i < 3; i++) if (vfs_std_target[i] == fd) return 1;
    for (i = 0; i < VFS_SAVED_MAX; i++)
        if (vfs_saved[i].used && vfs_saved[i].target == fd) return 1;
    return 0;
}

static int vfs_is_std_target_except(int fd, int skip);

static void vfs_std_release(int stdfd) {
    int t = vfs_std_target[stdfd];
    if (t >= 0 && !vfs_std_alias[stdfd] && !vfs_is_std_target_except(t, stdfd))
        (void)fs_close_fd(t);
    vfs_std_target[stdfd] = -1;
    vfs_std_alias[stdfd] = 0;
}

static int vfs_is_std_target_except(int fd, int skip) {
    int i;
    if (fd < 0) return 0;
    for (i = 0; i < 3; i++) if (i != skip && vfs_std_target[i] == fd) return 1;
    for (i = 0; i < VFS_SAVED_MAX; i++)
        if (vfs_saved[i].used && vfs_saved[i].target == fd) return 1;
    return 0;
}

int dup2(int oldfd, int newfd) {
    if (newfd < 0 || newfd > 2) { nl_errno_slot = 9 /* EBADF */; return -1; }
    if (oldfd >= VFS_SAVED_BASE && oldfd < VFS_SAVED_BASE + VFS_SAVED_MAX) {
        /* Restoring a saved descriptor. */
        VfsSaved *sv = &vfs_saved[oldfd - VFS_SAVED_BASE];
        if (!sv->used) { nl_errno_slot = 9; return -1; }
        vfs_std_release(newfd);
        vfs_std_target[newfd] = sv->target;
        vfs_std_alias[newfd] = sv->alias;
        return newfd;
    }
    if (oldfd >= 0 && oldfd < 3) {           /* `2>&1` */
        int t = vfs_std_target[oldfd];
        vfs_std_release(newfd);
        vfs_std_target[newfd] = t;
        vfs_std_alias[newfd] = 1;
        return newfd;
    }
    if (!fs_is_file_fd(oldfd)) { nl_errno_slot = 9; return -1; }
    vfs_std_release(newfd);
    vfs_std_target[newfd] = oldfd;
    vfs_std_alias[newfd] = 0;
    return newfd;
}

int dup(int fd) {
    int i;
    if (fd < 0 || fd > 2) { nl_errno_slot = 9; return -1; }
    for (i = 0; i < VFS_SAVED_MAX; i++) {
        if (vfs_saved[i].used) continue;
        vfs_saved[i].used = 1;
        vfs_saved[i].target = vfs_std_target[fd];
        /* The save carries the OWNERSHIP with it. Recording it as a
         * borrow instead loses track of who closes the file: restoring
         * the descriptor would then leave the redirected file open and
         * unflushed, which is how a `$(cmd | cmd)` came back empty —
         * the capture file was still buffered when it was read. */
        vfs_saved[i].alias = vfs_std_alias[fd];
        return VFS_SAVED_BASE + i;
    }
    nl_errno_slot = 24 /* EMFILE */;
    return -1;
}

/* fcntl(2), the F_DUPFD form only — which is how a shell saves a
 * descriptor before redirecting it. Everything else is refused. */
int fcntl(int fd, int cmd, long arg) {
    (void)arg;
    if (cmd != 0 /* F_DUPFD */) { nl_errno_slot = 38 /* ENOSYS */; return -1; }
    return dup(fd);
}

/* Close a saved slot; ordinary descriptors go to fs_close_fd. */
int vfs_close_saved(int fd) {
    if (fd < VFS_SAVED_BASE || fd >= VFS_SAVED_BASE + VFS_SAVED_MAX) return 0;
    vfs_saved[fd - VFS_SAVED_BASE].used = 0;
    return 1;
}

/* ── the working directory ───────────────────────────────────────
 *
 * The guest has one namespace, and until now it had no cursor into it:
 * every path was resolved from the root, so `cd` could not work and a
 * shell script that changed directory and then opened a relative name
 * opened the wrong thing — or nothing.
 *
 * One string, and one resolution step in front of every path-taking
 * entry point. `..` and `.` are folded by the archive's own normaliser
 * (initfs.c), so this only has to decide whether a path is absolute and
 * prefix the cursor when it is not.
 */
#define VFS_CWD_MAX 512
static char vfs_cwd[VFS_CWD_MAX] = "/";

/* Make `path` absolute against the working directory AND fold away `.`
 * and `..`. Both halves matter: the layers underneath — the archive's
 * lookup and the FAT driver — walk the path component by component, and
 * neither has a kernel in front of it to tidy `./tmp.abcdef` or
 * `a/../b` first. `mkstemp` producing `./tmp.XXXXXX` is exactly how
 * that showed up: a name the disk could not open, reported as "nowhere
 * writable" on a machine with a perfectly good disk. */
static const char *vfs_resolve(const char *path, char *buf, unsigned long cap) {
    unsigned long n = 0, i = 0, out = 0;
    static char tmp[VFS_CWD_MAX * 2];
    const char *src;

    if (!path) return path;
    if (path[0] == '/') {
        src = path;
    } else {
        while (vfs_cwd[n] && n + 2 < sizeof tmp) { tmp[n] = vfs_cwd[n]; n++; }
        if (n == 0 || tmp[n - 1] != '/') tmp[n++] = '/';
        while (path[i] && n + 1 < sizeof tmp) tmp[n++] = path[i++];
        tmp[n] = 0;
        src = tmp;
    }

    /* Fold the components. `..` at the root stays at the root, which is
     * what every kernel does with `/..`. */
    i = 0;
    buf[out++] = '/';
    for (;;) {
        unsigned long start, len;
        while (src[i] == '/') i++;
        if (!src[i]) break;
        start = i;
        while (src[i] && src[i] != '/') i++;
        len = i - start;
        if (len == 1 && src[start] == '.') continue;
        if (len == 2 && src[start] == '.' && src[start + 1] == '.') {
            while (out > 1 && buf[out - 1] != '/') out--;
            if (out > 1) out--;
            continue;
        }
        if (out > 1 && out + 1 < cap) buf[out++] = '/';
        {
            unsigned long k = 0;
            while (k < len && out + 1 < cap) buf[out++] = src[start + k++];
        }
    }
    buf[out] = 0;
    return buf;
}

char *getcwd(char *buf, unsigned long size) {
    unsigned long n = 0;
    if (!buf) { nl_errno_slot = 22 /* EINVAL */; return 0; }
    while (vfs_cwd[n]) n++;
    if (size < n + 1) { nl_errno_slot = 34 /* ERANGE */; return 0; }
    for (n = 0; vfs_cwd[n]; n++) buf[n] = vfs_cwd[n];
    buf[n] = 0;
    return buf;
}

int chdir(const char *path) {
    char tmp[VFS_CWD_MAX];
    const char *full;
    unsigned long n = 0;
    if (!path) { nl_errno_slot = 22; return -1; }
    full = vfs_resolve(path, tmp, sizeof tmp);
    /* It has to BE a directory. A `cd` that succeeded onto a file would
     * make every relative path after it fail for no visible reason. */
    if (ifs_kind(full, 0) != 2) {
        if (!(disk_live() && nurl_disk_is_dir && nurl_disk_is_dir(full) == 1)) {
            nl_errno_slot = 2 /* ENOENT */;
            return -1;
        }
    }
    (void)n;
    {
        unsigned long i = 0, o = (full[0] == '/') ? 0 : 1;
        if (o == 1) vfs_cwd[0] = '/';
        while (full[i] && o + 1 < VFS_CWD_MAX) vfs_cwd[o++] = full[i++];
        /* Strip a trailing slash so `cd /etc/` and `cd /etc` agree. */
        while (o > 1 && vfs_cwd[o - 1] == '/') o--;
        vfs_cwd[o] = 0;
    }
    return 0;
}

int nl_open(const char *path0, int flags, int mode) {
    char rbuf[VFS_CWD_MAX];
    const char *path;
    if (!path0) { nl_errno_slot = 22 /* EINVAL */; return -1; }
    path = vfs_resolve(path0, rbuf, sizeof rbuf);

    int wants_write = (flags & VFS_O_ACCMODE) != 0 || (flags & VFS_O_CREAT) != 0;

    /* A read of something the image holds is served from the image,
     * before the disk is even asked. See the header. */
    if (!wants_write && !(flags & VFS_O_DIRECTORY)) {
        int fd = ifs_open(path, flags, mode);
        if (fd >= 0) return fd;
    }

    /* A directory the IMAGE holds is a directory: the archive's paths
     * spell a tree, and refusing to open it would make `ls` and every
     * "is this a directory?" predicate wrong about files that are
     * plainly there. Checked before the disk, for the same reason a
     * file read is. */
    if (flags & VFS_O_DIRECTORY) {
        /* An EMPTY archive has no root to speak of — it must not
         * shadow the disk's. */
        int have_arch = ifs_kind(path, 0) == 2 && nurl_initfs_size() > 0;
        int fd = ifsdir_open(path, have_arch);
        if (fd >= 0) return fd;
        if (!disk_live()) { nl_errno_slot = 2 /* ENOENT */; return -1; }
    }

    if (disk_live()) {
        long long h;
        if (flags & VFS_O_DIRECTORY) {
            h = nurl_disk_opendir(path);
        } else {
            h = nurl_disk_open(path, (long long)flags);
        }
        if (h < 0) { nl_errno_slot = (int)-h; return -1; }
        if (h >= (long long)(VFS_DISK_FD_MAX - VFS_DISK_FD_BASE)) {
            (void)nurl_disk_close(h);
            nl_errno_slot = 24 /* EMFILE */;
            return -1;
        }
        return VFS_DISK_FD_BASE + (int)h;
    }

    /* No disk: whatever the archive says IS what the machine says,
     * including its EROFS and its ENOTDIR. */
    return ifs_open(path, flags, mode);
}

int fs_is_file_fd(int fd) { return ifs_is_fd(fd) || disk_is_fd(fd); }

vfs_ssize_t fs_read_fd(int fd, void *buf, vfs_size_t n) {
    if (ifs_is_fd(fd)) return ifs_read(fd, buf, n);
    if (disk_is_fd(fd) && nurl_disk_read)
        return (vfs_ssize_t)posix_ret_ll(nurl_disk_read(fd - VFS_DISK_FD_BASE, buf, (long long)n));
    nl_errno_slot = 9 /* EBADF */;
    return -1;
}

vfs_ssize_t fs_write_fd(int fd, const void *buf, vfs_size_t n) {
    if (ifs_is_fd(fd)) { nl_errno_slot = 30 /* EROFS */; return -1; }
    if (disk_is_fd(fd) && nurl_disk_write)
        return (vfs_ssize_t)posix_ret_ll(nurl_disk_write(fd - VFS_DISK_FD_BASE, buf, (long long)n));
    nl_errno_slot = 9;
    return -1;
}

long long fs_lseek_fd(int fd, long long off, int whence) {
    if (ifs_is_fd(fd)) return ifs_lseek(fd, off, whence);
    if (disk_is_fd(fd) && nurl_disk_lseek)
        return posix_ret_ll(nurl_disk_lseek(fd - VFS_DISK_FD_BASE, off, (long long)whence));
    nl_errno_slot = 9;
    return -1;
}

int fs_close_fd(int fd) {
    if (ifsdir_is_fd(fd)) {
        VfsIfsDir *d = &vfs_ifsdirs[fd - VFS_IFSDIR_FD_BASE];
        if (d->disk_h >= 0 && nurl_disk_closedir) (void)nurl_disk_closedir(d->disk_h);
        d->disk_h = -1;
        d->used = 0;
        return 0;
    }
    if (ifs_is_fd(fd)) return ifs_close(fd);
    if (disk_is_fd(fd) && nurl_disk_close)
        return posix_ret(nurl_disk_close(fd - VFS_DISK_FD_BASE));
    nl_errno_slot = 9;
    return -1;
}

/* The bytes of an open file, in place — only ever true of the archive,
 * which is already in memory. A disk file has no address to hand back,
 * and answering one would be answering with a pointer into a sector
 * cache that the next read evicts. Zero sends `std/fs.nu`'s POSIX read
 * path down its copying branch, which is the correct one here. */
const unsigned char *fs_map_fd(int fd, vfs_size_t off) {
    if (ifs_is_fd(fd)) return ifs_map(fd, off);
    return 0;
}

/* A file-backed `mmap`, which `std/fs.nu`'s read path uses instead of a
 * read loop. The archive answers with a pointer into itself — it is
 * already in memory and the mapping asked for read-only. A disk file has
 * no such address, so the pages are allocated and FILLED: MAP_PRIVATE
 * read-only is a snapshot, and a copy is a correct one.
 *
 * Returning MAP_FAILED here instead would not degrade gracefully —
 * `read_file` reports failure rather than falling back to a read loop,
 * which is exactly what the guest did: a file it had just written came
 * back as "cannot read", because `mmap` had handed out anonymous pages
 * with nothing of the file in them. */
unsigned long pa_alloc(unsigned long len);

void *vfs_map_file(int fd, unsigned long len, long off) {
    if (ifs_is_fd(fd)) {
        const unsigned char *p = ifs_map(fd, (vfs_size_t)off);
        return p ? (void *)p : (void *)-1;
    }
    if (!disk_is_fd(fd) || !nurl_disk_read || !nurl_disk_lseek) return (void *)-1;

    long long h = fd - VFS_DISK_FD_BASE;
    unsigned long m = pa_alloc(len);
    if (!m) return (void *)-1;

    long long keep = nurl_disk_lseek(h, 0, 1);
    if (nurl_disk_lseek(h, (long long)off, 0) < 0) return (void *)-1;
    unsigned long got = 0;
    while (got < len) {
        long long n = nurl_disk_read(h, (char *)m + got, (long long)(len - got));
        if (n <= 0) break;
        got += (unsigned long)n;
    }
    /* Short is not an error: a caller may map more than the file holds,
     * and the tail of a fresh page is zero either way. */
    for (unsigned long i = got; i < len; i++) ((char *)m)[i] = 0;
    if (keep >= 0) (void)nurl_disk_lseek(h, keep, 0);
    return (void *)m;
}

int fs_exists(const char *path0) {
    char rbuf[VFS_CWD_MAX];
    const char *path;
    if (!path0) return 0;
    path = vfs_resolve(path0, rbuf, sizeof rbuf);
    /* A directory exists as surely as a file does; `ifs_exists` only
     * answers about regular entries, which made `access` say no about
     * every directory in the image. */
    if (ifs_kind(path, 0) != 0) return 1;
    if (ifs_exists(path)) return 1;
    if (disk_live() && nurl_disk_exists) return nurl_disk_exists(path) == 1;
    return 0;
}

int fs_fsync_fd(int fd) {
    if (ifs_is_fd(fd)) return 0;            /* nothing of ours is volatile */
    if (disk_is_fd(fd) && nurl_disk_fsync)
        return posix_ret(nurl_disk_fsync(fd - VFS_DISK_FD_BASE));
    nl_errno_slot = 9;
    return -1;
}

/* Positional read/write, which `stdlib/runtime_core.c` calls through its
 * `nurl_pread`/`nurl_pwrite` shims — so runtime_core.o references them
 * and the guest has to define them. `nolibc/syscall_linux.c` has the
 * syscall versions for the Linux -nostdlib build, and the guest does
 * not link that file: the platform replaces it, which is exactly the
 * twin-drift this directory exists to catch.
 *
 * Emulated with a seek because there is no positional primitive
 * underneath. The position is SAVED AND RESTORED: a positional read is
 * defined not to move the file offset, and a caller interleaving one
 * with ordinary reads would otherwise find its cursor moved by a call
 * that promised not to touch it. */
long long pread(int fd, void *buf, unsigned long n, long long off) {
    long long keep = fs_lseek_fd(fd, 0, 1 /* SEEK_CUR */);
    if (keep < 0) return -1;
    if (fs_lseek_fd(fd, off, 0 /* SEEK_SET */) < 0) return -1;
    long long got = (long long)fs_read_fd(fd, buf, (vfs_size_t)n);
    (void)fs_lseek_fd(fd, keep, 0);
    return got;
}

long long pwrite(int fd, const void *buf, unsigned long n, long long off) {
    long long keep = fs_lseek_fd(fd, 0, 1);
    if (keep < 0) return -1;
    if (fs_lseek_fd(fd, off, 0) < 0) return -1;
    long long put = (long long)fs_write_fd(fd, buf, (vfs_size_t)n);
    (void)fs_lseek_fd(fd, keep, 0);
    return put;
}

/* ── the POSIX names that used to be refusals ────────────────────── */
/*
 * Each of these was a stub in `platform_*.c` or `nosys.c` that returned
 * -1 because there was nothing on this machine that could do the job.
 * With a disk there is, and the refusal has to become conditional —
 * but ONLY conditional: a machine with no disk answers exactly what it
 * answered before, because a caller whose error path stopped being
 * reachable is a caller whose success path is now wrong.
 */

int unlink(const char *p0) {
    char rbuf[VFS_CWD_MAX];
    const char *p = vfs_resolve(p0, rbuf, sizeof rbuf);
    if (!p) { nl_errno_slot = 22; return -1; }
    if (disk_live() && nurl_disk_unlink) return posix_ret(nurl_disk_unlink(p));
    nl_errno_slot = ifs_exists(p) ? 30 /* EROFS */ : 2 /* ENOENT */;
    return -1;
}

int rename(const char *a0, const char *b0) {
    char rbuf_a[VFS_CWD_MAX];
    char rbuf_b[VFS_CWD_MAX];
    const char *a = vfs_resolve(a0, rbuf_a, sizeof rbuf_a);
    const char *b = vfs_resolve(b0, rbuf_b, sizeof rbuf_b);
    if (!a || !b) { nl_errno_slot = 22; return -1; }
    if (disk_live() && nurl_disk_rename) return posix_ret(nurl_disk_rename(a, b));
    nl_errno_slot = 30;
    return -1;
}

int mkdir(const char *p0, int mode) {
    char rbuf[VFS_CWD_MAX];
    const char *p = vfs_resolve(p0, rbuf, sizeof rbuf);
    (void)mode;
    if (!p) { nl_errno_slot = 22; return -1; }
    if (disk_live() && nurl_disk_mkdir) return posix_ret(nurl_disk_mkdir(p));
    nl_errno_slot = 30;
    return -1;
}

int rmdir(const char *p0) {
    char rbuf[VFS_CWD_MAX];
    const char *p = vfs_resolve(p0, rbuf, sizeof rbuf);
    if (!p) { nl_errno_slot = 22; return -1; }
    if (disk_live() && nurl_disk_rmdir) return posix_ret(nurl_disk_rmdir(p));
    nl_errno_slot = 30;
    return -1;
}

int truncate(const char *p0, long long len) {
    char rbuf[VFS_CWD_MAX];
    const char *p = vfs_resolve(p0, rbuf, sizeof rbuf);
    if (!p) { nl_errno_slot = 22; return -1; }
    if (disk_live() && nurl_disk_truncate) return posix_ret(nurl_disk_truncate(p, len));
    nl_errno_slot = 30;
    return -1;
}

/* fsync on a descriptor. The version this replaces refused ALWAYS, on
 * the reasoning that a machine which cannot write has nothing to make
 * durable — which stays true for the archive and stops being true the
 * moment a disk is attached. Answering 0 without a disk would tell a
 * write-ahead log its log is on the medium. */
int fsync(int fd) { return fs_fsync_fd(fd); }

int fdatasync(int fd) { return fs_fsync_fd(fd); }

/* Everything every open handle has written, on the medium. Called at
 * shutdown so a guest that is stopped cleanly does not lose the writes
 * it never explicitly synced. */
int vfs_sync_all(void) {
    if (disk_live() && nurl_disk_sync) return posix_ret(nurl_disk_sync());
    return 0;
}

/* access(2), against the filesystem this machine actually has. F_OK (0)
 * and R_OK (4) are answerable — the machine either has the file or it
 * does not. W_OK (2) used to be refused unconditionally because the
 * archive lives in the text segment; now it is refused only for a path
 * that exists ONLY there. X_OK (1) stays refused: nothing here is
 * executable, disk or no disk. */
int access(const char *p, int mode) {
    if (!p) { nl_errno_slot = 22; return -1; }
    if (mode & 1) { nl_errno_slot = 13 /* EACCES */; return -1; }
    int on_disk = disk_live() && nurl_disk_exists && nurl_disk_exists(p) == 1;
    int in_image = ifs_exists(p);
    if (!on_disk && !in_image) { nl_errno_slot = 2 /* ENOENT */; return -1; }
    if ((mode & 2) && !on_disk) { nl_errno_slot = 13; return -1; }
    if ((mode & 2) && (!nurl_disk_writable || nurl_disk_writable() != 1)) {
        nl_errno_slot = 30 /* EROFS */;
        return -1;
    }
    return 0;
}

/* ── getdents64 ──────────────────────────────────────────────────── */
/*
 * `nolibc/misc.c` builds opendir/readdir out of `nl_open(O_DIRECTORY)`
 * plus this one syscall, and it reads the records at the kernel's own
 * offsets: d_reclen at 16, d_name at 19. Those are the offsets glibc's
 * `struct dirent` uses too, which is why `nurl_dirent_name` — compiled
 * against the real header into runtime.o — can read a record this file
 * wrote. Getting them wrong would not fail to compile anywhere.
 *
 * The syscall NUMBER is x86-64's on every architecture here, because
 * the only caller is `misc.c` and it spells 217 unconditionally. There
 * is no kernel on the other side to disagree.
 */
#define VFS_SYS_GETDENTS64 217

#define VFS_DT_DIR 4
#define VFS_DT_REG 8

static void vfs_put_u64(char *p, unsigned long long v) {
    for (int i = 0; i < 8; i++) p[i] = (char)((v >> (i * 8)) & 0xff);
}

static void vfs_put_u16(char *p, unsigned short v) {
    p[0] = (char)(v & 0xff);
    p[1] = (char)((v >> 8) & 0xff);
}

long vfs_getdents64(int fd, void *buf, unsigned long len) {
    if (!disk_is_fd(fd) || !nurl_disk_readdir_name) { nl_errno_slot = 9; return -9; }
    char *out = (char *)buf;
    unsigned long used = 0;
    long long h = fd - VFS_DISK_FD_BASE;

    for (;;) {
        char name[256];
        /* The record is 19 bytes of header, the name, a terminator, and
         * padding to a multiple of eight. Reserve it BEFORE asking for
         * the name: a name read out of the directory and then dropped
         * for want of room is an entry the caller never sees again,
         * because the handle's cursor has already moved past it. */
        if (used + 19 + 1 + 8 > len) break;
        unsigned long room = len - used - 19 - 1;
        if (room > sizeof name - 1) room = sizeof name - 1;

        long long n = nurl_disk_readdir_name(h, name, (long long)room + 1);
        if (n == 0) break;                       /* end of directory */
        if (n < 0) {
            /* The name did not fit. With nothing written yet that is a
             * buffer too small to make progress in; with records
             * already in it, the caller comes back with an empty one. */
            if (used == 0) { nl_errno_slot = 22; return -22; }
            break;
        }

        unsigned long reclen = 19 + (unsigned long)n + 1;
        reclen = (reclen + 7) & ~7UL;
        if (used + reclen > len) {
            /* Cannot happen given the reservation above, but a record
             * written past the end of a caller's buffer is not a bug to
             * find later. */
            break;
        }

        char *rec = out + used;
        vfs_put_u64(rec, (unsigned long long)(used + 1));        /* d_ino  */
        vfs_put_u64(rec + 8, (unsigned long long)(used + reclen)); /* d_off */
        vfs_put_u16(rec + 16, (unsigned short)reclen);           /* d_reclen */
        rec[18] = (char)(nurl_disk_dirent_is_dir && nurl_disk_dirent_is_dir()
                             ? VFS_DT_DIR : VFS_DT_REG);
        for (long long i = 0; i < n; i++) rec[19 + i] = name[i];
        for (unsigned long i = 19 + (unsigned long)n; i < reclen; i++) rec[i] = 0;
        used += reclen;
    }
    return (long)used;
}

/* mkstemp(3). The template's trailing XXXXXX becomes a number, and the
 * file is created with O_EXCL so the loop stops on the first name
 * nobody else has — which is the whole point of the call and the only
 * part of it that is not string handling.
 *
 * Without a disk this refuses exactly as it did when it lived in
 * `nosys.c`: there is nowhere to put a temporary file, and a caller
 * that got a descriptor would discover that at the first write. */
int mkstemp(char *tmpl) {
    if (!tmpl) { nl_errno_slot = 22; return -1; }
    if (!disk_live()) { nl_errno_slot = 30 /* EROFS */; return -1; }

    unsigned long n = 0;
    while (tmpl[n]) n++;
    if (n < 6) { nl_errno_slot = 22; return -1; }
    for (unsigned long i = n - 6; i < n; i++)
        if (tmpl[i] != 'X') { nl_errno_slot = 22; return -1; }

    static unsigned long seq = 0;
    for (int tries = 0; tries < 4096; tries++) {
        unsigned long v = (seq += 7919);
        for (int d = 5; d >= 0; d--) {
            tmpl[n - 6 + d] = (char)('a' + (int)(v % 26));
            v /= 26;
        }
        int fd = nl_open(tmpl, VFS_O_RDWR | VFS_O_CREAT | VFS_O_EXCL, 0600);
        if (fd >= 0) return fd;
        if (nl_errno_slot != 17 /* EEXIST */) return -1;
    }
    nl_errno_slot = 17;
    return -1;
}

/* ── stat(2) ─────────────────────────────────────────────────────
 *
 * `struct stat` on x86_64 is a fixed layout, and runtime_core.c was
 * compiled against exactly that header — so this fills it by offset
 * rather than by declaring a struct nobody here can see.
 *
 *   0 st_dev   8 st_ino  16 st_nlink  24 st_mode(u32)  28 st_uid(u32)
 *  32 st_gid   40 st_rdev 48 st_size   56 st_blksize    64 st_blocks
 *  72 atime    88 mtime  104 ctime                     (144 bytes)
 *
 * The timestamps are ZERO, deliberately: the archive is baked at link
 * time and the FAT layer does not surface a modification time, so `ls
 * -l` shows the epoch. That is the machine saying "I do not know",
 * which is a thing a reader can act on; a boot-time value would be a
 * plausible-looking number that means nothing.
 */
#define VFS_S_IFREG 0100000
#define VFS_S_IFDIR 0040000

static void vfs_put_u32(char *p, unsigned int v) {
    p[0] = (char)(v & 0xff); p[1] = (char)((v >> 8) & 0xff);
    p[2] = (char)((v >> 16) & 0xff); p[3] = (char)((v >> 24) & 0xff);
}

static void vfs_fill_stat(void *st, int is_dir, long long size) {
    char *p = (char *)st;
    unsigned long i;
    for (i = 0; i < 144; i++) p[i] = 0;
    vfs_put_u64(p, 1);                                   /* st_dev  */
    vfs_put_u64(p + 8, 1);                               /* st_ino  */
    vfs_put_u64(p + 16, 1);                              /* st_nlink */
    /* Read-only for the archive; the disk's FAT has no permission bits
     * either, so 0555 / 0444 is the truth about both. */
    vfs_put_u32(p + 24, (unsigned int)(is_dir ? (VFS_S_IFDIR | 0555)
                                              : (VFS_S_IFREG | 0444)));
    vfs_put_u64(p + 48, (unsigned long long)size);       /* st_size */
    vfs_put_u64(p + 56, 512);                            /* st_blksize */
    vfs_put_u64(p + 64, (unsigned long long)((size + 511) / 512)); /* st_blocks */
}

static long vfs_stat_path(const char *path0, void *st) {
    char rbuf[VFS_CWD_MAX];
    const char *path;
    vfs_size_t size = 0;
    int kind;
    if (!path0 || !st) return -14 /* EFAULT */;
    path = vfs_resolve(path0, rbuf, sizeof rbuf);
    kind = ifs_kind(path, &size);
    /* The archive's ROOT is a directory only when the archive has
     * something in it; an empty image must not shadow the disk's `/`. */
    if (kind == 2 && nurl_initfs_size() == 0) kind = 0;
    if (kind != 0) {
        vfs_fill_stat(st, kind == 2, (long long)size);
        return 0;
    }
    if (disk_live() && nurl_disk_exists && nurl_disk_exists(path) == 1) {
        int is_dir = nurl_disk_is_dir && nurl_disk_is_dir(path) == 1;
        long long sz = (!is_dir && nurl_disk_stat_size) ? nurl_disk_stat_size(path) : 0;
        vfs_fill_stat(st, is_dir, sz < 0 ? 0 : sz);
        return 0;
    }
    return -2 /* ENOENT */;
}

static long vfs_fstat_fd(int fd, void *st) {
    if (!st) return -14;
    if (ifsdir_is_fd(fd)) { vfs_fill_stat(st, 1, 0); return 0; }
    if (ifs_is_fd(fd)) {
        /* The archive's own size, via the seek the handle already
         * supports — no second index to keep in step. */
        long long cur = ifs_lseek(fd, 0, 1);
        long long end = ifs_lseek(fd, 0, 2);
        (void)ifs_lseek(fd, cur, 0);
        vfs_fill_stat(st, 0, end < 0 ? 0 : end);
        return 0;
    }
    if (disk_is_fd(fd) && nurl_disk_size) {
        long long sz = nurl_disk_size(fd - VFS_DISK_FD_BASE);
        vfs_fill_stat(st, 0, sz < 0 ? 0 : sz);
        return 0;
    }
    /* stdin/stdout/stderr: a character device, which is what they are. */
    if (fd >= 0 && fd <= 2) {
        char *p = (char *)st;
        unsigned long i;
        for (i = 0; i < 144; i++) p[i] = 0;
        vfs_put_u32(p + 24, 020000 | 0620);              /* S_IFCHR */
        vfs_put_u64(p + 56, 1024);
        return 0;
    }
    return -9 /* EBADF */;
}

/* getdents64 over the union directory — the same record layout the
 * disk-only path emits, so nolibc's readdir cannot tell them apart. */
static int vfs_ifs_has(const char *dir, const char *name) {
    char probe[256];
    int i = 0, is_dir = 0;
    while (ifs_dirent(dir, i, probe, (int)sizeof probe, &is_dir)) {
        int k = 0;
        while (probe[k] && probe[k] == name[k]) k++;
        if (!probe[k] && !name[k]) return 1;
        i++;
    }
    return 0;
}

static long vfs_ifs_getdents(int fd, void *buf, unsigned long len) {
    VfsIfsDir *d = &vfs_ifsdirs[fd - VFS_IFSDIR_FD_BASE];
    char *out = (char *)buf;
    unsigned long used = 0;
    char name[256];

    for (;;) {
        int is_dir = 0;
        unsigned long reclen, n = 0;
        int from_disk = 0;
        if (used + 19 + 1 + 8 > len) break;

        if (!d->archive_done) {
            if (!ifs_dirent(d->path, d->cursor, name, (int)sizeof name, &is_dir)) {
                d->archive_done = 1;
                continue;
            }
            d->cursor++;
        } else if (d->disk_h >= 0 && nurl_disk_readdir_name) {
            unsigned long room = len - used - 19 - 1;
            long long got;
            if (room > sizeof name - 1) room = sizeof name - 1;
            got = nurl_disk_readdir_name(d->disk_h, name, (long long)room + 1);
            if (got == 0) break;
            if (got < 0) {
                if (used == 0) { nl_errno_slot = 22; return -22; }
                break;
            }
            name[got] = 0;
            is_dir = nurl_disk_dirent_is_dir && nurl_disk_dirent_is_dir();
            from_disk = 1;
            /* Already listed from the archive: read resolution is
             * archive-first, so the listing must be too. */
            if (vfs_ifs_has(d->path, name)) continue;
        } else {
            break;
        }
        (void)from_disk;

        while (name[n]) n++;
        reclen = (19 + n + 1 + 7) & ~7UL;
        if (used + reclen > len) break;
        {
            char *rec = out + used;
            unsigned long i;
            vfs_put_u64(rec, (unsigned long long)(used + 1));
            vfs_put_u64(rec + 8, (unsigned long long)(used + reclen));
            vfs_put_u16(rec + 16, (unsigned short)reclen);
            rec[18] = (char)(is_dir ? VFS_DT_DIR : VFS_DT_REG);
            for (i = 0; i < n; i++) rec[19 + i] = name[i];
            for (i = 19 + n; i < reclen; i++) rec[i] = 0;
        }
        used += reclen;
    }
    return (long)used;
}

/* The syscalls this machine answers. Everything else is -ENOSYS, which
 * is what a Linux kernel says about a syscall it does not implement, so
 * every caller already knows the shape. */
#define VFS_SYS_STAT   4
#define VFS_SYS_FSTAT  5
#define VFS_SYS_LSTAT  6

long vfs_syscall(long n, long a, long b, long c) {
    if (n == VFS_SYS_GETDENTS64) {
        if (ifsdir_is_fd((int)a)) return vfs_ifs_getdents((int)a, (void *)b, (unsigned long)c);
        return vfs_getdents64((int)a, (void *)b, (unsigned long)c);
    }
    /* lstat is stat here: neither the archive nor a FAT volume has
     * symlinks, so there is nothing for the two to disagree about. */
    if (n == VFS_SYS_STAT || n == VFS_SYS_LSTAT) return vfs_stat_path((const char *)a, (void *)b);
    if (n == VFS_SYS_FSTAT) return vfs_fstat_fd((int)a, (void *)b);
    return -38;
}
