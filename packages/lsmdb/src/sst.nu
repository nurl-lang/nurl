// packages/lsmdb/src/sst.nu — the immutable on-disk table.
//
// An SSTable is what a memtable becomes when it stops changing: entries
// sorted by (key ascending, sequence descending), cut into ~4 KiB blocks,
// each block CRC-32'd, with a block index and a Bloom filter at the tail
// and a fixed 48-byte footer that names them.
//
//   [data block 0][data block 1]…[index block][bloom block][footer 48B]
//
// Data block payload — entries back to back, sorted:
//   [u32 klen][u32 vlen][u64 seq][u8 kind][key bytes][value bytes]
// followed on disk by [u32 crc32(payload)]. A block is closed once its
// payload reaches SST_BLOCK bytes, so one oversized value still gets a
// block of its own rather than being rejected.
//
// Index block payload — one entry per data block, carrying that block's
// LAST key:
//   [u32 nblocks] then [u32 klen][key][u64 off][u32 payload_len]…
// The last key (not the first) is what makes the search correct when a
// key's versions straddle a block boundary: "first block whose last key
// >= probe" always lands on the block holding the NEWEST version, and the
// reader then continues into the next block for the rest of the run.
//
// Bloom block payload: [u32 nbits][u32 k][bit bytes]. A negative lookup
// that the filter rejects costs no disk read at all — the reason a get
// for an absent key does not have to touch every table in the tree.
//
// Footer: [u64 index_off][u32 index_len][u64 bloom_off][u32 bloom_len]
//         [u64 nentries][u64 max_seq]["LSMDBv1\n"]
//
// Nothing here is read wholesale: open() loads only the index and the
// filter, and every get pulls exactly the one block it needs. A table
// larger than RAM is an ordinary table.
//
//   ( sst_create path )            → !*SstWriter String
//   ( sst_add w key val seq kind ) → !v String     keys must arrive sorted
//   ( sst_finish w )               → !i String     entries written
//   ( sst_open path )              → !*SstReader String
//   ( sst_get r key snap )         → !SstHit String
//   ( sst_cursor r ) / ( sc_seek ) / ( sc_next ) / ( sc_valid ) …
//   ( sst_close r ) / ( sc_free c )

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/deflate.nu`
$ `memtable.nu`

: i SST_BLOCK 4096
: i SST_HDR 17  // u32 klen + u32 vlen + u64 seq + u8 kind
: i SST_FOOTER 48
: i SST_BLOOM_BITS 10  // bits per key → ~1 % false positives at k=7
: i SST_BLOOM_K 7
: i SST_CACHE 32  // resident data blocks per open table

@ __sst_magic → s { ^ `LSMDBv1
` }

// ── Bloom filter ────────────────────────────────────────────────────

// FNV-1a over the key, folded to 64 bits. The filter needs two
// independent hashes; the second is derived by odd-shifting the first
// (Kirsch–Mitzenmacher), which is standard and keeps one pass over the key.
@ lsm_key_hash * u p i off i len → i {
    : ~ i h 1469598103934665603
    : ~ i k 0
    ~ < k len {
        = h ^^ h # i . p + off k
        = h * h 1099511628211
        = k + k 1
    }
    ^ & h 9223372036854775807
}

@ __bloom_bits i nkeys → i {
    : i want * ? > nkeys 0 nkeys 1 SST_BLOOM_BITS
    : i rounded * + / want 8 1 8
    ^ ? < rounded 64 64 rounded
}

// Set the k bit positions of one hash into `bits`.
@ __bloom_set ( Vec u ) bits i nbits i h → v {
    : i h2 | >> h 33 1
    : *u p ( vec_data [u] bits )
    : ~ i i 0
    ~ < i SST_BLOOM_K {
        : i pos % & + h * i h2 9223372036854775807 nbits
        : i byte / pos 8
        : i cur # i . p byte
        = . p byte # u | cur << 1 % pos 8
        = i + i 1
    }
}

@ __bloom_test ( Vec u ) bits i nbits i h → b {
    ? <= nbits 0 { ^ T } {}
    : i h2 | >> h 33 1
    : *u p ( vec_data [u] bits )
    : ~ i i 0
    ~ < i SST_BLOOM_K {
        : i pos % & + h * i h2 9223372036854775807 nbits
        : i byte / pos 8
        ? == 0 & # i . p byte << 1 % pos 8 { ^ F } {}
        = i + i 1
    }
    ^ T
}

// ── writer ──────────────────────────────────────────────────────────

: SstWriter {
    File f
    ( Vec u ) buf  // current block payload
    ( Vec u ) index  // index payload so far
    ( Vec i ) hashes  // one key hash per entry, for the filter
    i off  // next file offset to write at
    i blkoff  // file offset of the block being built
    i count
    i maxseq
    i nblocks
    i lastkoff  // offset of the last entry's key inside buf
    i lastklen
    i failed
    Crc32 crc
}

@ sst_create s path → !*SstWriter String {
    : !File IoErr fr ( file_create path )
    ?? fr {
        T f → {
            : *SstWriter w # *SstWriter ( nurl_alloc Z SstWriter )
            = . w f f
            = . w buf ( vec_with_cap [u] + SST_BLOCK 1024 )
            = . w index ( vec_new [u] )
            = . w hashes ( vec_new [i] )
            = . w off 0
            = . w blkoff 0
            = . w count 0
            = . w maxseq 0
            = . w nblocks 0
            = . w lastkoff 0
            = . w lastklen 0
            = . w failed 0
            = . w crc ( crc32_ctx )
            ^ @ !*SstWriter String { T w }
        }
        F _ → {
            : String msg ( string_from `lsmdb: cannot create table ` )
            ( string_push_str msg path )
            ^ @ !*SstWriter String { F msg }
        }
    }
}

@ __sstw_free * SstWriter w → v {
    ( crc32_ctx_free . w crc )
    ( vec_free [u] . w buf )
    ( vec_free [u] . w index )
    ( vec_free [i] . w hashes )
    ( nurl_free # s w )
}

// Close the current block: append its CRC trailer, write it, and record
// (last key, offset, payload length) in the index.
@ __sst_flush_block * SstWriter w → !v String {
    : i plen ( vec_len [u] . w buf )
    ? == plen 0 { ^ @ !v String { T 0 } } {}
    : i crc ( crc32_ctx_hash . w crc . w buf )

    // Index entry first — it reads the last key out of the payload,
    // before the CRC trailer lands on the end of the same buffer.
    ( bytes_push_u32_le . w index # u32 . w lastklen )
    ( vec_extend_range [u] . w index . w buf . w lastkoff . w lastklen )
    ( bytes_push_u64_le . w index # u64 . w blkoff )
    ( bytes_push_u32_le . w index # u32 plen )

    ( bytes_push_u32_le . w buf # u32 crc )
    : !v IoErr wr ( file_write_chunk . w f . w buf )
    ?? wr {
        T _ → {}
        F _ → {
            = . w failed 1
            ^ @ !v String { F ( string_from `lsmdb: table write failed (disk full?)` ) }
        }
    }
    = . w off + . w off + plen 4
    = . w blkoff . w off
    = . w nblocks + . w nblocks 1
    ( vec_clear [u] . w buf )
    ^ @ !v String { T 0 }
}

// Append one entry. Keys must arrive in the package's total order —
// the memtable walk and the compaction merge both produce exactly that.
@ sst_add * SstWriter w ( Vec u ) key ( Vec u ) val i seq i kind → !v String {
    : i kl ( vec_len [u] key )
    : i vl ? == kind MT_PUT ( vec_len [u] val ) 0
    ( bytes_push_u32_le . w buf # u32 kl )
    ( bytes_push_u32_le . w buf # u32 vl )
    ( bytes_push_u64_le . w buf # u64 seq )
    ( vec_push [u] . w buf # u kind )
    = . w lastkoff ( vec_len [u] . w buf )
    = . w lastklen kl
    ( vec_extend [u] . w buf key )
    ? > vl 0 { ( vec_extend [u] . w buf val ) } {}

    ( vec_push [i] . w hashes ( lsm_key_hash ( vec_data [u] key ) 0 kl ) )
    = . w count + . w count 1
    ? > seq . w maxseq { = . w maxseq seq } {}

    ? >= ( vec_len [u] . w buf ) SST_BLOCK { ^ ( __sst_flush_block w ) } {}
    ^ @ !v String { T 0 }
}

@ __sst_write_tail * SstWriter w ( Vec u ) payload → !i String {
    : i at . w off
    : i crc ( crc32_ctx_hash . w crc payload )
    ( bytes_push_u32_le payload # u32 crc )
    : !v IoErr wr ( file_write_chunk . w f payload )
    ?? wr {
        T _ → { = . w off + . w off ( vec_len [u] payload ) ^ @ !i String { T at } }
        F _ → { ^ @ !i String { F ( string_from `lsmdb: table write failed (disk full?)` ) } }
    }
}

// Flush the tail block, emit the filter, the index and the footer, then
// fsync. When this returns the table is durable and self-describing;
// only after that may a manifest name it.
@ sst_finish * SstWriter w → !i String {
    : !v String fb ( __sst_flush_block w )
    ?? fb { T _ → {} F e → { ( file_close . w f ) ( __sstw_free w ) ^ @ !i String { F e } } }

    : i nkeys ( vec_len [i] . w hashes )
    : i nbits ( __bloom_bits nkeys )
    : ( Vec u ) bloom ( vec_new [u] )
    ( bytes_push_u32_le bloom # u32 nbits )
    ( bytes_push_u32_le bloom # u32 SST_BLOOM_K )
    : i nbytes / nbits 8
    : ( Vec u ) bits ( vec_with_cap [u] nbytes )
    : ~ i z 0
    ~ < z nbytes { ( vec_push [u] bits # u 0 ) = z + z 1 }
    : ~ i h 0
    ~ < h nkeys {
        ( __bloom_set bits nbits ?? ( vec_get [i] . w hashes h ) { T x → x F _ → 0 } )
        = h + h 1
    }
    ( vec_extend [u] bloom bits )
    ( vec_free [u] bits )

    : ( Vec u ) idx ( vec_new [u] )
    ( bytes_push_u32_le idx # u32 . w nblocks )
    ( vec_extend [u] idx . w index )
    : i idx_payload ( vec_len [u] idx )

    : !i String ir ( __sst_write_tail w idx )
    ( vec_free [u] idx )
    : ~ i index_off 0
    ?? ir { T o → { = index_off o } F e → {
            ( vec_free [u] bloom ) ( file_close . w f ) ( __sstw_free w )
            ^ @ !i String { F e } } }

    : i bloom_payload ( vec_len [u] bloom )
    : !i String br ( __sst_write_tail w bloom )
    ( vec_free [u] bloom )
    : ~ i bloom_off 0
    ?? br { T o → { = bloom_off o } F e → {
            ( file_close . w f ) ( __sstw_free w )
            ^ @ !i String { F e } } }

    : ( Vec u ) foot ( vec_with_cap [u] SST_FOOTER )
    ( bytes_push_u64_le foot # u64 index_off )
    ( bytes_push_u32_le foot # u32 idx_payload )
    ( bytes_push_u64_le foot # u64 bloom_off )
    ( bytes_push_u32_le foot # u32 bloom_payload )
    ( bytes_push_u64_le foot # u64 . w count )
    ( bytes_push_u64_le foot # u64 . w maxseq )
    ( bytes_extend_str foot ( __sst_magic ) )
    : !v IoErr fw ( file_write_chunk . w f foot )
    ( vec_free [u] foot )
    : i n . w count
    : ~ b ok T
    ?? fw { T _ → {} F _ → { = ok F } }
    ?? ( file_sync . w f ) { T _ → {} F _ → { = ok F } }
    ( file_close . w f )
    ( __sstw_free w )
    ? ok {} { ^ @ !i String { F ( string_from `lsmdb: table write failed (disk full?)` ) } }
    ^ @ !i String { T n }
}

// ── reader ──────────────────────────────────────────────────────────

: SstReader {
    File f
    String path
    ( Vec u ) ikeys  // concatenated per-block last keys
    ( Vec i ) ikoff
    ( Vec i ) iklen
    ( Vec i ) iboff  // block offset in the file
    ( Vec i ) iblen  // block payload length
    ( Vec u ) bloom  // bit bytes only
    i nbits
    i nblocks
    i nentries
    i maxseq
    i filesize
    i reads  // blocks actually pulled off disk
    i filtered  // gets the filter answered without a read
    i hits  // blocks served from the cache
    Crc32 crc  // one CRC table for the life of the reader
    ( Vec ( Vec u ) ) cache  // SST_CACHE slots, direct-mapped by block index
    ( Vec i ) cache_bi  // which block each slot holds, -1 = empty
}

: SstHit {
    i found
    i kind
    i seq
    ( Vec u ) val
}

@ sst_hit_free SstHit h → v { ( vec_free [u] . h val ) }

@ __sst_err s path s what → String {
    : String msg ( string_from `lsmdb: ` )
    ( string_push_str msg path )
    ( string_push_str msg `: ` )
    ( string_push_str msg what )
    ^ msg
}

// Read `n` bytes at `off` and prove them against their CRC trailer.
// Returns the payload only. A checksum mismatch is an error — never
// data: a torn or rotted block must not surface as a value.
@ __sst_read_verified * SstReader r i off i plen → !( Vec u ) String {
    : !( Vec u ) IoErr rr ( file_read_at . r f off + plen 4 )
    ?? rr {
        T raw → {
            ? != ( vec_len [u] raw ) + plen 4 {
                ( vec_free [u] raw )
                ^ @ !( Vec u ) String { F ( __sst_err ( string_data . r path ) `truncated block (file shorter than its index says)` ) }
            } {}
            : i want ?? ( bytes_read_u32_le raw plen ) { T x → # i x F _ → 0 }
            : ( Vec u ) payload ( _mt_slice raw 0 plen )
            ( vec_free [u] raw )
            : i got ( crc32_ctx_hash . r crc payload )
            ? == got want { ^ @ !( Vec u ) String { T payload } } {}
            ( vec_free [u] payload )
            ^ @ !( Vec u ) String { F ( __sst_err ( string_data . r path ) `CHECKSUM MISMATCH — block is corrupt` ) }
        }
        F _ → {
            ^ @ !( Vec u ) String { F ( __sst_err ( string_data . r path ) `cannot read block` ) }
        }
    }
}

@ sst_open s path → !*SstReader String {
    : !File IoErr fr ( file_open path )
    : ~ File f @ File { # s 0 }
    ?? fr { T h → { = f h } F _ → {
            ^ @ !*SstReader String { F ( __sst_err path `cannot open table` ) } } }

    : *SstReader r # *SstReader ( nurl_alloc Z SstReader )
    = . r f f
    = . r path ( string_from path )
    = . r ikeys ( vec_new [u] )
    = . r ikoff ( vec_new [i] )
    = . r iklen ( vec_new [i] )
    = . r iboff ( vec_new [i] )
    = . r iblen ( vec_new [i] )
    = . r bloom ( vec_new [u] )
    = . r nbits 0
    = . r nblocks 0
    = . r nentries 0
    = . r maxseq 0
    = . r filesize 0
    = . r reads 0
    = . r filtered 0
    = . r hits 0
    = . r crc ( crc32_ctx )
    = . r cache ( vec_with_cap [( Vec u )] SST_CACHE )
    = . r cache_bi ( vec_with_cap [i] SST_CACHE )
    : ~ i cs 0
    ~ < cs SST_CACHE {
        ( vec_push [( Vec u )] . r cache ( vec_new [u] ) )
        ( vec_push [i] . r cache_bi -1 )
        = cs + cs 1
    }

    : !i IoErr sr ( file_seek f 0 FS_SEEK_END )
    ?? sr { T sz → { = . r filesize sz } F _ → {
            ( sst_close r )
            ^ @ !*SstReader String { F ( __sst_err path `cannot size table` ) } } }
    ? < . r filesize SST_FOOTER {
        ( sst_close r )
        ^ @ !*SstReader String { F ( __sst_err path `too short to be a table` ) }
    } {}

    : !( Vec u ) IoErr foot ( file_read_at f - . r filesize SST_FOOTER SST_FOOTER )
    : ~ ( Vec u ) fb ( vec_new [u] )
    ?? foot { T v → { ( vec_free [u] fb ) = fb v } F _ → {
            ( sst_close r )
            ^ @ !*SstReader String { F ( __sst_err path `cannot read footer` ) } } }
    ? != ( vec_len [u] fb ) SST_FOOTER {
        ( vec_free [u] fb ) ( sst_close r )
        ^ @ !*SstReader String { F ( __sst_err path `short footer` ) }
    } {}
    : s magic ( __sst_magic )
    : ~ b good T
    : ~ i mi 0
    ~ < mi 8 {
        : i c ?? ( vec_get [u] fb + 40 mi ) { T x → # i x F _ → 0 }
        ? != c ( nurl_str_get magic mi ) { = good F } {}
        = mi + mi 1
    }
    ? good {} {
        ( vec_free [u] fb ) ( sst_close r )
        ^ @ !*SstReader String { F ( __sst_err path `not an lsmdb table (bad magic)` ) }
    }
    : i index_off ?? ( bytes_read_u64_le fb 0 ) { T x → # i x F _ → 0 }
    : i index_len ?? ( bytes_read_u32_le fb 8 ) { T x → # i x F _ → 0 }
    : i bloom_off ?? ( bytes_read_u64_le fb 12 ) { T x → # i x F _ → 0 }
    : i bloom_len ?? ( bytes_read_u32_le fb 20 ) { T x → # i x F _ → 0 }
    = . r nentries ?? ( bytes_read_u64_le fb 24 ) { T x → # i x F _ → 0 }
    = . r maxseq ?? ( bytes_read_u64_le fb 32 ) { T x → # i x F _ → 0 }
    ( vec_free [u] fb )

    : !( Vec u ) String ir ( __sst_read_verified r index_off index_len )
    : ~ ( Vec u ) idx ( vec_new [u] )
    ?? ir { T v → { ( vec_free [u] idx ) = idx v } F e → {
            ( sst_close r ) ^ @ !*SstReader String { F e } } }
    : !v String pr ( __sst_parse_index r idx )
    ( vec_free [u] idx )
    ?? pr { T _ → {} F e → { ( sst_close r ) ^ @ !*SstReader String { F e } } }

    : !( Vec u ) String br ( __sst_read_verified r bloom_off bloom_len )
    ?? br {
        T bl → {
            = . r nbits ?? ( bytes_read_u32_le bl 0 ) { T x → # i x F _ → 0 }
            ( vec_extend_range [u] . r bloom bl 8 - ( vec_len [u] bl ) 8 )
            ( vec_free [u] bl )
        }
        F e → { ( sst_close r ) ^ @ !*SstReader String { F e } }
    }
    ^ @ !*SstReader String { T r }
}

@ __sst_parse_index * SstReader r ( Vec u ) idx → !v String {
    : i n ( vec_len [u] idx )
    ? < n 4 { ^ @ !v String { F ( __sst_err ( string_data . r path ) `malformed index` ) } } {}
    : i nb ?? ( bytes_read_u32_le idx 0 ) { T x → # i x F _ → 0 }
    : ~ i pos 4
    : ~ i k 0
    ~ < k nb {
        ? > + pos 4 n { ^ @ !v String { F ( __sst_err ( string_data . r path ) `malformed index` ) } } {}
        : i kl ?? ( bytes_read_u32_le idx pos ) { T x → # i x F _ → 0 }
        = pos + pos 4
        ? > + pos + kl 12 n { ^ @ !v String { F ( __sst_err ( string_data . r path ) `malformed index` ) } } {}
        ( vec_push [i] . r ikoff ( vec_len [u] . r ikeys ) )
        ( vec_push [i] . r iklen kl )
        ( vec_extend_range [u] . r ikeys idx pos kl )
        = pos + pos kl
        ( vec_push [i] . r iboff ?? ( bytes_read_u64_le idx pos ) { T x → # i x F _ → 0 } )
        = pos + pos 8
        ( vec_push [i] . r iblen ?? ( bytes_read_u32_le idx pos ) { T x → # i x F _ → 0 } )
        = pos + pos 4
        = k + k 1
    }
    = . r nblocks nb
    ^ @ !v String { T 0 }
}

@ sst_close * SstReader r → v {
    ( crc32_ctx_free . r crc )
    ( vec_free_with [( Vec u )] . r cache \ ( Vec u ) b → v { ( vec_free [u] b ) } )
    ( vec_free [i] . r cache_bi )
    ( file_close . r f )
    ( string_free . r path )
    ( vec_free [u] . r ikeys )
    ( vec_free [i] . r ikoff )
    ( vec_free [i] . r iklen )
    ( vec_free [i] . r iboff )
    ( vec_free [i] . r iblen )
    ( vec_free [u] . r bloom )
    ( nurl_free # s r )
}

@ sst_entries * SstReader r → i { ^ . r nentries }

@ sst_maxseq * SstReader r → i { ^ . r maxseq }

@ sst_blocks * SstReader r → i { ^ . r nblocks }

@ sst_filesize * SstReader r → i { ^ . r filesize }

@ sst_reads * SstReader r → i { ^ . r reads }

@ sst_filtered * SstReader r → i { ^ . r filtered }

@ sst_hits * SstReader r → i { ^ . r hits }

// First block whose LAST key >= probe, or nblocks if the probe is past
// the end of the table. Binary search over the index.
@ __sst_find_block * SstReader r * u kp i klen → i {
    : *u ip ( vec_data [u] . r ikeys )
    : ~ i lo 0
    : ~ i hi . r nblocks
    ~ < lo hi {
        : i mid / + lo hi 2
        : i c ( lsm_bytes_cmp_raw ip ( _mt_iat . r ikoff mid ) ( _mt_iat . r iklen mid ) kp 0 klen )
        ? < c 0 { = lo + mid 1 } { = hi mid }
    }
    ^ lo
}

// Load a data block, from the cache when it is there.
//
// A read that hits the cache skips both the syscall and the checksum —
// the block was verified when it was read, and nothing can rot in RAM
// that would not equally rot in the copy we would re-verify. That is the
// same rule LevelDB's block cache follows, and it is why a scan (or any
// workload with locality) costs one verification per block rather than
// one per key: at ~100 entries to a 4 KiB block, that is the difference
// between checksumming 4 KiB per read and 40 bytes.
@ __sst_load_block * SstReader r i bi → !( Vec u ) String {
    : i slot % bi SST_CACHE
    ? == ( _mt_iat . r cache_bi slot ) bi {
        ?? ( vec_get [( Vec u )] . r cache slot ) {
            T cached → {
                = . r hits + . r hits 1
                ^ @ !( Vec u ) String { T ( vec_clone [u] cached ) }
            }
            F _ → {}
        }
    } {}
    = . r reads + . r reads 1
    : !( Vec u ) String rr ( __sst_read_verified r ( _mt_iat . r iboff bi ) ( _mt_iat . r iblen bi ) )
    ?? rr {
        T blk → {
            ?? ( vec_get [( Vec u )] . r cache slot ) {
                T old → { ( vec_free [u] old ) }
                F _ → {}
            }
            : b _ok ( vec_set [( Vec u )] . r cache slot ( vec_clone [u] blk ) )
            : b _ok2 ( vec_set [i] . r cache_bi slot bi )
            ^ @ !( Vec u ) String { T blk }
        }
        F e → { ^ @ !( Vec u ) String { F e } }
    }
}

// Decode the entry at `pos`; returns the total entry length, or 0 if the
// block does not hold a whole entry there.
@ __sst_entry_len ( Vec u ) blk i pos → i {
    : i n ( vec_len [u] blk )
    ? > + pos SST_HDR n { ^ 0 } {}
    : i kl ?? ( bytes_read_u32_le blk pos ) { T x → # i x F _ → 0 }
    : i vl ?? ( bytes_read_u32_le blk + pos 4 ) { T x → # i x F _ → 0 }
    : i total + SST_HDR + kl vl
    ? > + pos total n { ^ 0 } {}
    ^ total
}

// ── point lookup ────────────────────────────────────────────────────

// The newest version of `key` with seq <= snap. `found` is 0 when the
// table has nothing for the key; a tombstone comes back as found=1 with
// kind=MT_DEL, which the store must honour as "deleted here, stop".
@ sst_get * SstReader r ( Vec u ) key i snap → !SstHit String {
    : i klen ( vec_len [u] key )
    : *u kp ( vec_data [u] key )
    ? ( __bloom_test . r bloom . r nbits ( lsm_key_hash kp 0 klen ) ) {} {
        = . r filtered + . r filtered 1
        ^ @ !SstHit String { T @ SstHit { 0 MT_PUT 0 ( vec_new [u] ) } }
    }
    : ~ i bi ( __sst_find_block r kp klen )
    : ~ b scanning T
    ~ & scanning < bi . r nblocks {
        : !( Vec u ) String br ( __sst_load_block r bi )
        ?? br {
            T blk → {
                : i n ( vec_len [u] blk )
                : ~ i pos 0
                : ~ b past F
                ~ & ! past < pos n {
                    : i total ( __sst_entry_len blk pos )
                    ? == total 0 { = past T } {
                        : i kl ?? ( bytes_read_u32_le blk pos ) { T x → # i x F _ → 0 }
                        : i vl ?? ( bytes_read_u32_le blk + pos 4 ) { T x → # i x F _ → 0 }
                        : i seq ?? ( bytes_read_u64_le blk + pos 8 ) { T x → # i x F _ → 0 }
                        : i kind ?? ( vec_get [u] blk + pos 16 ) { T x → # i x F _ → 0 }
                        : i koff + pos SST_HDR
                        : i c ( lsm_bytes_cmp_raw ( vec_data [u] blk ) koff kl kp 0 klen )
                        ? > c 0 {
                            // past the key entirely — no older versions anywhere
                            = past T = scanning F
                        } {
                            ? & == c 0 <= seq snap {
                                : ( Vec u ) val ( _mt_slice blk + koff kl vl )
                                ( vec_free [u] blk )
                                ^ @ !SstHit String { T @ SstHit { 1 kind seq val } }
                            } {}
                        }
                        = pos + pos total
                    }
                }
                ( vec_free [u] blk )
                // Ran off the end of the block still inside (or before)
                // the key's run: the older versions continue in the next
                // block. This is the boundary case the last-key index is
                // built to make safe.
                ? scanning { = bi + bi 1 } {}
            }
            F e → { ^ @ !SstHit String { F e } }
        }
    }
    ^ @ !SstHit String { T @ SstHit { 0 MT_PUT 0 ( vec_new [u] ) } }
}

// ── cursor (ordered iteration, one block resident at a time) ────────

: SstCursor {
    * SstReader r
    ( Vec u ) blk
    i bi
    i pos
    i valid
    i kl
    i vl
    i seq
    i kind
    i koff
    i failed
    String err
}

@ sst_cursor * SstReader r → *SstCursor {
    : *SstCursor c # *SstCursor ( nurl_alloc Z SstCursor )
    = . c r r
    = . c blk ( vec_new [u] )
    = . c bi 0
    = . c pos 0
    = . c valid 0
    = . c kl 0
    = . c vl 0
    = . c seq 0
    = . c kind MT_PUT
    = . c koff 0
    = . c failed 0
    = . c err ( string_new )
    ^ c
}

@ sc_free * SstCursor c → v {
    ( vec_free [u] . c blk )
    ( string_free . c err )
    ( nurl_free # s c )
}

@ sc_valid * SstCursor c → b { ^ == . c valid 1 }

@ sc_failed * SstCursor c → b { ^ == . c failed 1 }

@ sc_err * SstCursor c → s { ^ ( string_data . c err ) }

@ sc_seq * SstCursor c → i { ^ . c seq }

@ sc_kind * SstCursor c → i { ^ . c kind }

@ sc_klen * SstCursor c → i { ^ . c kl }

@ sc_kptr * SstCursor c → *u { ^ ( vec_data [u] . c blk ) }

@ sc_koff * SstCursor c → i { ^ . c koff }

@ sc_key * SstCursor c → ( Vec u ) { ^ ( _mt_slice . c blk . c koff . c kl ) }

@ sc_val * SstCursor c → ( Vec u ) { ^ ( _mt_slice . c blk + . c koff . c kl . c vl ) }

@ __sc_fail * SstCursor c String e → v {
    = . c failed 1
    = . c valid 0
    ( string_free . c err )
    = . c err e
}

// Decode the entry the cursor's `pos` points at.
@ __sc_decode * SstCursor c → b {
    : i total ( __sst_entry_len . c blk . c pos )
    ? == total 0 { ^ F } {}
    = . c kl ?? ( bytes_read_u32_le . c blk . c pos ) { T x → # i x F _ → 0 }
    = . c vl ?? ( bytes_read_u32_le . c blk + . c pos 4 ) { T x → # i x F _ → 0 }
    = . c seq ?? ( bytes_read_u64_le . c blk + . c pos 8 ) { T x → # i x F _ → 0 }
    = . c kind ?? ( vec_get [u] . c blk + . c pos 16 ) { T x → # i x F _ → 0 }
    = . c koff + . c pos SST_HDR
    = . c valid 1
    ^ T
}

@ __sc_load * SstCursor c i bi → b {
    : *SstReader rr . c r
    ? >= bi . rr nblocks { = . c valid 0 ^ F } {}
    : !( Vec u ) String br ( __sst_load_block . c r bi )
    ?? br {
        T blk → {
            ( vec_free [u] . c blk )
            = . c blk blk
            = . c bi bi
            = . c pos 0
            ^ ( __sc_decode c )
        }
        F e → { ( __sc_fail c e ) ^ F }
    }
}

@ sc_first * SstCursor c → v {
    = . c valid 0
    : b _ok ( __sc_load c 0 )
}

@ sc_next * SstCursor c → v {
    ? == . c valid 1 {} { ^ }
    = . c pos + . c pos + SST_HDR + . c kl . c vl
    ? ( __sc_decode c ) {} {
        : b _ok ( __sc_load c + . c bi 1 )
    }
}

// Position at the first entry >= (key, snap).
@ sc_seek * SstCursor c ( Vec u ) key i snap → v {
    = . c valid 0
    : i klen ( vec_len [u] key )
    : *u kp ( vec_data [u] key )
    : i bi ( __sst_find_block . c r kp klen )
    ? ( __sc_load c bi ) {} { ^ }
    : ~ b searching T
    ~ searching {
        ? == . c valid 1 {} { = searching F }
        ? searching {
            : i cc ( lsm_bytes_cmp_raw ( vec_data [u] . c blk ) . c koff . c kl kp 0 klen )
            ? | > cc 0 & == cc 0 <= . c seq snap { = searching F } { ( sc_next c ) }
        } {}
    }
}
