// data.nu — a training DataLoader: batching + seeded shuffle + epochs +
// drop-last + worker sharding, over an in-memory dataset OR one streamed
// off disk.
//
// A dataset is n examples, each d f64 features and l f64 labels (l may be
// 0). In memory it is two flat vectors (x: n·d, y: n·l). On disk it is the
// .ndf format — a magic + n/d/l header, then n rows of (d+l) little-endian
// f64 (x then y) — read with random-access preads so a corpus larger than
// RAM never loads whole.
//
// A DataLoader holds a permutation of its shard's example indices; dl_next
// gathers the next `batch` rows (in memory: a copy; streaming: one pread per
// row) into caller-provided vectors and returns the row count (0 =
// exhausted). dl_reset reshuffles for the next epoch. Sharding partitions
// [0,n) into contiguous, exactly-once slices — shard s of N gets
// [s·n/N, (s+1)·n/N).
//
//   ( data_new x y n d l )                → *DataSet   (takes ownership of x,y)
//   ( dl_new ds batch drop_last seed )    → *DataLoader
//   ( dl_new_shard ds batch drop_last seed nshards shard ) → *DataLoader
//   ( dl_next dl bx by )                  → i          (rows; 0 = end)
//   ( dl_reset dl seed )                  → v          (next epoch)
//   ( dl_num_batches dl )                 → i
//   ( data_save_ndf path ds )             → !v String
//   ( ndf_open path )                     → !*NdfStream String
//   ( dl_stream st batch drop_last seed )                → *DataLoader
//   ( dl_stream_shard st batch drop_last seed nshards shard ) → *DataLoader

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`

@ __data_gf ( Vec f ) v i k → f { ?? ( vec_get [f] v k ) { T x → x F → 0.0 } }

@ __data_gi ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → x F → 0 } }

// ── dataset ────────────────────────────────────────────────────────────

: DataSet {
    ( Vec f ) x  // n·d features, row-major
    ( Vec f ) y  // n·l labels (empty when l == 0)
    i n
    i d
    i l
}

// Take ownership of x (n·d) and y (n·l); data_free releases both.
@ data_new ( Vec f ) x ( Vec f ) y i n i d i l → *DataSet {
    : *DataSet ds # *DataSet ( nurl_alloc Z DataSet )
    = . ds x x
    = . ds y y
    = . ds n n
    = . ds d d
    = . ds l l
    ^ ds
}

@ data_free * DataSet ds → v {
    ( vec_free [f] . ds x )
    ( vec_free [f] . ds y )
    ( nurl_free # s ds )
}

@ data_n * DataSet ds → i { ^ . ds n }

@ data_d * DataSet ds → i { ^ . ds d }

@ data_l * DataSet ds → i { ^ . ds l }

// ── .ndf on-disk format ────────────────────────────────────────────────
// bytes:  'N' 'D' 'F' '1' | u64 n | u64 d | u64 l | rows((d+l) f64 LE)…
: i __NDF_HDR 28

: NdfStream {
    File f
    i n
    i d
    i l
    i data_off
}

@ data_save_ndf s path * DataSet ds → !v String {
    : ( Vec u ) out ( vec_new [u] )
    ( vec_push [u] out # u 78 ) ( vec_push [u] out # u 68 )
    ( vec_push [u] out # u 70 ) ( vec_push [u] out # u 49 )
    ( bytes_push_u64_le out # u64 . ds n )
    ( bytes_push_u64_le out # u64 . ds d )
    ( bytes_push_u64_le out # u64 . ds l )
    : i nd . ds d
    : i nl . ds l
    : ~ i e 0
    ~ < e . ds n {
        : ~ i c 0
        ~ < c nd { ( bytes_push_f64_le out ( __data_gf . ds x + * e nd c ) ) = c + c 1 }
        = c 0
        ~ < c nl { ( bytes_push_f64_le out ( __data_gf . ds y + * e nl c ) ) = c + c 1 }
        = e + e 1
    }
    : ~ b wok T
    ?? ( write_file_bytes path out ) { T _ → {} F _ → { = wok F } }
    ( vec_free [u] out )
    ? wok { ^ @ !v String { T } }
    ^ @ !v String { F ( string_from `data: cannot write .ndf` ) }
}

@ ndf_open s path → !*NdfStream String {
    : !File IoErr fr ( file_open path )
    : ~ File fh @ File { # s 0 }
    ?? fr { T h → { = fh h } F _ → { ^ @ !*NdfStream String { F ( string_from `data: cannot open .ndf` ) } } }
    : !( Vec u ) IoErr hr ( file_read_at fh 0 __NDF_HDR )
    ?? hr {
        T hb → {
            ? >= ( vec_len [u] hb ) __NDF_HDR {} {
                ( vec_free [u] hb ) ( file_close fh )
                ^ @ !*NdfStream String { F ( string_from `data: truncated .ndf header` ) }
            }
            : ~ b magic T
            ? == ?? ( vec_get [u] hb 0 ) { T x → x F → # u 0 } # u 78 {} { = magic F }
            ? == ?? ( vec_get [u] hb 1 ) { T x → x F → # u 0 } # u 68 {} { = magic F }
            ? == ?? ( vec_get [u] hb 2 ) { T x → x F → # u 0 } # u 70 {} { = magic F }
            ? == ?? ( vec_get [u] hb 3 ) { T x → x F → # u 0 } # u 49 {} { = magic F }
            ? magic {} {
                ( vec_free [u] hb ) ( file_close fh )
                ^ @ !*NdfStream String { F ( string_from `data: bad .ndf magic` ) }
            }
            : i n # i ?? ( bytes_read_u64_le hb 4 ) { T v → v F → # u64 0 }
            : i d # i ?? ( bytes_read_u64_le hb 12 ) { T v → v F → # u64 0 }
            : i l # i ?? ( bytes_read_u64_le hb 20 ) { T v → v F → # u64 0 }
            ( vec_free [u] hb )
            : *NdfStream st # *NdfStream ( nurl_alloc Z NdfStream )
            = . st f fh
            = . st n n
            = . st d d
            = . st l l
            = . st data_off __NDF_HDR
            ^ @ !*NdfStream String { T st }
        }
        F _ → {
            ( file_close fh )
            ^ @ !*NdfStream String { F ( string_from `data: cannot read .ndf header` ) }
        }
    }
    ^ @ !*NdfStream String { F ( string_from `data: cannot read .ndf header` ) }
}

@ ndf_close * NdfStream st → v {
    ( file_close . st f )
    ( nurl_free # s st )
}

@ ndf_n * NdfStream st → i { ^ . st n }

@ ndf_d * NdfStream st → i { ^ . st d }

@ ndf_l * NdfStream st → i { ^ . st l }

// Read example `idx`: append its d features to x_out and l labels to y_out.
@ ndf_read_row * NdfStream st i idx ( Vec f ) x_out ( Vec f ) y_out → b {
    : i rowf + . st d . st l
    : i off + . st data_off * idx * rowf 8
    : !( Vec u ) IoErr rr ( file_read_at . st f off * rowf 8 )
    ?? rr {
        T b → {
            ? >= ( vec_len [u] b ) * rowf 8 {} { ( vec_free [u] b ) ^ F }
            : ~ i c 0
            ~ < c . st d {
                ( vec_push [f] x_out ?? ( bytes_read_f64_le b * c 8 ) { T v → v F → 0.0 } )
                = c + c 1
            }
            = c 0
            ~ < c . st l {
                ( vec_push [f] y_out ?? ( bytes_read_f64_le b * + . st d c 8 ) { T v → v F → 0.0 } )
                = c + c 1
            }
            ( vec_free [u] b )
            ^ T
        }
        F _ → { ^ F }
    }
    ^ F
}

// ── index machinery ────────────────────────────────────────────────────

// Fisher-Yates shuffle of `idx` in place with a fresh seeded rng.
@ __data_shuffle ( Vec i ) idx i seed → v {
    : Rng g ( rng_seed seed )
    : i n ( vec_len [i] idx )
    : ~ i k - n 1
    ~ > k 0 {
        : i j ( rng_below g + k 1 )
        : i a ( __data_gi idx k )
        : i b ( __data_gi idx j )
        ( vec_set [i] idx k b )
        ( vec_set [i] idx j a )
        = k - k 1
    }
    ( rng_free g )
}

// The shard's absolute example range [base, base+count) of [0,n).
@ __data_shard_base i n i nshards i shard → i { ^ / * shard n nshards }

// ── loader ─────────────────────────────────────────────────────────────

: DataLoader {
    * DataSet ds  // in-memory source (0 when streaming)
    * NdfStream st  // streaming source (0 when in-memory)
    i n  // examples in this shard
    i d
    i l
    i base  // absolute index of this shard's first example
    i batch
    b drop_last
    b shuffle
    ( Vec i ) idx  // permutation of [base, base+n)
    i pos
    i last_rows
}

@ __dl_make * DataSet ds * NdfStream st i n i d i l i batch b drop_last i seed i nshards i shard → *DataLoader {
    : i base ( __data_shard_base n nshards shard )
    : i end ( __data_shard_base n nshards + shard 1 )
    : i cnt - end base
    : *DataLoader dl # *DataLoader ( nurl_alloc Z DataLoader )
    = . dl ds ds
    = . dl st st
    = . dl n cnt
    = . dl d d
    = . dl l l
    = . dl base base
    = . dl batch batch
    = . dl drop_last drop_last
    = . dl shuffle > seed 0
    = . dl pos 0
    = . dl last_rows 0
    : ( Vec i ) idx ( vec_with_cap [i] cnt )
    : ~ i k 0
    ~ < k cnt { ( vec_push [i] idx + base k ) = k + k 1 }
    = . dl idx idx
    ? . dl shuffle { ( __data_shuffle . dl idx seed ) } {}
    ^ dl
}

// Full in-memory dataset (one shard). seed <= 0 disables shuffling.
@ dl_new * DataSet ds i batch b drop_last i seed → *DataLoader {
    ^ ( __dl_make ds # *NdfStream 0 . ds n . ds d . ds l batch drop_last seed 1 0 )
}

@ dl_new_shard * DataSet ds i batch b drop_last i seed i nshards i shard → *DataLoader {
    ^ ( __dl_make ds # *NdfStream 0 . ds n . ds d . ds l batch drop_last seed nshards shard )
}

// Streaming dataset (one shard).
@ dl_stream * NdfStream st i batch b drop_last i seed → *DataLoader {
    ^ ( __dl_make # *DataSet 0 st . st n . st d . st l batch drop_last seed 1 0 )
}

@ dl_stream_shard * NdfStream st i batch b drop_last i seed i nshards i shard → *DataLoader {
    ^ ( __dl_make # *DataSet 0 st . st n . st d . st l batch drop_last seed nshards shard )
}

// Reshuffle for the next epoch and rewind. The permutation is a pure
// function of `seed` — idx is reset to the ordered shard range [base,
// base+n) BEFORE the shuffle, so the same seed always yields the same
// order regardless of the loader's prior state.
@ dl_reset * DataLoader dl i seed → v {
    : ~ i k 0
    ~ < k . dl n { ( vec_set [i] . dl idx k + . dl base k ) = k + k 1 }
    ? > seed 0 { ( __data_shuffle . dl idx seed ) } {}
    = . dl pos 0
}

@ dl_num_batches * DataLoader dl → i {
    : i b . dl batch
    ? <= b 0 { ^ 0 } {}
    ? . dl drop_last { ^ / . dl n b } {}
    ^ / + . dl n - b 1 b
}

// Emit the next batch into bx (rows·d) and by (rows·l), overwriting them.
// Returns the row count (0 at end-of-epoch; the last batch may be partial
// unless drop_last).
@ dl_next * DataLoader dl ( Vec f ) bx ( Vec f ) by → i {
    : i rem - . dl n . dl pos
    ? <= rem 0 { = . dl last_rows 0 ^ 0 } {}
    : ~ i rows . dl batch
    ? > rows rem { = rows rem } {}
    ? & . dl drop_last < rows . dl batch { = . dl last_rows 0 ^ 0 } {}
    : b _cx ( vec_set_len [f] bx 0 )
    : b _cy ( vec_set_len [f] by 0 )
    : i d . dl d
    : i l . dl l
    : ~ i k 0
    ~ < k rows {
        : i ex ( __data_gi . dl idx + . dl pos k )
        ? != # i . dl ds 0 {
            : *DataSet ds . dl ds
            : ~ i c 0
            ~ < c d { ( vec_push [f] bx ( __data_gf . ds x + * ex d c ) ) = c + c 1 }
            = c 0
            ~ < c l { ( vec_push [f] by ( __data_gf . ds y + * ex l c ) ) = c + c 1 }
        } {
            : b _r ( ndf_read_row . dl st ex bx by )
        }
        = k + k 1
    }
    = . dl pos + . dl pos rows
    = . dl last_rows rows
    ^ rows
}

@ dl_last_rows * DataLoader dl → i { ^ . dl last_rows }

@ dl_free * DataLoader dl → v {
    ( vec_free [i] . dl idx )
    ( nurl_free # s dl )
}
