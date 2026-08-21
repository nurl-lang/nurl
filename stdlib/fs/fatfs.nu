// stdlib/fs/fatfs.nu — files and directories on a FAT volume: the
// POSIX-shaped half of the filesystem, sitting on the format half in
// `stdlib/fs/fat.nu`.
//
// The surface is deliberately the one a C library calls — open/read/
// write/lseek/close plus unlink, rename, mkdir and readdir — because
// the point of a disk in the unikernel is that programs which already
// read and write files keep working. Nothing above this file should
// need to know it is talking to FAT.
//
// NAMES. Long names are read AND written (the VFAT extension), so
// `data.lsm.wal` is a name this filesystem can hold rather than one it
// mangles. Comparison is case-insensitive, which is FAT's rule and not
// a shortcut: `README` and `readme` are one file here, and a program
// that relies on them being two is a program this filesystem cannot
// host. Names are UTF-8 on the way in and out, stored as UCS-2; a code
// point outside the basic multilingual plane is REFUSED at create
// rather than silently written as a pair of replacement characters.
//
// ERRORS are negative errno values, the Linux numbers, because the C
// side that calls these turns them straight into `errno`.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/hal/blockdev.nu`
$ `stdlib/fs/fat.nu`

@ fe_noent → i { ^ - 0 2 }

@ fe_io → i { ^ - 0 5 }

@ fe_badf → i { ^ - 0 9 }

@ fe_exist → i { ^ - 0 17 }

@ fe_notdir → i { ^ - 0 20 }

@ fe_isdir → i { ^ - 0 21 }

@ fe_inval → i { ^ - 0 22 }

@ fe_mfile → i { ^ - 0 24 }

@ fe_nospc → i { ^ - 0 28 }

@ fe_rofs → i { ^ - 0 30 }

@ fe_nametoolong → i { ^ - 0 36 }

@ fe_notempty → i { ^ - 0 39 }

// Open flags, the Linux x86 values — the same numbers the C side hands
// down, so there is no translation table to get wrong.
@ fo_wronly → i { ^ 1 }

@ fo_rdwr → i { ^ 2 }

@ fo_creat → i { ^ 64 }

@ fo_excl → i { ^ 128 }

@ fo_trunc → i { ^ 512 }

@ fo_append → i { ^ 1024 }

@ fatfs_max_open → i { ^ 32 }

@ fat_name_max → i { ^ 255 }

// ── the clock ───────────────────────────────────────────────────────
//
// FAT timestamps are local time with no zone, counted from 1980. A
// machine that does not know the time writes 1980-01-01 rather than
// inventing a plausible date — the same contract `wallclock=` carries
// in the guest, where an unset clock is a stated fact and not a guess.

: ~ i g_fat_epoch 0

@ fatfs_set_time i epoch_secs → v { = g_fat_epoch epoch_secs }

@ fatfs_time → i { ^ g_fat_epoch }

// Epoch seconds → (FAT date << 16) | FAT time. Date: yyyyyyym mmmddddd
// with the year counted from 1980; time: hhhhhmmm mmmsssss with seconds
// in units of two.
@ __fat_stamp → i {
    ? <= g_fat_epoch 315532800 { ^ 2162688 } {}  // 1980-01-01 00:00:00
    : i days / g_fat_epoch 86400
    : i rem % g_fat_epoch 86400
    : i hh / rem 3600
    : i mm / % rem 3600 60
    : i ss % rem 60
    // Civil-from-days, the shift-to-March algorithm: no tables, no
    // leap-year special cases beyond the two divisions.
    : i z + days 719468
    : i era / ? >= z 0 z - z 146096 146097
    : i doe - z * era 146097
    : i yoe / - - doe / doe 1460 + / doe 36524 / doe 146096 365
    : i y + yoe * era 400
    : i doy - doe + - * 365 yoe / yoe 4 / yoe 100
    : i mp / + * 5 doy 2 153
    : i d + - doy / + * 153 mp 2 5 1
    : i m ? < mp 10 + mp 3 - mp 9
    : i year ? <= m 2 + y 1 y
    : i fy - year 1980
    ? < fy 0 { ^ 2162688 } {}
    ? > fy 127 { ^ 2162688 } {}
    : i date | | << fy 9 << m 5 d
    : i time | | << hh 11 << mm 5 / ss 2
    ^ | << date 16 time
}

// ── the open-file table ─────────────────────────────────────────────

: FatFile {
    b used
    i first  // first cluster, 0 = empty file
    i size
    i pos
    i dlba  // where the short directory entry lives
    i doff
    b writable
    b append
    b isdir
    b meta_dirty  // size / first cluster changed since the entry was written
    i cur_clus  // chain cursor: the cluster at index cur_idx
    i cur_idx
}

: FatTab { ( Vec i ) f }

: ~ i g_ftab 0

@ __tab → *FatTab {
    ? != g_ftab 0 { ^ # *FatTab g_ftab } {}
    : *FatTab t # *FatTab ( nurl_alloc Z FatTab )
    = . t f ( vec_new [i] )
    : ~ i k 0
    ~ < k ( fatfs_max_open ) { ( vec_push [i] . t f 0 ) = k + k 1 }
    = g_ftab # i t
    ^ t
}

@ __file i h → *FatFile {
    ? || < h 0 >= h ( fatfs_max_open ) { ^ # *FatFile 0 } {}
    : *FatTab t ( __tab )
    : i p ?? ( vec_get [i] . t f h ) { T x → x F → 0 }
    ? == p 0 { ^ # *FatFile 0 } {}
    : *FatFile f # *FatFile p
    ? ! . f used { ^ # *FatFile 0 } {}
    ^ f
}

@ __file_slot → i {
    : *FatTab t ( __tab )
    : ~ i k 0
    ~ < k ( fatfs_max_open ) {
        : i p ?? ( vec_get [i] . t f k ) { T x → x F → 0 }
        ? == p 0 {
            : *FatFile nf # *FatFile ( nurl_alloc Z FatFile )
            = . nf used F
            : b _s ( vec_set [i] . t f k # i nf )
            ^ k
        } {}
        : *FatFile f # *FatFile p
        ? ! . f used { ^ k } {}
        = k + k 1
    }
    ^ - 0 1
}

// ── a cursor over a directory ───────────────────────────────────────
//
// A directory is a cluster chain, except the FAT12/16 root, which is a
// fixed run of sectors with no chain at all. `dirclus == 0` means that
// root; every other value is a first cluster. Unifying the two here is
// what keeps the scanning and creation code below free of the special
// case.

: DirPos {
    i dirclus
    i clus
    i lba
    i sec_in_clus
    i left  // fixed root only: sectors remaining
    i eidx  // 0..15 within the sector
    b done
    b fixed
}

@ __dp_new * FatVol v i dirclus → *DirPos {
    : *DirPos p # *DirPos ( nurl_alloc Z DirPos )
    = . p dirclus dirclus
    = . p eidx 0
    = . p sec_in_clus 0
    = . p done F
    ? == dirclus 0 {
        = . p fixed T
        = . p clus 0
        = . p lba . v root_start
        = . p left . v root_secs
        ? == . v root_secs 0 { = . p done T } {}
    } {
        = . p fixed F
        = . p clus dirclus
        = . p left 0
        ? ! ( fat_clus_ok v dirclus ) { = . p done T } { = . p lba ( fat_clus_lba v dirclus ) }
    }
    ^ p
}

@ __dp_free * DirPos p → v { ( nurl_free # s p ) }

@ __dp_lba * DirPos p → i { ^ . p lba }

@ __dp_off * DirPos p → i { ^ * . p eidx ( fat_ent_size ) }

// Move to the next 32-byte entry. Sets `done` at the end of the
// directory; a chain that runs out is the end, and so is a chain whose
// FAT read failed — the caller distinguishes them by asking the volume,
// not by getting a different answer from the cursor.
@ __dp_advance * FatVol v * DirPos p → v {
    ? . p done { ^ } {}
    = . p eidx + . p eidx 1
    ? < . p eidx ( fat_ents_per_sector ) { ^ } {}
    = . p eidx 0
    ? . p fixed {
        = . p left - . p left 1
        ? <= . p left 0 { = . p done T ^ } {}
        = . p lba + . p lba 1
        ^
    } {}
    = . p sec_in_clus + . p sec_in_clus 1
    ? < . p sec_in_clus . v spc { = . p lba + . p lba 1 ^ } {}
    : i nxt ( fat_next_clus v . p clus )
    ? <= nxt 0 { = . p done T ^ } {}
    = . p clus nxt
    = . p sec_in_clus 0
    = . p lba ( fat_clus_lba v nxt )
}

// ── directory entry fields ──────────────────────────────────────────

@ __ent_b * FatVol v * DirPos p i k → i { ^ ( fat_rd8 v ( __dp_lba p ) + ( __dp_off p ) k ) }

@ __ent_attr * FatVol v * DirPos p → i { ^ ( __ent_b v p 11 ) }

@ __ent_first_clus * FatVol v i lba i off → i {
    : i hi ( fat_rd16 v lba + off 20 )
    : i lo ( fat_rd16 v lba + off 26 )
    ? || < hi 0 < lo 0 { ^ - 0 1 } {}
    ^ | << hi 16 lo
}

@ __ent_size * FatVol v i lba i off → i {
    : i a ( fat_rd32 v lba + off 28 )
    ^ ? < a 0 - 0 1 & a 4294967295
}

@ __ent_set_first * FatVol v i lba i off i c → b {
    ? ! ( fat_wr16 v lba + off 20 & >> c 16 65535 ) { ^ F } {}
    ^ ( fat_wr16 v lba + off 26 & c 65535 )
}

@ __ent_set_size * FatVol v i lba i off i n → b { ^ ( fat_wr32 v lba + off 28 n ) }

// The 8.3 name's checksum, which is what ties a run of long-name
// entries to the short entry that follows them. A mismatch means the
// long name belongs to a file that no longer exists — an old name left
// by a writer that did not clean up — and the short name wins.
@ __sfn_checksum * FatVol v i lba i off → i {
    : ~ i sum 0
    : ~ i k 0
    ~ < k 11 {
        : i c ( fat_rd8 v lba + off k )
        ? < c 0 { ^ - 0 1 } {}
        = sum & + | & >> sum 1 127 & << sum 7 255 c 255
        = k + k 1
    }
    ^ sum
}

// ── names ───────────────────────────────────────────────────────────

@ __cb ( Vec u ) v i k → i { ^ # i ?? ( vec_get [u] v k ) { T x → x F → # u 0 } }

@ __upper i c → i { ^ ? && >= c 97 <= c 122 - c 32 c }

@ __is_sfn_char i c → b {
    ? || < c 32 > c 126 { ^ F } {}
    // The characters a short name may not hold (FAT spec §6.1).
    ? == c 34 { ^ F } {}  // "
    ? == c 42 { ^ F } {}  // *
    ? == c 43 { ^ F } {}  // +
    ? == c 44 { ^ F } {}  // ,
    ? == c 47 { ^ F } {}  // /
    ? == c 58 { ^ F } {}  // :
    ? == c 59 { ^ F } {}  // ;
    ? == c 60 { ^ F } {}  // <
    ? == c 61 { ^ F } {}  // =
    ? == c 62 { ^ F } {}  // >
    ? == c 63 { ^ F } {}  // ?
    ? == c 91 { ^ F } {}  // [
    ? == c 92 { ^ F } {}  // backslash
    ? == c 93 { ^ F } {}  // ]
    ? == c 124 { ^ F } {}  // |
    ^ T
}

// A long name may hold everything a short one may not, except these.
@ __is_lfn_char i c → b {
    ? < c 32 { ^ F } {}
    ? == c 34 { ^ F } {}
    ? == c 42 { ^ F } {}
    ? == c 47 { ^ F } {}
    ? == c 58 { ^ F } {}
    ? == c 60 { ^ F } {}
    ? == c 62 { ^ F } {}
    ? == c 63 { ^ F } {}
    ? == c 92 { ^ F } {}
    ? == c 124 { ^ F } {}
    ^ T
}

// UTF-8 → code points, over `name[start .. start+len)`. Returns F on
// malformed input or anything above the basic multilingual plane, which
// UCS-2 cannot hold.
//
// The range is passed rather than a slice on purpose: a slice would be
// a fresh allocation per path component, and an owned `s` built inline
// as a call argument is exactly the temporary this repository has
// leaked before.
@ fat_utf8_to_cps s name i start i len ( Vec i ) out → b {
    : ~ i k 0
    ~ < k len {
        : i c0 & ( nurl_str_get name + start k ) 255
        : ~ i cp 0
        : ~ i n 0
        ? < c0 128 { = cp c0 = n 1 } {
            ? == & c0 224 192 { = cp & c0 31 = n 2 } {
                ? == & c0 240 224 { = cp & c0 15 = n 3 } { ^ F }
            }
        }
        ? > + k n len { ^ F } {}
        : ~ i j 1
        ~ < j n {
            : i cc & ( nurl_str_get name + start + k j ) 255
            ? != & cc 192 128 { ^ F } {}
            = cp | << cp 6 & cc 63
            = j + j 1
        }
        ? == cp 0 { ^ F } {}
        ? && >= cp 55296 <= cp 57343 { ^ F } {}  // surrogates
        ( vec_push [i] out cp )
        = k + k n
    }
    ^ T
}

@ fat_cps_to_utf8 ( Vec i ) cps String out → v {
    : i n ( vec_len [i] cps )
    : ~ i k 0
    ~ < k n {
        : i cp ?? ( vec_get [i] cps k ) { T x → x F → 63 }
        ? < cp 128 {
            ( string_push_char out cp )
        } {
            ? < cp 2048 {
                ( string_push_char out | 192 >> cp 6 )
                ( string_push_char out | 128 & cp 63 )
            } {
                ( string_push_char out | 224 >> cp 12 )
                ( string_push_char out | 128 & >> cp 6 63 )
                ( string_push_char out | 128 & cp 63 )
            }
        }
        = k + k 1
    }
}

// The 8.3 name of a short entry, as code points, with the NT lowercase
// flags honoured — Linux and mkfs.vfat both set them, and ignoring them
// turns every `readme.txt` into `README.TXT` on the way out.
@ __sfn_cps * FatVol v i lba i off ( Vec i ) out → b {
    : i ntflags ( fat_rd8 v lba + off 12 )
    ? < ntflags 0 { ^ F } {}
    : b base_lower != & ntflags 8 0
    : b ext_lower != & ntflags 16 0
    : ~ i k 0
    : ~ i blen 0
    ~ < k 8 {
        : i c ( fat_rd8 v lba + off k )
        ? < c 0 { ^ F } {}
        ? != c 32 { = blen + k 1 } {}
        = k + k 1
    }
    = k 0
    ~ < k blen {
        : ~ i c ( fat_rd8 v lba + off k )
        // 0x05 in the first byte stands for 0xE5, which would otherwise
        // mark the entry deleted.
        ? && == k 0 == c 5 { = c 229 } {}
        ? base_lower { ? && >= c 65 <= c 90 { = c + c 32 } {} } {}
        ( vec_push [i] out c )
        = k + k 1
    }
    : ~ i elen 0
    = k 0
    ~ < k 3 {
        : i c ( fat_rd8 v lba + off + 8 k )
        ? < c 0 { ^ F } {}
        ? != c 32 { = elen + k 1 } {}
        = k + k 1
    }
    ? > elen 0 {
        ( vec_push [i] out 46 )
        = k 0
        ~ < k elen {
            : ~ i c ( fat_rd8 v lba + off + 8 k )
            ? ext_lower { ? && >= c 65 <= c 90 { = c + c 32 } {} } {}
            ( vec_push [i] out c )
            = k + k 1
        }
    } {}
    ^ T
}

// The thirteen UCS-2 characters an LFN entry carries, at their three
// disjoint offsets.
@ __lfn_char * FatVol v i lba i off i j → i {
    : i o ? < j 5 + 1 * j 2 ? < j 11 + 14 * - j 5 2 + 28 * - j 11 2
    ^ ( fat_rd16 v lba + off o )
}

@ __lfn_set_char * FatVol v i lba i off i j i ch → b {
    : i o ? < j 5 + 1 * j 2 ? < j 11 + 14 * - j 5 2 + 28 * - j 11 2
    ^ ( fat_wr16 v lba + off o ch )
}

// ── scanning a directory ────────────────────────────────────────────

// What a scan found: where the short entry is, plus the long-name run
// in front of it (so a deletion can erase all of it).
: FatEnt {
    b found
    i lba
    i off
    i idx  // index of the short entry within the directory
    i first_idx  // index of the first slot (start of the long-name run)
    i nslots  // long-name entries + 1
    i dirclus
    i attr
    i first_clus
    i size
    b err
}

@ __ent_none → FatEnt { ^ @ FatEnt { F 0 0 0 0 0 0 0 0 0 F } }

@ __cps_eq_ci ( Vec i ) a ( Vec i ) b → b {
    : i n ( vec_len [i] a )
    ? != n ( vec_len [i] b ) { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i x ( __upper ?? ( vec_get [i] a k ) { T c → c F → 0 } )
        : i y ( __upper ?? ( vec_get [i] b k ) { T c → c F → 0 } )
        ? != x y { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Find `want` (already decoded to code points) in the directory whose
// first cluster is `dirclus`. One pass, assembling long names as it
// goes.
@ fat_dir_find * FatVol v i dirclus ( Vec i ) want → FatEnt {
    : ~ FatEnt res ( __ent_none )
    : *DirPos p ( __dp_new v dirclus )
    : ~ i lfn_sum - 0 1
    : ~ i lfn_start 0
    : ~ i lfn_n 0
    : ( Vec i ) lfn ( vec_new [i] )
    : ~ i idx 0
    : ~ i guard 0
    : i guard_max 4194304

    = . res dirclus dirclus
    ~ && ! . p done < guard guard_max {
        = guard + guard 1
        : i lba ( __dp_lba p )
        : i off ( __dp_off p )
        : i b0 ( fat_rd8 v lba off )
        ? < b0 0 { = . res err T = . p done T } {
            ? == b0 0 {
                = . p done T
            } {
                ? == b0 229 {
                    = lfn_sum - 0 1
                    = lfn_n 0
                    ( vec_clear [i] lfn )
                    ( __dp_advance v p )
                    = idx + idx 1
                } {
                    : i attr ( __ent_attr v p )
                    ? == & attr 63 ( fat_attr_lfn ) {
                        : i ord & b0 63
                        ? || < ord 1 > ord 20 {
                            = lfn_sum - 0 1
                            = lfn_n 0
                        } {
                            ? != 0 & b0 64 {
                                = lfn_sum ( fat_rd8 v lba + off 13 )
                                = lfn_n ord
                                = lfn_start idx
                                ( vec_clear [i] lfn )
                                : ~ i z 0
                                ~ < z * ord 13 { ( vec_push [i] lfn - 0 1 ) = z + z 1 }
                            } {}
                            ? && > lfn_n 0 <= ord lfn_n {
                                ? == ( fat_rd8 v lba + off 13 ) lfn_sum {
                                    : ~ i j 0
                                    ~ < j 13 {
                                        : i ch ( __lfn_char v lba off j )
                                        : b _s ( vec_set [i] lfn + * - ord 1 13 j ch )
                                        = j + j 1
                                    }
                                } { = lfn_n 0 }
                            } {}
                        }
                        ( __dp_advance v p )
                        = idx + idx 1
                    } {
                        // A short entry. It ends whatever long-name run
                        // preceded it — matching or not.
                        ? == & attr ( fat_attr_volid ) ( fat_attr_volid ) {
                            = lfn_n 0
                            ( __dp_advance v p )
                            = idx + idx 1
                        } {
                            : ( Vec i ) name ( vec_new [i] )
                            : ~ b have_long F
                            ? > lfn_n 0 {
                                : i sum ( __sfn_checksum v lba off )
                                ? == sum lfn_sum {
                                    : ~ i j 0
                                    : i m ( vec_len [i] lfn )
                                    : ~ b bad F
                                    ~ < j m {
                                        : i ch ?? ( vec_get [i] lfn j ) { T x → x F → - 0 1 }
                                        ? || == ch 0 == ch 65535 { = j m } {
                                            ? < ch 0 { = bad T = j m } {
                                                ( vec_push [i] name ch )
                                                = j + j 1
                                            }
                                        }
                                    }
                                    ? ! bad { = have_long T } { ( vec_clear [i] name ) }
                                } {}
                            } {}
                            ? ! have_long {
                                ( vec_clear [i] name )
                                : b _o ( __sfn_cps v lba off name )
                            } {}
                            ? ( __cps_eq_ci name want ) {
                                = . res found T
                                = . res lba lba
                                = . res off off
                                = . res attr attr
                                = . res first_clus ( __ent_first_clus v lba off )
                                = . res size ( __ent_size v lba off )
                                = . res idx idx
                                ? have_long {
                                    = . res first_idx lfn_start
                                    = . res nslots + lfn_n 1
                                } {
                                    = . res first_idx idx
                                    = . res nslots 1
                                }
                                = . p done T
                            } {
                                = lfn_n 0
                                ( __dp_advance v p )
                                = idx + idx 1
                            }
                            ( vec_free [i] name )
                        }
                    }
                }
            }
        }
    }
    ( vec_free [i] lfn )
    ( __dp_free p )
    ^ res
}

// ── path resolution ─────────────────────────────────────────────────

// Split off the next component of `path` starting at `k`; returns the
// index just past it, with the component's code points appended to
// `out`. Repeated and trailing slashes are skipped.
@ __path_next s path i len i k ( Vec i ) out → i {
    : ~ i i0 k
    ~ && < i0 len == & ( nurl_str_get path i0 ) 255 47 { = i0 + i0 1 }
    ? >= i0 len { ^ - 0 1 } {}
    : ~ i i1 i0
    ~ && < i1 len != & ( nurl_str_get path i1 ) 255 47 { = i1 + i1 1 }
    ? ! ( fat_utf8_to_cps path i0 - i1 i0 out ) { ^ - 0 2 } {}
    ^ i1
}

// Resolve everything up to the LAST component: the directory that would
// hold it. `leaf` receives the last component's code points. Returns the
// directory's first cluster, or a negative errno.
@ fat_resolve_parent * FatVol v s path ( Vec i ) leaf → i {
    : i len ( nurl_str_len path )
    : ~ i dir ( fat_root_cluster )
    : ~ i k 0
    ( vec_clear [i] leaf )
    : ( Vec i ) comp ( vec_new [i] )
    : ~ i rc 0
    : ~ b have F
    ~ T {
        ( vec_clear [i] comp )
        : i nk ( __path_next path len k comp )
        ? == nk - 0 2 { = rc ( fe_inval ) = have F ( vec_free [i] comp ) ^ rc } {}
        ? < nk 0 {
            // No more components: whatever `leaf` already holds is the
            // last one. An empty leaf means the path was "/" or "".
            ? ! have { ( vec_free [i] comp ) ^ ( fe_inval ) } {}
            ( vec_free [i] comp )
            ^ dir
        } {}
        ? have {
            // The component we were holding is not the last one after
            // all: it must be a directory, and it becomes the parent.
            : FatEnt e ( fat_dir_find v dir leaf )
            ? . e err { ( vec_free [i] comp ) ^ ( fe_io ) } {}
            ? ! . e found { ( vec_free [i] comp ) ^ ( fe_noent ) } {}
            ? == 0 & . e attr ( fat_attr_dir ) { ( vec_free [i] comp ) ^ ( fe_notdir ) } {}
            // ".." in the root of a FAT32 volume is stored as cluster 0,
            // which means "the root" — not "the fixed root region",
            // which does not exist here.
            : i fc . e first_clus
            = dir ? && == fc 0 == . v ftype 32 . v root_clus fc
        } {}
        ( vec_clear [i] leaf )
        ( vec_extend [i] leaf comp )
        = have T
        = k nk
    }
    ( vec_free [i] comp )
    ^ dir
}

// Resolve a whole path to its entry.
@ fat_lookup * FatVol v s path → FatEnt {
    : ( Vec i ) leaf ( vec_new [i] )
    : i dir ( fat_resolve_parent v path leaf )
    ? < dir 0 {
        ( vec_free [i] leaf )
        : ~ FatEnt e ( __ent_none )
        = . e err ? == dir ( fe_io ) T F
        ^ e
    } {}
    : FatEnt e ( fat_dir_find v dir leaf )
    ( vec_free [i] leaf )
    ^ e
}

// ── positioning and growth ──────────────────────────────────────────

// A cursor parked on entry `idx`, counting from the start of the
// directory. Re-walking from the beginning is O(n) where remembering
// the cursor would be O(1) — and a directory is a handful of sectors,
// while a saved cursor that outlived the directory it pointed into is
// a class of bug this trades away.
@ __dp_seek * FatVol v i dirclus i idx → *DirPos {
    : *DirPos p ( __dp_new v dirclus )
    : ~ i k 0
    ~ && < k idx ! . p done { ( __dp_advance v p ) = k + k 1 }
    ^ p
}

// One more zeroed cluster on the end of a directory's chain. The fixed
// FAT12/16 root has no chain and cannot grow: that is the format's
// limit, not this code's, and `root_ents` is where it is written down.
@ __dir_extend * FatVol v i dirclus → b {
    ? == dirclus 0 { ^ F } {}
    : ~ i cur dirclus
    : ~ i guard 0
    : i limit + . v nclus 2
    ~ < guard limit {
        : i nxt ( fat_next_clus v cur )
        ? < nxt 0 { ^ F } {}
        ? == nxt 0 {
            : i c ( fat_extend_chain v cur )
            ? == c 0 { ^ F } {}
            ^ ( fat_zero_clus v c )
        } {}
        = cur nxt
        = guard + guard 1
    }
    ^ F
}

// The index of the first of `need` consecutive free slots, or -1.
// Both spellings of free count: 0xE5 is a deleted entry and 0x00 is
// one that was never used, and the second also ends the directory —
// but the SPACE after it exists, so it is free rather than absent.
@ __dir_find_run * FatVol v i dirclus i need → i {
    : *DirPos p ( __dp_new v dirclus )
    : ~ i idx 0
    : ~ i run_start 0
    : ~ i run 0
    : ~ i found - 0 1
    : ~ i guard 0
    ~ && ! . p done < guard 4194304 {
        = guard + guard 1
        : i b0 ( fat_rd8 v ( __dp_lba p ) ( __dp_off p ) )
        ? < b0 0 { = . p done T } {
            ? || == b0 0 == b0 229 {
                ? == run 0 { = run_start idx } {}
                = run + run 1
                ? >= run need { = found run_start = . p done T } {}
            } { = run 0 }
            ? ! . p done { ( __dp_advance v p ) = idx + idx 1 } {}
        }
    }
    ( __dp_free p )
    ^ found
}

// ── short names ─────────────────────────────────────────────────────

@ __name11_new → ( Vec u ) {
    : ( Vec u ) o ( vec_new [u] )
    : ~ i k 0
    ~ < k 11 { ( vec_push [u] o # u 32 ) = k + k 1 }
    ^ o
}

@ __name11_set ( Vec u ) o i k i c → v { : b _s ( vec_set [u] o k # u & c 255 ) }

// Is this exact 8.3 name already taken in the directory? Two different
// long names can generate one short name, and a directory holding two
// identical short entries is one a checker calls corrupt.
@ __sfn_exists * FatVol v i dirclus ( Vec u ) name11 → b {
    : *DirPos p ( __dp_new v dirclus )
    : ~ b hit F
    : ~ i guard 0
    ~ && ! . p done < guard 4194304 {
        = guard + guard 1
        : i lba ( __dp_lba p )
        : i off ( __dp_off p )
        : i b0 ( fat_rd8 v lba off )
        ? < b0 0 { = . p done T } {
            ? == b0 0 { = . p done T } {
                : i attr ( __ent_attr v p )
                ? && != b0 229 != & attr 63 ( fat_attr_lfn ) {
                    : ~ b same T
                    : ~ i k 0
                    ~ < k 11 {
                        : i c ( fat_rd8 v lba + off k )
                        ? != c ( __cb name11 k ) { = same F = k 11 } { = k + k 1 }
                    }
                    ? same { = hit T = . p done T } {}
                } {}
                ? ! . p done { ( __dp_advance v p ) } {}
            }
        }
    }
    ( __dp_free p )
    ^ hit
}

// Can this name be stored as a short name with nothing lost? Returns
// the NT case flags (0, 8, 16 or 24) when it can and -1 when it cannot.
//
// "Nothing lost" includes CASE: FAT stores short names uppercased, and
// the two NT flags can restore an all-lowercase base or extension but
// nothing in between. `ReadMe.txt` therefore needs a long name, which
// is the correct answer and not a missed optimisation.
@ __sfn_exact ( Vec i ) cps ( Vec u ) out11 → i {
    : i n ( vec_len [i] cps )
    ? || == n 0 > n 12 { ^ - 0 1 } {}
    : ~ i dot - 0 1
    : ~ i k 0
    ~ < k n {
        : i c ?? ( vec_get [i] cps k ) { T x → x F → 0 }
        ? == c 46 { ? >= dot 0 { ^ - 0 1 } { = dot k } } {}
        = k + k 1
    }
    : i blen ? >= dot 0 dot n
    : i elen ? >= dot 0 - - n dot 1 0
    ? || == blen 0 > blen 8 { ^ - 0 1 } {}
    ? > elen 3 { ^ - 0 1 } {}
    ? && >= dot 0 == elen 0 { ^ - 0 1 } {}
    // A name that is all dots is `.` or `..`, which belong to the
    // directory machinery and are never created through this path.
    : ~ b b_lower F
    : ~ b b_upper F
    : ~ b e_lower F
    : ~ b e_upper F
    = k 0
    ~ < k n {
        : i c ?? ( vec_get [i] cps k ) { T x → x F → 0 }
        ? != k dot {
            ? > c 126 { ^ - 0 1 } {}
            ? ! ( __is_sfn_char c ) { ^ - 0 1 } {}
            ? == c 32 { ^ - 0 1 } {}
            : b in_ext && >= dot 0 > k dot
            ? && >= c 97 <= c 122 { ? in_ext { = e_lower T } { = b_lower T } } {}
            ? && >= c 65 <= c 90 { ? in_ext { = e_upper T } { = b_upper T } } {}
        } {}
        = k + k 1
    }
    ? && b_lower b_upper { ^ - 0 1 } {}
    ? && e_lower e_upper { ^ - 0 1 } {}
    = k 0
    ~ < k blen {
        ( __name11_set out11 k ( __upper ?? ( vec_get [i] cps k ) { T x → x F → 32 } ) )
        = k + k 1
    }
    = k 0
    ~ < k elen {
        ( __name11_set out11 + 8 k ( __upper ?? ( vec_get [i] cps + + dot 1 k ) { T x → x F → 32 } ) )
        = k + k 1
    }
    // 0xE5 as the first byte means "deleted"; the format's own escape
    // for a name that really starts with it is 0x05.
    ? == ( __cb out11 0 ) 229 { ( __name11_set out11 0 5 ) } {}
    ^ | ? b_lower 8 0 ? e_lower 16 0
}

// The `NAME~1.EXT` fallback, made unique in this directory. The basis
// keeps only characters a short name may hold; everything else — a
// space, a second dot, anything above ASCII — becomes an underscore,
// which is what every other FAT implementation does and what makes the
// short name recognisable next to the long one.
@ __sfn_generate * FatVol v i dirclus ( Vec i ) cps ( Vec u ) out11 → b {
    : i n ( vec_len [i] cps )
    : ~ i dot - 0 1
    : ~ i k 0
    ~ < k n {
        : i c ?? ( vec_get [i] cps k ) { T x → x F → 0 }
        ? == c 46 { = dot k } {}
        = k + k 1
    }
    : ( Vec i ) base ( vec_new [i] )
    : ( Vec i ) ext ( vec_new [i] )
    = k 0
    ~ < k n {
        : i c0 ?? ( vec_get [i] cps k ) { T x → x F → 0 }
        : i c ? || > c0 126 ? ( __is_sfn_char c0 ) F T 95 ( __upper c0 )
        ? == c 32 {} {
            ? == c0 46 {} {
                ? && >= dot 0 > k dot {
                    ? < ( vec_len [i] ext ) 3 { ( vec_push [i] ext c ) } {}
                } {
                    ? < ( vec_len [i] base ) 8 { ( vec_push [i] base c ) } {}
                }
            }
        }
        = k + k 1
    }
    ? == ( vec_len [i] base ) 0 { ( vec_push [i] base 95 ) } {}

    : ~ i seq 1
    : ~ b ok F
    ~ && ! ok <= seq 999999 {
        // How many digits the tail needs decides how much of the basis
        // survives: `~1` leaves six characters, `~999999` leaves one.
        : ~ i digits 1
        : ~ i probe seq
        ~ >= probe 10 { = digits + digits 1 = probe / probe 10 }
        : i keep - - 8 digits 1
        : i take ? > ( vec_len [i] base ) keep keep ( vec_len [i] base )
        : ~ i j 0
        ~ < j 11 { ( __name11_set out11 j 32 ) = j + j 1 }
        = j 0
        ~ < j take {
            ( __name11_set out11 j ?? ( vec_get [i] base j ) { T x → x F → 95 } )
            = j + j 1
        }
        ( __name11_set out11 take 126 )  // '~'
        : ~ i d digits
        : ~ i rest seq
        ~ > d 0 {
            ( __name11_set out11 + + take d % rest 10 + 48 0 )
            = rest / rest 10
            = d - d 1
        }
        = j 0
        ~ < j ( vec_len [i] ext ) {
            ( __name11_set out11 + 8 j ?? ( vec_get [i] ext j ) { T x → x F → 95 } )
            = j + j 1
        }
        ? ! ( __sfn_exists v dirclus out11 ) { = ok T } { = seq + seq 1 }
    }
    ( vec_free [i] base )
    ( vec_free [i] ext )
    ^ ok
}

// ── writing entries ─────────────────────────────────────────────────

@ __write_short * FatVol v i lba i off ( Vec u ) name11 i ntflags i attr i first i size → b {
    : ~ i k 0
    ~ < k 11 {
        ? ! ( fat_wr8 v lba + off k ( __cb name11 k ) ) { ^ F } {}
        = k + k 1
    }
    ? ! ( fat_wr8 v lba + off 11 attr ) { ^ F } {}
    ? ! ( fat_wr8 v lba + off 12 ntflags ) { ^ F } {}
    ? ! ( fat_wr8 v lba + off 13 0 ) { ^ F } {}
    : i st ( __fat_stamp )
    : i date & >> st 16 65535
    : i time & st 65535
    ? ! ( fat_wr16 v lba + off 14 time ) { ^ F } {}
    ? ! ( fat_wr16 v lba + off 16 date ) { ^ F } {}
    ? ! ( fat_wr16 v lba + off 18 date ) { ^ F } {}
    ? ! ( fat_wr16 v lba + off 22 time ) { ^ F } {}
    ? ! ( fat_wr16 v lba + off 24 date ) { ^ F } {}
    ? ! ( __ent_set_first v lba off first ) { ^ F } {}
    ^ ( __ent_set_size v lba off size )
}

@ __write_lfn * FatVol v i lba i off i ord b last i sum ( Vec i ) cps i from → b {
    ? ! ( fat_wr8 v lba + off 0 | ord ? last 64 0 ) { ^ F } {}
    ? ! ( fat_wr8 v lba + off 11 ( fat_attr_lfn ) ) { ^ F } {}
    ? ! ( fat_wr8 v lba + off 12 0 ) { ^ F } {}
    ? ! ( fat_wr8 v lba + off 13 sum ) { ^ F } {}
    ? ! ( fat_wr16 v lba + off 26 0 ) { ^ F } {}
    : i n ( vec_len [i] cps )
    : ~ i j 0
    ~ < j 13 {
        : i at + from j
        // Past the end of the name: one NUL terminator, then 0xFFFF
        // padding. Writing zeros all the way instead is a name every
        // other reader shows with trailing spaces.
        : i ch ? < at n ?? ( vec_get [i] cps at ) { T x → x F → 0 } ? == at n 0 65535
        ? ! ( __lfn_set_char v lba off j ch ) { ^ F } {}
        = j + j 1
    }
    ^ T
}

// Create `name` in `dirclus`. The caller has already established that
// it is not there.
@ fat_dir_create * FatVol v i dirclus ( Vec i ) name i attr i first i size → FatEnt {
    : ~ FatEnt res ( __ent_none )
    = . res dirclus dirclus
    ? ! . v rw { = . res err T ^ res } {}
    : i nlen ( vec_len [i] name )
    ? || == nlen 0 > nlen ( fat_name_max ) { = . res err T ^ res } {}

    : ( Vec u ) name11 ( __name11_new )
    : ~ i ntflags ( __sfn_exact name name11 )
    : ~ b needs_lfn F
    ? >= ntflags 0 {
        ? ( __sfn_exists v dirclus name11 ) { = needs_lfn T } {}
    } { = needs_lfn T }
    ? needs_lfn {
        = ntflags 0
        ? ! ( __sfn_generate v dirclus name name11 ) {
            ( vec_free [u] name11 )
            = . res err T
            ^ res
        } {}
    } {}

    : i nlfn ? needs_lfn / + nlen 12 13 0
    : i slots + nlfn 1
    : ~ i at ( __dir_find_run v dirclus slots )
    : ~ i grows 0
    ~ && < at 0 < grows 4096 {
        ? ! ( __dir_extend_ok v dirclus ) { = grows 4096 } {
            ? ! ( __dir_extend v dirclus ) { = grows 4096 } {
                = at ( __dir_find_run v dirclus slots )
                = grows + grows 1
            }
        }
    }
    ? < at 0 {
        ( vec_free [u] name11 )
        = . res err T
        ^ res
    } {}

    : *DirPos p ( __dp_seek v dirclus at )
    : ~ b ok T
    ? needs_lfn {
        // The long-name run is stored in REVERSE: the fragment carrying
        // the end of the name comes first physically, flagged as last,
        // and ordinals count down to 1 immediately before the short
        // entry. A reader that meets them in the other order is reading
        // somebody else's directory.
        : ~ i sum 0
        : ~ i k 0
        ~ < k 11 {
            = sum & + | & >> sum 1 127 & << sum 7 255 ( __cb name11 k ) 255
            = k + k 1
        }
        : ~ i j 0
        ~ && < j nlfn ok {
            : i ord - nlfn j
            ? ! ( __write_lfn v ( __dp_lba p ) ( __dp_off p ) ord == j 0 sum name * - ord 1 13 ) { = ok F } {}
            ( __dp_advance v p )
            ? . p done { = ok F } {}
            = j + j 1
        }
    } {}
    ? ok {
        : i lba ( __dp_lba p )
        : i off ( __dp_off p )
        ? ( __write_short v lba off name11 ntflags attr first size ) {
            = . res found T
            = . res lba lba
            = . res off off
            = . res idx + at nlfn
            = . res first_idx at
            = . res nslots slots
            = . res attr attr
            = . res first_clus first
            = . res size size
        } { = . res err T }
    } { = . res err T }
    ( __dp_free p )
    ( vec_free [u] name11 )
    ^ res
}

// Can this directory grow at all? The fixed root cannot, and a caller
// that kept asking would loop until its retry budget ran out instead of
// reporting the full directory it actually hit.
@ __dir_extend_ok * FatVol v i dirclus → b { ^ != dirclus 0 }

// Erase an entry and the long-name run in front of it.
@ fat_dir_remove * FatVol v FatEnt e → b {
    ? ! . v rw { ^ F } {}
    ? ! . e found { ^ F } {}
    : *DirPos p ( __dp_seek v . e dirclus . e first_idx )
    : ~ i k 0
    : ~ b ok T
    ~ && < k . e nslots ok {
        ? . p done { = ok F } {
            ? ! ( fat_wr8 v ( __dp_lba p ) ( __dp_off p ) 229 ) { = ok F } {}
            ( __dp_advance v p )
            = k + k 1
        }
    }
    ( __dp_free p )
    ^ ok
}

// ── the chain cursor a file carries ─────────────────────────────────

// The cluster holding byte range `idx` of this file, without extending
// it. 0 means the file is shorter than that.
@ __clus_for * FatVol v * FatFile f i idx → i {
    ? <= . f first 0 { ^ 0 } {}
    ? || <= . f cur_clus 0 > . f cur_idx idx {
        = . f cur_clus . f first
        = . f cur_idx 0
    } {}
    ~ < . f cur_idx idx {
        : i nxt ( fat_next_clus v . f cur_clus )
        ? <= nxt 0 { ^ 0 } {}
        = . f cur_clus nxt
        = . f cur_idx + . f cur_idx 1
    }
    ^ . f cur_clus
}

// The same, allocating whatever is missing. The cursor is what makes a
// sequential write O(1) per cluster instead of O(n): without it every
// write would walk the chain from the front, and a file large enough to
// matter is exactly the one that would take quadratic time.
@ __clus_for_write * FatVol v * FatFile f i idx → i {
    ? <= . f first 0 {
        : i c ( fat_extend_chain v 0 )
        ? == c 0 { ^ 0 } {}
        = . f first c
        = . f cur_clus c
        = . f cur_idx 0
        = . f meta_dirty T
    } {}
    ? || <= . f cur_clus 0 > . f cur_idx idx {
        = . f cur_clus . f first
        = . f cur_idx 0
    } {}
    ~ < . f cur_idx idx {
        : ~ i nxt ( fat_next_clus v . f cur_clus )
        ? < nxt 0 { ^ 0 } {}
        ? == nxt 0 {
            = nxt ( fat_extend_chain v . f cur_clus )
            ? == nxt 0 { ^ 0 } {}
        } {}
        = . f cur_clus nxt
        = . f cur_idx + . f cur_idx 1
    }
    ^ . f cur_clus
}

// The directory entry catches up with the file. Called at close, at
// fsync, and at unmount — not at every write, because a size field
// rewritten per byte is a sector rewritten per byte.
@ __flush_meta * FatVol v * FatFile f → b {
    ? ! . f meta_dirty { ^ T } {}
    ? ! . v rw { ^ F } {}
    ? == . f dlba 0 { ^ T } {}
    ? ! ( __ent_set_first v . f dlba . f doff . f first ) { ^ F } {}
    ? ! ( __ent_set_size v . f dlba . f doff ? . f isdir 0 . f size ) { ^ F } {}
    : i st ( __fat_stamp )
    ? ! ( fat_wr16 v . f dlba + . f doff 22 & st 65535 ) { ^ F } {}
    ? ! ( fat_wr16 v . f dlba + . f doff 24 & >> st 16 65535 ) { ^ F } {}
    // The archive bit is what every backup tool reads as "changed".
    : i attr ( fat_rd8 v . f dlba + . f doff 11 )
    ? >= attr 0 {
        ? == 0 & attr ( fat_attr_dir ) {
            ? ! ( fat_wr8 v . f dlba + . f doff 11 | attr ( fat_attr_archive ) ) { ^ F } {}
        } {}
    } {}
    = . f meta_dirty F
    ^ T
}

// ── open / close ────────────────────────────────────────────────────

@ __path_is_root s path → b {
    : i n ( nurl_str_len path )
    : ~ i k 0
    ~ < k n {
        ? != & ( nurl_str_get path k ) 255 47 { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ fatfs_open s path i flags → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    : *FatVol v ( fat_vol )
    : b wants_write != 0 & flags 3
    ? && wants_write ! . v rw { ^ ( fe_rofs ) } {}
    ? ( __path_is_root path ) { ^ ? wants_write ( fe_isdir ) ( __open_dir_clus v ( fat_root_cluster ) ) } {}

    : ( Vec i ) leaf ( vec_new [i] )
    : i dir ( fat_resolve_parent v path leaf )
    ? < dir 0 { ( vec_free [i] leaf ) ^ dir } {}
    : ~ FatEnt e ( fat_dir_find v dir leaf )
    ? . e err { ( vec_free [i] leaf ) ^ ( fe_io ) } {}

    ? ! . e found {
        ? == 0 & flags ( fo_creat ) { ( vec_free [i] leaf ) ^ ( fe_noent ) } {}
        ? ! . v rw { ( vec_free [i] leaf ) ^ ( fe_rofs ) } {}
        ? > ( vec_len [i] leaf ) ( fat_name_max ) { ( vec_free [i] leaf ) ^ ( fe_nametoolong ) } {}
        = e ( fat_dir_create v dir leaf ( fat_attr_archive ) 0 0 )
        ( vec_free [i] leaf )
        ? ! . e found { ^ ( fe_nospc ) } {}
    } {
        ( vec_free [i] leaf )
        // O_EXCL means something only together with O_CREAT, and the
        // test is that BOTH bits are set — `flags & (CREAT & EXCL)` is
        // `flags & 0`, which is a condition that can never be true and
        // an exclusive create that always succeeded.
        : i ce | ( fo_creat ) ( fo_excl )
        ? == & flags ce ce { ^ ( fe_exist ) } {}
        ? != 0 & . e attr ( fat_attr_dir ) { ? wants_write { ^ ( fe_isdir ) } {} } {}
    }

    : i h ( __file_slot )
    ? < h 0 { ^ ( fe_mfile ) } {}
    : *FatFile f # *FatFile ?? ( vec_get [i] . ( __tab ) f h ) { T x → x F → 0 }
    = . f used T
    = . f first . e first_clus
    = . f size . e size
    = . f pos 0
    = . f dlba . e lba
    = . f doff . e off
    = . f writable wants_write
    = . f append != 0 & flags ( fo_append )
    = . f isdir != 0 & . e attr ( fat_attr_dir )
    = . f meta_dirty F
    = . f cur_clus 0
    = . f cur_idx 0

    ? && != 0 & flags ( fo_trunc ) ! . f isdir {
        ? ! . f writable { = . f used F ^ ( fe_inval ) } {}
        ? > . f first 0 {
            ? ! ( fat_free_chain v . f first ) { = . f used F ^ ( fe_io ) } {}
        } {}
        = . f first 0
        = . f size 0
        = . f cur_clus 0
        = . f cur_idx 0
        = . f meta_dirty T
    } {}
    ^ h
}

// A handle onto a directory identified by its cluster — what opening
// "/" gives you, since the root has no entry of its own to describe it.
@ __open_dir_clus * FatVol v i clus → i {
    : i h ( __file_slot )
    ? < h 0 { ^ ( fe_mfile ) } {}
    : *FatFile f # *FatFile ?? ( vec_get [i] . ( __tab ) f h ) { T x → x F → 0 }
    = . f used T
    = . f first clus
    = . f size 0
    = . f pos 0
    = . f dlba 0
    = . f doff 0
    = . f writable F
    = . f append F
    = . f isdir T
    = . f meta_dirty F
    = . f cur_clus 0
    = . f cur_idx 0
    ^ h
}

@ fatfs_close i h → i {
    : *FatFile f ( __file h )
    ? == # i f 0 { ^ ( fe_badf ) } {}
    : ~ i rc 0
    ? ( fat_mounted ) {
        ? ! ( __flush_meta ( fat_vol ) f ) { = rc ( fe_io ) } {}
    } {}
    = . f used F
    ^ rc
}

@ fatfs_is_dir_handle i h → b {
    : *FatFile f ( __file h )
    ? == # i f 0 { ^ F } {}
    ^ . f isdir
}

// ── read ────────────────────────────────────────────────────────────

@ fatfs_read_raw i h s buf i n → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    : *FatVol v ( fat_vol )
    : *FatFile f ( __file h )
    ? == # i f 0 { ^ ( fe_badf ) } {}
    ? . f isdir { ^ ( fe_isdir ) } {}
    ? < n 0 { ^ ( fe_inval ) } {}
    : i avail - . f size . f pos
    : ~ i want ? > n avail avail n
    ? <= want 0 { ^ 0 } {}
    : i cbytes ( fat_cluster_bytes )
    : ~ i total 0
    ~ < total want {
        : i cidx / . f pos cbytes
        : i coff % . f pos cbytes
        : i c ( __clus_for v f cidx )
        ? <= c 0 { ^ ? > total 0 total ( fe_io ) } {}
        : i sec / coff ( blk_sector_size )
        : i soff % coff ( blk_sector_size )
        : i lba + ( fat_clus_lba v c ) sec
        : i left - want total
        : i in_clus - cbytes coff
        : i chunk ? > left in_clus in_clus left
        : ~ i got 0
        ? && == soff 0 >= chunk ( blk_sector_size ) {
            : i maxsec - . v spc sec
            : ~ i nsec / chunk ( blk_sector_size )
            ? > nsec maxsec { = nsec maxsec } {}
            ? ! ( fat_read_run v # s + # i buf total lba nsec ) { ^ ? > total 0 total ( fe_io ) } {}
            = got * nsec ( blk_sector_size )
        } {
            : i room - ( blk_sector_size ) soff
            = got ? > chunk room room chunk
            ? ! ( fat_copy_out v lba soff # s + # i buf total got ) { ^ ? > total 0 total ( fe_io ) } {}
        }
        = total + total got
        = . f pos + . f pos got
    }
    ^ total
}

@ fatfs_read i h ( Vec u ) out i n → i {
    ? < n 0 { ^ ( fe_inval ) } {}
    : i base ( vec_len [u] out )
    : ~ i k 0
    ~ < k n { ( vec_push [u] out # u 0 ) = k + k 1 }
    : i got ( fatfs_read_raw h # s + # i ( vec_data [u] out ) base n )
    : b _t ( vec_set_len [u] out + base ? > got 0 got 0 )
    ^ got
}

// ── write ───────────────────────────────────────────────────────────

// A file written past its end has a hole, and FAT has no holes: the
// bytes between the old size and the new position must be written as
// zeros or they are whatever the last file to own those clusters left.
@ __zero_fill * FatVol v * FatFile f i from i to → b {
    : i cbytes ( fat_cluster_bytes )
    : ( Vec u ) z ( vec_with_cap [u] ( blk_sector_size ) )
    : ~ i k 0
    ~ < k ( blk_sector_size ) { ( vec_push [u] z # u 0 ) = k + k 1 }
    : ~ i at from
    : ~ b ok T
    ~ && < at to ok {
        : i cidx / at cbytes
        : i coff % at cbytes
        : i c ( __clus_for_write v f cidx )
        ? <= c 0 { = ok F } {
            : i sec / coff ( blk_sector_size )
            : i soff % coff ( blk_sector_size )
            : i lba + ( fat_clus_lba v c ) sec
            : i room - ( blk_sector_size ) soff
            : i left - to at
            : i chunk ? > left room room left
            ? ! ( fat_copy_in v lba soff # s ( vec_data [u] z ) chunk ) { = ok F } {}
            = at + at chunk
        }
    }
    ( vec_free [u] z )
    ^ ok
}

@ fatfs_write_raw i h s buf i n → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    : *FatVol v ( fat_vol )
    : *FatFile f ( __file h )
    ? == # i f 0 { ^ ( fe_badf ) } {}
    ? . f isdir { ^ ( fe_isdir ) } {}
    ? ! . f writable { ^ ( fe_badf ) } {}
    ? ! . v rw { ^ ( fe_rofs ) } {}
    ? < n 0 { ^ ( fe_inval ) } {}
    ? == n 0 { ^ 0 } {}
    ? . f append { = . f pos . f size } {}
    ? > . f pos . f size {
        ? ! ( __zero_fill v f . f size . f pos ) { ^ ( fe_nospc ) } {}
        = . f size . f pos
        = . f meta_dirty T
    } {}

    : i cbytes ( fat_cluster_bytes )
    : ~ i total 0
    ~ < total n {
        : i cidx / . f pos cbytes
        : i coff % . f pos cbytes
        : i c ( __clus_for_write v f cidx )
        ? <= c 0 { ^ ? > total 0 total ( fe_nospc ) } {}
        : i sec / coff ( blk_sector_size )
        : i soff % coff ( blk_sector_size )
        : i lba + ( fat_clus_lba v c ) sec
        : i left - n total
        : i in_clus - cbytes coff
        : i chunk ? > left in_clus in_clus left
        : ~ i put 0
        ? && == soff 0 >= chunk ( blk_sector_size ) {
            : i maxsec - . v spc sec
            : ~ i nsec / chunk ( blk_sector_size )
            ? > nsec maxsec { = nsec maxsec } {}
            ? ! ( fat_write_run v # s + # i buf total lba nsec ) { ^ ? > total 0 total ( fe_io ) } {}
            = put * nsec ( blk_sector_size )
        } {
            : i room - ( blk_sector_size ) soff
            = put ? > chunk room room chunk
            ? ! ( fat_copy_in v lba soff # s + # i buf total put ) { ^ ? > total 0 total ( fe_io ) } {}
        }
        = total + total put
        = . f pos + . f pos put
        ? > . f pos . f size { = . f size . f pos = . f meta_dirty T } {}
    }
    = . f meta_dirty T
    ^ total
}

@ fatfs_write i h ( Vec u ) src i off i n → i {
    ? || < off 0 > + off n ( vec_len [u] src ) { ^ ( fe_inval ) } {}
    ^ ( fatfs_write_raw h # s + # i ( vec_data [u] src ) off n )
}

// ── position, size, durability ──────────────────────────────────────

@ fatfs_seek i h i off i whence → i {
    : *FatFile f ( __file h )
    ? == # i f 0 { ^ ( fe_badf ) } {}
    : i base ? == whence 0 0 ? == whence 1 . f pos . f size
    : i np + base off
    ? < np 0 { ^ ( fe_inval ) } {}
    = . f pos np
    ^ np
}

@ fatfs_tell i h → i {
    : *FatFile f ( __file h )
    ? == # i f 0 { ^ ( fe_badf ) } {}
    ^ . f pos
}

@ fatfs_size i h → i {
    : *FatFile f ( __file h )
    ? == # i f 0 { ^ ( fe_badf ) } {}
    ^ . f size
}

// Everything this handle has written is on the medium when this
// returns 0. The ORDER is the promise: data and the FAT chain that
// names it are already in the cache, the entry catches up here, and the
// whole cache goes down before the device is told to flush — so a crash
// mid-sync loses the newest bytes rather than the file that held them.
@ fatfs_fsync i h → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    : *FatFile f ( __file h )
    ? == # i f 0 { ^ ( fe_badf ) } {}
    ? ! ( __flush_meta ( fat_vol ) f ) { ^ ( fe_io ) } {}
    ? ! ( fat_write_fsinfo ) { ^ ( fe_io ) } {}
    ? ! ( fat_cache_flush ) { ^ ( fe_io ) } {}
    ? ! ( blk_flush ) { ^ ( fe_io ) } {}
    ^ 0
}

@ fatfs_sync → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    : *FatVol v ( fat_vol )
    : *FatTab t ( __tab )
    : ~ i k 0
    : ~ i rc 0
    ~ < k ( fatfs_max_open ) {
        : i p ?? ( vec_get [i] . t f k ) { T x → x F → 0 }
        ? != p 0 {
            : *FatFile f # *FatFile p
            ? . f used { ? ! ( __flush_meta v f ) { = rc ( fe_io ) } {} } {}
        } {}
        = k + k 1
    }
    ? ! ( fat_write_fsinfo ) { = rc ( fe_io ) } {}
    ? ! ( fat_cache_flush ) { = rc ( fe_io ) } {}
    ? ! ( blk_flush ) { = rc ( fe_io ) } {}
    ^ rc
}

// ── stat / exists ───────────────────────────────────────────────────

@ fatfs_lookup s path → FatEnt {
    ? ! ( fat_mounted ) { : ~ FatEnt e ( __ent_none ) = . e err T ^ e } {}
    ^ ( fat_lookup ( fat_vol ) path )
}

@ fatfs_exists s path → b {
    ? ! ( fat_mounted ) { ^ F } {}
    ? ( __path_is_root path ) { ^ T } {}
    : FatEnt e ( fat_lookup ( fat_vol ) path )
    ^ . e found
}

@ fatfs_is_dir s path → b {
    ? ! ( fat_mounted ) { ^ F } {}
    ? ( __path_is_root path ) { ^ T } {}
    : FatEnt e ( fat_lookup ( fat_vol ) path )
    ^ && . e found != 0 & . e attr ( fat_attr_dir )
}

@ fatfs_stat_size s path → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    ? ( __path_is_root path ) { ^ ( fe_isdir ) } {}
    : FatEnt e ( fat_lookup ( fat_vol ) path )
    ? . e err { ^ ( fe_io ) } {}
    ? ! . e found { ^ ( fe_noent ) } {}
    ^ . e size
}

// The modification stamp, as it is stored: (date << 16) | time. A
// caller wanting epoch seconds converts; this returns the truth on the
// medium rather than a conversion through a zone nobody stated.
@ fatfs_stat_mtime s path → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    : FatEnt e ( fat_lookup ( fat_vol ) path )
    ? ! . e found { ^ ( fe_noent ) } {}
    : *FatVol v ( fat_vol )
    : i t ( fat_rd16 v . e lba + . e off 22 )
    : i d ( fat_rd16 v . e lba + . e off 24 )
    ? || < t 0 < d 0 { ^ ( fe_io ) } {}
    ^ | << d 16 t
}

// ── unlink ──────────────────────────────────────────────────────────

@ fatfs_unlink s path → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    : *FatVol v ( fat_vol )
    ? ! . v rw { ^ ( fe_rofs ) } {}
    ? ( __path_is_root path ) { ^ ( fe_isdir ) } {}
    : FatEnt e ( fat_lookup v path )
    ? . e err { ^ ( fe_io ) } {}
    ? ! . e found { ^ ( fe_noent ) } {}
    ? != 0 & . e attr ( fat_attr_dir ) { ^ ( fe_isdir ) } {}
    ? != 0 & . e attr ( fat_attr_ro ) { ^ ( fe_rofs ) } {}
    // The ENTRY goes first and the chain second. A crash between them
    // leaves clusters no directory names — which `fsck.vfat` reclaims —
    // where the other order leaves a directory entry pointing at
    // clusters the allocator has already handed to somebody else.
    ? ! ( fat_dir_remove v e ) { ^ ( fe_io ) } {}
    ? > . e first_clus 0 {
        ? ! ( fat_free_chain v . e first_clus ) { ^ ( fe_io ) } {}
    } {}
    ^ 0
}

// ── directories ─────────────────────────────────────────────────────

@ __dot_name ( Vec u ) o b dotdot → v {
    : ~ i k 0
    ~ < k 11 { ( __name11_set o k 32 ) = k + k 1 }
    ( __name11_set o 0 46 )
    ? dotdot { ( __name11_set o 1 46 ) } {}
}

@ fatfs_mkdir s path → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    : *FatVol v ( fat_vol )
    ? ! . v rw { ^ ( fe_rofs ) } {}
    ? ( __path_is_root path ) { ^ ( fe_exist ) } {}
    : ( Vec i ) leaf ( vec_new [i] )
    : i dir ( fat_resolve_parent v path leaf )
    ? < dir 0 { ( vec_free [i] leaf ) ^ dir } {}
    : FatEnt old ( fat_dir_find v dir leaf )
    ? . old err { ( vec_free [i] leaf ) ^ ( fe_io ) } {}
    ? . old found { ( vec_free [i] leaf ) ^ ( fe_exist ) } {}

    // The cluster comes first and is zeroed before anything points at
    // it: a directory entry naming an unzeroed cluster is a directory
    // full of whatever the previous owner wrote, and every one of those
    // 32-byte runs is an entry to a reader.
    : i c ( fat_extend_chain v 0 )
    ? == c 0 { ( vec_free [i] leaf ) ^ ( fe_nospc ) } {}
    ? ! ( fat_zero_clus v c ) { ( vec_free [i] leaf ) ^ ( fe_io ) } {}

    : i lba ( fat_clus_lba v c )
    : ( Vec u ) n11 ( __name11_new )
    ( __dot_name n11 F )
    : ~ b ok ( __write_short v lba 0 n11 0 ( fat_attr_dir ) c 0 )
    ( __dot_name n11 T )
    // ".." in a child of the root is stored as cluster ZERO on every
    // FAT, including FAT32 where the root has a real cluster number.
    // Writing the real one there is a difference `fsck.vfat` reports.
    : i parent ? == dir ( fat_root_cluster ) 0 dir
    ? ok { = ok ( __write_short v lba ( fat_ent_size ) n11 0 ( fat_attr_dir ) parent 0 ) } {}
    ( vec_free [u] n11 )
    ? ! ok {
        : b _f ( fat_free_chain v c )
        ( vec_free [i] leaf )
        ^ ( fe_io )
    } {}

    : FatEnt e ( fat_dir_create v dir leaf ( fat_attr_dir ) c 0 )
    ( vec_free [i] leaf )
    ? ! . e found {
        : b _f ( fat_free_chain v c )
        ^ ( fe_nospc )
    } {}
    ^ 0
}

// Is this directory empty apart from "." and ".."?
@ __dir_is_empty * FatVol v i dirclus → b {
    : *DirPos p ( __dp_new v dirclus )
    : ~ b empty T
    : ~ i guard 0
    ~ && ! . p done < guard 4194304 {
        = guard + guard 1
        : i lba ( __dp_lba p )
        : i off ( __dp_off p )
        : i b0 ( fat_rd8 v lba off )
        ? < b0 0 { = empty F = . p done T } {
            ? == b0 0 { = . p done T } {
                ? != b0 229 {
                    : i attr ( __ent_attr v p )
                    ? != & attr 63 ( fat_attr_lfn ) {
                        : i b1 ( fat_rd8 v lba + off 1 )
                        : b is_dot && == b0 46 == b1 32
                        : b is_dotdot && == b0 46 == b1 46
                        ? || is_dot is_dotdot {} { = empty F = . p done T }
                    } { = empty F = . p done T }
                } {}
                ? ! . p done { ( __dp_advance v p ) } {}
            }
        }
    }
    ( __dp_free p )
    ^ empty
}

@ fatfs_rmdir s path → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    : *FatVol v ( fat_vol )
    ? ! . v rw { ^ ( fe_rofs ) } {}
    ? ( __path_is_root path ) { ^ ( fe_inval ) } {}
    : FatEnt e ( fat_lookup v path )
    ? . e err { ^ ( fe_io ) } {}
    ? ! . e found { ^ ( fe_noent ) } {}
    ? == 0 & . e attr ( fat_attr_dir ) { ^ ( fe_notdir ) } {}
    ? ! ( __dir_is_empty v . e first_clus ) { ^ ( fe_notempty ) } {}
    ? ! ( fat_dir_remove v e ) { ^ ( fe_io ) } {}
    ? > . e first_clus 0 {
        ? ! ( fat_free_chain v . e first_clus ) { ^ ( fe_io ) } {}
    } {}
    ^ 0
}

// ── rename ──────────────────────────────────────────────────────────

// A rename here is: create the new entry pointing at the same chain,
// then erase the old one. It is NOT atomic — FAT has no mechanism that
// would make it so — and the failure it is arranged to survive is the
// one that matters: a crash after the create leaves BOTH names on one
// chain, which a reader can see and a checker can repair, where the
// other order would leave the file with no name at all.
@ fatfs_rename s oldp s newp → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    : *FatVol v ( fat_vol )
    ? ! . v rw { ^ ( fe_rofs ) } {}
    ? || ( __path_is_root oldp ) ( __path_is_root newp ) { ^ ( fe_inval ) } {}

    : FatEnt src ( fat_lookup v oldp )
    ? . src err { ^ ( fe_io ) } {}
    ? ! . src found { ^ ( fe_noent ) } {}

    : ( Vec i ) leaf ( vec_new [i] )
    : i dir ( fat_resolve_parent v newp leaf )
    ? < dir 0 { ( vec_free [i] leaf ) ^ dir } {}
    : FatEnt dst ( fat_dir_find v dir leaf )
    ? . dst err { ( vec_free [i] leaf ) ^ ( fe_io ) } {}
    ? . dst found {
        // POSIX replaces the destination. A directory is never replaced
        // by a file, nor the other way round.
        : b s_dir != 0 & . src attr ( fat_attr_dir )
        : b d_dir != 0 & . dst attr ( fat_attr_dir )
        ? != s_dir d_dir { ( vec_free [i] leaf ) ^ ? d_dir ( fe_isdir ) ( fe_notdir ) } {}
        ? d_dir {
            ? ! ( __dir_is_empty v . dst first_clus ) { ( vec_free [i] leaf ) ^ ( fe_notempty ) } {}
        } {}
        // Same file, different spelling of the same name: nothing to do
        // and nothing to destroy.
        ? && == . dst lba . src lba == . dst off . src off {
            ( vec_free [i] leaf )
            ^ 0
        } {}
        ? ! ( fat_dir_remove v dst ) { ( vec_free [i] leaf ) ^ ( fe_io ) } {}
        ? > . dst first_clus 0 {
            ? ! ( fat_free_chain v . dst first_clus ) { ( vec_free [i] leaf ) ^ ( fe_io ) } {}
        } {}
    } {}

    : FatEnt made ( fat_dir_create v dir leaf . src attr . src first_clus . src size )
    ( vec_free [i] leaf )
    ? ! . made found { ^ ( fe_nospc ) } {}

    // Re-read the source rather than trusting the entry found before
    // the create. Two names that differ only in case are ONE name to
    // this filesystem, so `rename a.txt A.TXT` can find that the
    // "old" entry is now the one just written — and removing that
    // would delete the file the rename was supposed to keep. Looking
    // it up again and comparing positions is cheaper than reasoning
    // about which spellings can collide.
    : FatEnt again ( fat_lookup v oldp )
    : b same_entry && == . again lba . made lba == . again off . made off
    ? && . again found ! same_entry {
        ? ! ( fat_dir_remove v again ) { ^ ( fe_io ) } {}
    } {}

    // A moved directory's ".." must follow it.
    ? != 0 & . src attr ( fat_attr_dir ) {
        ? > . src first_clus 0 {
            : i lba ( fat_clus_lba v . src first_clus )
            : i parent ? == dir ( fat_root_cluster ) 0 dir
            ? ! ( __ent_set_first v lba ( fat_ent_size ) parent ) { ^ ( fe_io ) } {}
        } {}
    } {}
    ^ 0
}

// ── truncate ────────────────────────────────────────────────────────

@ fatfs_truncate s path i len → i {
    ? ! ( fat_mounted ) { ^ ( fe_io ) } {}
    : *FatVol v ( fat_vol )
    ? ! . v rw { ^ ( fe_rofs ) } {}
    ? < len 0 { ^ ( fe_inval ) } {}
    : FatEnt e ( fat_lookup v path )
    ? . e err { ^ ( fe_io ) } {}
    ? ! . e found { ^ ( fe_noent ) } {}
    ? != 0 & . e attr ( fat_attr_dir ) { ^ ( fe_isdir ) } {}

    : i cbytes ( fat_cluster_bytes )
    ? >= len . e size {
        ? == len . e size { ^ 0 } {}
        // Growing a file by truncation must write the zeros, same as a
        // write past the end would.
        : i h ( fatfs_open path ( fo_rdwr ) )
        ? < h 0 { ^ h } {}
        : i rc ( fatfs_seek h len 0 )
        ? < rc 0 { : i _c ( fatfs_close h ) ^ rc } {}
        : *FatFile f ( __file h )
        : ~ i out 0
        ? ! ( __zero_fill v f . e size len ) { = out ( fe_nospc ) } {
            = . f size len
            = . f meta_dirty T
        }
        : i cr ( fatfs_close h )
        ^ ? != out 0 out cr
    } {}

    // Shrinking: keep the clusters the new length needs, free the rest.
    : i keep / + len - cbytes 1 cbytes
    ? == keep 0 {
        ? > . e first_clus 0 {
            ? ! ( fat_free_chain v . e first_clus ) { ^ ( fe_io ) } {}
        } {}
        ? ! ( __ent_set_first v . e lba . e off 0 ) { ^ ( fe_io ) } {}
    } {
        : i tail ( fat_walk_chain v . e first_clus - keep 1 )
        ? <= tail 0 { ^ ( fe_io ) } {}
        : i rest ( fat_next_clus v tail )
        ? < rest 0 { ^ ( fe_io ) } {}
        ? ! ( fat_set_entry v tail ( fat_eoc_mark . v ftype ) ) { ^ ( fe_io ) } {}
        ? > rest 0 {
            ? ! ( fat_free_chain v rest ) { ^ ( fe_io ) } {}
        } {}
    }
    ? ! ( __ent_set_size v . e lba . e off len ) { ^ ( fe_io ) } {}
    ^ 0
}

// ── readdir ─────────────────────────────────────────────────────────

// Names, one call at a time, out of a handle opened on a directory.
// `pos` on the handle is the entry index, so the caller holds the
// cursor and this file holds none.
@ fatfs_readdir i h String out → b { ^ >= ( fatfs_readdir_attr h out ) 0 }

// The same, with the entry's attribute byte — which is how a caller
// tells a directory from a file without a second lookup, and what the
// guest's `getdents64` fills `d_type` from. -1 is the end.
@ fatfs_readdir_attr i h String out → i {
    ? ! ( fat_mounted ) { ^ - 0 1 } {}
    : *FatVol v ( fat_vol )
    : *FatFile f ( __file h )
    ? == # i f 0 { ^ - 0 1 } {}
    ? ! . f isdir { ^ - 0 1 } {}

    : *DirPos p ( __dp_seek v . f first . f pos )
    : ( Vec i ) lfn ( vec_new [i] )
    : ( Vec i ) name ( vec_new [i] )
    : ~ i lfn_sum - 0 1
    : ~ i lfn_n 0
    : ~ i got - 0 1
    : ~ i guard 0

    ~ && ! . p done < guard 4194304 {
        = guard + guard 1
        : i lba ( __dp_lba p )
        : i off ( __dp_off p )
        : i b0 ( fat_rd8 v lba off )
        ? < b0 0 { = . p done T } {
            ? == b0 0 { = . p done T } {
                = . f pos + . f pos 1
                ? == b0 229 {
                    = lfn_n 0
                    ( __dp_advance v p )
                } {
                    : i attr ( __ent_attr v p )
                    ? == & attr 63 ( fat_attr_lfn ) {
                        : i ord & b0 63
                        ? && >= ord 1 <= ord 20 {
                            ? != 0 & b0 64 {
                                = lfn_sum ( fat_rd8 v lba + off 13 )
                                = lfn_n ord
                                ( vec_clear [i] lfn )
                                : ~ i z 0
                                ~ < z * ord 13 { ( vec_push [i] lfn - 0 1 ) = z + z 1 }
                            } {}
                            ? && > lfn_n 0 <= ord lfn_n {
                                ? == ( fat_rd8 v lba + off 13 ) lfn_sum {
                                    : ~ i j 0
                                    ~ < j 13 {
                                        : b _s ( vec_set [i] lfn + * - ord 1 13 j ( __lfn_char v lba off j ) )
                                        = j + j 1
                                    }
                                } { = lfn_n 0 }
                            } {}
                        } { = lfn_n 0 }
                        ( __dp_advance v p )
                    } {
                        ? != 0 & attr ( fat_attr_volid ) {
                            = lfn_n 0
                            ( __dp_advance v p )
                        } {
                            ( vec_clear [i] name )
                            : ~ b have_long F
                            ? > lfn_n 0 {
                                ? == ( __sfn_checksum v lba off ) lfn_sum {
                                    : ~ i j 0
                                    : i m ( vec_len [i] lfn )
                                    ~ < j m {
                                        : i ch ?? ( vec_get [i] lfn j ) { T x → x F → - 0 1 }
                                        ? || || == ch 0 == ch 65535 < ch 0 { = j m } {
                                            ( vec_push [i] name ch )
                                            = j + j 1
                                        }
                                    }
                                    = have_long T
                                } {}
                            } {}
                            ? ! have_long {
                                ( vec_clear [i] name )
                                : b _o ( __sfn_cps v lba off name )
                            } {}
                            ( fat_cps_to_utf8 name out )
                            = got attr
                            = . p done T
                        }
                    }
                }
            }
        }
    }
    ( vec_free [i] lfn )
    ( vec_free [i] name )
    ( __dp_free p )
    ^ got
}
