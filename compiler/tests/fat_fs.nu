// Test: the FAT filesystem — stdlib/fs/fat.nu (the format),
// stdlib/fs/fatfs.nu (files and directories) and stdlib/fs/fatfmt.nu
// (making one), driven over stdlib/fs/blkdev_file.nu.
//
// The volume this exercises is built and read entirely by this
// repository's own code, which is exactly why it is not the whole
// story: `unikernel/tests/disk_gate.sh` runs the same operations
// against volumes `mkfs.vfat` built and hands the result to
// `fsck.vfat`, so the on-disk format is checked by a program that has
// never seen this one. What lives here is the behaviour a golden can
// pin — sizes, contents, error numbers, and what survives a remount.
//
// Both layouts are covered, because they are two different filesystems
// wearing one name: FAT16 has a fixed root directory that cannot grow
// and 16-bit table entries, FAT32 has a root that is an ordinary
// cluster chain and 32-bit ones. A bug in either is invisible from the
// other.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/hal/blockdev.nu`
$ `stdlib/fs/blkdev_file.nu`
$ `stdlib/fs/fat.nu`
$ `stdlib/fs/fatfs.nu`
$ `stdlib/fs/fatfmt.nu`

@ ck b ok s name → v {
    ( nurl_print name )
    ( nurl_print ? ok `: YES\n` `: NO\n` )
}

@ ckn i got i want s name → v {
    ( nurl_print name )
    ( nurl_print ? == got want `: YES\n` `: NO (` )
    ? != got want {
        ( nurl_print_int got )
        ( nurl_print ` want ` )
        ( nurl_print_int want )
        ( nurl_print `)\n` )
    } {}
}

@ __tmpdir → String {
    : ~ String tdir ( env_var_or `TMPDIR` `` )
    ? == ( string_len tdir ) 0 {
        ( string_free tdir )
        = tdir ( env_var_or `TEMP` `/tmp` )
    } {}
    ^ tdir
}

@ img_path s tag → String {
    : String p ( __tmpdir )
    ( string_push_str p `/nurl_fat_` )
    ( string_push_str p tag )
    ( string_push_str p `.img` )
    ^ p
}

// ── helpers ─────────────────────────────────────────────────────────

@ put s path s text → i {
    : i h ( fatfs_open path | | ( fo_rdwr ) ( fo_creat ) ( fo_trunc ) )
    ? < h 0 { ^ h } {}
    : i n ( fatfs_write_raw h text ( nurl_str_len text ) )
    : i c ( fatfs_close h )
    ^ ? < n 0 n c
}

@ get s path String out → i {
    : i h ( fatfs_open path 0 )
    ? < h 0 { ^ h } {}
    : i sz ( fatfs_size h )
    : ( Vec u ) buf ( vec_new [u] )
    : i got ( fatfs_read h buf sz )
    : ~ i k 0
    ~ < k ( vec_len [u] buf ) {
        ( string_push_char out # i ?? ( vec_get [u] buf k ) { T x → x F → # u 0 } )
        = k + k 1
    }
    ( vec_free [u] buf )
    : i c ( fatfs_close h )
    ^ ? < got 0 got got
}

@ text_is s path s want → b {
    : String got ( string_new )
    : i rc ( get path got )
    : b same && >= rc 0 ( string_eq got ( string_from want ) )
    ( string_free got )
    ^ same
}

// A byte pattern that catches an off-by-one anywhere in the chain
// walk: every byte is a function of its own offset, so a block read
// from the wrong cluster is wrong in a way a comparison sees.
@ pattern_byte i k → i { ^ & ^^ * k 7 >> k 8 255 }

@ write_pattern s path i n → i {
    : i h ( fatfs_open path | | ( fo_rdwr ) ( fo_creat ) ( fo_trunc ) )
    ? < h 0 { ^ h } {}
    : ( Vec u ) chunk ( vec_new [u] )
    : ~ i k 0
    ~ < k n { ( vec_push [u] chunk # u ( pattern_byte k ) ) = k + k 1 }
    : i wrote ( fatfs_write h chunk 0 n )
    ( vec_free [u] chunk )
    : i s ( fatfs_fsync h )
    : i c ( fatfs_close h )
    ^ ? < wrote 0 wrote wrote
}

@ check_pattern s path i n → b {
    : i h ( fatfs_open path 0 )
    ? < h 0 { ^ F } {}
    : ( Vec u ) buf ( vec_new [u] )
    : i got ( fatfs_read h buf n )
    : ~ b same == got n
    : ~ i k 0
    ~ && < k n same {
        : i b # i ?? ( vec_get [u] buf k ) { T x → x F → # u 0 }
        ? != b ( pattern_byte k ) { = same F } {}
        = k + k 1
    }
    ( vec_free [u] buf )
    : i c ( fatfs_close h )
    ^ same
}

// ── the body, run once per layout ───────────────────────────────────

@ run_layout s tag i sectors i want_type → v {
    ( nurl_print `--- ` )
    ( nurl_print tag )
    ( nurl_print ` ---\n` )
    : String path ( img_path tag )
    : s p ( string_data path )

    ( ck ( blkfile_create p sectors ) `device created` )
    ( ck ( fat_format `NURLTEST` ) `formatted` )
    ( ck ( fat_mount T ) `mounted` )
    ( ckn ( fat_type ) want_type `FAT type` )
    : i free0 ( fat_free_clusters )
    ( ck > free0 0 `free clusters counted` )

    // ── names ──
    ( ckn ( put `/hello.txt` `hello` ) 0 `8.3 name written` )
    ( ck ( text_is `/hello.txt` `hello` ) `8.3 name read back` )
    // Two dots is not an 8.3 name; it needs the long-name entries.
    ( ckn ( put `/data.lsm.wal` `record` ) 0 `long name written` )
    ( ck ( text_is `/data.lsm.wal` `record` ) `long name read back` )
    // FAT is case-insensitive and case-PRESERVING: one file, and the
    // spelling that comes back is the one that went in.
    ( ck ( text_is `/DATA.LSM.WAL` `record` ) `lookup is case-insensitive` )
    ( ckn ( put `/MixedCase.Txt` `mc` ) 0 `mixed-case name written` )
    ( ck ( text_is `/mixedcase.txt` `mc` ) `mixed-case found by lower` )

    // ── directories ──
    ( ckn ( fatfs_mkdir `/var` ) 0 `mkdir` )
    ( ckn ( fatfs_mkdir `/var/log` ) 0 `mkdir nested` )
    ( ck ( fatfs_is_dir `/var/log` ) `nested dir is a dir` )
    ( ckn ( fatfs_mkdir `/var` ) ( fe_exist ) `mkdir on an existing name` )
    ( ckn ( put `/var/log/boot.log` `up` ) 0 `file in a nested dir` )
    ( ck ( text_is `/var/log/boot.log` `up` ) `nested file read back` )
    ( ckn ( fatfs_rmdir `/var` ) ( fe_notempty ) `rmdir refuses a full dir` )
    ( ckn ( put `/var/log/boot.log/x` `x` ) ( fe_notdir ) `a file is not a directory` )

    // ── a file bigger than a cluster and than the cache ──
    ( ckn ( write_pattern `/big.bin` 131072 ) 131072 `128 KiB written` )
    ( ck ( check_pattern `/big.bin` 131072 ) `128 KiB reads back byte for byte` )
    ( ckn ( fatfs_stat_size `/big.bin` ) 131072 `size on the medium` )

    // ── seek, append, partial reads ──
    : i h ( fatfs_open `/big.bin` 0 )
    ( ckn ( fatfs_seek h 65536 0 ) 65536 `seek to the middle` )
    : ( Vec u ) mid ( vec_new [u] )
    ( ckn ( fatfs_read h mid 4 ) 4 `short read at an offset` )
    ( ck == # i ?? ( vec_get [u] mid 0 ) { T x → x F → # u 0 } ( pattern_byte 65536 ) `the offset's own byte` )
    ( vec_free [u] mid )
    ( ckn ( fatfs_seek h 0 2 ) 131072 `seek to the end` )
    : i _c ( fatfs_close h )

    : i ah ( fatfs_open `/hello.txt` | ( fo_rdwr ) ( fo_append ) )
    ( ckn ( fatfs_write_raw ah ` world` 6 ) 6 `append wrote` )
    : i _a ( fatfs_close ah )
    ( ck ( text_is `/hello.txt` `hello world` ) `append landed at the end` )

    // ── truncate, both directions ──
    ( ckn ( fatfs_truncate `/hello.txt` 5 ) 0 `truncate down` )
    ( ck ( text_is `/hello.txt` `hello` ) `truncated content` )
    ( ckn ( fatfs_truncate `/big.bin` 4096 ) 0 `truncate a big file down` )
    ( ckn ( fatfs_stat_size `/big.bin` ) 4096 `shrunk size` )
    ( ck ( check_pattern `/big.bin` 4096 ) `what is left is still right` )

    // ── rename ──
    ( ckn ( fatfs_rename `/hello.txt` `/greeting.txt` ) 0 `rename` )
    ( ck ! ( fatfs_exists `/hello.txt` ) `old name gone` )
    ( ck ( text_is `/greeting.txt` `hello` ) `new name has the content` )
    ( ckn ( put `/victim.txt` `doomed` ) 0 `a file to replace` )
    ( ckn ( fatfs_rename `/greeting.txt` `/victim.txt` ) 0 `rename over a file` )
    ( ck ( text_is `/victim.txt` `hello` ) `replacement content` )
    ( ckn ( fatfs_rename `/nope.txt` `/x.txt` ) ( fe_noent ) `rename of a missing file` )
    ( ckn ( fatfs_rename `/var` `/victim.txt` ) ( fe_notdir ) `dir cannot replace a file` )

    // ── errors ──
    ( ckn ( fatfs_open `/missing.txt` 0 ) ( fe_noent ) `open of a missing file` )
    ( ckn ( fatfs_open `/victim.txt` | | ( fo_rdwr ) ( fo_creat ) ( fo_excl ) ) ( fe_exist ) `O_EXCL on an existing file` )
    ( ckn ( fatfs_open `/var` ( fo_rdwr ) ) ( fe_isdir ) `opening a directory to write` )
    ( ckn ( fatfs_unlink `/var` ) ( fe_isdir ) `unlink refuses a directory` )
    ( ckn ( fatfs_truncate `/missing.txt` 0 ) ( fe_noent ) `truncate of a missing file` )

    // ── a directory with more entries than one cluster holds ──
    : ~ i made 0
    : ~ i k 0
    ~ < k 120 {
        : String nm ( string_from `/var/log/entry-` )
        ( string_push_int nm k )
        ( string_push_str nm `.txt` )
        ? == ( put ( string_data nm ) `e` ) 0 { = made + made 1 } {}
        ( string_free nm )
        = k + k 1
    }
    ( ckn made 120 `120 long-named entries created` )
    : i dh ( fatfs_open `/var/log` 0 )
    ( ck >= dh 0 `directory opened` )
    : ~ i seen 0
    : ~ b more T
    ~ more {
        : String nm ( string_new )
        = more ( fatfs_readdir dh nm )
        ? more {
            // "." and ".." are entries too, and a readdir that hid them
            // would be hiding the two the format guarantees.
            ? ! ( string_eq nm ( string_from `.` ) ) {
                ? ! ( string_eq nm ( string_from `..` ) ) { = seen + seen 1 } {}
            } {}
        } {}
        ( string_free nm )
    }
    : i _dc ( fatfs_close dh )
    ( ckn seen 121 `readdir sees every one of them` )

    // ── it survives a remount ──
    ( ckn ( fatfs_sync ) 0 `sync` )
    ( fat_unmount )
    ( ck ! ( fat_mounted ) `unmounted` )
    ( ck ( fat_mount T ) `re-mounted` )
    ( ck ( text_is `/victim.txt` `hello` ) `content survived the remount` )
    ( ck ( check_pattern `/big.bin` 4096 ) `the big file survived too` )
    ( ck ( fatfs_is_dir `/var/log` ) `directories survived` )

    // ── read-only means read-only ──
    ( fat_unmount )
    ( ck ( fat_mount F ) `mounted read-only` )
    ( ck ( text_is `/victim.txt` `hello` ) `read-only still reads` )
    ( ckn ( put `/nope.txt` `x` ) ( fe_rofs ) `read-only refuses a create` )
    ( ckn ( fatfs_unlink `/victim.txt` ) ( fe_rofs ) `read-only refuses an unlink` )
    ( fat_unmount )

    // ── deleting everything gives the clusters back ──
    ( ck ( fat_mount T ) `mounted again` )
    ( ckn ( fatfs_unlink `/big.bin` ) 0 `unlink the big file` )
    ( ckn ( fatfs_unlink `/victim.txt` ) 0 `unlink the small one` )
    ( ckn ( fatfs_unlink `/data.lsm.wal` ) 0 `unlink the long name` )
    ( ckn ( fatfs_unlink `/MixedCase.Txt` ) 0 `unlink the mixed-case name` )
    = k 0
    : ~ i gone 0
    ~ < k 120 {
        : String nm ( string_from `/var/log/entry-` )
        ( string_push_int nm k )
        ( string_push_str nm `.txt` )
        ? == ( fatfs_unlink ( string_data nm ) ) 0 { = gone + gone 1 } {}
        ( string_free nm )
        = k + k 1
    }
    ( ckn gone 120 `bulk unlink` )
    ( ckn ( fatfs_unlink `/var/log/boot.log` ) 0 `unlink the nested file` )
    ( ckn ( fatfs_rmdir `/var/log` ) 0 `rmdir the empty dir` )
    ( ckn ( fatfs_rmdir `/var` ) 0 `rmdir its parent` )
    : i free1 ( fat_free_clusters )
    ( ck == free1 free0 `every cluster came back` )
    ( fat_unmount )
    ( blkfile_close )
    ( string_free path )
}

@ main → i {
    // 8 MiB lands in FAT16's cluster range, 40 MiB in FAT32's. The
    // formatter picks by count, so these two numbers ARE the coverage.
    ( run_layout `f16` 16384 16 )
    ( run_layout `f32` 81920 32 )
    ( nurl_print `done\n` )
    ^ 0
}
