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

/* ── the archive, one layer down ─────────────────────────────────── */

int                  ifs_open(const char *path, int flags, int mode);
int                  ifs_is_fd(int fd);
vfs_ssize_t          ifs_read(int fd, void *buf, vfs_size_t n);
long long            ifs_lseek(int fd, long long off, int whence);
int                  ifs_close(int fd);
const unsigned char *ifs_map(int fd, vfs_size_t off);
int                  ifs_exists(const char *path);

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

int nl_open(const char *path, int flags, int mode) {
    if (!path) { nl_errno_slot = 22 /* EINVAL */; return -1; }

    int wants_write = (flags & VFS_O_ACCMODE) != 0 || (flags & VFS_O_CREAT) != 0;

    /* A read of something the image holds is served from the image,
     * before the disk is even asked. See the header. */
    if (!wants_write && !(flags & VFS_O_DIRECTORY)) {
        int fd = ifs_open(path, flags, mode);
        if (fd >= 0) return fd;
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

int fs_exists(const char *path) {
    if (!path) return 0;
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

/* ── the POSIX names that used to be refusals ────────────────────── */
/*
 * Each of these was a stub in `platform_*.c` or `nosys.c` that returned
 * -1 because there was nothing on this machine that could do the job.
 * With a disk there is, and the refusal has to become conditional —
 * but ONLY conditional: a machine with no disk answers exactly what it
 * answered before, because a caller whose error path stopped being
 * reachable is a caller whose success path is now wrong.
 */

int unlink(const char *p) {
    if (!p) { nl_errno_slot = 22; return -1; }
    if (disk_live() && nurl_disk_unlink) return posix_ret(nurl_disk_unlink(p));
    nl_errno_slot = ifs_exists(p) ? 30 /* EROFS */ : 2 /* ENOENT */;
    return -1;
}

int rename(const char *a, const char *b) {
    if (!a || !b) { nl_errno_slot = 22; return -1; }
    if (disk_live() && nurl_disk_rename) return posix_ret(nurl_disk_rename(a, b));
    nl_errno_slot = 30;
    return -1;
}

int mkdir(const char *p, int mode) {
    (void)mode;
    if (!p) { nl_errno_slot = 22; return -1; }
    if (disk_live() && nurl_disk_mkdir) return posix_ret(nurl_disk_mkdir(p));
    nl_errno_slot = 30;
    return -1;
}

int rmdir(const char *p) {
    if (!p) { nl_errno_slot = 22; return -1; }
    if (disk_live() && nurl_disk_rmdir) return posix_ret(nurl_disk_rmdir(p));
    nl_errno_slot = 30;
    return -1;
}

int truncate(const char *p, long long len) {
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

/* The one syscall this machine answers. Everything else is -ENOSYS,
 * which is what a Linux kernel says about a syscall it does not
 * implement, so every caller already knows the shape. */
long vfs_syscall(long n, long a, long b, long c) {
    if (n == VFS_SYS_GETDENTS64) return vfs_getdents64((int)a, (void *)b, (unsigned long)c);
    return -38;
}
