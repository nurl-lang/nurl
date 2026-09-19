// nurl-cov/lines.nu — from basic blocks to "this line ran N times".
//
// A line is not a block, and the answer is not "add up the blocks that
// touch it". A condition and the two arms it guards can all carry the same
// source line; adding them reports the line running twice as often as the
// function was entered. The rule that IS correct — and the one `gcov`
// itself implements — measures flow instead of blocks:
//
//   the count of a line is the traffic ENTERING that line's blocks from
//   outside them, plus the traffic that goes round in circles INSIDE them.
//
// The first part is a sum over incoming arcs whose source is not itself on
// the line (the entry block has no predecessors, so its outgoing arcs stand
// in). The second part is what makes a one-line loop report the number of
// iterations rather than the single entry into it; finding it is cycle
// cancelling over the line's own sub-graph, repeatedly draining the
// cheapest arc of some cycle until no cycle is left.
//
// Both halves are needed. Without the first, a loop header reports its
// back-edge only; without the second, it reports the one entry.
//
// The same table drives the annotated listing and the merged report, so
// there is exactly one implementation of the rule in this package.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `gcov.nu`

// Occurrence table stride: one row each time a block names a line.
: i LOC_W 3
: i LOC_LINE 0
: i LOC_FN 1
: i LOC_BLK 2

// Branch table stride.
: i LBR_W 3
: i LBR_LINE 0
: i LBR_COUNT 1  // this arc's traffic
: i LBR_TOTAL 2  // traffic over all arcs leaving the same block

// Function-start table stride.
: i LFN_W 2
: i LFN_LINE 0
: i LFN_FN 1

: LineTab {
    i src  // which of the object's source files this describes
    i maxline
    ( Vec i ) exists  // per line: 1 when some block names it
    ( Vec i ) count  // per line: executions
    ( Vec i ) br  // stride LBR_W, in gcov's print order
    ( Vec i ) fnrow  // stride LFN_W: functions starting on a line
    ( Vec i ) occ  // stride LOC_W
    ( Vec i ) occ_next  // next occurrence on the same line, + 1
    ( Vec i ) head  // per line: first occurrence + 1
    ( Vec i ) tail  // per line: last occurrence + 1
}

@ __ln_at ( Vec i ) v i idx → i {
    ^ ?? ( vec_get [i] v idx ) { T x → x F _ → 0 }
}

@ __ln_grow ( Vec i ) v i idx → v {
    : i have ( vec_len [i] v )
    ? > + idx 1 have {
        : ~ i k have
        ~ < k + idx 1 { ( vec_push [i] v 0 ) = k + k 1 }
    } {}
}

// Append to the tail, so a chain keeps insertion order.
@ __ln_link ( Vec i ) head ( Vec i ) tail ( Vec i ) next i key i slot → v {
    ? == 0 ( __ln_at head key ) {
        ( vec_set [i] head key + slot 1 )
    } {
        ( vec_set [i] next - ( __ln_at tail key ) 1 + slot 1 )
    }
    ( vec_set [i] tail key + slot 1 )
}

@ __ln_zeros i n → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v 0 ) = k + k 1 }
    ^ v
}

// ── Building the table ───────────────────────────────────────────

@ linetab_free sink * LineTab t → v {
    ( vec_free [i] . t exists )
    ( vec_free [i] . t count )
    ( vec_free [i] . t br )
    ( vec_free [i] . t fnrow )
    ( vec_free [i] . t occ )
    ( vec_free [i] . t occ_next )
    ( vec_free [i] . t head )
    ( vec_free [i] . t tail )
    ( nurl_free # s t )
}

@ lines_build * GcovObj o i src → *LineTab {
    : *LineTab t # *LineTab ( nurl_alloc Z LineTab )
    = . t src src
    = . t maxline 0
    = . t exists ( vec_new [i] )
    = . t count ( vec_new [i] )
    = . t br ( vec_new [i] )
    = . t fnrow ( vec_new [i] )
    = . t occ ( vec_new [i] )
    = . t occ_next ( vec_new [i] )
    = . t head ( vec_new [i] )
    = . t tail ( vec_new [i] )
    : i nfn ( gcov_fn_count o )
    : ~ i fi 0
    ~ < fi nfn {
        ? == src ( gcov_fn_src o fi ) {
            : i fl ( gcov_fn_line o fi )
            ( vec_push [i] . t fnrow fl )
            ( vec_push [i] . t fnrow fi )
        } {}
        ( __ln_scan_fn o t fi src )
        = fi + fi 1
    }
    ( __ln_resolve o t )
    ^ t
}

// Walk one function's block-line rows in BLOCK order, which is the order
// gcov visits them and therefore the order a line's blocks are listed in.
// The notes store them per block already, but nothing in the format
// promises ascending order, so the rows are chained per block first.
@ __ln_scan_fn * GcovObj o * LineTab t i fi i src → v {
    : i nb ( gcov_fn_nblocks o fi )
    ? == nb 0 { ^ v } {}
    : i first ( gcov_fn_bl_first o fi )
    : i blend ( gcov_fn_bl_end o fi )
    : i nrow / - blend first GBL_W
    ? == nrow 0 { ^ v } {}
    : ( Vec i ) bhead ( __ln_zeros nb )
    : ( Vec i ) btail ( __ln_zeros nb )
    : ( Vec i ) bnext ( __ln_zeros nrow )
    : ~ i k 0
    ~ < k nrow {
        : i blk ( gcov_bl_block o + first * k GBL_W )
        ? < blk nb { ( __ln_link bhead btail bnext blk k ) } {}
        = k + k 1
    }
    : ~ i b 0
    ~ < b nb {
        : ~ i slot ( __ln_at bhead b )
        ~ > slot 0 {
            : i row + first * - slot 1 GBL_W
            ? == src ( gcov_bl_src o row ) {
                ( __ln_add_occ t ( gcov_bl_line o row ) fi b )
            } {}
            = slot ( __ln_at bnext - slot 1 )
        }
        = b + b 1
    }
    ( vec_free [i] bhead )
    ( vec_free [i] btail )
    ( vec_free [i] bnext )
}

@ __ln_add_occ * LineTab t i line i fi i blk → v {
    : i slot / ( vec_len [i] . t occ ) LOC_W
    ( vec_push [i] . t occ line )
    ( vec_push [i] . t occ fi )
    ( vec_push [i] . t occ blk )
    ( vec_push [i] . t occ_next 0 )
    ( __ln_grow . t head line )
    ( __ln_grow . t tail line )
    ( __ln_grow . t exists line )
    ( __ln_grow . t count line )
    ( vec_set [i] . t exists line 1 )
    ( __ln_link . t head . t tail . t occ_next line slot )
    ? > line . t maxline { = . t maxline line } {}
}

@ __ln_occ * LineTab t i slot i field → i {
    ^ ( __ln_at . t occ + * slot LOC_W field )
}

// Is (fi, blk) one of the blocks on this line? The membership test is what
// separates traffic entering the line from traffic already inside it.
@ __ln_on_line * LineTab t i line i fi i blk → b {
    : ~ i slot ( __ln_at . t head line )
    ~ > slot 0 {
        : i s - slot 1
        ? & == fi ( __ln_occ t s LOC_FN ) == blk ( __ln_occ t s LOC_BLK ) { ^ T } {}
        = slot ( __ln_at . t occ_next s )
    }
    ^ F
}

@ __ln_resolve * GcovObj o * LineTab t → v {
    : ~ i line 1
    ~ <= line . t maxline {
        ? != 0 ( __ln_at . t head line ) {
            ( vec_set [i] . t count line ( __ln_line_count o t line ) )
            ( __ln_line_branches o t line )
        } {}
        = line + line 1
    }
}

@ __ln_line_count * GcovObj o * LineTab t i line → i {
    : ~ i total 0
    : ~ i slot ( __ln_at . t head line )
    ~ > slot 0 {
        : i s - slot 1
        : i fi ( __ln_occ t s LOC_FN )
        : i blk ( __ln_occ t s LOC_BLK )
        ? == blk 0 {
            // The entry block has no predecessors worth trusting: the
            // synthetic exit-to-entry arc is one, and for a function
            // that forks or exits abnormally its count is not the
            // traffic that arrived. gcov reads block 0 from its OUTGOING
            // arcs instead, and so does this.
            : ~ i a ( gcov_edge_first o fi blk 1 )
            ~ > a 0 {
                = total + total ( gcov_arc_count o ( gcov_edge_arc a ) )
                = a ( gcov_edge_next o a 1 )
            }
        } {
            : ~ i a ( gcov_edge_first o fi blk 0 )
            ~ > a 0 {
                : i ai ( gcov_edge_arc a )
                ? ! ( __ln_on_line t line fi ( gcov_arc_src o ai ) ) {
                    = total + total ( gcov_arc_count o ai )
                } {}
                = a ( gcov_edge_next o a 0 )
            }
        }
        = slot ( __ln_at . t occ_next s )
    }
    ^ + total ( __ln_cycles o t line )
}

// ── Branches ─────────────────────────────────────────────────────
//
// A decision is reported on the LAST line its block names, and only when
// the block has more than one way out. The denominator is the traffic over
// all of them: zero means the decision was never reached, which reads very
// differently from "reached, and always went the same way".

@ __ln_line_branches * GcovObj o * LineTab t i line → v {
    : ~ i slot ( __ln_at . t head line )
    ~ > slot 0 {
        : i s - slot 1
        : i fi ( __ln_occ t s LOC_FN )
        : i blk ( __ln_occ t s LOC_BLK )
        ? == line ( __ln_block_last_line o fi blk ) {
            : ~ i n 0
            : ~ i sum 0
            : ~ i a ( gcov_edge_first o fi blk 1 )
            ~ > a 0 {
                = n + n 1
                = sum + sum ( gcov_arc_count o ( gcov_edge_arc a ) )
                = a ( gcov_edge_next o a 1 )
            }
            ? > n 1 {
                = a ( gcov_edge_first o fi blk 1 )
                ~ > a 0 {
                    ( vec_push [i] . t br line )
                    ( vec_push [i] . t br ( gcov_arc_count o ( gcov_edge_arc a ) ) )
                    ( vec_push [i] . t br sum )
                    = a ( gcov_edge_next o a 1 )
                }
            } {}
        } {}
        = slot ( __ln_at . t occ_next s )
    }
}

@ __ln_block_last_line * GcovObj o i fi i blk → i {
    : i first ( gcov_fn_bl_first o fi )
    : i blend ( gcov_fn_bl_end o fi )
    : ~ i last -1
    : ~ i row first
    ~ < row blend {
        ? == blk ( gcov_bl_block o row ) { = last ( gcov_bl_line o row ) } {}
        = row + row GBL_W
    }
    ^ last
}

// ── Cycles ───────────────────────────────────────────────────────
//
// Traffic that never leaves the line: a loop written on one line. Naming
// loops in a flow graph is hard; cancelling cycles is not. Repeatedly find
// any cycle among the line's blocks, drain its cheapest arc, and add what
// was drained. When no cycle is left, the total is the number of times the
// line went round.

@ __ln_cycles * GcovObj o * LineTab t i line → i {
    // Collect the line's distinct blocks as the nodes of a sub-graph.
    : ( Vec i ) nd_fn ( vec_new [i] )
    : ( Vec i ) nd_blk ( vec_new [i] )
    : ~ i slot ( __ln_at . t head line )
    ~ > slot 0 {
        : i s - slot 1
        : i fi ( __ln_occ t s LOC_FN )
        : i blk ( __ln_occ t s LOC_BLK )
        ? ! ( __ln_node_known nd_fn nd_blk fi blk ) {
            ( vec_push [i] nd_fn fi )
            ( vec_push [i] nd_blk blk )
        } {}
        = slot ( __ln_at . t occ_next s )
    }
    : i nn ( vec_len [i] nd_fn )
    ? < nn 2 {
        ( vec_free [i] nd_fn )
        ( vec_free [i] nd_blk )
        ^ 0
    } {}

    // Edges that stay inside the sub-graph, grouped by source node so a
    // walk can index them directly.
    : ( Vec i ) e_to ( vec_new [i] )
    : ( Vec i ) e_cc ( vec_new [i] )
    : ( Vec i ) n_off ( vec_new [i] )
    : ( Vec i ) n_cnt ( vec_new [i] )
    : ~ i u 0
    ~ < u nn {
        ( vec_push [i] n_off ( vec_len [i] e_to ) )
        : i fi ( __ln_at nd_fn u )
        : ~ i cnt 0
        : ~ i a ( gcov_edge_first o fi ( __ln_at nd_blk u ) 1 )
        ~ > a 0 {
            : i ai ( gcov_edge_arc a )
            : i v ( __ln_node_index nd_fn nd_blk fi ( gcov_arc_dst o ai ) )
            ? >= v 0 {
                ( vec_push [i] e_to v )
                ( vec_push [i] e_cc ( gcov_arc_count o ai ) )
                = cnt + cnt 1
            } {}
            = a ( gcov_edge_next o a 1 )
        }
        ( vec_push [i] n_cnt cnt )
        = u + u 1
    }

    : ~ i total 0
    ? > ( vec_len [i] e_to ) 0 {
        : ( Vec i ) travers ( __ln_zeros nn )
        : ( Vec i ) incoming ( __ln_zeros nn )
        : ( Vec i ) st_node ( __ln_zeros + nn 1 )
        : ( Vec i ) st_edge ( __ln_zeros + nn 1 )
        : ( Vec i ) e_from ( __ln_zeros ( vec_len [i] e_to ) )
        = u 0
        ~ < u nn {
            : i off ( __ln_at n_off u )
            : ~ i k 0
            ~ < k ( __ln_at n_cnt u ) { ( vec_set [i] e_from + off k u ) = k + k 1 }
            = u + u 1
        }
        : ~ b more T
        ~ more {
            = u 0
            ~ < u nn {
                ( vec_set [i] travers u 1 )
                ( vec_set [i] incoming u 0 )  // 0 = none; slot + 1 otherwise
                = u + u 1
            }
            : ~ i drained 0
            = u 0
            ~ < u nn {
                ? & != 0 ( __ln_at travers u ) == 0 drained {
                    = drained ( __ln_augment nn e_to e_cc e_from n_off n_cnt
                    travers incoming st_node st_edge u )
                } {}
                = u + u 1
            }
            ? == drained 0 { = more F } { = total + total drained }
        }
        ( vec_free [i] travers )
        ( vec_free [i] incoming )
        ( vec_free [i] st_node )
        ( vec_free [i] st_edge )
        ( vec_free [i] e_from )
    } {}

    ( vec_free [i] nd_fn )
    ( vec_free [i] nd_blk )
    ( vec_free [i] e_to )
    ( vec_free [i] e_cc )
    ( vec_free [i] n_off )
    ( vec_free [i] n_cnt )
    ^ total
}

@ __ln_node_known ( Vec i ) nd_fn ( Vec i ) nd_blk i fi i blk → b {
    ^ >= ( __ln_node_index nd_fn nd_blk fi blk ) 0
}

@ __ln_node_index ( Vec i ) nd_fn ( Vec i ) nd_blk i fi i blk → i {
    : i n ( vec_len [i] nd_fn )
    : ~ i k 0
    ~ < k n {
        ? & == fi ( __ln_at nd_fn k ) == blk ( __ln_at nd_blk k ) { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// One depth-first walk from `src`. Returns what it drained: the cheapest
// arc of the first cycle it closed, subtracted from every arc on that
// cycle, or zero when the walk found none and `src` is exhausted.
@ __ln_augment i nn ( Vec i ) e_to ( Vec i ) e_cc ( Vec i ) e_from
( Vec i ) n_off ( Vec i ) n_cnt ( Vec i ) travers ( Vec i ) incoming
( Vec i ) st_node ( Vec i ) st_edge i src → i {
    : ~ i sp 0
    ( vec_set [i] st_node 0 src )
    ( vec_set [i] st_edge 0 0 )
    // A non-zero marker so the walk treats the root as visited. It is
    // never followed: a cycle closes at a node already on the path, and a
    // self-arc is rejected, so the root's own marker is never dereferenced.
    ( vec_set [i] incoming src -1 )
    ~ >= sp 0 {
        : i u ( __ln_at st_node sp )
        : i ei ( __ln_at st_edge sp )
        ? >= ei ( __ln_at n_cnt u ) {
            ( vec_set [i] travers u 0 )
            = sp - sp 1
        } {
            ( vec_set [i] st_edge sp + ei 1 )
            : i e + ( __ln_at n_off u ) ei
            : i v ( __ln_at e_to e )
            ? ! | | == 0 ( __ln_at e_cc e ) == 0 ( __ln_at travers v ) == v u {
                ? == 0 ( __ln_at incoming v ) {
                    ( vec_set [i] incoming v + e 1 )
                    = sp + sp 1
                    ( vec_set [i] st_node sp v )
                    ( vec_set [i] st_edge sp 0 )
                } {
                    // The cycle is closed. Walk back along `incoming` from
                    // u to v to find its cheapest arc, then drain it.
                    : ~ i minc ( __ln_at e_cc e )
                    : ~ i w u
                    : ~ b going T
                    ~ going {
                        : i ie - ( __ln_at incoming w ) 1
                        ? < ( __ln_at e_cc ie ) minc { = minc ( __ln_at e_cc ie ) } {}
                        = w ( __ln_at e_from ie )
                        ? == w v { = going F } {}
                    }
                    ( vec_set [i] e_cc e - ( __ln_at e_cc e ) minc )
                    = w u
                    = going T
                    ~ going {
                        : i ie - ( __ln_at incoming w ) 1
                        ( vec_set [i] e_cc ie - ( __ln_at e_cc ie ) minc )
                        = w ( __ln_at e_from ie )
                        ? == w v { = going F } {}
                    }
                    ^ minc
                }
            } {}
        }
    }
    ^ 0
}
