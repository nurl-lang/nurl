// stdlib/fs/blkdev_file.nu — a block device that is a file on a host.
//
// One of the three providers of the `nurl_blk_*` seam declared in
// `stdlib/hal/blockdev.nu`; the other two live in `unikernel/fs/`. This
// one exists so the filesystem above it can be developed, tested and
// fuzzed where `mkfs.vfat` and `fsck.vfat` are — an image built by the
// system's own tools, written by ours, and validated by theirs is a
// real oracle, which a filesystem checking its own work is not.
//
// It is also how a disk image gets BUILT for a guest: the same code
// that mounts a virtio device in the unikernel formats and fills a file
// here, so the image handed to `-drive` was written by the reader that
// will read it.
//
// `nurl_pread`/`nurl_pwrite`/`nurl_fd_sync` rather than the POSIX names:
// the offset is part of the call, so there is no file position to get
// out of step with a caller that interleaved two requests — and the
// MSVC CRT has none of `pread`, `pwrite` or `fsync`, so spelling them
// directly links everywhere except Windows. The shims are in
// `stdlib/runtime_core.c`, beside `nurl_file_sync`, which exists for
// the same reason.
//
// O_BINARY is ORed in unconditionally. It is 0 on every platform that
// has no text mode, and on the one that does, a device image read in
// text mode has its 0x0A bytes mangled — which is not a filesystem bug
// anyone would find by reading filesystem code.
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/hal/blockdev.nu`

& `c` @ nurl_pread i32 fd *u buf i n i off → i

& `c` @ nurl_pwrite i32 fd *u buf i n i off → i

& `c` @ nurl_fd_sync i32 fd → i

: ~ i g_blkfd - 0 1
: ~ i g_blksectors 0
: ~ b g_blkro F

// Attach to `path`. `writable` false opens it read-only, which is what
// a checker wants and what stops a test from editing its own fixture.
// The size is measured, not asked for: a device is as many whole
// sectors as the file holds, and a trailing partial sector is not one.
@ blkfile_open s path b writable → b {
    ( blkfile_close )
    : i o_rdonly ( posix_const `O_RDONLY` )
    : i o_rdwr ( posix_const `O_RDWR` )
    : i fd # i ( open path # i32 | ( posix_const `O_BINARY` ) ? writable o_rdwr o_rdonly )
    ? < fd 0 { ^ F } {}
    : i size ( lseek # i32 fd 0 # i32 2 )
    ? < size 0 { : i32 _c ( close # i32 fd ) ^ F } {}
    = g_blkfd fd
    = g_blksectors / size ( blk_sector_size )
    = g_blkro ! writable
    ^ > g_blksectors 0
}

// Create (or re-create) a file of exactly `sectors` sectors and attach
// to it, writable. The file is TRUNCATED: a formatter that reused the
// tail of a bigger image would leave structures the new one never wrote
// and cannot explain.
@ blkfile_create s path i sectors → b {
    ( blkfile_close )
    ? <= sectors 0 { ^ F } {}
    : i flags | | | ( posix_const `O_RDWR` ) ( posix_const `O_CREAT` ) ( posix_const `O_TRUNC` ) ( posix_const `O_BINARY` )
    : i fd # i ( open path # i32 flags # i32 420 )
    ? < fd 0 { ^ F } {}
    // One zero sector written at the very end gives the file its full
    // length; the holes in between read as zeros, which is what a fresh
    // device gives you anyway.
    : ( Vec u ) z ( vec_with_cap [u] ( blk_sector_size ) )
    : ~ i k 0
    ~ < k ( blk_sector_size ) { ( vec_push [u] z # u 0 ) = k + k 1 }
    : i want ( blk_sector_size )
    : i wrote ( nurl_pwrite # i32 fd # *u ( vec_data [u] z ) want * - sectors 1 want )
    ( vec_free [u] z )
    ? != wrote want { : i32 _c ( close # i32 fd ) ^ F } {}
    = g_blkfd fd
    = g_blksectors sectors
    = g_blkro F
    ^ T
}

@ blkfile_close → v {
    ? >= g_blkfd 0 {
        : i _s ( nurl_fd_sync # i32 g_blkfd )
        : i32 _c ( close # i32 g_blkfd )
    } {}
    = g_blkfd - 0 1
    = g_blksectors 0
    = g_blkro F
}

// ── the seam ────────────────────────────────────────────────────────

@ nurl_blk_sector_count → i { ^ g_blksectors }

@ nurl_blk_read i lba s buf i nsec → i {
    ? < g_blkfd 0 { ^ - 0 1 } {}
    : i want * nsec ( blk_sector_size )
    : i got ( nurl_pread # i32 g_blkfd # *u buf want * lba ( blk_sector_size ) )
    ? != got want { ^ - 0 1 } {}
    ^ nsec
}

@ nurl_blk_write i lba s buf i nsec → i {
    ? < g_blkfd 0 { ^ - 0 1 } {}
    ? g_blkro { ^ - 0 1 } {}
    : i want * nsec ( blk_sector_size )
    : i put ( nurl_pwrite # i32 g_blkfd # *u buf want * lba ( blk_sector_size ) )
    ? != put want { ^ - 0 1 } {}
    ^ nsec
}

@ nurl_blk_flush → i {
    ? < g_blkfd 0 { ^ - 0 1 } {}
    ? g_blkro { ^ 0 } {}
    ^ ( nurl_fd_sync # i32 g_blkfd )
}
