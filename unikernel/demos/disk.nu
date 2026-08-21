// unikernel/demos/disk.nu — the guest writes to a real disk, and says
// what it found there.
//
// This is the gate for the whole block stack: virtio-blk (the driver),
// FAT (the format), the VFS in `boot/vfs.c` (the dispatch) and the
// ordinary `std/fs.nu` calls a program already makes. NOTHING in the
// body below is disk-aware — `write_file`, `read_file`, `file_exists`
// and `dir_list` are the same functions a hosted program calls, which
// is the entire claim being tested.
//
// It is run TWICE against the same disk image by
// `unikernel/tests/disk_gate.sh`: the first boot finds an empty
// filesystem and writes; the second finds the first boot's files. A
// filesystem that only worked while the machine that wrote it was
// still running would pass a one-boot test.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`

@ say s m → v { ( nurl_print m ) ( nurl_print `\n` ) }

@ kv s k s v → v {
    ( nurl_print k )
    ( nurl_print `=` )
    ( nurl_print v )
    ( nurl_print `\n` )
}

@ kvn s k i n → v {
    ( nurl_print k )
    ( nurl_print `=` )
    ( nurl_print_int n )
    ( nurl_print `\n` )
}

@ counter_path → s { ^ `/boots.txt` }

// How many times this image has booted against this disk, read out of
// the disk itself. The point of the demo in one number: it can only be
// right if a write from a previous boot survived a power cycle.
@ read_boots → i {
    ? ! ( file_exists ( counter_path ) ) { ^ 0 } {}
    ?? ( read_file ( counter_path ) ) {
        T txt → {
            : i n ?? ( string_to_int txt ) { T v → v F _ → 0 }
            ( string_free txt )
            ^ n
        }
        F _ → 0
    }
}

@ main → i {
    : i boots ( read_boots )
    ( kvn `boots_before` boots )

    : String next ( string_new )
    ( string_push_int next + boots 1 )
    ?? ( write_file ( counter_path ) ( string_data next ) ) {
        T _ → ( say `counter written: yes` )
        F _ → ( say `counter written: no` )
    }
    ( string_free next )

    // A long name with two dots — the case an 8.3-only filesystem
    // mangles and this one stores whole.
    ?? ( write_file `/data.lsm.wal` `record-0001\n` ) {
        T _ → ( say `long name written: yes` )
        F _ → ( say `long name written: no` )
    }
    ( kv `long name reads` ?? ( read_file `/data.lsm.wal` ) {
        T t → { : s d ( string_data t ) ( nurl_print d ) ( nurl_print `` ) `ok` }
        F _ → `FAILED`
    } )

    // A subdirectory, and a file inside it.
    ?? ( dir_create `/var` ) { T _ → {} F _ → {} }
    ?? ( write_file `/var/state.json` `{"up":true}` ) {
        T _ → ( say `nested write: yes` )
        F _ → ( say `nested write: no` )
    }

    // Something big enough to cross clusters and the sector cache.
    : String big ( string_new )
    : ~ i k 0
    ~ < k 8192 { ( string_push_char big + 97 % k 26 ) = k + k 1 }
    ?? ( write_file `/big.txt` ( string_data big ) ) {
        T _ → ( say `big write: yes` )
        F _ → ( say `big write: no` )
    }
    ( string_free big )
    ( kvn `big size` ?? ( file_size `/big.txt` ) { T n → n F _ → - 0 1 } )

    // The directory, as any program would list it — opendir/readdir,
    // through the guest's own getdents64.
    ?? ( dir_list `/` ) {
        T names → {
            ( kvn `root entries` ( vec_len [String] names ) )
            : ~ i j 0
            ~ < j ( vec_len [String] names ) {
                ?? ( vec_get [String] names j ) {
                    T nm → { ( nurl_print `ent: ` ) ( nurl_print ( string_data nm ) ) ( nurl_print `\n` ) }
                    F → {}
                }
                = j + j 1
            }
            ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
        }
        F _ → ( say `root entries=FAILED` )
    }

    // Durability, said out loud: everything above is on the medium when
    // this returns. The ordinary handle API — open, sync, close — with
    // nothing disk-specific about it.
    ?? ( file_append ( counter_path ) ) {
        T f → {
            ?? ( file_sync f ) {
                T _ → ( say `synced: yes` )
                F _ → ( say `synced: no` )
            }
            ( file_close f )
        }
        F _ → ( say `synced: no` )
    }
    ( say `disk demo done` )
    ^ 0
}
