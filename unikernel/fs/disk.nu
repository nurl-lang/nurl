// unikernel/fs/disk.nu — the guest's writable filesystem, as the VFS in
// `boot/vfs.c` calls it.
//
// This is the disk's counterpart to `net/sockets.nu`: a shim whose only
// job is to answer a set of `nurl_*` symbols the C side declares, over
// layers that were written and tested somewhere the hardware is not.
// Everything here is bookkeeping — the filesystem is `stdlib/fs/`, the
// device is `drivers/virtioblk.nu`.
//
// WHEN THE DISK IS MOUNTED. On the first call that needs it, not at
// boot: a machine whose program never opens a file never touches the
// device, and a mount that failed at boot would have to be reported
// through a console message nobody is reading yet. What the command
// line says is honoured exactly:
//
//   disk=rw       mount read-write (the default when a device exists)
//   disk=ro       mount read-only — every write is refused with EROFS
//   disk=format   format the device, then mount read-write. ONLY when
//                 the volume does not mount: a `disk=format` that
//                 reformatted a perfectly good filesystem on every boot
//                 would be a data-loss switch spelled as a convenience
//   disk=off      there is no filesystem, whatever the machine has
//
// The clock comes from `wallclock=`, which the boot code already turns
// into an environment variable — so a file written by a guest that was
// told the time carries that time, and one written by a guest that was
// not carries 1980, which is the honest answer rather than a plausible
// one.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/hal/blockdev.nu`
$ `stdlib/fs/fat.nu`
$ `stdlib/fs/fatfs.nu`
$ `stdlib/fs/fatfmt.nu`

& `c` @ getenv s name → s

: ~ i g_state 0  // 0 = untried, 1 = mounted, 2 = no filesystem

// The attribute byte of the entry the last `nurl_disk_readdir_name`
// returned. Kept beside the name rather than packed into its return
// value: two calls that read one entry are clearer than one call whose
// integer means two things.
: ~ i g_last_attr 0

@ __streq s a s b → b { ^ != 0 ( nurl_str_eq a b ) }

@ __env_or s name s dflt → s {
    : s v ( getenv name )
    ? == # i v 0 { ^ dflt } {}
    ? == ( nurl_str_len v ) 0 { ^ dflt } {}
    ^ v
}

// The epoch, if the machine was told it. `wallclock=` is seconds; an
// unparseable one is treated as absent rather than as zero, because
// zero is a time (1970) and absent is not.
@ __wallclock → i {
    : s w ( getenv `wallclock` )
    ? == # i w 0 { ^ 0 } {}
    : i n ( nurl_str_len w )
    ? == n 0 { ^ 0 } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get w k )
        ? || < c 48 > c 57 { ^ 0 } {}
        = k + k 1
    }
    ^ ( nurl_str_to_int w )
}

@ __mount_once → b {
    ? == g_state 1 { ^ T } {}
    ? == g_state 2 { ^ F } {}
    = g_state 2

    : s mode ( __env_or `disk` `rw` )
    ? ( __streq mode `off` ) { ^ F } {}
    ? ! ( blk_present ) { ^ F } {}

    : b want_rw ! ( __streq mode `ro` )
    ? ( fat_mount want_rw ) {
        = g_state 1
        ( fatfs_set_time ( __wallclock ) )
        ^ T
    } {}

    // Only now, and only when asked: an unmountable device plus
    // `disk=format` is the one case where writing a filesystem over
    // whatever is there is what the operator meant.
    ? ( __streq mode `format` ) {
        ? ( fat_format `NURLDISK` ) {
            ? ( fat_mount T ) {
                = g_state 1
                ( fatfs_set_time ( __wallclock ) )
                ^ T
            } {}
        } {}
    } {}
    ^ F
}

@ nurl_disk_ready → i { ^ ? ( __mount_once ) 1 0 }

@ nurl_disk_writable → i { ^ ? && ( __mount_once ) ( fat_writable ) 1 0 }

@ nurl_disk_open s path i flags → i {
    ? ! ( __mount_once ) { ^ - 0 19 } {}  // ENODEV
    ^ ( fatfs_open path flags )
}

@ nurl_disk_read i h s buf i n → i { ^ ( fatfs_read_raw h buf n ) }

@ nurl_disk_write i h s buf i n → i { ^ ( fatfs_write_raw h buf n ) }

@ nurl_disk_lseek i h i off i whence → i { ^ ( fatfs_seek h off whence ) }

@ nurl_disk_close i h → i { ^ ( fatfs_close h ) }

@ nurl_disk_size i h → i { ^ ( fatfs_size h ) }

@ nurl_disk_fsync i h → i { ^ ( fatfs_fsync h ) }

@ nurl_disk_sync → i {
    ? != g_state 1 { ^ 0 } {}
    ^ ( fatfs_sync )
}

@ nurl_disk_exists s path → i {
    ? ! ( __mount_once ) { ^ 0 } {}
    ^ ? ( fatfs_exists path ) 1 0
}

@ nurl_disk_is_dir s path → i {
    ? ! ( __mount_once ) { ^ 0 } {}
    ^ ? ( fatfs_is_dir path ) 1 0
}

@ nurl_disk_stat_size s path → i {
    ? ! ( __mount_once ) { ^ - 0 19 } {}
    ^ ( fatfs_stat_size path )
}

@ nurl_disk_unlink s path → i {
    ? ! ( __mount_once ) { ^ - 0 19 } {}
    ^ ( fatfs_unlink path )
}

@ nurl_disk_rename s a s b → i {
    ? ! ( __mount_once ) { ^ - 0 19 } {}
    ^ ( fatfs_rename a b )
}

@ nurl_disk_mkdir s path → i {
    ? ! ( __mount_once ) { ^ - 0 19 } {}
    ^ ( fatfs_mkdir path )
}

@ nurl_disk_rmdir s path → i {
    ? ! ( __mount_once ) { ^ - 0 19 } {}
    ^ ( fatfs_rmdir path )
}

@ nurl_disk_truncate s path i len → i {
    ? ! ( __mount_once ) { ^ - 0 19 } {}
    ^ ( fatfs_truncate path len )
}

// ── directory reading ───────────────────────────────────────────────
//
// `getdents64` in the guest is built out of these two: a handle opened
// on a directory, then one name at a time. The name is copied into the
// caller's buffer rather than returned as a string, because the caller
// is C and an owned `s` crossing that boundary is a leak nobody frees.

@ nurl_disk_opendir s path → i {
    ? ! ( __mount_once ) { ^ - 0 19 } {}
    : i h ( fatfs_open path 0 )
    ? < h 0 { ^ h } {}
    ? ! ( fatfs_is_dir_handle h ) {
        : i _c ( fatfs_close h )
        ^ - 0 20  // ENOTDIR
    } {}
    ^ h
}

// The next entry's name into `buf` (at most `cap` bytes including the
// terminator). Returns the name's length, 0 at the end of the
// directory, and -1 when the name did not fit — which is a refusal, not
// a truncated name a caller would then look up and fail to find.
@ nurl_disk_readdir_name i h s buf i cap → i {
    : String nm ( string_new )
    : i attr ( fatfs_readdir_attr h nm )
    ? < attr 0 { ( string_free nm ) ^ 0 } {}
    : i n ( string_len nm )
    ? >= n cap { ( string_free nm ) ^ - 0 1 } {}
    ( nurl_memcpy buf ( string_data nm ) n )
    ( nurl_memset # s + # i buf n 0 1 )
    = g_last_attr attr
    ( string_free nm )
    ^ n
}

@ nurl_disk_dirent_is_dir → i { ^ ? != 0 & g_last_attr ( fat_attr_dir ) 1 0 }

@ nurl_disk_closedir i h → i { ^ ( fatfs_close h ) }
