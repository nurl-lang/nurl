// stdlib/fs/fatfmt.nu — make a FAT filesystem on the attached block
// device. `mkfs.vfat`, for a machine that has no host to run it on.
//
// WHY THIS EXISTS. A unikernel handed a blank disk has no shell, no
// package manager and no second machine: either it can format the disk
// itself or the disk is useless until somebody else prepares it. The
// same code formats an image on a host, which is how a guest's disk
// gets built — by the writer that will later read it.
//
// THE TYPE IS CHOSEN BY SIZE, and the choice is the format's, not a
// preference: FAT16 holds 4085..65524 clusters and FAT32 holds 65525
// and up, so a disk small enough to fall below FAT16's floor at every
// legal cluster size cannot hold a filesystem this code will write. It
// says so rather than writing a FAT12 volume nobody asked for.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/hal/blockdev.nu`
$ `stdlib/fs/fat.nu`

@ fatfmt_min_sectors → i { ^ 64 }

// A sector's worth of zeros, reused.
@ __zsec → ( Vec u ) {
    : ( Vec u ) z ( vec_with_cap [u] ( blk_sector_size ) )
    : ~ i k 0
    ~ < k ( blk_sector_size ) { ( vec_push [u] z # u 0 ) = k + k 1 }
    ^ z
}

@ __put8 ( Vec u ) b i off i val → v { : b _s ( vec_set [u] b off # u & val 255 ) }

@ __put16 ( Vec u ) b i off i val → v {
    ( __put8 b off & val 255 )
    ( __put8 b + off 1 & >> val 8 255 )
}

@ __put32 ( Vec u ) b i off i val → v {
    ( __put16 b off & val 65535 )
    ( __put16 b + off 2 & >> val 16 65535 )
}

@ __puts ( Vec u ) b i off s text i n → v {
    : i len ( nurl_str_len text )
    : ~ i k 0
    ~ < k n {
        ( __put8 b + off k ? < k len ( nurl_str_get text k ) 32 )
        = k + k 1
    }
}

// How many sectors one FAT needs, given a cluster size.
//
// The answer feeds back into itself — a bigger FAT leaves fewer data
// sectors, which need fewer FAT entries — and the fixed point does NOT
// generally exist: on a 64 MiB disk the recurrence OSCILLATES between
// 1008 and 1009 for ever, because 1008 sectors of FAT leave room for
// clusters that need 1009 and 1009 leave room for clusters that need
// 1008. A loop looking for `need == fat_secs` runs out of iterations
// and returns whichever it happened to stop on; when that was the
// smaller one the FAT was one entry short of the clusters the volume
// claimed, which is a volume every checker calls corrupt and which
// this repository's own mount refused — correctly, and only because
// the check existed.
//
// So the criterion is SAFETY, not equality: grow until the FAT covers
// the clusters, then shrink while it still does. The result is the
// smallest safe size, which is what `mkfs.vfat` picks too.
@ __solve_fat_secs i total i rsvd i nfats i root_secs i spc i entry_bytes → i {
    : ~ i fat_secs 1
    : ~ i k 0
    : ~ b safe F
    ~ && < k 32 ! safe {
        : i need ( __fat_need total rsvd nfats root_secs spc entry_bytes fat_secs )
        ? < need 0 { ^ 0 } {}
        ? <= need fat_secs { = safe T } { = fat_secs need }
        = k + k 1
    }
    ? ! safe { ^ 0 } {}
    : ~ i shrink 0
    ~ && > fat_secs 1 < shrink 65536 {
        : i try - fat_secs 1
        : i need ( __fat_need total rsvd nfats root_secs spc entry_bytes try )
        ? || < need 0 > need try { = shrink 65536 } { = fat_secs try = shrink + shrink 1 }
    }
    ^ fat_secs
}

// How many FAT sectors the clusters would need if the FAT were
// `fat_secs` sectors long. -1 when a FAT that size leaves no data.
@ __fat_need i total i rsvd i nfats i root_secs i spc i entry_bytes i fat_secs → i {
    : i data - - - total rsvd root_secs * nfats fat_secs
    ? <= data 0 { ^ - 0 1 } {}
    : i nclus / data spc
    ^ / + * + nclus 2 entry_bytes - ( blk_sector_size ) 1 ( blk_sector_size )
}

@ __clusters_for i total i rsvd i nfats i root_secs i spc i fat_secs → i {
    : i data - - - total rsvd root_secs * nfats fat_secs
    ? <= data 0 { ^ 0 } {}
    ^ / data spc
}

// Format the attached device. `label` may be empty. Returns T on
// success; the device is left with a filesystem a checker calls clean,
// or untouched enough that the caller knows it failed.
//
// The volume is NOT mounted afterwards: formatting and mounting are two
// decisions, and a formatter that mounted its result would hide a
// mount failure behind a format success.
@ fat_format s label → b {
    : i total ( blk_sector_count )
    ? < total ( fatfmt_min_sectors ) { ^ F } {}

    : ~ i ftype 0
    : ~ i spc 0
    : ~ i rsvd 0
    : ~ i root_ents 0
    : ~ i root_secs 0
    : ~ i fat_secs 0
    : i nfats 2

    // FAT32 first: it is what any disk big enough should get, because
    // FAT16's 64 K clusters put a 2 GiB ceiling on the volume and a
    // 32 KiB floor under every file.
    : ~ i try_spc 1
    ~ && == ftype 0 <= try_spc 128 {
        : i fs ( __solve_fat_secs total 32 nfats 0 try_spc 4 )
        ? > fs 0 {
            : i nc ( __clusters_for total 32 nfats 0 try_spc fs )
            ? && >= nc 65525 < nc 268435445 {
                = ftype 32
                = spc try_spc
                = rsvd 32
                = fat_secs fs
            } {}
        } {}
        = try_spc * try_spc 2
    }

    ? == ftype 0 {
        // FAT16, with the classic 512-entry fixed root.
        : i re 512
        : i rs / * re ( fat_ent_size ) ( blk_sector_size )
        = try_spc 1
        ~ && == ftype 0 <= try_spc 64 {
            : i fs ( __solve_fat_secs total 1 nfats rs try_spc 2 )
            ? > fs 0 {
                : i nc ( __clusters_for total 1 nfats rs try_spc fs )
                ? && >= nc 4085 < nc 65525 {
                    = ftype 16
                    = spc try_spc
                    = rsvd 1
                    = root_ents re
                    = root_secs rs
                    = fat_secs fs
                } {}
            } {}
            = try_spc * try_spc 2
        }
    } {}

    ? == ftype 0 { ^ F } {}

    : i nclus ( __clusters_for total rsvd nfats root_secs spc fat_secs )
    : i fat_start rsvd
    : i data_start + + rsvd * nfats fat_secs root_secs

    // ── the boot sector ──
    : ( Vec u ) bs ( __zsec )
    ( __put8 bs 0 235 )  // jmp short
    ( __put8 bs 1 ? == ftype 32 88 60 )
    ( __put8 bs 2 144 )  // nop
    ( __puts bs 3 `NURLFAT` 8 )
    ( __put16 bs 11 ( blk_sector_size ) )
    ( __put8 bs 13 spc )
    ( __put16 bs 14 rsvd )
    ( __put8 bs 16 nfats )
    ( __put16 bs 17 root_ents )
    ( __put16 bs 19 ? > total 65535 0 total )
    ( __put8 bs 21 248 )  // fixed disk
    ( __put16 bs 22 ? == ftype 16 fat_secs 0 )
    ( __put16 bs 24 63 )  // sectors per track
    ( __put16 bs 26 255 )  // heads
    ( __put32 bs 28 0 )  // hidden sectors
    ( __put32 bs 32 ? > total 65535 total 0 )
    // A volume id nobody will mistake for a serial number: derived from
    // the geometry, so formatting the same disk twice gives the same
    // number and a diff of two images is empty rather than noisy.
    : i volid & ^^ * total 2654435761 << nclus 3 4294967295
    ? == ftype 32 {
        ( __put32 bs 36 fat_secs )
        ( __put16 bs 40 0 )  // ext flags: mirror all FATs
        ( __put16 bs 42 0 )  // version
        ( __put32 bs 44 2 )  // root cluster
        ( __put16 bs 48 1 )  // FSInfo sector
        ( __put16 bs 50 6 )  // backup boot sector
        ( __put8 bs 64 128 )
        ( __put8 bs 66 41 )
        ( __put32 bs 67 volid )
        ( __puts bs 71 label 11 )
        ( __puts bs 82 `FAT32` 8 )
    } {
        ( __put8 bs 36 128 )
        ( __put8 bs 38 41 )
        ( __put32 bs 39 volid )
        ( __puts bs 43 label 11 )
        ( __puts bs 54 `FAT16` 8 )
    }
    ( __put16 bs 510 43605 )

    : ~ b ok ( blk_write bs 0 0 1 )

    // ── FSInfo, and the backup pair ──
    ? && ok == ftype 32 {
        : ( Vec u ) fsi ( __zsec )
        ( __put32 fsi 0 1096897106 )  // "RRaA"
        ( __put32 fsi 484 1631679090 )  // "rrAa"
        ( __put32 fsi 488 - nclus 1 )  // free clusters
        ( __put32 fsi 492 3 )  // next free hint
        ( __put16 fsi 510 43605 )
        = ok ( blk_write fsi 0 1 1 )
        ? ok { = ok ( blk_write bs 0 6 1 ) } {}
        ? ok { = ok ( blk_write fsi 0 7 1 ) } {}
        ( vec_free [u] fsi )
    } {}
    ( vec_free [u] bs )
    ? ! ok { ^ F } {}

    // ── the FATs ──
    //
    // Zeroed in full: a FAT with the previous filesystem's entries in
    // it is a volume whose every file is already allocated.
    : ( Vec u ) z ( __zsec )
    : ~ i k 0
    ~ && < k * nfats fat_secs ok {
        = ok ( blk_write z 0 + fat_start k 1 )
        = k + k 1
    }
    // The fixed root region, for FAT16.
    = k 0
    ~ && < k root_secs ok {
        = ok ( blk_write z 0 + + rsvd * nfats fat_secs k 1 )
        = k + k 1
    }
    ( vec_free [u] z )
    ? ! ok { ^ F } {}

    // ── entries 0 and 1, and the root chain ──
    //
    // Entry 0 is the media byte with the rest of its bits set; entry 1
    // is an end-of-chain whose top two bits are the "clean" and "no I/O
    // error" flags a checker reads. Writing them by hand here rather
    // than mounting first is what keeps the formatter independent of
    // the mount path it is about to make possible.
    : ( Vec u ) f0 ( __zsec )
    ? == ftype 32 {
        ( __put32 f0 0 268435448 )  // 0x0FFFFFF8
        ( __put32 f0 4 268435455 )
        ( __put32 f0 8 268435455 )  // cluster 2 = root, EOC
    } {
        ( __put16 f0 0 65528 )
        ( __put16 f0 2 65535 )
    }
    = k 0
    ~ && < k nfats ok {
        = ok ( blk_write f0 0 + fat_start * k fat_secs 1 )
        = k + k 1
    }
    ( vec_free [u] f0 )
    ? ! ok { ^ F } {}

    // The FAT32 root directory is a cluster and must be empty, which
    // means zeroed: an unzeroed one is a directory full of whatever the
    // disk held before.
    ? == ftype 32 {
        : ( Vec u ) z2 ( __zsec )
        = k 0
        ~ && < k spc ok {
            = ok ( blk_write z2 0 + data_start k 1 )
            = k + k 1
        }
        ( vec_free [u] z2 )
    } {}
    ? ! ok { ^ F } {}

    // THE LABEL LIVES TWICE. The boot sector's copy is the one a human
    // reads out of a hexdump; the one that counts is a directory entry
    // in the root with the volume-id attribute, and a volume with only
    // the first is one `fsck.vfat` offers to repair by deleting the
    // label it did find. Writing both is what makes the filesystem
    // agree with itself.
    ? > ( nurl_str_len label ) 0 {
        : ( Vec u ) rootsec ( __zsec )
        : ~ i j 0
        ~ < j 11 {
            : i c ? < j ( nurl_str_len label ) ( nurl_str_get label j ) 32
            ( __put8 rootsec j ? && >= c 97 <= c 122 - c 32 c )
            = j + j 1
        }
        ( __put8 rootsec 11 8 )  // ATTR_VOLUME_ID
        ( __put16 rootsec 22 0 )  // 1980-01-01
        ( __put16 rootsec 24 33 )
        : i root_lba ? == ftype 32 data_start + rsvd * nfats fat_secs
        = ok ( blk_write rootsec 0 root_lba 1 )
        ( vec_free [u] rootsec )
    } {}
    ? ! ok { ^ F } {}
    ^ ( blk_flush )
}
