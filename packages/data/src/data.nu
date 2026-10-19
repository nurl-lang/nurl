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
//   ( data_new x y n d l )                → DataSet    (takes ownership of x,y)
//   ( dl_new ds batch drop_last seed )    → DataLoader
//   ( dl_new_shard ds batch drop_last seed nshards shard ) → DataLoader
//   ( dl_next dl bx by )                  → i          (rows; 0 = end)
//   ( dl_reset dl seed )                  → v          (next epoch)
//   ( dl_num_batches dl )                 → i
//   ( data_save_ndf path ds )             → !v String
//   ( ndf_open path )                     → !NdfStream String
//   ( dl_stream st batch drop_last seed )                → DataLoader
//   ( dl_stream_shard st batch drop_last seed nshards shard ) → DataLoader
//
// DataSet, NdfStream and DataLoader are handles: every copy is the same
// object, and the last owner releases it — an NdfStream closes its file. A
// loader holds a share of its source, so the source outlives every loader
// over it. data_free / ndf_close / dl_free are optional early releases.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/pfile.nu`

@ __data_gf ( Vec f ) v i k → f { ?? ( vec_get [f] v k ) { T x → x F → 0.0 } }

@ __data_gi ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → x F → 0 } }

// ── dataset ────────────────────────────────────────────────────────────

: DataSetImpl {
    ( Vec f ) x  // n·d features, row-major
    ( Vec f ) y  // n·l labels (empty when l == 0)
    i n
    i d
    i l
}

// A DataSet is a handle: every copy (each loader over it holds one) is the
// same data, and the last owner releases it.
: DataSet { ( Arc DataSetImpl ) a }

@ DataSet_share DataSet h → DataSet { ^ @ DataSet { ( arc_clone [DataSetImpl] . h a ) } }

@ DataSet_drop sink DataSet h → v {}

// Take ownership of x (n·d) and y (n·l).
@ data_new sink ( Vec f ) x sink ( Vec f ) y i n i d i l → DataSet {
    : DataSetImpl ds @ DataSetImpl { x y n d l }
    ^ @ DataSet { ( arc_new [DataSetImpl] ds ) }
}

// Let go of `ds` now rather than at the end of its owner's scope.
@ data_free sink DataSet ds → v {}

@ data_n DataSet ds__h → i {
    : DataSetImpl ds ( arc_get [DataSetImpl] . ds__h a )
    ^ . ds n
}

@ data_d DataSet ds__h → i {
    : DataSetImpl ds ( arc_get [DataSetImpl] . ds__h a )
    ^ . ds d
}

@ data_l DataSet ds__h → i {
    : DataSetImpl ds ( arc_get [DataSetImpl] . ds__h a )
    ^ . ds l
}

// ── .ndf on-disk format ────────────────────────────────────────────────
// bytes:  'N' 'D' 'F' '1' | u64 n | u64 d | u64 l | rows((d+l) f64 LE)…
: i __NDF_HDR 28

: NdfStreamImpl {
    // Read at offsets (pread): a DataLoader's copies on several threads
    // read rows of one stream at once, and a stream with one position
    // (seek, then read) would move it under another thread's read. The
    // last owner of the handle closes the file.
    PFile f
    i n
    i d
    i l
    i data_off
}

: NdfStream { ( Arc NdfStreamImpl ) a }

@ NdfStream_share NdfStream h → NdfStream { ^ @ NdfStream { ( arc_clone [NdfStreamImpl] . h a ) } }

@ NdfStream_drop sink NdfStream h → v {}

@ data_save_ndf s path DataSet ds__h → !v String {
    : DataSetImpl ds ( arc_get [DataSetImpl] . ds__h a )
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
    ? wok { ^ @ !v String { T } }
    ^ @ !v String { F ( string_from `data: cannot write .ndf` ) }
}

@ ndf_open s path → !NdfStream String {
    : !PFile IoErr fr ( pfile_open path PFILE_READ )
    ?? fr {
        F _ → { ^ @ !NdfStream String { F ( string_from `data: cannot open .ndf` ) } }
        T fh → {
            // (An early return below lets go of `fh`, and its drop closes
            // the file.)
            : !( Vec u ) IoErr hr ( pfile_read_vec_at fh 0 __NDF_HDR )
            ?? hr {
                T hb → {
                    ? >= ( vec_len [u] hb ) __NDF_HDR {} {
                        ^ @ !NdfStream String { F ( string_from `data: truncated .ndf header` ) }
                    }
                    : ~ b magic T
                    ? == ?? ( vec_get [u] hb 0 ) { T x → x F → # u 0 } # u 78 {} { = magic F }
                    ? == ?? ( vec_get [u] hb 1 ) { T x → x F → # u 0 } # u 68 {} { = magic F }
                    ? == ?? ( vec_get [u] hb 2 ) { T x → x F → # u 0 } # u 70 {} { = magic F }
                    ? == ?? ( vec_get [u] hb 3 ) { T x → x F → # u 0 } # u 49 {} { = magic F }
                    ? magic {} {
                        ^ @ !NdfStream String { F ( string_from `data: bad .ndf magic` ) }
                    }
                    : i n # i ?? ( bytes_read_u64_le hb 4 ) { T v → v F → # u64 0 }
                    : i d # i ?? ( bytes_read_u64_le hb 12 ) { T v → v F → # u64 0 }
                    : i l # i ?? ( bytes_read_u64_le hb 20 ) { T v → v F → # u64 0 }
                    : NdfStreamImpl st @ NdfStreamImpl { fh n d l __NDF_HDR }
                    ^ @ !NdfStream String { T @ NdfStream { ( arc_new [NdfStreamImpl] st ) } }
                }
                F _ → {
                    ^ @ !NdfStream String { F ( string_from `data: cannot read .ndf header` ) }
                }
            }
        }
    }
    ^ @ !NdfStream String { F ( string_from `data: cannot read .ndf header` ) }
}

// Let go of `st` now rather than at the end of its owner's scope (the
// last owner closes the file).
@ ndf_close sink NdfStream st → v {}

@ ndf_n NdfStream st__h → i {
    : NdfStreamImpl st ( arc_get [NdfStreamImpl] . st__h a )
    ^ . st n
}

@ ndf_d NdfStream st__h → i {
    : NdfStreamImpl st ( arc_get [NdfStreamImpl] . st__h a )
    ^ . st d
}

@ ndf_l NdfStream st__h → i {
    : NdfStreamImpl st ( arc_get [NdfStreamImpl] . st__h a )
    ^ . st l
}

// Read example `idx`: append its d features to x_out and l labels to y_out.
@ ndf_read_row NdfStream st__h i idx ( Vec f ) x_out ( Vec f ) y_out → b {
    ^ ( __ndf_read_row ( arc_get [NdfStreamImpl] . st__h a ) idx x_out y_out )
}

@ __ndf_read_row NdfStreamImpl st i idx ( Vec f ) x_out ( Vec f ) y_out → b {
    : i rowf + . st d . st l
    : i off + . st data_off * idx * rowf 8
    : !( Vec u ) IoErr rr ( pfile_read_vec_at . st f off * rowf 8 )
    ?? rr {
        T b → {
            ? >= ( vec_len [u] b ) * rowf 8 {} { ^ F }
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
}

// The shard's absolute example range [base, base+count) of [0,n).
@ __data_shard_base i n i nshards i shard → i { ^ / * shard n nshards }

// ── loader ─────────────────────────────────────────────────────────────

: DataLoaderImpl {
    ? DataSet ds  // in-memory source (F when streaming)
    ? NdfStream st  // streaming source (F when in-memory)
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

// A DataLoader is a handle: every copy is the same loader (one cursor
// through the epoch), and the last owner releases it — and with it its
// share of the dataset or stream it reads. The cursor is in a Locked
// (stdlib/std/thread.nu): a step checks it out and back in, so copies on
// several threads take batches in turn.
: DataLoader { ( Locked DataLoaderImpl ) st }

@ DataLoader_share DataLoader h → DataLoader { ^ @ DataLoader { ( Locked_share [DataLoaderImpl] . h st ) } }

@ DataLoader_drop sink DataLoader h → v {}

@ __dl_make ? DataSet ds ? NdfStream st i n i d i l i batch b drop_last i seed i nshards i shard → DataLoader {
    : i base ( __data_shard_base n nshards shard )
    : i end ( __data_shard_base n nshards + shard 1 )
    : i cnt - end base
    : ( Vec i ) idx ( vec_with_cap [i] cnt )
    : ~ i k 0
    ~ < k cnt { ( vec_push [i] idx + base k ) = k + k 1 }
    ? > seed 0 { ( __data_shuffle idx seed ) } {}
    : DataLoaderImpl dl @ DataLoaderImpl { ds st cnt d l base batch drop_last > seed 0 idx 0 0 }
    ^ @ DataLoader { ( locked_new [DataLoaderImpl] dl ) }
}

// Full in-memory dataset (one shard). seed <= 0 disables shuffling.
@ dl_new DataSet ds__h i batch b drop_last i seed → DataLoader {
    : DataSetImpl ds ( arc_get [DataSetImpl] . ds__h a )
    ^ ( __dl_make @ ?DataSet { T ( DataSet_share ds__h ) } @ ?NdfStream { F } . ds n . ds d . ds l batch drop_last seed 1 0 )
}

@ dl_new_shard DataSet ds__h i batch b drop_last i seed i nshards i shard → DataLoader {
    : DataSetImpl ds ( arc_get [DataSetImpl] . ds__h a )
    ^ ( __dl_make @ ?DataSet { T ( DataSet_share ds__h ) } @ ?NdfStream { F } . ds n . ds d . ds l batch drop_last seed nshards shard )
}

// Streaming dataset (one shard).
@ dl_stream NdfStream st__h i batch b drop_last i seed → DataLoader {
    : NdfStreamImpl st ( arc_get [NdfStreamImpl] . st__h a )
    ^ ( __dl_make @ ?DataSet { F } @ ?NdfStream { T ( NdfStream_share st__h ) } . st n . st d . st l batch drop_last seed 1 0 )
}

@ dl_stream_shard NdfStream st__h i batch b drop_last i seed i nshards i shard → DataLoader {
    : NdfStreamImpl st ( arc_get [NdfStreamImpl] . st__h a )
    ^ ( __dl_make @ ?DataSet { F } @ ?NdfStream { T ( NdfStream_share st__h ) } . st n . st d . st l batch drop_last seed nshards shard )
}

// Reshuffle for the next epoch and rewind. The permutation is a pure
// function of `seed` — idx is reset to the ordered shard range [base,
// base+n) BEFORE the shuffle, so the same seed always yields the same
// order regardless of the loader's prior state.
@ dl_reset DataLoader dl__h i seed → v {
    : ~ DataLoaderImpl dl ( locked_take [DataLoaderImpl] . dl__h st )
    : ~ i k 0
    ~ < k . dl n { ( vec_set [i] . dl idx k + . dl base k ) = k + k 1 }
    ? > seed 0 { ( __data_shuffle . dl idx seed ) } {}
    = . dl pos 0
    ( locked_restore [DataLoaderImpl] . dl__h st dl )
}

@ dl_num_batches DataLoader dl__h → i {
    : ~ DataLoaderImpl dl ( locked_take [DataLoaderImpl] . dl__h st )
    : i r ( __dl_num_batches dl )
    ( locked_restore [DataLoaderImpl] . dl__h st dl )
    ^ r
}

@ __dl_num_batches DataLoaderImpl dl → i {
    : i b . dl batch
    ? <= b 0 { ^ 0 } {}
    ? . dl drop_last { ^ / . dl n b } {}
    ^ / + . dl n - b 1 b
}

// Emit the next batch into bx (rows·d) and by (rows·l), overwriting them.
// Returns the row count (0 at end-of-epoch; the last batch may be partial
// unless drop_last).
@ dl_next DataLoader dl__h ( Vec f ) bx ( Vec f ) by → i {
    : ~ DataLoaderImpl dl ( locked_take [DataLoaderImpl] . dl__h st )
    : i r ( __dl_next dl bx by )
    ( locked_restore [DataLoaderImpl] . dl__h st dl )
    ^ r
}

@ __dl_next inout DataLoaderImpl dl ( Vec f ) bx ( Vec f ) by → i {
    : i rem - . dl n . dl pos
    ? <= rem 0 { = . dl last_rows 0 ^ 0 } {}
    : ~ i rows . dl batch
    ? > rows rem { = rows rem } {}
    ? & . dl drop_last < rows . dl batch { = . dl last_rows 0 ^ 0 } {}
    ( vec_clear [f] bx )
    ( vec_clear [f] by )
    : i d . dl d
    : i l . dl l
    // The source, opened once per batch (only the one that is set is read).
    ?? . dl ds {
        T h → {
            : DataSetImpl ds ( arc_get [DataSetImpl] . h a )
            : ( Slice f ) xs ( slice_from_vec [f] . ds x )
            : ( Slice f ) ys ( slice_from_vec [f] . ds y )
            : ~ i k 0
            ~ < k rows {
                : i ex ( __data_gi . dl idx + . dl pos k )
                : ~ i c 0
                ~ < c d { ( vec_push [f] bx ( slice_at [f] xs + * ex d c ) ) = c + c 1 }
                = c 0
                ~ < c l { ( vec_push [f] by ( slice_at [f] ys + * ex l c ) ) = c + c 1 }
                = k + k 1
            }
        }
        F _ → {
            ?? . dl st {
                T h → {
                    : NdfStreamImpl st ( arc_get [NdfStreamImpl] . h a )
                    : ~ i k 0
                    ~ < k rows {
                        : b _r ( __ndf_read_row st ( __data_gi . dl idx + . dl pos k ) bx by )
                        = k + k 1
                    }
                }
                F _ → {}
            }
        }
    }
    = . dl pos + . dl pos rows
    = . dl last_rows rows
    ^ rows
}

@ dl_last_rows DataLoader dl__h → i {
    : ~ DataLoaderImpl dl ( locked_take [DataLoaderImpl] . dl__h st )
    : i r . dl last_rows
    ( locked_restore [DataLoaderImpl] . dl__h st dl )
    ^ r
}

// Let go of `dl` now rather than at the end of its owner's scope.
@ dl_free sink DataLoader dl → v {}
