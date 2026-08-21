// stdlib/fs/fat.nu — FAT12/16/32, the format: volume layout, the
// allocation table, directory entries and the two ways FAT spells a
// name. The file API that sits on top is `stdlib/fs/fatfs.nu`.
//
// WHY FAT. A unikernel with a disk needs a filesystem, and the choice
// is between one nobody else can read and one everybody can. FAT is the
// second: `mkfs.vfat` builds the image, `fsck.vfat` validates what we
// wrote, and any host can look inside a guest's disk without a tool
// this repository had to ship. That external oracle is worth more than
// any feature a private format would have bought, because a filesystem
// that only its own reader can check is a filesystem whose bugs are
// invisible until somebody's data is already in it.
//
// WHAT IT IS NOT. FAT has no journal and this implementation does not
// invent one. `fatfs_sync` puts everything on the medium in an order
// chosen so a crash loses the newest data rather than the file that
// held it — data blocks and their FAT chain before the directory entry
// that publishes the new size — but a crash between two of those writes
// can still leave a chain the directory does not name (lost clusters,
// which `fsck.vfat` finds and reclaims). That is stated here because
// the alternative is a caller believing otherwise.
//
// SECTORS ARE 512 BYTES. A volume whose BPB says anything else is
// REFUSED at mount: the block seam under this file speaks 512-byte
// sectors (see `stdlib/hal/blockdev.nu`), and quietly reading a 4096-
// byte-sector volume through it would put every structure at the wrong
// offset while looking like a successful mount.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/hal/blockdev.nu`

// ── directory-entry attributes (FAT spec, §6) ───────────────────────

@ fat_attr_ro → i { ^ 1 }

@ fat_attr_hidden → i { ^ 2 }

@ fat_attr_system → i { ^ 4 }

@ fat_attr_volid → i { ^ 8 }

@ fat_attr_dir → i { ^ 16 }

@ fat_attr_archive → i { ^ 32 }

// A long-name entry is spelled as all four of read-only, hidden, system
// and volume-id at once — a combination no real file has, which is
// exactly why it was chosen: a FAT reader that predates long names
// skips these entries instead of showing them.
@ fat_attr_lfn → i { ^ 15 }

@ fat_ent_size → i { ^ 32 }

@ fat_ents_per_sector → i { ^ 16 }

// How many 512-byte sectors the cache holds. Sixteen is 8 KiB — enough
// that a directory scan and the FAT sector it consults do not evict
// each other, small enough to live in the 4 MiB guest the README pins.
@ fat_cache_slots → i { ^ 16 }

// The cluster numbers that are not clusters. 0 and 1 are reserved by
// the format; the first real one is 2.
@ fat_clus_first → i { ^ 2 }

// ── the volume ──────────────────────────────────────────────────────

: FatVol {
    i spc  // sectors per cluster
    i rsvd  // reserved sectors, i.e. where FAT #0 starts
    i nfats
    i root_ents  // FAT12/16 only: entries in the fixed root
    i fat_secs  // sectors per FAT
    i tot_secs
    i fat_start
    i root_start  // FAT12/16: first sector of the fixed root region
    i root_secs
    i data_start
    i nclus  // number of DATA clusters, i.e. highest is nclus+1
    i ftype  // 12, 16 or 32
    i root_clus  // FAT32 only
    i hint  // where the next free-cluster search starts
    i free_count  // -1 = not known; nobody has counted and nobody lied
    i fsinfo_lba  // FAT32 only, 0 = none
    b rw
    b dirty  // FSInfo / metadata needs writing back
    // ── the sector cache ──
    ( Vec u ) cbuf
    ( Vec i ) clba  // -1 = empty
    ( Vec i ) cdirty
    ( Vec i ) cage
    i clock
    // ── scratch for direct (uncached) transfers ──
    ( Vec u ) scratch
}

: ~ i g_vol 0

@ fat_mounted → b { ^ != g_vol 0 }

@ fat_vol → *FatVol { ^ # *FatVol g_vol }

@ fat_type → i { ? == g_vol 0 { ^ 0 } {} ^ . ( fat_vol ) ftype }

@ fat_cluster_bytes → i {
    ? == g_vol 0 { ^ 0 } {}
    ^ * . ( fat_vol ) spc ( blk_sector_size )
}

@ fat_cluster_count → i { ? == g_vol 0 { ^ 0 } {} ^ . ( fat_vol ) nclus }

@ fat_root_cluster → i {
    ? == g_vol 0 { ^ 0 } {}
    : *FatVol v ( fat_vol )
    ^ ? == . v ftype 32 . v root_clus 0
}

@ fat_writable → b { ? == g_vol 0 { ^ F } {} ^ . ( fat_vol ) rw }

// ── the sector cache ────────────────────────────────────────────────
//
// Write-back, LRU by a monotone clock. Every metadata read and every
// partial-sector data read goes through it; a transfer that covers
// whole sectors goes straight to the device (see `fat_read_run`) after
// dropping any cached copy of the sectors it touches, because two
// copies of one sector with one of them dirty is the oldest bug in
// block I/O.

@ __cache_init * FatVol v → v {
    : i n ( fat_cache_slots )
    = . v cbuf ( vec_with_cap [u] * n ( blk_sector_size ) )
    : ~ i k 0
    ~ < k * n ( blk_sector_size ) { ( vec_push [u] . v cbuf # u 0 ) = k + k 1 }
    = . v clba ( vec_new [i] )
    = . v cdirty ( vec_new [i] )
    = . v cage ( vec_new [i] )
    = k 0
    ~ < k n {
        ( vec_push [i] . v clba - 0 1 )
        ( vec_push [i] . v cdirty 0 )
        ( vec_push [i] . v cage 0 )
        = k + k 1
    }
    = . v clock 0
    = . v scratch ( vec_new [u] )
}

@ __ci ( Vec i ) v i k → i { ^ ?? ( vec_get [i] v k ) { T x → x F → 0 } }

// One byte out of a Vec, as an integer. Public and shared with
// `fatfs.nu` rather than duplicated there: NURL's namespace is flat, so
// two files with a private `__cb` are a collision the stdlib gate
// rejects — a `__` name is file-SCOPED, not file-local at link time.
@ fat_vb ( Vec u ) v i k → i { ^ # i ?? ( vec_get [u] v k ) { T x → x F → # u 0 } }

@ __cache_writeback * FatVol v i slot → b {
    ? == ( __ci . v cdirty slot ) 0 { ^ T } {}
    : i lba ( __ci . v clba slot )
    ? < lba 0 { ^ T } {}
    ? ! ( blk_write . v cbuf * slot ( blk_sector_size ) lba 1 ) { ^ F } {}
    : b _s ( vec_set [i] . v cdirty slot 0 )
    ^ T
}

// The slot holding `lba`, loading it if it is not there. -1 means the
// device refused, which is the one answer above this that must not be
// confused with "a sector of zeros".
@ __cache_slot * FatVol v i lba → i {
    : i n ( fat_cache_slots )
    : ~ i k 0
    = . v clock + . v clock 1
    ~ < k n {
        ? == ( __ci . v clba k ) lba {
            : b _a ( vec_set [i] . v cage k . v clock )
            ^ k
        } {}
        = k + k 1
    }
    // Evict the oldest. An empty slot is age 0 and therefore always
    // oldest, so "fill first, then evict" needs no separate pass.
    : ~ i victim 0
    : ~ i best ( __ci . v cage 0 )
    = k 1
    ~ < k n {
        : i a ( __ci . v cage k )
        ? < a best { = best a = victim k } {}
        = k + k 1
    }
    ? ! ( __cache_writeback v victim ) { ^ - 0 1 } {}
    ? ! ( blk_read . v cbuf * victim ( blk_sector_size ) lba 1 ) {
        : b _e ( vec_set [i] . v clba victim - 0 1 )
        : b _g ( vec_set [i] . v cage victim 0 )
        ^ - 0 1
    } {}
    : b _l ( vec_set [i] . v clba victim lba )
    : b _d ( vec_set [i] . v cdirty victim 0 )
    : b _g2 ( vec_set [i] . v cage victim . v clock )
    ^ victim
}

// Drop `n` sectors from the cache, writing back anything dirty first.
// Called before a direct transfer over the same range.
@ __cache_drop * FatVol v i lba i n → b {
    : i slots ( fat_cache_slots )
    : ~ i k 0
    : ~ b ok T
    ~ < k slots {
        : i l ( __ci . v clba k )
        ? && >= l lba < l + lba n {
            ? ! ( __cache_writeback v k ) { = ok F } {}
            : b _e ( vec_set [i] . v clba k - 0 1 )
            : b _g ( vec_set [i] . v cage k 0 )
        } {}
        = k + k 1
    }
    ^ ok
}

@ fat_cache_flush → b {
    ? == g_vol 0 { ^ F } {}
    : *FatVol v ( fat_vol )
    : i n ( fat_cache_slots )
    : ~ i k 0
    : ~ b ok T
    ~ < k n {
        ? ! ( __cache_writeback v k ) { = ok F } {}
        = k + k 1
    }
    ^ ok
}

// ── byte access to a sector, through the cache ──────────────────────

@ fat_rd8 * FatVol v i lba i off → i {
    : i slot ( __cache_slot v lba )
    ? < slot 0 { ^ - 0 1 } {}
    ^ ( fat_vb . v cbuf + * slot ( blk_sector_size ) off )
}

@ fat_wr8 * FatVol v i lba i off i val → b {
    : i slot ( __cache_slot v lba )
    ? < slot 0 { ^ F } {}
    : b ok ( vec_set [u] . v cbuf + * slot ( blk_sector_size ) off # u & val 255 )
    ? ! ok { ^ F } {}
    : b _d ( vec_set [i] . v cdirty slot 1 )
    ^ T
}

@ fat_rd16 * FatVol v i lba i off → i {
    : i a ( fat_rd8 v lba off )
    : i b ( fat_rd8 v lba + off 1 )
    ? || < a 0 < b 0 { ^ - 0 1 } {}
    ^ | a << b 8
}

@ fat_rd32 * FatVol v i lba i off → i {
    : i a ( fat_rd16 v lba off )
    : i b ( fat_rd16 v lba + off 2 )
    ? || < a 0 < b 0 { ^ - 0 1 } {}
    ^ | a << b 16
}

@ fat_wr16 * FatVol v i lba i off i val → b {
    ? ! ( fat_wr8 v lba off & val 255 ) { ^ F } {}
    ^ ( fat_wr8 v lba + off 1 & >> val 8 255 )
}

@ fat_wr32 * FatVol v i lba i off i val → b {
    ? ! ( fat_wr16 v lba off & val 65535 ) { ^ F } {}
    ^ ( fat_wr16 v lba + off 2 & >> val 16 65535 )
}

// ── mount ───────────────────────────────────────────────────────────

// The BPB, read straight off sector 0 with the block layer rather than
// the cache — the cache does not exist yet, and the volume it would
// belong to is what this is computing.
@ __read_boot ( Vec u ) sec → b {
    : ~ i k 0
    ( vec_clear [u] sec )
    ~ < k ( blk_sector_size ) { ( vec_push [u] sec # u 0 ) = k + k 1 }
    ^ ( blk_read sec 0 0 1 )
}

@ __le16 ( Vec u ) b i off → i {
    ^ | ( fat_vb b off ) << ( fat_vb b + off 1 ) 8
}

@ __le32 ( Vec u ) b i off → i {
    ^ | ( __le16 b off ) << ( __le16 b + off 2 ) 16
}

// Mount the device the block seam is attached to. `writable` false is
// honoured all the way down: every write path checks it, so a reader
// cannot dirty a volume it was handed for inspection.
//
// Failure is a REFUSAL with the volume left unmounted, never a
// half-mounted one: every field below is derived from the BPB, and a
// BPB that does not describe a FAT volume produces numbers that address
// arbitrary sectors.
@ fat_mount b writable → b {
    ( fat_unmount )
    ? ! ( blk_present ) { ^ F } {}

    : ( Vec u ) sec ( vec_new [u] )
    ? ! ( __read_boot sec ) { ( vec_free [u] sec ) ^ F } {}

    : i bps ( __le16 sec 11 )
    : i spc ( fat_vb sec 13 )
    : i rsvd ( __le16 sec 14 )
    : i nfats ( fat_vb sec 16 )
    : i root_ents ( __le16 sec 17 )
    : i tot16 ( __le16 sec 19 )
    : i spf16 ( __le16 sec 22 )
    : i tot32 ( __le32 sec 32 )
    : i spf32 ( __le32 sec 36 )
    : i rootc ( __le32 sec 44 )
    : i fsinfo ( __le16 sec 48 )
    : i sig ( __le16 sec 510 )
    ( vec_free [u] sec )

    // Each of these is a way a non-FAT sector 0 produces a plausible
    // number. `bps` is the one that matters most: see the header.
    ? != bps ( blk_sector_size ) { ^ F } {}
    ? != sig 43605 { ^ F } {}  // 0xAA55
    ? == spc 0 { ^ F } {}
    ? != ( __fat_pow2 spc ) T { ^ F } {}
    ? > spc 128 { ^ F } {}
    ? == rsvd 0 { ^ F } {}
    ? || == nfats 0 > nfats 4 { ^ F } {}

    : i fat_secs ? != spf16 0 spf16 spf32
    ? == fat_secs 0 { ^ F } {}
    : i tot ? != tot16 0 tot16 tot32
    ? == tot 0 { ^ F } {}
    ? > tot ( blk_sector_count ) { ^ F } {}

    : i root_secs / + * root_ents ( fat_ent_size ) - ( blk_sector_size ) 1 ( blk_sector_size )
    : i fat_start rsvd
    : i root_start + rsvd * nfats fat_secs
    : i data_start + root_start root_secs
    ? >= data_start tot { ^ F } {}
    : i nclus / - tot data_start spc
    ? == nclus 0 { ^ F } {}

    // THE COUNT DECIDES THE TYPE, not the label in the boot sector:
    // the thresholds below are the format's own definition (FAT spec
    // §3.5), and `mkfs.vfat` writes "FAT16   " into a field that has
    // been observed to disagree with the arithmetic. Reading the string
    // is how a volume gets its FAT entries decoded at the wrong width.
    : ~ i ftype 32
    ? < nclus 4085 { = ftype 12 } {
        ? < nclus 65525 { = ftype 16 } { = ftype 32 }
    }

    // FAT32 has no fixed root region and FAT12/16 must have one.
    ? == ftype 32 {
        ? != root_ents 0 { ^ F } {}
        ? || < rootc ( fat_clus_first ) > rootc + nclus 1 { ^ F } {}
    } {
        ? == root_ents 0 { ^ F } {}
    }

    // Every FAT must be big enough to hold an entry per cluster, or a
    // chain walk reads past the table into the root directory.
    : i need_bytes ? == ftype 32 * + nclus 2 4 ? == ftype 16 * + nclus 2 2 / + * + nclus 2 3 1 2
    ? < * fat_secs ( blk_sector_size ) need_bytes { ^ F } {}

    : *FatVol v # *FatVol ( nurl_alloc Z FatVol )
    = . v spc spc
    = . v rsvd rsvd
    = . v nfats nfats
    = . v root_ents root_ents
    = . v fat_secs fat_secs
    = . v tot_secs tot
    = . v fat_start fat_start
    = . v root_start root_start
    = . v root_secs root_secs
    = . v data_start data_start
    = . v nclus nclus
    = . v ftype ftype
    = . v root_clus ? == ftype 32 rootc 0
    = . v hint ( fat_clus_first )
    // NOT read from FSInfo. That field is a hint the format explicitly
    // permits to be wrong, and a mount that believed it would report a
    // free-space figure it had never verified — so the answer starts as
    // "nobody has counted", and `fat_free_clusters` is what changes it.
    = . v free_count - 0 1
    = . v fsinfo_lba ? && == ftype 32 && >= fsinfo 1 < fsinfo rsvd fsinfo 0
    = . v rw writable
    = . v dirty F
    ( __cache_init v )
    = g_vol # i v
    ^ T
}

@ __fat_pow2 i n → b {
    ? <= n 0 { ^ F } {}
    ^ == & n - n 1 0
}

@ fat_unmount → v {
    ? == g_vol 0 { ^ } {}
    : *FatVol v ( fat_vol )
    : b _i ( fat_write_fsinfo )
    : b _f ( fat_cache_flush )
    : b _d ( blk_flush )
    ( vec_free [u] . v cbuf )
    ( vec_free [i] . v clba )
    ( vec_free [i] . v cdirty )
    ( vec_free [i] . v cage )
    ( vec_free [u] . v scratch )
    ( nurl_free # s v )
    = g_vol 0
}

// ── the allocation table ────────────────────────────────────────────

@ fat_eoc_min i ftype → i {
    ? == ftype 12 { ^ 4088 } {}  // 0xFF8
    ? == ftype 16 { ^ 65528 } {}  // 0xFFF8
    ^ 268435448  // 0x0FFFFFF8
}

@ fat_is_eoc i ftype i e → b { ^ >= e ( fat_eoc_min ftype ) }

@ fat_bad_mark i ftype → i {
    ? == ftype 12 { ^ 4087 } {}
    ? == ftype 16 { ^ 65527 } {}
    ^ 268435447
}

@ fat_eoc_mark i ftype → i {
    ? == ftype 12 { ^ 4095 } {}
    ? == ftype 16 { ^ 65535 } {}
    ^ 268435455
}

@ __clus_valid * FatVol v i c → b {
    ^ && >= c ( fat_clus_first ) <= c + . v nclus 1
}

// The same question, for the layers above.
@ fat_clus_ok * FatVol v i c → b { ^ ( __clus_valid v c ) }

// Read the FAT entry for `c` from FAT copy `which`. -1 on I/O error,
// which the callers must not confuse with a free cluster (0).
@ fat_get_entry * FatVol v i c → i {
    ? ! ( __clus_valid v c ) { ^ - 0 1 } {}
    ? == . v ftype 32 {
        : i off * c 4
        : i lba + . v fat_start / off ( blk_sector_size )
        : i e ( fat_rd32 v lba % off ( blk_sector_size ) )
        ? < e 0 { ^ - 0 1 } {}
        ^ & e 268435455
    } {}
    ? == . v ftype 16 {
        : i off * c 2
        : i lba + . v fat_start / off ( blk_sector_size )
        ^ ( fat_rd16 v lba % off ( blk_sector_size ) )
    } {}
    // FAT12: an entry is twelve bits, so consecutive entries share a
    // byte and an entry can straddle a sector boundary. Reading it byte
    // by byte is how that stops being a special case.
    : i off + c / c 2
    : i b0 ( __fat12_byte v off )
    : i b1 ( __fat12_byte v + off 1 )
    ? || < b0 0 < b1 0 { ^ - 0 1 } {}
    : i raw | b0 << b1 8
    ^ ? == % c 2 0 & raw 4095 & >> raw 4 4095
}

@ __fat12_byte * FatVol v i off → i {
    : i lba + . v fat_start / off ( blk_sector_size )
    ^ ( fat_rd8 v lba % off ( blk_sector_size ) )
}

@ __fat12_put * FatVol v i fatbase i off i val → b {
    : i lba + fatbase / off ( blk_sector_size )
    ^ ( fat_wr8 v lba % off ( blk_sector_size ) val )
}

// Write `val` into every FAT copy. Mirroring is not optional: a
// checker compares the copies, and a volume whose FATs disagree is
// reported as corrupt even when the one we used is perfect.
@ fat_set_entry * FatVol v i c i val → b {
    ? ! . v rw { ^ F } {}
    ? ! ( __clus_valid v c ) { ^ F } {}
    : ~ i f 0
    ~ < f . v nfats {
        : i base + . v fat_start * f . v fat_secs
        ? == . v ftype 32 {
            : i off * c 4
            : i lba + base / off ( blk_sector_size )
            : i o % off ( blk_sector_size )
            // The top four bits of a FAT32 entry belong to nobody and
            // must be PRESERVED (spec §4): they are not ours to clear.
            : i old ( fat_rd32 v lba o )
            ? < old 0 { ^ F } {}
            ? ! ( fat_wr32 v lba o | & old 4026531840 & val 268435455 ) { ^ F } {}
        } {
            ? == . v ftype 16 {
                : i off * c 2
                : i lba + base / off ( blk_sector_size )
                ? ! ( fat_wr16 v lba % off ( blk_sector_size ) & val 65535 ) { ^ F } {}
            } {
                : i off + c / c 2
                : i b0 ( __fat12_byte_at v base off )
                : i b1 ( __fat12_byte_at v base + off 1 )
                ? || < b0 0 < b1 0 { ^ F } {}
                : ~ i raw | b0 << b1 8
                ? == % c 2 0 {
                    = raw | & raw 61440 & val 4095
                } {
                    = raw | & raw 15 << & val 4095 4
                }
                ? ! ( __fat12_put v base off & raw 255 ) { ^ F } {}
                ? ! ( __fat12_put v base + off 1 & >> raw 8 255 ) { ^ F } {}
            }
        }
        = f + f 1
    }
    ^ T
}

@ __fat12_byte_at * FatVol v i base i off → i {
    : i lba + base / off ( blk_sector_size )
    ^ ( fat_rd8 v lba % off ( blk_sector_size ) )
}

// The first sector of a cluster.
@ fat_clus_lba * FatVol v i c → i {
    ^ + . v data_start * - c ( fat_clus_first ) . v spc
}

// The next cluster in a chain: 0 = end (EOC or free), -1 = error.
@ fat_next_clus * FatVol v i c → i {
    : i e ( fat_get_entry v c )
    ? < e 0 { ^ - 0 1 } {}
    ? ( fat_is_eoc . v ftype e ) { ^ 0 } {}
    ? == e 0 { ^ 0 } {}
    ? ! ( __clus_valid v e ) { ^ - 0 1 } {}
    ^ e
}

// Find one free cluster, starting from the volume's hint and wrapping
// once. Returns 0 when the volume is full — which is ENOSPC, not an
// error to retry.
@ fat_alloc_clus * FatVol v → i {
    ? ! . v rw { ^ 0 } {}
    : i last + . v nclus 1
    : ~ i c . v hint
    ? < c ( fat_clus_first ) { = c ( fat_clus_first ) } {}
    : ~ i tried 0
    : i total + - last ( fat_clus_first ) 1
    ~ < tried total {
        : i e ( fat_get_entry v c )
        ? < e 0 { ^ 0 } {}
        ? == e 0 {
            ? ! ( fat_set_entry v c ( fat_eoc_mark . v ftype ) ) { ^ 0 } {}
            = . v hint ? >= + c 1 last ( fat_clus_first ) + c 1
            ? > . v free_count 0 { = . v free_count - . v free_count 1 } {}
            ^ c
        } {}
        = c + c 1
        ? > c last { = c ( fat_clus_first ) } {}
        = tried + tried 1
    }
    ^ 0
}

// Zero a whole cluster — required for a directory (an unzeroed one is
// full of whatever the last file left, and every byte of that is a
// directory entry to a reader) and cheap enough to be worth doing.
@ fat_zero_clus * FatVol v i c → b {
    ? ! ( __clus_valid v c ) { ^ F } {}
    : i lba ( fat_clus_lba v c )
    ? ! ( __cache_drop v lba . v spc ) { ^ F } {}
    : i nbytes * . v spc ( blk_sector_size )
    ( vec_clear [u] . v scratch )
    : ~ i k 0
    ~ < k nbytes { ( vec_push [u] . v scratch # u 0 ) = k + k 1 }
    ^ ( blk_write . v scratch 0 lba . v spc )
}

// Free a whole chain from `c`. Bounded by the cluster count: a chain
// that loops back on itself would otherwise free clusters for ever,
// and a corrupt FAT is exactly when that happens.
@ fat_free_chain * FatVol v i c → b {
    ? ! . v rw { ^ F } {}
    : ~ i cur c
    : ~ i steps 0
    : i limit + . v nclus 2
    ~ && && > cur 0 ( __clus_valid v cur ) < steps limit {
        : i nxt ( fat_next_clus v cur )
        ? < nxt 0 { ^ F } {}
        ? ! ( fat_set_entry v cur 0 ) { ^ F } {}
        ? >= . v free_count 0 { = . v free_count + . v free_count 1 } {}
        ? < cur . v hint { = . v hint cur } {}
        = cur nxt
        = steps + steps 1
    }
    ^ < steps limit
}

// Append one freshly-allocated cluster to the chain ending at `tail`
// (0 = the chain does not exist yet). Returns the new cluster, or 0.
@ fat_extend_chain * FatVol v i tail → i {
    : i c ( fat_alloc_clus v )
    ? == c 0 { ^ 0 } {}
    ? > tail 0 {
        // The new cluster is marked EOC by the allocator BEFORE the old
        // tail points at it: a crash between the two loses a cluster,
        // where the other order publishes a chain whose end is whatever
        // the FAT happened to hold.
        ? ! ( fat_set_entry v tail c ) { ^ 0 } {}
    } {}
    ^ c
}

// Walk `n` clusters along a chain. Returns 0 if the chain is shorter.
@ fat_walk_chain * FatVol v i start i n → i {
    : ~ i cur start
    : ~ i k 0
    ~ && < k n > cur 0 {
        = cur ( fat_next_clus v cur )
        ? < cur 0 { ^ 0 } {}
        = k + k 1
    }
    ^ cur
}

// How many clusters a chain holds. -1 on error or a loop.
@ fat_chain_len * FatVol v i start → i {
    ? <= start 0 { ^ 0 } {}
    : ~ i cur start
    : ~ i n 0
    : i limit + . v nclus 2
    ~ && > cur 0 < n limit {
        = n + n 1
        = cur ( fat_next_clus v cur )
        ? < cur 0 { ^ - 0 1 } {}
    }
    ? >= n limit { ^ - 0 1 } {}
    ^ n
}

// How many clusters are free. Walks the whole FAT, so it is a query a
// caller asks once and not per write.
@ fat_free_clusters → i {
    ? == g_vol 0 { ^ 0 } {}
    : *FatVol v ( fat_vol )
    : ~ i c ( fat_clus_first )
    : ~ i n 0
    : i last + . v nclus 1
    ~ <= c last {
        : i e ( fat_get_entry v c )
        ? < e 0 { ^ n } {}
        ? == e 0 { = n + n 1 } {}
        = c + c 1
    }
    = . v free_count n
    ^ n
}

// FSInfo catches up with what this mount knows. A count nobody has
// verified goes on the medium as 0xFFFFFFFF — the format's own spelling
// of "unknown" — rather than as the number the last writer happened to
// leave, which is how a checker ends up reporting a free-cluster
// summary that disagrees with the FAT it just walked.
@ fat_write_fsinfo → b {
    ? == g_vol 0 { ^ F } {}
    : *FatVol v ( fat_vol )
    ? == . v fsinfo_lba 0 { ^ T } {}
    ? ! . v rw { ^ T } {}
    : i free ? >= . v free_count 0 . v free_count 4294967295
    ? ! ( fat_wr32 v . v fsinfo_lba 488 free ) { ^ F } {}
    ^ ( fat_wr32 v . v fsinfo_lba 492 . v hint )
}

// ── whole-sector transfers, around the cache ────────────────────────

// Read `nsec` sectors from `lba` straight into the caller's buffer.
// Any cached copy of those sectors is written back and dropped first,
// so the device's bytes are the current ones — two copies of one sector
// with one of them dirty is the oldest bug in block I/O, and the whole
// reason this is not just a `blk_read`.
@ fat_read_run * FatVol v s buf i lba i nsec → b {
    ? ! ( __cache_drop v lba nsec ) { ^ F } {}
    ^ ( blk_read_raw buf lba nsec )
}

@ fat_write_run * FatVol v s buf i lba i nsec → b {
    ? ! . v rw { ^ F } {}
    ? ! ( __cache_drop v lba nsec ) { ^ F } {}
    ^ ( blk_write_raw buf lba nsec )
}

// ── partial sectors, through the cache ──────────────────────────────
//
// `fat_rd8` in a loop would take a cache lookup per byte. These take
// one for the whole run, which is what makes a 100-byte read of a file
// cost a hundred bytes of copying rather than sixteen hundred slot
// comparisons.

@ fat_copy_out * FatVol v i lba i off s dst i n → b {
    ? || < off 0 > + off n ( blk_sector_size ) { ^ F } {}
    ? <= n 0 { ^ T } {}
    : i slot ( __cache_slot v lba )
    ? < slot 0 { ^ F } {}
    ( nurl_memcpy dst # s + + # i ( vec_data [u] . v cbuf ) * slot ( blk_sector_size ) off n )
    ^ T
}

@ fat_copy_in * FatVol v i lba i off s src i n → b {
    ? ! . v rw { ^ F } {}
    ? || < off 0 > + off n ( blk_sector_size ) { ^ F } {}
    ? <= n 0 { ^ T } {}
    : i slot ( __cache_slot v lba )
    ? < slot 0 { ^ F } {}
    ( nurl_memcpy # s + + # i ( vec_data [u] . v cbuf ) * slot ( blk_sector_size ) off src n )
    : b _d ( vec_set [i] . v cdirty slot 1 )
    ^ T
}
