// nurl-cov/gcovtext.nu — the annotated source listing, in gcov's own format.
//
// One listing per source file: every line of the original, prefixed by how
// many times it ran. A line with no code gets `-`, a line with code that
// never ran gets `#####`, and that column is the whole point — it is where
// you look to find what the tests never touched.
//
//     function classify called 2 returned 100% blocks executed 70%
//             2:    1:@ classify i n → s {
//             2:    2:    ? < n 0 { ^ `negative` } {}
//     branch  0 taken 2
//     branch  1 taken 0
//         #####:    5:    ^ `large`
//
// The layout is deliberately byte-compatible with `llvm-cov gcov -b -c`.
// That is not nostalgia. It means this reader can be checked against an
// independent implementation of the same files, which is the only way to
// know that numbers nobody can compute by hand are right — and the
// package's test suite does exactly that, over the compiler's own corpus.
//
// This renders ONE object. Merged, multi-binary reporting is `report.nu`'s
// job; it cannot answer per-block questions like "blocks executed" and
// does not pretend to.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `gcov.nu`
$ `lines.nu`

// Right-align into a fixed column, the way gcov lays out its gutter.
@ __gt_pad String out s text i width → v {
    : i n ( nurl_str_len text )
    : ~ i k n
    ~ < k width { ( string_push_char out 32 ) = k + k 1 }
    ( string_push_str out text )
}

@ __gt_pad_int String out i value i width → v {
    : String tmp ( string_with_cap 24 )
    ( string_push_int tmp value )
    : i n ( string_len tmp )
    : ~ i k n
    ~ < k width { ( string_push_char out 32 ) = k + k 1 }
    ( string_push_str out ( string_data tmp ) )
    ( string_free tmp )
}

// 9 columns of count, then the line number in 5.
@ __gt_gutter String out b has_code i count i line → v {
    ? ! has_code { ( __gt_pad out `-` 9 ) } {
        ? == count 0 { ( __gt_pad out `#####` 9 ) } { ( __gt_pad_int out count 9 ) }
    }
    ( string_push_char out 58 )
    ( __gt_pad_int out line 5 )
    ( string_push_char out 58 )
}

@ __gt_at ( Vec i ) v i idx → i {
    ^ ?? ( vec_get [i] v idx ) { T x → x F _ → 0 }
}

@ __gt_growto ( Vec i ) v i idx → v {
    : i have ( vec_len [i] v )
    ? > + idx 1 have {
        : ~ i k have
        ~ < k + idx 1 { ( vec_push [i] v 0 ) = k + k 1 }
    } {}
}

@ __gt_header String out s label s value → v {
    ( __gt_gutter out F 0 0 )
    ( string_push_str out label )
    ( string_push_str out value )
    ( string_push_char out 10 )
}

// Render one source file's annotated listing. A file whose text cannot be
// read still gets a listing: the counts are the part that matters, and a
// missing source is not a reason to withhold them.
@ gcovtext_render * GcovObj o i src → String {
    : s path ( gcov_file_path o src )
    : *LineTab t ( lines_build o src )

    : String out ( string_with_cap 65536 )
    ( __gt_header out `Source:` path )
    ( __gt_header out `Graph:` ( gcov_notes_path o ) )
    ( __gt_header out `Data:`
    ? == 0 ( nurl_str_len ( gcov_data_path o ) ) `-` ( gcov_data_path o ) )
    ( __gt_gutter out F 0 0 )
    ( string_push_str out `Runs:` )
    ( string_push_int out ( gcov_runs o ) )
    ( string_push_char out 10 )
    ( __gt_gutter out F 0 0 )
    ( string_push_str out `Programs:` )
    ( string_push_int out ? > ( gcov_runs o ) 0 1 0 )
    ( string_push_char out 10 )

    // Functions starting on a line, chained so the walk below is one pass.
    // Several can share a line: a generic monomorphised four ways, or a
    // closure declared inside a call.
    : i nfr / ( vec_len [i] . t fnrow ) LFN_W
    : ( Vec i ) fhead ( vec_new [i] )
    : ( Vec i ) ftail ( vec_new [i] )
    : ( Vec i ) fnext ( vec_new [i] )
    : ~ i k 0
    ~ < k nfr {
        : i fline ( __gt_at . t fnrow + * k LFN_W LFN_LINE )
        ( __gt_growto fhead fline )
        ( __gt_growto ftail fline )
        ( vec_push [i] fnext 0 )
        ? == 0 ( __gt_at fhead fline ) {
            ( vec_set [i] fhead fline + k 1 )
        } {
            ( vec_set [i] fnext - ( __gt_at ftail fline ) 1 + k 1 )
        }
        ( vec_set [i] ftail fline + k 1 )
        = k + k 1
    }

    : ( Vec String ) lines ( __gt_source_lines path )
    : i nsrc ( vec_len [String] lines )
    : i last ? > nsrc . t maxline nsrc . t maxline
    : i nbr / ( vec_len [i] . t br ) LBR_W
    : ~ i bcur 0
    : ~ i idx 0
    : ~ i l 1
    ~ <= l last {
        : ~ i slot ? < l ( vec_len [i] fhead ) ( __gt_at fhead l ) 0
        ~ > slot 0 {
            ( __gt_fn_header out o
            ( __gt_at . t fnrow + * - slot 1 LFN_W LFN_FN ) )
            = slot ( __gt_at fnext - slot 1 )
        }
        : b has & < l ( vec_len [i] . t exists ) != 0 ( __gt_at . t exists l )
        ( __gt_gutter out has ? has ( __gt_at . t count l ) 0 l )
        ?? ( vec_get [String] lines - l 1 ) {
            T text → ( string_push_str out ( string_data text ) )
            F _ → {}
        }
        ( string_push_char out 10 )
        // Branch rows arrive in ascending line order, so one cursor walks
        // them alongside the source.
        = idx 0
        ~ & < bcur nbr == l ( __gt_at . t br + * bcur LBR_W LBR_LINE ) {
            ( string_push_str out `branch ` )
            ( __gt_pad_int out idx 2 )
            ? == 0 ( __gt_at . t br + * bcur LBR_W LBR_TOTAL ) {
                ( string_push_str out ` never executed` )
            } {
                ( string_push_str out ` taken ` )
                ( string_push_int out ( __gt_at . t br + * bcur LBR_W LBR_COUNT ) )
            }
            ( string_push_char out 10 )
            = idx + idx 1
            = bcur + bcur 1
        }
        = l + l 1
    }

    ( vec_free [i] fhead )
    ( vec_free [i] ftail )
    ( vec_free [i] fnext )
    ( __gt_free_lines lines )
    ( linetab_free t )
    ^ out
}

// How often the function was entered, how often it returned, and how much
// of its body ran. "returned" counts the traffic INTO the exit block
// rather than that block's own solved count: an abnormal exit can leave
// the block unreachable while its incoming arcs are perfectly well known.
@ __gt_fn_header String out * GcovObj o i fi → v {
    : i nb ( gcov_fn_nblocks o fi )
    : i entry ( gcov_block_count o fi 0 )
    : ~ i exitc 0
    ? > nb 1 {
        : ~ i a ( gcov_edge_first o fi 1 0 )
        ~ > a 0 {
            = exitc + exitc ( gcov_arc_count o ( gcov_edge_arc a ) )
            = a ( gcov_edge_next o a 0 )
        }
    } {}
    : ~ i execd 0
    : ~ i b 2
    ~ < b nb {
        ? > ( gcov_block_count o fi b ) 0 { = execd + execd 1 } {}
        = b + b 1
    }
    ( string_push_str out `function ` )
    ( string_push_str out ( gcov_fn_name o fi ) )
    ( string_push_str out ` called ` )
    ( string_push_int out entry )
    ( string_push_str out ` returned ` )
    ( string_push_int out ( gcovtext_pct exitc entry ) )
    ( string_push_str out `% blocks executed ` )
    ( string_push_int out ( gcovtext_pct execd - nb 2 ) )
    ( string_push_str out `%\n` )
}

// gcov's percentage: truncating, except that anything above zero but below
// one percent reports as 1 rather than rounding away to nothing.
@ gcovtext_pct i part i whole → i {
    ? | == part 0 <= whole 0 { ^ 0 } {}
    : i scaled * part 100
    ? < scaled whole { ^ 1 } {}
    ^ / scaled whole
}

// ── Source text ──────────────────────────────────────────────────

@ __gt_source_lines s path → ( Vec String ) {
    ^ ?? ( read_file path ) {
        T text → {
            : ( Vec String ) v ( __gt_split_lines ( string_data text ) )
            ( string_free text )
            v
        }
        F _ → ( vec_new [String] )
    }
}

// Split on newlines without inventing a final empty line for a file that
// ends in one: gcov numbers the lines a person would count.
@ __gt_split_lines s text → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_str_len text )
    : ~ i start 0
    : ~ i i 0
    ~ < i n {
        ? == 10 ( nurl_str_at text n i ) {
            ( vec_push [String] out ( __gt_slice text start - i start ) )
            = start + i 1
        } {}
        = i + i 1
    }
    ? < start n { ( vec_push [String] out ( __gt_slice text start - n start ) ) } {}
    ^ out
}

@ __gt_slice s text i from i len → String {
    : *u at # *u + # i text from
    ^ ( string_from_bytes at len )
}

@ __gt_free_lines ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] v i ) { T s → ( string_free s ) F _ → {} }
        = i + i 1
    }
    ( vec_free [String] v )
}
