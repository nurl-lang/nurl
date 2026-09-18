// nurl-cov/gcov.nu — read the compiler's coverage graphs, in pure NURL.
//
// `nurlc --coverage=PREFIX` asks LLVM's GCOV pass to write two files:
//
//   PREFIX.gcno   the NOTES: one control-flow graph per function, and the
//                 source lines each basic block came from. Written once,
//                 at compile time.
//   PREFIX.gcda   the DATA: one counter per instrumented arc, written when
//                 the instrumented program exits. Re-running the program
//                 accumulates into the same file.
//
// Neither file holds a per-line count. The notes hold a spanning tree over
// each function's arcs, and only the arcs OUTSIDE that tree are counted —
// that is the whole point of the encoding, and it is why a coverage reader
// has real work to do. This module does that work:
//
//   1. parse both files (a tagged record stream, 32-bit words, LE),
//   2. hand each counted arc its counter,
//   3. solve the flow graph for every remaining arc and every block count,
//   4. hand back the per-block counts with the lines each block covers.
//
// Turning that into per-line numbers is `model.nu`'s job; rendering it the
// way `gcov` does is `gcovtext.nu`'s.
//
// Format: the version word is "408*" — GCC 4.8's layout, which is what
// LLVM's GCOV pass emits and what this reader implements. A file that
// announces a different version is rejected rather than guessed at.
//
// Memory model: `gcov_read` returns a heap `*GcovObj`; free it with
// `gcov_free`. Every table inside it is flat — parallel `( Vec i )` columns
// indexed by function/block/arc number — so nothing owns anything twice.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`

// Record tags, as they appear in both files.
: i GCOV_TAG_FUNCTION 0x01000000
: i GCOV_TAG_BLOCKS 0x01410000
: i GCOV_TAG_ARCS 0x01430000
: i GCOV_TAG_LINES 0x01450000
: i GCOV_TAG_COUNTER 0x01a10000
: i GCOV_TAG_PROGRAM 0xa3000000

// Arc flags.
: i GCOV_ARC_ON_TREE 1
: i GCOV_ARC_FAKE 2

// Function table stride. One row per function.
: i GFN_W 13
: i GFN_IDENT 0
: i GFN_LCS 11  // line-number checksum, as the notes recorded it
: i GFN_CCS 12  // control-flow checksum
: i GFN_SRC 1  // index into `files`
: i GFN_LINE 2
: i GFN_NBLOCK 3
: i GFN_BLK_OFF 4  // first row in `blk_count`
: i GFN_ARC_OFF 5  // first row in `arcs` (already multiplied by GARC_W)
: i GFN_ARC_N 6
: i GFN_BL_OFF 7  // first row in `blines` (already multiplied by GBL_W)
: i GFN_BL_N 8
: i GFN_CTR_OFF 9  // first slot in `counters`
: i GFN_CTR_N 10

// Arc table stride.
: i GARC_W 5
: i GARC_SRC 0
: i GARC_DST 1
: i GARC_FLAGS 2
: i GARC_COUNT 3
: i GARC_VALID 4

// Block-line table stride: which source line a block covers.
: i GBL_W 3
: i GBL_BLOCK 0
: i GBL_SRC 1
: i GBL_LINE 2

// A line number no source file reaches. The per-line tables are indexed BY
// line number, so an untrusted number decides how much memory this reader
// asks for: one flipped byte in a notes file named line 1970155382, and a
// dense table that long is tens of gigabytes and a hang. The largest file
// in this project is 33795 lines. Sixteen million is a ceiling no real
// source reaches and every corrupt one blows straight through.
: i GCOV_MAX_LINE 16777216

: GcovObj {
    String notes  // path of the .gcno that was read
    String data  // path of the .gcda, or empty when none was found
    i stamp
    i runs  // how many times the instrumented program has exited
    b has_data  // false → the program never ran; every counter is 0
    ( Vec String ) files  // source files this object mentions
    ( Vec i ) fns  // stride GFN_W
    ( Vec String ) fn_names
    ( Vec i ) blk_count  // solved execution count, per block, per function
    ( Vec i ) arcs  // stride GARC_W
    ( Vec i ) blines  // stride GBL_W
    ( Vec i ) counters  // raw arc counters from the .gcda
    // Edge index: for every block, the arcs entering and leaving it, in
    // the order the notes stored them. Without it, finding a block's
    // arcs means scanning its function's whole arc table, and a large
    // module turns into an O(n^2) walk.
    ( Vec i ) pred_head  // per block slot: first arc slot + 1
    ( Vec i ) pred_next  // per arc slot: next arc slot + 1
    ( Vec i ) pred_tail
    ( Vec i ) succ_head
    ( Vec i ) succ_next
    ( Vec i ) succ_tail
}

: | GcovErr {
    GcovNoNotes  // the .gcno could not be read
    GcovBadMagic  // not a coverage file at all
    GcovBadVersion  // a GCOV layout this reader does not implement
    GcovTruncated  // a record runs past the end of the file
    GcovStampMismatch  // .gcda belongs to a different build than the .gcno
    GcovChecksumMismatch  // a function's own checksums disagree across the pair
    GcovBadLine  // a line number no source file could have
    GcovBadBlock  // a record names a block the function does not have
}

@ gcov_err_name GcovErr e → s {
    ^ ?? e {
        GcovNoNotes → `notes file could not be read`
        GcovBadMagic → `not a GCOV file (bad magic)`
        GcovBadVersion → `unsupported GCOV version (this reader implements "408*")`
        GcovTruncated → `truncated record`
        GcovStampMismatch → `.gcda was produced by a different build than the .gcno`
        GcovChecksumMismatch → `a function's checksums differ between the .gcno and the .gcda`
        GcovBadLine → `a line number larger than any source file has`
        GcovBadBlock → `a record names a block the function does not have`
    }
}

// ── Word-level reading ───────────────────────────────────────────
//
// Both files are streams of 32-bit little-endian words. A string is a
// word-count followed by that many words of NUL-padded bytes.

@ __g_u32 * u p i off → i {
    ^ | | | # i . p off
    << # i . p + off 1 8
    << # i . p + off 2 16
    << # i . p + off 3 24
}

// Counters are 64-bit, stored low word first.
@ __g_u64 * u p i off → i {
    ^ | ( __g_u32 p off ) << ( __g_u32 p + off 4 ) 32
}

// A GCOV string: `words` words of payload, NUL-padded to the word
// boundary. The stored length is the padded one, so the real end is the
// first NUL.
//
// `limit` is where the record ends, and it is not optional. The word count
// comes straight out of the file: a flipped byte turned one into 738
// million here, and a reader that trusts it walks that far off the end of
// the buffer. A span that does not fit is not a short string, it is a
// broken record, and the caller is told by getting nothing back.
@ __g_str * u p i off i words i limit → String {
    ? | < words 0 > + off * words 4 limit { ^ ( string_new ) } {}
    : i cap * words 4
    : ~ i n 0
    ~ < n cap {
        ? == 0 # i . p + off n { = n cap } { = n + n 1 }
    }
    : *u at # *u + # i p off
    ^ ( string_from_bytes at n )
}

// ── The file table ───────────────────────────────────────────────

@ __g_file_idx * GcovObj o String path → i {
    : i n ( vec_len [String] . o files )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] . o files i ) {
            T f → ? ( string_eq f path ) { ^ i } {}
            F _ → {}
        }
        = i + i 1
    }
    ( vec_push [String] . o files ( string_clone path ) )
    ^ n
}

// ── Notes (.gcno) ────────────────────────────────────────────────

@ __g_read_notes * GcovObj o ( Vec u ) buf → !v GcovErr {
    : i len ( vec_len [u] buf )
    ? < len 12 { ^ @ !v GcovErr { F GcovTruncated } } {}
    : *u p ( vec_data [u] buf )
    // "oncg" on disk: the magic is stored so that a little-endian reader
    // sees the characters in reverse. A big-endian producer would spell it
    // "gcno"; nurlc never emits that, so it is rejected rather than swapped.
    ? ! & & == 111 # i . p 0 == 110 # i . p 1
    & == 99 # i . p 2 == 103 # i . p 3
    { ^ @ !v GcovErr { F GcovBadMagic } } {}
    ? ! ( __g_version_ok p 4 ) { ^ @ !v GcovErr { F GcovBadVersion } } {}
    = . o stamp ( __g_u32 p 8 )

    : ~ i off 12
    : ~ i cur -1  // index of the function whose records we are inside
    : ~ i cursrc -1  // file index the current LINES record is naming
    ~ <= + off 8 len {
        : i tag ( __g_u32 p off )
        : i words ( __g_u32 p + off 4 )
        : i body + off 8
        : i end + body * words 4
        ? > end len { ^ @ !v GcovErr { F GcovTruncated } } {}
        ? == tag GCOV_TAG_FUNCTION {
            ( __g_close_fn o cur )
            = cur ( __g_notes_function o p body end )
        } {
            ? == tag GCOV_TAG_BLOCKS {
                ? >= cur 0 { ( __g_notes_blocks o cur words ) } {}
            } {
                ? == tag GCOV_TAG_ARCS {
                    ? >= cur 0 {
                        ? ! ( __g_notes_arcs o cur p body end ) {
                            ^ @ !v GcovErr { F GcovBadBlock }
                        } {}
                    } {}
                } {
                    ? == tag GCOV_TAG_LINES {
                        ? >= cur 0 {
                            = cursrc ( __g_notes_lines o cur p body end )
                            ? == cursrc -2 { ^ @ !v GcovErr { F GcovBadLine } } {}
                            ? == cursrc -3 { ^ @ !v GcovErr { F GcovBadBlock } } {}
                        } {}
                    } {}
                }
            }
        }
        = off end
    }
    ( __g_close_fn o cur )
    ^ @ !v GcovErr { T 0 }
}

// Close a function's arc range with the arc gcov adds itself: one from
// the exit block back to the entry, on the spanning tree. It closes the
// graph so that flow is conserved even for a function that only ever
// falls out of the bottom — without it, the propagation below has no
// equation to solve for the last arc.
//
// It is allocated HERE, while the function's arcs are still the last
// thing in the shared table, because every function's arcs live in one
// flat array: appending later would land it after some other function's.
@ __g_close_fn * GcovObj o i fi → v {
    ? < fi 0 { ^ v } {}
    ? < ( __g_fn o fi GFN_NBLOCK ) 2 { ^ v } {}
    ( vec_push [i] . o arcs 1 )  // from the exit block
    ( vec_push [i] . o arcs 0 )  // to the entry block
    ( vec_push [i] . o arcs GCOV_ARC_ON_TREE )
    ( vec_push [i] . o arcs 0 )
    ( vec_push [i] . o arcs 0 )
    ( vec_set [i] . o fns + * fi GFN_W GFN_ARC_N + 1 ( __g_fn o fi GFN_ARC_N ) )
}

// Only the layout this reader implements is accepted. Guessing at an
// unknown one produces numbers that look plausible and are wrong.
@ __g_version_ok * u p i off → b {
    ^ & & == 42 # i . p off == 56 # i . p + off 1
    & == 48 # i . p + off 2 == 52 # i . p + off 3
}

// A FUNCTION record opens a new function: identity, checksums, name,
// source file and the line it starts on.
@ __g_notes_function * GcovObj o * u p i body i end → i {
    ? > + body 12 end { ^ -1 } {}
    : i ident ( __g_u32 p body )
    : i lcs ( __g_u32 p + body 4 )
    : i ccs ( __g_u32 p + body 8 )
    : ~ i q + body 12
    ? > + q 4 end { ^ -1 } {}
    : i namew ( __g_u32 p q )
    : String name ( __g_str p + q 4 namew end )
    = q + q + 4 * namew 4
    ? > + q 4 end { ( string_free name ) ^ -1 } {}
    : i filew ( __g_u32 p q )
    : String file ( __g_str p + q 4 filew end )
    = q + q + 4 * filew 4
    ? > q end { ( string_free name ) ( string_free file ) ^ -1 } {}
    : i line ? <= + q 4 end ( __g_u32 p q ) 0
    : i src ( __g_file_idx o file )
    ( string_free file )

    : i idx / ( vec_len [i] . o fns ) GFN_W
    ( vec_push [String] . o fn_names name )
    ( vec_push [i] . o fns ident )
    ( vec_push [i] . o fns src )
    ( vec_push [i] . o fns line )
    ( vec_push [i] . o fns 0 )  // NBLOCK
    ( vec_push [i] . o fns ( vec_len [i] . o blk_count ) )  // BLK_OFF
    ( vec_push [i] . o fns ( vec_len [i] . o arcs ) )  // ARC_OFF
    ( vec_push [i] . o fns 0 )  // ARC_N
    ( vec_push [i] . o fns ( vec_len [i] . o blines ) )  // BL_OFF
    ( vec_push [i] . o fns 0 )  // BL_N
    ( vec_push [i] . o fns 0 )  // CTR_OFF
    ( vec_push [i] . o fns 0 )  // CTR_N
    ( vec_push [i] . o fns lcs )
    ( vec_push [i] . o fns ccs )
    ^ idx
}

// A BLOCKS record is one word of flags per basic block; the count of words
// IS the number of blocks. Block 0 is the entry, block 1 the exit.
@ __g_notes_blocks * GcovObj o i fi i words → v {
    ( vec_set [i] . o fns + * fi GFN_W GFN_NBLOCK words )
    : ~ i k 0
    ~ < k words { ( vec_push [i] . o blk_count 0 ) = k + k 1 }
}

// An ARCS record is a source block followed by (destination, flags) pairs.
//
// A block number out of range is not an arc to skip: the graph it
// describes is not this function's, and an arc pointing outside the block
// table makes the walk that solves the flow unable to mark where it has
// been. It loops. So the file is refused, which is what gcov does too.
@ __g_notes_arcs * GcovObj o i fi * u p i body i end → b {
    ? > + body 4 end { ^ T } {}
    : i nb ( __g_fn o fi GFN_NBLOCK )
    : i from ( __g_u32 p body )
    ? >= from nb { ^ F } {}
    : ~ i q + body 4
    ~ <= + q 8 end {
        : i dst ( __g_u32 p q )
        : i flags ( __g_u32 p + q 4 )
        ? >= dst nb { ^ F } {}
        ( vec_push [i] . o arcs from )
        ( vec_push [i] . o arcs dst )
        ( vec_push [i] . o arcs flags )
        ( vec_push [i] . o arcs 0 )  // COUNT
        ( vec_push [i] . o arcs 0 )  // VALID
        ( vec_set [i] . o fns + * fi GFN_W GFN_ARC_N
        + 1 ( __g_fn o fi GFN_ARC_N ) )
        = q + q 8
    }
    ^ T
}

// A LINES record is a block number followed by line numbers, with a
// zero word introducing a new source-file name and a zero-length name
// ending the record. A block can span more than one file: a call that was
// inlined, or — in NURL — a closure body whose declaration site lives in
// the enclosing function's file.
// Returns the file index the record ended on, or -2 for a line number no
// source file could have and -3 for a block the function does not have.
// Neither is a record to skip: nothing else in such a file can be trusted
// either.
@ __g_notes_lines * GcovObj o i fi * u p i body i end → i {
    ? > + body 4 end { ^ -1 } {}
    : i blk ( __g_u32 p body )
    ? >= blk ( __g_fn o fi GFN_NBLOCK ) { ^ -3 } {}
    : ~ i src ( __g_fn o fi GFN_SRC )
    : ~ i q + body 4
    ~ <= + q 4 end {
        : i w ( __g_u32 p q )
        ? > w GCOV_MAX_LINE { ^ -2 } {}
        ? != w 0 {
            ( vec_push [i] . o blines blk )
            ( vec_push [i] . o blines src )
            ( vec_push [i] . o blines w )
            ( vec_set [i] . o fns + * fi GFN_W GFN_BL_N
            + 1 ( __g_fn o fi GFN_BL_N ) )
            = q + q 4
        } {
            = q + q 4
            ? > + q 4 end { = q end } {
                : i namew ( __g_u32 p q )
                ? | <= namew 0 > + q + 4 * namew 4 end { = q end } {
                    : String f ( __g_str p + q 4 namew end )
                    = src ( __g_file_idx o f )
                    ( string_free f )
                    = q + q + 4 * namew 4
                }
            }
        }
    }
    ^ src
}

// ── Data (.gcda) ─────────────────────────────────────────────────

@ __g_read_data * GcovObj o ( Vec u ) buf → !v GcovErr {
    : i len ( vec_len [u] buf )
    ? < len 12 { ^ @ !v GcovErr { F GcovTruncated } } {}
    : *u p ( vec_data [u] buf )
    // "adcg" — the .gcda spelling of the same reversed magic.
    ? ! & & == 97 # i . p 0 == 100 # i . p 1
    & == 99 # i . p 2 == 103 # i . p 3
    { ^ @ !v GcovErr { F GcovBadMagic } } {}
    ? ! ( __g_version_ok p 4 ) { ^ @ !v GcovErr { F GcovBadVersion } } {}
    // The stamp ties data to notes. A stale .gcda read against fresh notes
    // silently mis-attributes every counter, so it is an error, not a warning.
    ? != ( __g_u32 p 8 ) . o stamp { ^ @ !v GcovErr { F GcovStampMismatch } } {}

    : ~ i off 12
    : ~ i cur -1
    ~ <= + off 8 len {
        : i tag ( __g_u32 p off )
        : i words ( __g_u32 p + off 4 )
        : i body + off 8
        : i end + body * words 4
        ? > end len { ^ @ !v GcovErr { F GcovTruncated } } {}
        ? & == tag 0 == words 0 { = off len } {
            ? == tag GCOV_TAG_FUNCTION {
                = cur ? >= words 1 ( __g_fn_by_ident o ( __g_u32 p body ) ) -1
                // The file stamp says the pair came from one build. These
                // say this FUNCTION did: a notes file that was corrupted
                // after the fact keeps the stamp and loses these, and
                // every counter after it would land on the wrong arcs.
                ? & >= cur 0 >= words 3 {
                    ? | != ( __g_u32 p + body 4 ) ( __g_fn o cur GFN_LCS )
                    != ( __g_u32 p + body 8 ) ( __g_fn o cur GFN_CCS ) {
                        ^ @ !v GcovErr { F GcovChecksumMismatch }
                    } {}
                } {}
            } {
                ? == tag GCOV_TAG_COUNTER {
                    ? >= cur 0 { ( __g_data_counters o cur p body / words 2 ) } {}
                } {
                    // The program summary carries the run count: how many
                    // times the instrumented binary has exited into this
                    // file. Re-running accumulates, and the report says so.
                    ? & == tag GCOV_TAG_PROGRAM >= words 3 {
                        = . o runs ( __g_u32 p + body 8 )
                    } {}
                }
            }
            = off end
        }
    }
    = . o has_data T
    ^ @ !v GcovErr { T 0 }
}

@ __g_data_counters * GcovObj o i fi * u p i body i n → v {
    : i have ( __g_fn o fi GFN_CTR_N )
    ? == have 0 {
        ( vec_set [i] . o fns + * fi GFN_W GFN_CTR_OFF ( vec_len [i] . o counters ) )
        ( vec_set [i] . o fns + * fi GFN_W GFN_CTR_N n )
        : ~ i k 0
        ~ < k n {
            ( vec_push [i] . o counters ( __g_u64 p + body * k 8 ) )
            = k + k 1
        }
        ^ v
    } {}
    // A second COUNTER record for the same function accumulates: that is
    // how a program that ran twice reports twice the traffic.
    : i base ( __g_fn o fi GFN_CTR_OFF )
    : ~ i k 0
    ~ & < k n < k have {
        ( vec_set [i] . o counters + base k
        + ( __g_ctr o + base k ) ( __g_u64 p + body * k 8 ) )
        = k + k 1
    }
}

// ── Small accessors ──────────────────────────────────────────────

@ __g_fn * GcovObj o i fi i field → i {
    ^ ?? ( vec_get [i] . o fns + * fi GFN_W field ) { T x → x F _ → 0 }
}

@ __g_ctr * GcovObj o i idx → i {
    ^ ?? ( vec_get [i] . o counters idx ) { T x → x F _ → 0 }
}

@ __g_arc * GcovObj o i ai i field → i {
    ^ ?? ( vec_get [i] . o arcs + ai field ) { T x → x F _ → 0 }
}

@ __g_fn_by_ident * GcovObj o i ident → i {
    : i n ( gcov_fn_count o )
    : ~ i i 0
    ~ < i n {
        ? == ident ( __g_fn o i GFN_IDENT ) { ^ i } {}
        = i + i 1
    }
    ^ -1
}

@ gcov_fn_count * GcovObj o → i {
    ^ / ( vec_len [i] . o fns ) GFN_W
}

@ gcov_fn_name * GcovObj o i fi → s {
    ^ ?? ( vec_get [String] . o fn_names fi ) { T x → ( string_data x ) F _ → `` }
}

@ gcov_fn_src * GcovObj o i fi → i { ^ ( __g_fn o fi GFN_SRC ) }

@ gcov_fn_line * GcovObj o i fi → i { ^ ( __g_fn o fi GFN_LINE ) }

@ gcov_fn_nblocks * GcovObj o i fi → i { ^ ( __g_fn o fi GFN_NBLOCK ) }

// Where this function's blocks start in the object-wide block table. An
// index over all blocks needs one flat numbering, and this is it.
@ gcov_fn_blk_off * GcovObj o i fi → i { ^ ( __g_fn o fi GFN_BLK_OFF ) }

@ gcov_total_blocks * GcovObj o → i { ^ ( vec_len [i] . o blk_count ) }

@ gcov_total_arcs * GcovObj o → i { ^ / ( vec_len [i] . o arcs ) GARC_W }

@ gcov_block_count * GcovObj o i fi i blk → i {
    ^ ?? ( vec_get [i] . o blk_count + ( __g_fn o fi GFN_BLK_OFF ) blk ) {
        T x → x
        F _ → 0
    }
}

@ gcov_file_count * GcovObj o → i { ^ ( vec_len [String] . o files ) }

@ gcov_runs * GcovObj o → i { ^ . o runs }

@ gcov_notes_path * GcovObj o → s { ^ ( string_data . o notes ) }

@ gcov_data_path * GcovObj o → s { ^ ( string_data . o data ) }

@ gcov_file_path * GcovObj o i idx → s {
    ^ ?? ( vec_get [String] . o files idx ) { T x → ( string_data x ) F _ → `` }
}

// The block-line rows of one function, as a half-open range over `blines`.
@ gcov_fn_bl_first * GcovObj o i fi → i { ^ ( __g_fn o fi GFN_BL_OFF ) }

@ gcov_fn_bl_end * GcovObj o i fi → i {
    ^ + ( __g_fn o fi GFN_BL_OFF ) * GBL_W ( __g_fn o fi GFN_BL_N )
}

@ gcov_bl_block * GcovObj o i row → i {
    ^ ?? ( vec_get [i] . o blines + row GBL_BLOCK ) { T x → x F _ → 0 }
}

@ gcov_bl_src * GcovObj o i row → i {
    ^ ?? ( vec_get [i] . o blines + row GBL_SRC ) { T x → x F _ → 0 }
}

@ gcov_bl_line * GcovObj o i row → i {
    ^ ?? ( vec_get [i] . o blines + row GBL_LINE ) { T x → x F _ → 0 }
}

@ gcov_fn_arc_first * GcovObj o i fi → i { ^ ( __g_fn o fi GFN_ARC_OFF ) }

@ gcov_fn_arc_end * GcovObj o i fi → i {
    ^ + ( __g_fn o fi GFN_ARC_OFF ) * GARC_W ( __g_fn o fi GFN_ARC_N )
}

@ gcov_arc_src * GcovObj o i ai → i { ^ ( __g_arc o ai GARC_SRC ) }

@ gcov_arc_dst * GcovObj o i ai → i { ^ ( __g_arc o ai GARC_DST ) }

@ gcov_arc_flags * GcovObj o i ai → i { ^ ( __g_arc o ai GARC_FLAGS ) }

@ gcov_arc_count * GcovObj o i ai → i { ^ ( __g_arc o ai GARC_COUNT ) }

// An arc the instrumenter treated as a real branch. Fake arcs (the ones
// LLVM adds for abnormal exits) are not branches a test can take.
@ gcov_arc_is_branch * GcovObj o i ai → b {
    ^ == 0 & ( __g_arc o ai GARC_FLAGS ) GCOV_ARC_FAKE
}

// ── Solving the flow graph ───────────────────────────────────────
//
// Only the arcs OUTSIDE the instrumenter's spanning tree carry a counter.
// Everything else follows from conservation of flow — what enters a block
// leaves it — and recovering it is the reader's real work.
//
// This is gcov's own edge-propagation, kept deliberately faithful:
//
//   * a counted arc takes its counter, in storage order, and adds to the
//     count of the block it LEAVES,
//   * a synthetic arc is added from the exit block back to the entry,
//     closing the graph so that flow is conserved even for a function
//     that only ever falls out of the bottom,
//   * every block is then walked; each tree arc's count is the excess of
//     the sub-tree hanging off it,
//   * finally every tree arc but the synthetic one adds to the count of
//     the block it leaves.
//
// An equivalent-looking fixed point is not good enough here. On a
// function with abnormal control flow — anything that forks, or does not
// return the way it was entered — the two disagree, and the difference
// shows up as a percentage that is quietly a few points wrong.

@ __g_arc_field * GcovObj o i ai i field → i {
    ^ ?? ( vec_get [i] . o arcs + ai field ) { T x → x F _ → 0 }
}

@ __g_on_tree * GcovObj o i ai → b {
    ^ != 0 & ( __g_arc_field o ai GARC_FLAGS ) GCOV_ARC_ON_TREE
}

// ── The edge index ───────────────────────────────────────────────

@ __g_ix ( Vec i ) v i idx → i {
    ^ ?? ( vec_get [i] v idx ) { T x → x F _ → 0 }
}

@ __g_zeros i n → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v 0 ) = k + k 1 }
    ^ v
}

// Append to the TAIL, so a chain keeps storage order. gcov numbers a
// block's branches in the order the notes stored them, and a report that
// renumbered them would not merge with anyone else's.
@ __g_link ( Vec i ) head ( Vec i ) tail ( Vec i ) next i key i slot → v {
    ? == 0 ( __g_ix head key ) {
        ( vec_set [i] head key + slot 1 )
    } {
        ( vec_set [i] next - ( __g_ix tail key ) 1 + slot 1 )
    }
    ( vec_set [i] tail key + slot 1 )
}

@ __g_index_build * GcovObj o → v {
    : i nblk ( gcov_total_blocks o )
    : i narc ( gcov_total_arcs o )
    // These start empty from `gcov_new` so that an error path can still
    // free the object; replacing a Vec field drops the old handle on the
    // floor unless it is released first.
    ( vec_free [i] . o pred_head )
    ( vec_free [i] . o pred_tail )
    ( vec_free [i] . o pred_next )
    ( vec_free [i] . o succ_head )
    ( vec_free [i] . o succ_tail )
    ( vec_free [i] . o succ_next )
    = . o pred_head ( __g_zeros nblk )
    = . o pred_tail ( __g_zeros nblk )
    = . o pred_next ( __g_zeros narc )
    = . o succ_head ( __g_zeros nblk )
    = . o succ_tail ( __g_zeros nblk )
    = . o succ_next ( __g_zeros narc )
    : i nfn ( gcov_fn_count o )
    : ~ i fi 0
    ~ < fi nfn {
        : i base ( __g_fn o fi GFN_BLK_OFF )
        : i a0 ( __g_fn o fi GFN_ARC_OFF )
        : i aend ( gcov_fn_arc_end o fi )
        : ~ i ai a0
        ~ < ai aend {
            : i slot / ai GARC_W
            ( __g_link . o succ_head . o succ_tail . o succ_next
            + base ( __g_arc_field o ai GARC_SRC ) slot )
            ( __g_link . o pred_head . o pred_tail . o pred_next
            + base ( __g_arc_field o ai GARC_DST ) slot )
            = ai + ai GARC_W
        }
        = fi + fi 1
    }
}

// The first arc entering (`side` 0) or leaving (`side` 1) a block, as a
// chain cursor: non-zero is an arc slot plus one, zero is the end.
@ gcov_edge_first * GcovObj o i fi i blk i side → i {
    : i key + ( __g_fn o fi GFN_BLK_OFF ) blk
    ^ ? == side 0 ( __g_ix . o pred_head key ) ( __g_ix . o succ_head key )
}

@ gcov_edge_next * GcovObj o i cursor i side → i {
    ^ ? == side 0 ( __g_ix . o pred_next - cursor 1 ) ( __g_ix . o succ_next - cursor 1 )
}

// The arc a cursor points at, as an index into the arc table.
@ gcov_edge_arc i cursor → i { ^ * - cursor 1 GARC_W }

// ── Propagation ──────────────────────────────────────────────────

// Stack frame layout for the walk below. An explicit stack, not
// recursion: a deeply nested function would otherwise decide how much
// stack a coverage report needs.
//
// The frame carries a CURSOR into the block's arc chain rather than a
// count of how many arcs it has consumed. Counting means re-walking the
// chain to find the next one, which is quadratic in a block's degree —
// invisible on ordinary code, and a hang on a graph where one block has
// thousands of arcs pointing at it.
: i GST_W 6
: i GST_BLK 0
: i GST_PRED 1  // arc index we arrived by, -1 at a root
: i GST_INDST 2  // did we arrive along that arc's direction?
: i GST_SIDE 3  // -1 not started, 0 walking the arcs in, 1 the arcs out
: i GST_CUR 4  // chain cursor, 0 when this side is exhausted
: i GST_EXCESS 5

@ __g_st ( Vec i ) st i sp i field → i {
    ^ ?? ( vec_get [i] st + * sp GST_W field ) { T x → x F _ → 0 }
}

@ __g_st_set ( Vec i ) st i sp i field i value → v {
    ( vec_set [i] st + * sp GST_W field value )
}

@ __g_st_push ( Vec i ) st i sp i blk i pred i indst → v {
    : i need * + sp 1 GST_W
    ~ < ( vec_len [i] st ) need { ( vec_push [i] st 0 ) }
    ( __g_st_set st sp GST_BLK blk )
    ( __g_st_set st sp GST_PRED pred )
    ( __g_st_set st sp GST_INDST indst )
    ( __g_st_set st sp GST_SIDE -1 )
    ( __g_st_set st sp GST_CUR 0 )
    ( __g_st_set st sp GST_EXCESS 0 )
}

// One walk out from `root` along the spanning tree. Each tree arc's count
// is the excess of everything hanging off it: what the counted arcs on
// that side could not account for.
@ __g_propagate * GcovObj o i fi i root ( Vec i ) visited ( Vec i ) st → v {
    : ~ i sp 0
    ( __g_st_push st sp root -1 0 )
    ~ >= sp 0 {
        : i blk ( __g_st st sp GST_BLK )
        : i side ( __g_st st sp GST_SIDE )
        ? < side 0 {
            // Arcs that do not in fact form a tree — bad input, or an arc
            // set the instrumenter never promised — must not spin forever.
            ? != 0 ( __g_ix visited blk ) {
                = sp - sp 1
            } {
                ( vec_set [i] visited blk 1 )
                ( __g_st_set st sp GST_SIDE 0 )
                ( __g_st_set st sp GST_CUR ( gcov_edge_first o fi blk 0 ) )
            }
        } {
            : i cur ( __g_st st sp GST_CUR )
            ? > cur 0 {
                : i e ( gcov_edge_arc cur )
                ( __g_st_set st sp GST_CUR ( gcov_edge_next o cur side ) )
                ? != e ( __g_st st sp GST_PRED ) {
                    ? ( __g_on_tree o e ) {
                        : i next_blk ? == side 0
                        ( __g_arc_field o e GARC_SRC ) ( __g_arc_field o e GARC_DST )
                        = sp + sp 1
                        ( __g_st_push st sp next_blk e side )
                    } {
                        : i c ( __g_arc_field o e GARC_COUNT )
                        ( __g_st_set st sp GST_EXCESS
                        ? == side 0
                        + ( __g_st st sp GST_EXCESS ) c
                        - ( __g_st st sp GST_EXCESS ) c )
                    }
                } {}
            } {
                ? == side 0 {
                    ( __g_st_set st sp GST_SIDE 1 )
                    ( __g_st_set st sp GST_CUR ( gcov_edge_first o fi blk 1 ) )
                } {
                    : i raw ( __g_st st sp GST_EXCESS )
                    : i excess ? < raw 0 - 0 raw raw
                    : i pred ( __g_st st sp GST_PRED )
                    ? >= pred 0 { ( vec_set [i] . o arcs + pred GARC_COUNT excess ) } {}
                    : i indst ( __g_st st sp GST_INDST )
                    = sp - sp 1
                    ? >= sp 0 {
                        ( __g_st_set st sp GST_EXCESS
                        + ( __g_st st sp GST_EXCESS ) ? != 0 indst - 0 excess excess )
                    } {}
                }
            }
        }
    }
}

@ __g_solve_fn * GcovObj o i fi ( Vec i ) st → v {
    : i nb ( __g_fn o fi GFN_NBLOCK )
    ? < nb 2 { ^ v } {}
    : i a0 ( __g_fn o fi GFN_ARC_OFF )
    : i aend ( gcov_fn_arc_end o fi )
    : i b0 ( __g_fn o fi GFN_BLK_OFF )
    : i c0 ( __g_fn o fi GFN_CTR_OFF )
    : i cn ( __g_fn o fi GFN_CTR_N )

    // The counted arcs take their counters in storage order, and each
    // adds to the count of the block it leaves.
    : ~ i ci 0
    : ~ i ai a0
    ~ < ai aend {
        ? ! ( __g_on_tree o ai ) {
            : i c ? < ci cn ( __g_ctr o + c0 ci ) 0
            ( vec_set [i] . o arcs + ai GARC_COUNT c )
            ( vec_set [i] . o arcs + ai GARC_VALID 1 )
            : i src ( __g_arc_field o ai GARC_SRC )
            ( vec_set [i] . o blk_count + b0 src + ( gcov_block_count o fi src ) c )
            = ci + ci 1
        } {}
        = ai + ai GARC_W
    }

    : ( Vec i ) visited ( __g_zeros nb )
    : ~ i b 0
    ~ < b nb { ( __g_propagate o fi b visited st ) = b + b 1 }
    ( vec_free [i] visited )

    // Every tree arc now adds to the block it leaves — except the last,
    // which is the synthetic exit-to-entry arc. The instrumenter never
    // emitted that one, and counting it would credit the exit block with
    // traffic the program never made.
    : ~ i ntree 0
    = ai a0
    ~ < ai aend {
        ? ( __g_on_tree o ai ) { = ntree + ntree 1 } {}
        = ai + ai GARC_W
    }
    : ~ i seen 0
    = ai a0
    ~ < ai aend {
        ? ( __g_on_tree o ai ) {
            ? < seen - ntree 1 {
                : i src ( __g_arc_field o ai GARC_SRC )
                ( vec_set [i] . o blk_count + b0 src
                + ( gcov_block_count o fi src ) ( __g_arc_field o ai GARC_COUNT ) )
            } {}
            = seen + seen 1
        } {}
        = ai + ai GARC_W
    }
}

// Without data there is nothing to solve: every counter is zero, every
// block is zero, and the report says so.
@ gcov_solve * GcovObj o → v {
    ? ! . o has_data { ^ v } {}
    : ( Vec i ) st ( vec_new [i] )
    : i n ( gcov_fn_count o )
    : ~ i i 0
    ~ < i n { ( __g_solve_fn o i st ) = i + i 1 }
    ( vec_free [i] st )
}

// ── Entry points ─────────────────────────────────────────────────

@ gcov_new → *GcovObj {
    : *GcovObj o # *GcovObj ( nurl_alloc Z GcovObj )
    = . o notes ( string_new )
    = . o data ( string_new )
    = . o stamp 0
    = . o runs 0
    = . o has_data F
    = . o files ( vec_new [String] )
    = . o fns ( vec_new [i] )
    = . o fn_names ( vec_new [String] )
    = . o blk_count ( vec_new [i] )
    = . o arcs ( vec_new [i] )
    = . o blines ( vec_new [i] )
    = . o counters ( vec_new [i] )
    = . o pred_head ( vec_new [i] )
    = . o pred_next ( vec_new [i] )
    = . o pred_tail ( vec_new [i] )
    = . o succ_head ( vec_new [i] )
    = . o succ_next ( vec_new [i] )
    = . o succ_tail ( vec_new [i] )
    ^ o
}

@ gcov_free sink * GcovObj o → v {
    ( string_free . o notes )
    ( string_free . o data )
    ( __g_free_strs . o files )
    ( __g_free_strs . o fn_names )
    ( vec_free [i] . o fns )
    ( vec_free [i] . o blk_count )
    ( vec_free [i] . o arcs )
    ( vec_free [i] . o blines )
    ( vec_free [i] . o counters )
    ( vec_free [i] . o pred_head )
    ( vec_free [i] . o pred_next )
    ( vec_free [i] . o pred_tail )
    ( vec_free [i] . o succ_head )
    ( vec_free [i] . o succ_next )
    ( vec_free [i] . o succ_tail )
    ( nurl_free # s o )
}

@ __g_free_strs ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] v i ) { T s → ( string_free s ) F _ → {} }
        = i + i 1
    }
    ( vec_free [String] v )
}

// Read one coverage object: the notes, and the data if it is there.
//
// A missing .gcda is NOT an error — it is the answer "this program was
// built but never run", and a coverage report has to be able to say that.
// Every counter then reads zero, which is exactly what it means.
@ gcov_read s notes_path s data_path → !*GcovObj GcovErr {
    : *GcovObj o ( gcov_new )
    ( string_push_str . o notes notes_path )
    : ~ i failed 0
    : ~ GcovErr err GcovNoNotes
    ?? ( read_file_bytes notes_path ) {
        T nb → {
            ?? ( __g_read_notes o nb ) {
                T _ → {}
                F e → { = failed 1 = err e }
            }
            ( vec_free [u] nb )
        }
        F _ → { = failed 1 = err GcovNoNotes }
    }
    ? != failed 0 { ( gcov_free o ) ^ @ !*GcovObj GcovErr { F err } } {}

    ? ( file_exists data_path ) {
        ( string_push_str . o data data_path )
        ?? ( read_file_bytes data_path ) {
            T db → {
                ?? ( __g_read_data o db ) {
                    T _ → {}
                    F e → { = failed 1 = err e }
                }
                ( vec_free [u] db )
            }
            F _ → {}
        }
    } {}
    ? != failed 0 { ( gcov_free o ) ^ @ !*GcovObj GcovErr { F err } } {}

    ( __g_index_build o )
    ( gcov_solve o )
    ^ @ !*GcovObj GcovErr { T o }
}
