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
//   ( sst_create path )            → !SstWriter String
//   ( sst_add w key val seq kind ) → !v String     keys must arrive sorted
//   ( sst_finish w )               → !i String     entries written
//   ( sst_open path )              → !SstReader String
//   ( sst_get r key snap )         → !SstHit String
//   ( sst_cursor r ) / ( sc_seek ) / ( sc_next ) / ( sc_valid ) …
//   ( sst_close r ) / ( sc_free c )  early release (optional)
//
// SstWriter, SstReader and SstCursor are handles: every copy is the same
// object, and the last owner releases it — a writer or reader closes its
// file, a cursor lets go of the reader it walks (it holds a share, so a
// table outlives every cursor over it).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/deflate.nu`
$ `memtable.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/slice.nu`

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
@ lsm_key_hash ( Slice u ) p → i {
    : ~ i h 1469598103934665603
    : ~ i k 0
    : i len ( slice_len [u] p )
    ~ < k len {
        = h ^^ h # i ( slice_at [u] p k )
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
    : ( Slice u ) p ( slice_from_vec [u] bits )
    : ~ i i 0
    ~ < i SST_BLOOM_K {
        : i pos % & + h * i h2 9223372036854775807 nbits
        : i byte / pos 8
        : i cur # i ( slice_at [u] p byte )
        ( slice_put [u] p byte # u | cur << 1 % pos 8 )
        = i + i 1
    }
}

@ __bloom_test ( Vec u ) bits i nbits i h → b {
    ? <= nbits 0 { ^ T } {}
    : i h2 | >> h 33 1
    : ( Slice u ) p ( slice_from_vec [u] bits )
    : ~ i i 0
    ~ < i SST_BLOOM_K {
        : i pos % & + h * i h2 9223372036854775807 nbits
        : i byte / pos 8
        ? == 0 & # i ( slice_at [u] p byte ) << 1 % pos 8 { ^ F } {}
        = i + i 1
    }
    ^ T
}

// ── writer ──────────────────────────────────────────────────────────

: SstWriterImpl {
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

// A writer nobody finished (a failed flush) still closes its file.
% Drop SstWriterImpl { @ drop SstWriterImpl w → v { ( file_close . w f ) } }

: SstWriter { ( Rc SstWriterImpl ) l }

@ SstWriter_share SstWriter h → SstWriter { ^ @ SstWriter { ( rc_clone [SstWriterImpl] . h l ) } }

@ SstWriter_drop sink SstWriter h → v {}

@ sst_create s path → !SstWriter String {
    : !File IoErr fr ( file_create path )
    ?? fr {
        T f → {
            : SstWriterImpl w @ SstWriterImpl { f ( vec_with_cap [u] + SST_BLOCK 1024 ) ( vec_new [u] ) ( vec_new [i] )
                0 0 0 0 0 0 0 0 ( crc32_ctx ) }
            ^ @ !SstWriter String { T @ SstWriter { ( rc_new [SstWriterImpl] w ) } }
        }
        F _ → {
            : String msg ( string_from `lsmdb: cannot create table ` )
            ( string_push_str msg path )
            ^ @ !SstWriter String { F msg }
        }
    }
}

// The table file is finished with (written out, or given up on): close
// it now, so the reader that opens it next sees every byte.
@ __sstw_close inout SstWriterImpl w → v {
    ( file_close . w f )
    // The closed file's handle leaves the writer (dropped here).
    = . w f ( file_none )
}

// Close the current block: append its CRC trailer, write it, and record
// (last key, offset, payload length) in the index.
@ __sst_flush_block inout SstWriterImpl w → !v String {
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
@ sst_add SstWriter w__h ( Vec u ) key ( Vec u ) val i seq i kind → !v String {
    : ~ SstWriterImpl w ( rc_take [SstWriterImpl] . w__h l )
    : !v String __res ( __sst_add_in w key val seq kind )
    ( rc_restore [SstWriterImpl] . w__h l w )
    ^ __res
}

@ __sst_add_in inout SstWriterImpl w ( Vec u ) key ( Vec u ) val i seq i kind → !v String {
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

    ( vec_push [i] . w hashes ( lsm_key_hash ( slice_from_vec [u] key ) ) )
    = . w count + . w count 1
    ? > seq . w maxseq { = . w maxseq seq } {}

    ? >= ( vec_len [u] . w buf ) SST_BLOCK { ^ ( __sst_flush_block w ) } {}
    ^ @ !v String { T 0 }
}

@ __sst_write_tail inout SstWriterImpl w ( Vec u ) payload → !i String {
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
@ sst_finish SstWriter w__h → !i String {
    : ~ SstWriterImpl w ( rc_take [SstWriterImpl] . w__h l )
    : !i String __res ( __sst_finish_in w )
    ( rc_restore [SstWriterImpl] . w__h l w )
    ^ __res
}

@ __sst_finish_in inout SstWriterImpl w → !i String {
    : !v String fb ( __sst_flush_block w )
    ?? fb { T _ → {} F e → { ( __sstw_close w ) ^ @ !i String { F e } } }

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

    : ( Vec u ) idx ( vec_new [u] )
    ( bytes_push_u32_le idx # u32 . w nblocks )
    ( vec_extend [u] idx . w index )
    : i idx_payload ( vec_len [u] idx )

    : !i String ir ( __sst_write_tail w idx )
    : ~ i index_off 0
    ?? ir { T o → { = index_off o } F e → {
            ( __sstw_close w )
            ^ @ !i String { F e } } }

    : i bloom_payload ( vec_len [u] bloom )
    : !i String br ( __sst_write_tail w bloom )
    : ~ i bloom_off 0
    ?? br { T o → { = bloom_off o } F e → {
            ( __sstw_close w )
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
    : i n . w count
    : ~ b ok T
    ?? fw { T _ → {} F _ → { = ok F } }
    ?? ( file_sync . w f ) { T _ → {} F _ → { = ok F } }
    ( __sstw_close w )
    ? ok {} { ^ @ !i String { F ( string_from `lsmdb: table write failed (disk full?)` ) } }
    ^ @ !i String { T n }
}

// ── reader ──────────────────────────────────────────────────────────

: SstReaderImpl {
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
    i hits  // blocks served from the cache
    Crc32 crc  // one CRC table for the life of the reader
    ( Vec ( Vec u ) ) cache  // SST_CACHE slots, direct-mapped by block index
    ( Vec i ) cache_bi  // which block each slot holds, -1 = empty
}

// The open table file is the reader's one raw resource; its last owner
// closes it (the index, the filter and the block cache go with the drop
// glue).
% Drop SstReaderImpl { @ drop SstReaderImpl r → v { ( file_close . r f ) } }

: SstReader {
    ( Locked SstReaderImpl ) l
    ( Arc SstFilter ) flt
}

// A table's Bloom filter, fixed once the table is open: a get that the
// filter rules out is answered without taking the reader's lock.
: SstFilter {
    ( Vec u ) bloom  // bit bytes only
    i nbits
}

@ SstReader_share SstReader h → SstReader { ^ @ SstReader { ( Locked_share [SstReaderImpl] . h l ) ( arc_clone [SstFilter] . h flt ) } }

@ SstReader_drop sink SstReader h → v {}

: SstHit {
    i found
    i kind
    i seq
    ( Vec u ) val
}

// Let go of `h` now rather than at the end of its owner's scope.
@ sst_hit_free sink SstHit h → v {}

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
@ __sst_read_verified inout SstReaderImpl r i off i plen → !( Vec u ) String {
    : !( Vec u ) IoErr rr ( file_read_at . r f off + plen 4 )
    ?? rr {
        T raw → {
            ? != ( vec_len [u] raw ) + plen 4 {
                ^ @ !( Vec u ) String { F ( __sst_err ( string_data . r path ) `truncated block (file shorter than its index says)` ) }
            } {}
            : i want ?? ( bytes_read_u32_le raw plen ) { T x → # i x F _ → 0 }
            : ( Vec u ) payload ( _mt_slice raw 0 plen )
            : i got ( crc32_ctx_hash . r crc payload )
            ? == got want { ^ @ !( Vec u ) String { T payload } } {}
            ^ @ !( Vec u ) String { F ( __sst_err ( string_data . r path ) `CHECKSUM MISMATCH — block is corrupt` ) }
        }
        F _ → {
            ^ @ !( Vec u ) String { F ( __sst_err ( string_data . r path ) `cannot read block` ) }
        }
    }
}

@ sst_open s path → !SstReader String {
    : !File IoErr fr ( file_open path )
    : ~ File f ( file_none )
    ?? fr { T h → { = f h } F _ → {
            ^ @ !SstReader String { F ( __sst_err path `cannot open table` ) } } }

    // The state first: every early return below lets go of it, and its
    // drop closes the file.
    : ~ SstReaderImpl r @ SstReaderImpl { ( File_share f ) ( string_from path ) ( vec_new [u] ) ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [u] ) 0 0 0 0 0 0 0 ( crc32_ctx )
        ( vec_with_cap [( Vec u )] SST_CACHE ) ( vec_with_cap [i] SST_CACHE ) }
    : ~ i cs 0
    ~ < cs SST_CACHE {
        ( vec_push [( Vec u )] . r cache ( vec_new [u] ) )
        ( vec_push [i] . r cache_bi -1 )
        = cs + cs 1
    }

    : !i IoErr sr ( file_seek f 0 FS_SEEK_END )
    ?? sr { T sz → { = . r filesize sz } F _ → {
            ^ @ !SstReader String { F ( __sst_err path `cannot size table` ) } } }
    ? < . r filesize SST_FOOTER {
        ^ @ !SstReader String { F ( __sst_err path `too short to be a table` ) }
    } {}

    : !( Vec u ) IoErr foot ( file_read_at f - . r filesize SST_FOOTER SST_FOOTER )
    : ~ ( Vec u ) fb ( vec_new [u] )
    ?? foot { T v → { = fb v } F _ → {
            ^ @ !SstReader String { F ( __sst_err path `cannot read footer` ) } } }
    ? != ( vec_len [u] fb ) SST_FOOTER {
        ^ @ !SstReader String { F ( __sst_err path `short footer` ) }
    } {}
    : s magic ( __sst_magic )
    : ( Slice u ) magic_v ( slice_of_str magic )
    : ~ b good T
    : ~ i mi 0
    ~ < mi 8 {
        : i c ?? ( vec_get [u] fb + 40 mi ) { T x → # i x F _ → 0 }
        ? != c ( slice_byte magic_v mi ) { = good F } {}
        = mi + mi 1
    }
    ? good {} {
        ^ @ !SstReader String { F ( __sst_err path `not an lsmdb table (bad magic)` ) }
    }
    : i index_off ?? ( bytes_read_u64_le fb 0 ) { T x → # i x F _ → 0 }
    : i index_len ?? ( bytes_read_u32_le fb 8 ) { T x → # i x F _ → 0 }
    : i bloom_off ?? ( bytes_read_u64_le fb 12 ) { T x → # i x F _ → 0 }
    : i bloom_len ?? ( bytes_read_u32_le fb 20 ) { T x → # i x F _ → 0 }
    = . r nentries ?? ( bytes_read_u64_le fb 24 ) { T x → # i x F _ → 0 }
    = . r maxseq ?? ( bytes_read_u64_le fb 32 ) { T x → # i x F _ → 0 }

    : !( Vec u ) String ir ( __sst_read_verified r index_off index_len )
    : ~ ( Vec u ) idx ( vec_new [u] )
    ?? ir { T v → { = idx v } F e → { ^ @ !SstReader String { F e } } }
    : !v String pr ( __sst_parse_index r idx )
    ?? pr { T _ → {} F e → { ^ @ !SstReader String { F e } } }

    : !( Vec u ) String br ( __sst_read_verified r bloom_off bloom_len )
    ?? br {
        T bl → {
            = . r nbits ?? ( bytes_read_u32_le bl 0 ) { T x → # i x F _ → 0 }
            ( vec_extend_range [u] . r bloom bl 8 - ( vec_len [u] bl ) 8 )
        }
        F e → { ^ @ !SstReader String { F e } }
    }
    : SstFilter flt @ SstFilter { ( vec_clone [u] . r bloom ) . r nbits }
    ^ @ !SstReader String { T @ SstReader { ( locked_new [SstReaderImpl] r ) ( arc_new [SstFilter] flt ) } }
}

@ __sst_parse_index inout SstReaderImpl r ( Vec u ) idx → !v String {
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

// Let go of `r` now rather than at the end of its owner's scope.
@ sst_close sink SstReader r → v {}

@ sst_entries SstReader r__h → i {
    : ~ SstReaderImpl r ( locked_take [SstReaderImpl] . r__h l )
    : i __res ( __sst_entries_in r )
    ( locked_restore [SstReaderImpl] . r__h l r )
    ^ __res
}

@ __sst_entries_in inout SstReaderImpl r → i {
    ^ . r nentries
}

@ sst_maxseq SstReader r__h → i {
    : ~ SstReaderImpl r ( locked_take [SstReaderImpl] . r__h l )
    : i __res ( __sst_maxseq_in r )
    ( locked_restore [SstReaderImpl] . r__h l r )
    ^ __res
}

@ __sst_maxseq_in inout SstReaderImpl r → i {
    ^ . r maxseq
}

@ sst_blocks SstReader r__h → i {
    : ~ SstReaderImpl r ( locked_take [SstReaderImpl] . r__h l )
    : i __res ( __sst_blocks_in r )
    ( locked_restore [SstReaderImpl] . r__h l r )
    ^ __res
}

@ __sst_blocks_in inout SstReaderImpl r → i {
    ^ . r nblocks
}

@ sst_filesize SstReader r__h → i {
    : ~ SstReaderImpl r ( locked_take [SstReaderImpl] . r__h l )
    : i __res ( __sst_filesize_in r )
    ( locked_restore [SstReaderImpl] . r__h l r )
    ^ __res
}

@ __sst_filesize_in inout SstReaderImpl r → i {
    ^ . r filesize
}

@ sst_reads SstReader r__h → i {
    : ~ SstReaderImpl r ( locked_take [SstReaderImpl] . r__h l )
    : i __res ( __sst_reads_in r )
    ( locked_restore [SstReaderImpl] . r__h l r )
    ^ __res
}

@ __sst_reads_in inout SstReaderImpl r → i {
    ^ . r reads
}

@ sst_hits SstReader r__h → i {
    : ~ SstReaderImpl r ( locked_take [SstReaderImpl] . r__h l )
    : i __res ( __sst_hits_in r )
    ( locked_restore [SstReaderImpl] . r__h l r )
    ^ __res
}

@ __sst_hits_in inout SstReaderImpl r → i {
    ^ . r hits
}

// First block whose LAST key >= probe, or nblocks if the probe is past
// the end of the table. Binary search over the index.
@ __sst_find_block SstReaderImpl r ( Slice u ) probe → i {
    : ( Slice u ) ip ( slice_from_vec [u] . r ikeys )
    : ~ i lo 0
    : ~ i hi . r nblocks
    ~ < lo hi {
        : i mid / + lo hi 2
        : i c ( slice_bytes_cmp ( slice_window [u] ip ( _mt_iat . r ikoff mid ) ( _mt_iat . r iklen mid ) ) probe )
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
@ __sst_load_block inout SstReaderImpl r i bi → !( Vec u ) String {
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
            // vec_set drops the block the slot held before
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
// table has nothing for the key, -1 when its filter said so without a
// read (the store counts those); a tombstone comes back as found=1 with
// kind=MT_DEL, which the store must honour as "deleted here, stop".
@ sst_get SstReader r__h ( Vec u ) key i snap → !SstHit String {
    ^ ( sst_get_hashed r__h key ( lsm_key_hash ( slice_from_vec [u] key ) ) snap )
}

// The same with the key's lsm_key_hash already computed — a store asking
// every table for one key hashes it once.
@ sst_get_hashed SstReader r__h ( Vec u ) key i kh i snap → !SstHit String {
    : SstFilter flt ( arc_get [SstFilter] . r__h flt )
    ? ( __bloom_test . flt bloom . flt nbits kh ) {} {
        ^ @ !SstHit String { T @ SstHit { -1 MT_PUT 0 ( vec_new [u] ) } }
    }
    : ~ SstReaderImpl r ( locked_take [SstReaderImpl] . r__h l )
    : !SstHit String __res ( __sst_get_in r key snap )
    ( locked_restore [SstReaderImpl] . r__h l r )
    ^ __res
}

@ __sst_get_in inout SstReaderImpl r ( Vec u ) key i snap → !SstHit String {
    : i klen ( vec_len [u] key )
    : ( Slice u ) kv ( slice_from_vec [u] key )
    : ~ i bi ( __sst_find_block r kv )
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
                        : i c ( slice_bytes_cmp ( slice_window [u] ( slice_from_vec [u] blk ) koff kl ) kv )
                        ? > c 0 {
                            // past the key entirely — no older versions anywhere
                            = past T = scanning F
                        } {
                            ? & == c 0 <= seq snap {
                                : ( Vec u ) val ( _mt_slice blk + koff kl vl )
                                ^ @ !SstHit String { T @ SstHit { 1 kind seq val } }
                            } {}
                        }
                        = pos + pos total
                    }
                }
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

: SstCursorImpl {
    SstReader r  // a share: the table stays open while a cursor walks it
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

: SstCursor { ( Rc SstCursorImpl ) l }

@ SstCursor_share SstCursor h → SstCursor { ^ @ SstCursor { ( rc_clone [SstCursorImpl] . h l ) } }

@ SstCursor_drop sink SstCursor h → v {}

// Package-shared (one underscore): the merge in lsmdb.nu opens each
// cursor once per step and reads its head in place.

@ sst_cursor SstReader r → SstCursor {
    ^ @ SstCursor { ( rc_new [SstCursorImpl] @ SstCursorImpl { ( SstReader_share r ) ( vec_new [u] ) 0 0 0 0 0 0 MT_PUT 0 0 ( string_new ) } ) }
}

// Let go of `c` now rather than at the end of its owner's scope.
@ sc_free sink SstCursor c → v {}

// Everything a merge needs from a cursor's head, read in one go: whether
// it is on an entry (and whether it failed), the key (an owned copy), the
// sequence and the kind.
: ScHead {
    b valid
    b failed
    ( Vec u ) key
    i seq
    i kind
}

@ __sc_head SstCursorImpl c → ScHead {
    : b valid == . c valid 1
    ^ @ ScHead { valid == . c failed 1 ? valid ( _sc_key c ) ( vec_new [u] ) . c seq . c kind }
}

@ sc_head SstCursor h → ScHead {
    : SstCursorImpl c ( rc_take [SstCursorImpl] . h l )
    : ScHead r ( __sc_head c )
    ( rc_restore [SstCursorImpl] . h l c )
    ^ r
}

// Step to the next entry and read its head (sc_next, then sc_head).
@ sc_next_head SstCursor h → ScHead {
    : ~ SstCursorImpl c ( rc_take [SstCursorImpl] . h l )
    ( _sc_next c )
    : ScHead r ( __sc_head c )
    ( rc_restore [SstCursorImpl] . h l c )
    ^ r
}

@ sc_valid SstCursor c__h → b {
    : ~ SstCursorImpl c ( rc_take [SstCursorImpl] . c__h l )
    : b __res ( __sc_valid_in c )
    ( rc_restore [SstCursorImpl] . c__h l c )
    ^ __res
}

@ __sc_valid_in inout SstCursorImpl c → b {
    ^ == . c valid 1
}

@ sc_failed SstCursor c__h → b {
    : ~ SstCursorImpl c ( rc_take [SstCursorImpl] . c__h l )
    : b __res ( __sc_failed_in c )
    ( rc_restore [SstCursorImpl] . c__h l c )
    ^ __res
}

@ __sc_failed_in inout SstCursorImpl c → b {
    ^ == . c failed 1
}

@ sc_err SstCursor c__h → String {
    : SstCursorImpl c ( rc_take [SstCursorImpl] . c__h l )
    : String r ( string_from ( string_data . c err ) )
    ( rc_restore [SstCursorImpl] . c__h l c )
    ^ r
}

@ sc_seq SstCursor c__h → i {
    : ~ SstCursorImpl c ( rc_take [SstCursorImpl] . c__h l )
    : i __res ( __sc_seq_in c )
    ( rc_restore [SstCursorImpl] . c__h l c )
    ^ __res
}

@ __sc_seq_in inout SstCursorImpl c → i {
    ^ . c seq
}

@ sc_kind SstCursor c__h → i {
    : ~ SstCursorImpl c ( rc_take [SstCursorImpl] . c__h l )
    : i __res ( __sc_kind_in c )
    ( rc_restore [SstCursorImpl] . c__h l c )
    ^ __res
}

@ __sc_kind_in inout SstCursorImpl c → i {
    ^ . c kind
}

@ sc_klen SstCursor c__h → i {
    : ~ SstCursorImpl c ( rc_take [SstCursorImpl] . c__h l )
    : i __res ( __sc_klen_in c )
    ( rc_restore [SstCursorImpl] . c__h l c )
    ^ __res
}

@ __sc_klen_in inout SstCursorImpl c → i {
    ^ . c kl
}

@ sc_koff SstCursor c__h → i {
    : ~ SstCursorImpl c ( rc_take [SstCursorImpl] . c__h l )
    : i __res ( __sc_koff_in c )
    ( rc_restore [SstCursorImpl] . c__h l c )
    ^ __res
}

@ __sc_koff_in inout SstCursorImpl c → i {
    ^ . c koff
}

@ sc_key SstCursor h → ( Vec u ) {
    : SstCursorImpl c ( rc_take [SstCursorImpl] . h l )
    : ( Vec u ) r ( _sc_key c )
    ( rc_restore [SstCursorImpl] . h l c )
    ^ r
}

@ sc_val SstCursor h → ( Vec u ) {
    : SstCursorImpl c ( rc_take [SstCursorImpl] . h l )
    : ( Vec u ) r ( _sc_val c )
    ( rc_restore [SstCursorImpl] . h l c )
    ^ r
}

@ _sc_key SstCursorImpl c → ( Vec u ) { ^ ( _mt_slice . c blk . c koff . c kl ) }

@ _sc_val SstCursorImpl c → ( Vec u ) { ^ ( _mt_slice . c blk + . c koff . c kl . c vl ) }

// The cursor's head against (key, seq) in merge order — key ascending,
// the newer version first: <0 when the head sorts first.
@ __sc_head_cmp_view SstCursorImpl c ( Slice u ) key i seq → i {
    : i cmp ( slice_bytes_cmp ( slice_window [u] ( slice_from_vec [u] . c blk ) . c koff . c kl ) key )
    ? != cmp 0 { ^ cmp } {}
    ? == . c seq seq { ^ 0 } {}
    ^ ? > . c seq seq -1 1
}

@ sc_head_cmp SstCursor h ( Slice u ) key i seq → i {
    : SstCursorImpl c ( rc_take [SstCursorImpl] . h l )
    : i r ( __sc_head_cmp_view c key seq )
    ( rc_restore [SstCursorImpl] . h l c )
    ^ r
}

// `a`'s head against `b`'s (two different cursors).
@ sc_head_cmp_cursor SstCursor a SstCursor b → i {
    : SstCursorImpl cb ( rc_take [SstCursorImpl] . b l )
    : i r ( sc_head_cmp a ( slice_window [u] ( slice_from_vec [u] . cb blk ) . cb koff . cb kl ) . cb seq )
    ( rc_restore [SstCursorImpl] . b l cb )
    ^ r
}

@ __sc_fail inout SstCursorImpl c sink String e → v {
    = . c failed 1
    = . c valid 0
    ( string_free . c err )
    = . c err e
}

// Decode the entry the cursor's `pos` points at.
@ __sc_decode inout SstCursorImpl c → b {
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

@ __sc_load inout SstCursorImpl c i bi → b {
    : ~ SstReaderImpl rr ( locked_take [SstReaderImpl] . . c r l )
    : b inside < bi . rr nblocks
    : !( Vec u ) String br ? inside ( __sst_load_block rr bi ) @ !( Vec u ) String { F ( string_new ) }
    ( locked_restore [SstReaderImpl] . . c r l rr )
    ? inside {} { = . c valid 0 ^ F }
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

@ sc_first SstCursor c__h → v {
    : ~ SstCursorImpl c ( rc_take [SstCursorImpl] . c__h l )
    ( __sc_first_in c )
    ( rc_restore [SstCursorImpl] . c__h l c )
}

@ __sc_first_in inout SstCursorImpl c → v {
    = . c valid 0
    : b _ok ( __sc_load c 0 )
}

@ sc_next SstCursor c__h → v {
    : ~ SstCursorImpl c ( rc_take [SstCursorImpl] . c__h l )
    ( __sc_next_in c )
    ( rc_restore [SstCursorImpl] . c__h l c )
}

@ __sc_next_in inout SstCursorImpl c → v {
    ( _sc_next c )
}

@ _sc_next inout SstCursorImpl c → v {
    ? == . c valid 1 {} { ^ }
    = . c pos + . c pos + SST_HDR + . c kl . c vl
    ? ( __sc_decode c ) {} {
        : b _ok ( __sc_load c + . c bi 1 )
    }
}

// Position at the first entry >= (key, snap).
@ sc_seek SstCursor c__h ( Vec u ) key i snap → v {
    : ~ SstCursorImpl c ( rc_take [SstCursorImpl] . c__h l )
    ( __sc_seek_in c key snap )
    ( rc_restore [SstCursorImpl] . c__h l c )
}

@ __sc_seek_in inout SstCursorImpl c ( Vec u ) key i snap → v {
    = . c valid 0
    : i klen ( vec_len [u] key )
    : ( Slice u ) kv ( slice_from_vec [u] key )
    : SstReaderImpl rr ( locked_take [SstReaderImpl] . . c r l )
    : i bi ( __sst_find_block rr kv )
    ( locked_restore [SstReaderImpl] . . c r l rr )
    ? ( __sc_load c bi ) {} { ^ }
    : ~ b searching T
    ~ searching {
        ? == . c valid 1 {} { = searching F }
        ? searching {
            : i cc ( slice_bytes_cmp ( slice_window [u] ( slice_from_vec [u] . c blk ) . c koff . c kl ) kv )
            ? | > cc 0 & == cc 0 <= . c seq snap { = searching F } { ( _sc_next c ) }
        } {}
    }
}
