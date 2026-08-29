// mermaid-server/src/layout.nu — layered (Sugiyama-style) flowchart layout.
//
// Five passes, all integer arithmetic so the emitted SVG carries no float
// formatting:
//
//   1. size     — every node measured from its label and its shape, using
//                 the template's font size, padding and glyph scale.
//   2. rank     — depth-first search marks the back edges that would make
//                 the graph cyclic, then a longest-path pass over what is
//                 left assigns each node to a layer.
//   3. split    — an edge crossing more than one layer boundary is cut
//                 into unit-length segments joined by DUMMY nodes, one per
//                 layer it passes through. Dummies are laid out like any
//                 other node, so a long edge reserves its own corridor
//                 instead of being drawn straight through whatever happens
//                 to sit between its endpoints, and the renderer gets the
//                 bend points as the edge's route.
//   4. order    — barycentre sweeps down and up the layers to pull linked
//                 nodes towards each other, which is what removes most
//                 crossings. Dummies take part, so long edges bend towards
//                 their neighbours rather than cutting across them.
//   5. place    — cross-axis positions from the ordering, refined twice
//                 towards the mean of each node's neighbours and then
//                 de-overlapped; layer positions from the running maximum
//                 layer thickness.
//
// The result is direction-agnostic until the last step: everything is
// computed on a (main, cross) axis pair and only then mapped to x/y for
// TD / LR / BT / RL.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `graph.nu`
$ `theme.nu`

: MmdPt {
    i x
    i y
}

: MmdBox {
    i x
    i y
    i w
    i h
    i rank
    i order
}

// A width/height pair.
: MmdSize {
    i w
    i h
}

: MmdLayout {
    ( Vec MmdBox ) boxes
    ( Vec MmdPt ) route  // every edge's bend points, concatenated
    ( Vec i ) route_start  // per edge: first bend point
    ( Vec i ) route_len  // per edge: how many
    i width
    i height
    i ranks
}

@ mmd_layout_free MmdLayout l → v {
    ( vec_free [MmdBox] . l boxes )
    ( vec_free [MmdPt] . l route )
    ( vec_free [i] . l route_start )
    ( vec_free [i] . l route_len )
}

@ mmd_layout_box MmdLayout l i idx → MmdBox {
    ?? ( vec_get [MmdBox] . l boxes idx ) {
        T b → ^ b
        F _ → {}
    }
    ^ @ MmdBox { 0 0 0 0 0 0 }
}

// How many bend points edge `e` routes through (0 for a direct link).
@ mmd_layout_bends MmdLayout l i e → i {
    ?? ( vec_get [i] . l route_len e ) {
        T n → ^ n
        F _ → {}
    }
    ^ 0
}

@ mmd_layout_bend MmdLayout l i e i k → MmdPt {
    ?? ( vec_get [i] . l route_start e ) {
        T from → {
            ?? ( vec_get [MmdPt] . l route + from k ) {
                T p → ^ p
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ @ MmdPt { 0 0 }
}

// ── Small integer-vector helpers ─────────────────────────────────────

@ __mmdl_get ( Vec i ) v i idx → i {
    ?? ( vec_get [i] v idx ) {
        T x → ^ x
        F _ → {}
    }
    ^ 0
}

@ __mmdl_put ( Vec i ) v i idx i x → v {
    ( vec_set [i] v idx x )
}

@ __mmdl_filled i n i x → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n {
        ( vec_push [i] v x )
        = k + k 1
    }
    ^ v
}

// ── 1. Measurement ───────────────────────────────────────────────────
//
// No font metrics are available to a pure server, so glyph advances are
// estimated from a small width table in percent of the font size. It is
// deliberately generous for the wide letters: a box slightly too big reads
// as deliberate, a box too small clips the text.

@ __mmdl_char_w i c → i {
    ? >= c 128 {
        // UTF-8: charge the lead byte, ignore continuations.
        ? == & c 192 128 { ^ 0 } {}
        ^ 62
    } {}
    ? == c 32 { ^ 30 } {}
    ? | == c 105 | == c 108 | == c 106 == c 73 { ^ 30 } {}  // i l j I
    ? | == c 124 | == c 46 | == c 44 == c 58 { ^ 30 } {}  // | . , :
    ? | == c 59 | == c 33 | == c 39 == c 96 { ^ 30 } {}  // ; ! ' `
    ? | == c 116 | == c 102 | == c 114 == c 47 { ^ 38 } {}  // t f r /
    ? | == c 40 | == c 41 | == c 91 == c 93 { ^ 38 } {}  // ( ) [ ]
    ? | == c 123 | == c 125 == c 92 { ^ 38 } {}  // { } backslash
    ? | == c 109 | == c 119 == c 37 { ^ 94 } {}  // m w %
    ? | == c 77 | == c 87 == c 64 { ^ 94 } {}  // M W @
    ? & >= c 65 <= c 90 { ^ 70 } {}  // A-Z
    ^ 57
}

// Width in percent-of-font-size units of the widest `\n`-separated line.
@ _mmdl_text_units s text → i {
    : i n ( nurl_str_len text )
    : ~ i best 0
    : ~ i cur 0
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at text n k )
        ? == c 10 {
            ? > cur best { = best cur } {}
            = cur 0
        } { = cur + cur ( __mmdl_char_w c ) }
        = k + k 1
    }
    ? > cur best { = best cur } {}
    ^ best
}

@ mmd_text_lines s text → i {
    : i n ( nurl_str_len text )
    : ~ i lines 1
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_at text n k ) 10 { = lines + lines 1 } {}
        = k + k 1
    }
    ^ lines
}

// Shape-specific growth: a diamond or a circle needs more box than the
// text it holds. Percentages are themable per shape.
@ __mmdl_shape_grow MmdTheme t i shape i w i h → MmdSize {
    : s nm ( mmd_shape_name shape )
    : ~ i dx 0
    : ~ i dy 0
    ? == shape MMD_SHAPE_DIAMOND { = dx / * w 45 100 = dy / * h 55 100 } {}
    ? == shape MMD_SHAPE_HEXAGON { = dx / h 2 } {}
    ? == shape MMD_SHAPE_STADIUM { = dx / h 3 } {}
    ? == shape MMD_SHAPE_ROUND { = dx / h 5 } {}
    ? == shape MMD_SHAPE_CYLINDER { = dy 14 } {}
    ? == shape MMD_SHAPE_SUBROUTINE { = dx 16 } {}
    ? == shape MMD_SHAPE_FLAG { = dx 16 } {}
    ? == shape MMD_SHAPE_PARALLELOGRAM { = dx 22 } {}
    ? == shape MMD_SHAPE_PARALLELOGRAM_ALT { = dx 22 } {}
    ? == shape MMD_SHAPE_TRAPEZOID { = dx 30 } {}
    ? == shape MMD_SHAPE_TRAPEZOID_ALT { = dx 30 } {}
    = dx ( mmd_theme_var_int t `node` nm `grow_x` dx )
    = dy ( mmd_theme_var_int t `node` nm `grow_y` dy )
    ^ @ MmdSize { + w dx + h dy }
}

// ── 2. Ranking ───────────────────────────────────────────────────────

// Depth-first search marking back edges (an edge into a node still on the
// DFS stack) so the longest-path pass below runs on an acyclic graph.
@ __mmdl_dfs MmdGraph g ( Vec i ) color ( Vec i ) back i u → v {
    ( __mmdl_put color u 1 )
    : i ne ( mmd_edge_count g )
    : ~ i k 0
    ~ < k ne {
        ?? ( vec_get [MmdEdge] . g edges k ) {
            T e → {
                ? == . e from u {
                    : i vtx . e to
                    : i cv ( __mmdl_get color vtx )
                    ? == cv 1 { ( __mmdl_put back k 1 ) } {
                        ? == cv 0 { ( __mmdl_dfs g color back vtx ) } {}
                    }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( __mmdl_put color u 2 )
}

@ __mmdl_ranks MmdGraph g ( Vec i ) back → ( Vec i ) {
    : i nn ( mmd_node_count g )
    : i ne ( mmd_edge_count g )
    : ( Vec i ) rank ( __mmdl_filled nn 0 )
    : ( Vec i ) indeg ( __mmdl_filled nn 0 )

    : ~ i k 0
    ~ < k ne {
        ? == ( __mmdl_get back k ) 0 {
            ?? ( vec_get [MmdEdge] . g edges k ) {
                T e → ( __mmdl_put indeg . e to + 1 ( __mmdl_get indeg . e to ) )
                F _ → {}
            }
        } {}
        = k + k 1
    }

    // Kahn's algorithm; `queue` doubles as the topological order.
    : ( Vec i ) queue ( vec_new [i] )
    : ~ i i 0
    ~ < i nn {
        ? == ( __mmdl_get indeg i ) 0 { ( vec_push [i] queue i ) } {}
        = i + i 1
    }
    : ~ i qi 0
    ~ < qi ( vec_len [i] queue ) {
        : i u ( __mmdl_get queue qi )
        : ~ i j 0
        ~ < j ne {
            ? == ( __mmdl_get back j ) 0 {
                ?? ( vec_get [MmdEdge] . g edges j ) {
                    T e → {
                        ? == . e from u {
                            : i vtx . e to
                            : i want + 1 ( __mmdl_get rank u )
                            ? > want ( __mmdl_get rank vtx ) { ( __mmdl_put rank vtx want ) } {}
                            : i d - ( __mmdl_get indeg vtx ) 1
                            ( __mmdl_put indeg vtx d )
                            ? == d 0 { ( vec_push [i] queue vtx ) } {}
                        } {}
                    }
                    F _ → {}
                }
            } {}
            = j + j 1
        }
        = qi + qi 1
    }
    ( vec_free [i] queue )
    ( vec_free [i] indeg )
    ^ rank
}

// ── 4. Ordering ──────────────────────────────────────────────────────
//
// One barycentre sweep over the members of a layer: each node moves to the
// mean position of its neighbours in the adjacent layer. `dir` = 1 sweeps
// from the layer above, -1 from the layer below. `sa`/`sb` are the SEGMENT
// endpoints (post-split), so a long edge pulls through its dummies.

@ __mmdl_bary ( Vec i ) sa ( Vec i ) sb ( Vec i ) rank ( Vec i ) order ( Vec i ) members i from i to i r i dir → v {
    : i nseg ( vec_len [i] sa )
    : i count - to from
    ? <= count 1 { ^ v } {}
    : ( Vec i ) key ( __mmdl_filled count 0 )

    : ~ i m 0
    ~ < m count {
        : i u ( __mmdl_get members + from m )
        : ~ i sum 0
        : ~ i cnt 0
        : ~ i k 0
        ~ < k nseg {
            : i a ( __mmdl_get sa k )
            : i b ( __mmdl_get sb k )
            : ~ i other - 0 1
            ? & == b u == dir 1 { = other a } {}
            ? & == a u == dir - 0 1 { = other b } {}
            ? >= other 0 {
                ? == ( __mmdl_get rank other ) - r dir {
                    = sum + sum * 1000 ( __mmdl_get order other )
                    = cnt + cnt 1
                } {}
            } {}
            = k + k 1
        }
        : i kv ? > cnt 0 / sum cnt * 1000 ( __mmdl_get order u )
        ( __mmdl_put key m kv )
        = m + m 1
    }

    // Insertion sort of the member slice by key — stable, so equal
    // barycentres keep the order the previous sweep produced.
    : ~ i a 1
    ~ < a count {
        : i cur_node ( __mmdl_get members + from a )
        : i cur_key ( __mmdl_get key a )
        : ~ i j - a 1
        : ~ b placed F
        ~ & ! placed >= j 0 {
            ? > ( __mmdl_get key j ) cur_key {
                ( __mmdl_put key + j 1 ( __mmdl_get key j ) )
                ( __mmdl_put members + from + j 1 ( __mmdl_get members + from j ) )
                = j - j 1
            } { = placed T }
        }
        ( __mmdl_put key + j 1 cur_key )
        ( __mmdl_put members + from + j 1 cur_node )
        = a + a 1
    }
    ( vec_free [i] key )

    : ~ i m2 0
    ~ < m2 count {
        ( __mmdl_put order ( __mmdl_get members + from m2 ) m2 )
        = m2 + m2 1
    }
}

// Map a (main, cross) centre onto the canvas.
@ __mmdl_place i dir i main i cross i main_extent → MmdPt {
    ? == dir MMD_DIR_BT { ^ @ MmdPt { cross - main_extent main } } {}
    ? == dir MMD_DIR_LR { ^ @ MmdPt { main cross } } {}
    ? == dir MMD_DIR_RL { ^ @ MmdPt { - main_extent main cross } } {}
    ^ @ MmdPt { cross main }
}

// ── The layout pass ──────────────────────────────────────────────────

@ mmd_layout MmdGraph g MmdTheme t → MmdLayout {
    : i nn ( mmd_node_count g )
    : i ne ( mmd_edge_count g )

    : i font ( mmd_theme_int t `canvas.font_size` 14 )
    : i char_scale ( mmd_theme_int t `layout.char_scale` 100 )
    : i pad_x ( mmd_theme_int t `layout.pad_x` 18 )
    : i pad_y ( mmd_theme_int t `layout.pad_y` 12 )
    : i min_w ( mmd_theme_int t `layout.min_width` 60 )
    : i min_h ( mmd_theme_int t `layout.min_height` 40 )
    : i line_h ( mmd_theme_int t `layout.line_height` + font 5 )
    : i rank_gap ( mmd_theme_int t `layout.rank_gap` 70 )
    : i node_gap ( mmd_theme_int t `layout.node_gap` 36 )
    : i lane ( mmd_theme_int t `layout.lane_width` 18 )
    : i pad ( mmd_theme_int t `canvas.padding` 24 )

    // 1. Sizes.
    : ( Vec i ) wv ( __mmdl_filled nn 0 )
    : ( Vec i ) hv ( __mmdl_filled nn 0 )
    : ~ i i 0
    ~ < i nn {
        ?? ( vec_get [MmdNode] . g nodes i ) {
            T nd → {
                : s label ( string_data . nd label )
                : i units ( _mmdl_text_units label )
                : i tw / / * * units font char_scale 100 100
                : i lines ( mmd_text_lines label )
                : ~ i w + tw * 2 pad_x
                : ~ i h + * lines line_h * 2 pad_y
                ? < w min_w { = w min_w } {}
                ? < h min_h { = h min_h } {}
                : MmdSize grown ( __mmdl_shape_grow t . nd shape w h )
                : ~ i fw . grown w
                : ~ i fh . grown h
                ? == . nd shape MMD_SHAPE_CIRCLE {
                    : i side / * ? > fw fh fw fh 112 100
                    = fw side
                    = fh side
                } {}
                ( __mmdl_put wv i fw )
                ( __mmdl_put hv i fh )
            }
            F _ → {}
        }
        = i + i 1
    }

    // 2. Ranking.
    : ( Vec i ) back ( __mmdl_filled ne 0 )
    : ( Vec i ) color ( __mmdl_filled nn 0 )
    : ~ i k0 0
    ~ < k0 ne {
        ?? ( vec_get [MmdEdge] . g edges k0 ) {
            T e → { ? == . e from . e to { ( __mmdl_put back k0 1 ) } {} }
            F _ → {}
        }
        = k0 + k0 1
    }
    : ~ i s0 0
    ~ < s0 nn {
        ? == ( __mmdl_get color s0 ) 0 { ( __mmdl_dfs g color back s0 ) } {}
        = s0 + s0 1
    }
    ( vec_free [i] color )
    : ( Vec i ) rank ( __mmdl_ranks g back )
    ( vec_free [i] back )

    : ~ i nranks 0
    : ~ i r0 0
    ~ < r0 nn {
        ? >= ( __mmdl_get rank r0 ) nranks { = nranks + 1 ( __mmdl_get rank r0 ) } {}
        = r0 + r0 1
    }
    ? < nranks 1 { = nranks 1 } {}

    // 3. Split long edges. Virtual node space: 0..nn-1 are the real nodes,
    // everything above is a dummy standing in for one layer crossing.
    : b horizontal | == . g dir MMD_DIR_LR == . g dir MMD_DIR_RL
    : ( Vec i ) vrank ( vec_new [i] )
    : ( Vec i ) vcross ( vec_new [i] )
    : ( Vec i ) vmain ( vec_new [i] )
    : ~ i v0 0
    ~ < v0 nn {
        ( vec_push [i] vrank ( __mmdl_get rank v0 ) )
        ( vec_push [i] vcross ? horizontal ( __mmdl_get hv v0 ) ( __mmdl_get wv v0 ) )
        ( vec_push [i] vmain ? horizontal ( __mmdl_get wv v0 ) ( __mmdl_get hv v0 ) )
        = v0 + v0 1
    }

    : ( Vec i ) sa ( vec_new [i] )
    : ( Vec i ) sb ( vec_new [i] )
    : ( Vec i ) route_start ( __mmdl_filled ne 0 )
    : ( Vec i ) route_len ( __mmdl_filled ne 0 )
    : ( Vec i ) route_nodes ( vec_new [i] )
    : ( Vec i ) chain ( vec_new [i] )

    : ~ i k 0
    ~ < k ne {
        ( __mmdl_put route_start k ( vec_len [i] route_nodes ) )
        ?? ( vec_get [MmdEdge] . g edges k ) {
            T e → {
                : i u . e from
                : i w . e to
                ? != u w {
                    : i ru ( __mmdl_get rank u )
                    : i rw ( __mmdl_get rank w )
                    : i lo ? < ru rw ru rw
                    : i hi ? < ru rw rw ru
                    ? <= - hi lo 1 {
                        ( vec_push [i] sa u )
                        ( vec_push [i] sb w )
                    } {
                        ( vec_clear [i] chain )
                        : ~ i prev ? < ru rw u w
                        : i last ? < ru rw w u
                        : ~ i r + lo 1
                        ~ < r hi {
                            : i d ( vec_len [i] vrank )
                            ( vec_push [i] vrank r )
                            ( vec_push [i] vcross lane )
                            ( vec_push [i] vmain 0 )
                            ( vec_push [i] sa prev )
                            ( vec_push [i] sb d )
                            ( vec_push [i] chain d )
                            = prev d
                            = r + r 1
                        }
                        ( vec_push [i] sa prev )
                        ( vec_push [i] sb last )
                        // The route runs from `from` to `to`; the chain was
                        // built in ascending rank order.
                        : i cn ( vec_len [i] chain )
                        ( __mmdl_put route_len k cn )
                        : ~ i c 0
                        ~ < c cn {
                            : i pick ? < ru rw c - - cn 1 c
                            ( vec_push [i] route_nodes ( __mmdl_get chain pick ) )
                            = c + c 1
                        }
                    }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [i] chain )
    : i nv ( vec_len [i] vrank )

    // 4. Ordering.
    : ( Vec i ) members ( vec_with_cap [i] ? > nv 0 nv 1 )
    : ( Vec i ) rank_from ( __mmdl_filled + nranks 1 0 )
    : ~ i r1 0
    ~ < r1 nranks {
        ( __mmdl_put rank_from r1 ( vec_len [i] members ) )
        : ~ i q 0
        ~ < q nv {
            ? == ( __mmdl_get vrank q ) r1 { ( vec_push [i] members q ) } {}
            = q + q 1
        }
        = r1 + r1 1
    }
    ( __mmdl_put rank_from nranks ( vec_len [i] members ) )

    : ( Vec i ) order ( __mmdl_filled nv 0 )
    : ~ i r2 0
    ~ < r2 nranks {
        : i from ( __mmdl_get rank_from r2 )
        : i to ( __mmdl_get rank_from + r2 1 )
        : ~ i m from
        ~ < m to {
            ( __mmdl_put order ( __mmdl_get members m ) - m from )
            = m + m 1
        }
        = r2 + r2 1
    }

    : ~ i sweep 0
    ~ < sweep 4 {
        : ~ i rd 1
        ~ < rd nranks {
            ( __mmdl_bary sa sb vrank order members ( __mmdl_get rank_from rd ) ( __mmdl_get rank_from + rd 1 ) rd 1 )
            = rd + rd 1
        }
        : ~ i ru2 - nranks 2
        ~ >= ru2 0 {
            ( __mmdl_bary sa sb vrank order members ( __mmdl_get rank_from ru2 ) ( __mmdl_get rank_from + ru2 1 ) ru2 - 0 1 )
            = ru2 - ru2 1
        }
        = sweep + sweep 1
    }

    // 5. Placement. Initial cross positions pack each layer, centred on
    // zero; two refinement passes then pull towards the neighbours and
    // push the overlaps apart again.
    : ( Vec i ) centre ( __mmdl_filled nv 0 )
    : ~ i r3 0
    ~ < r3 nranks {
        : i from ( __mmdl_get rank_from r3 )
        : i to ( __mmdl_get rank_from + r3 1 )
        : ~ i total 0
        : ~ i m from
        ~ < m to {
            = total + total ( __mmdl_get vcross ( __mmdl_get members m ) )
            = m + m 1
        }
        = total + total * node_gap - - to from 1
        : ~ i cur / total - 0 2
        : ~ i m2 from
        ~ < m2 to {
            : i u ( __mmdl_get members m2 )
            : i sz ( __mmdl_get vcross u )
            ( __mmdl_put centre u + cur / sz 2 )
            = cur + cur + sz node_gap
            = m2 + m2 1
        }
        = r3 + r3 1
    }

    : i nseg ( vec_len [i] sa )
    : ~ i pass 0
    ~ < pass 2 {
        : ~ i r4 0
        ~ < r4 nranks {
            : i from ( __mmdl_get rank_from r4 )
            : i to ( __mmdl_get rank_from + r4 1 )
            : ~ i m from
            ~ < m to {
                : i u ( __mmdl_get members m )
                : ~ i sum 0
                : ~ i cnt 0
                : ~ i k2 0
                ~ < k2 nseg {
                    : i a ( __mmdl_get sa k2 )
                    : i b ( __mmdl_get sb k2 )
                    : ~ i other - 0 1
                    ? == b u { = other a } {}
                    ? == a u { = other b } {}
                    ? & >= other 0 != other u {
                        ? != ( __mmdl_get vrank other ) r4 {
                            = sum + sum ( __mmdl_get centre other )
                            = cnt + cnt 1
                        } {}
                    } {}
                    = k2 + k2 1
                }
                ? > cnt 0 {
                    : i want / sum cnt
                    ( __mmdl_put centre u / + ( __mmdl_get centre u ) want 2 )
                } {}
                = m + m 1
            }
            : ~ i m3 + from 1
            ~ < m3 to {
                : i u ( __mmdl_get members m3 )
                : i p ( __mmdl_get members - m3 1 )
                : i need + + ( __mmdl_get centre p ) / ( __mmdl_get vcross p ) 2
                + node_gap / ( __mmdl_get vcross u ) 2
                ? < ( __mmdl_get centre u ) need { ( __mmdl_put centre u need ) } {}
                = m3 + m3 1
            }
            = r4 + r4 1
        }
        = pass + pass 1
    }

    // Main-axis position of each layer: running sum of the thickest node.
    : ( Vec i ) rank_pos ( __mmdl_filled + nranks 1 0 )
    : ( Vec i ) rank_thick ( __mmdl_filled nranks 0 )
    : ~ i r5 0
    ~ < r5 nranks {
        : i from ( __mmdl_get rank_from r5 )
        : i to ( __mmdl_get rank_from + r5 1 )
        : ~ i thick 0
        : ~ i m from
        ~ < m to {
            : i sz ( __mmdl_get vmain ( __mmdl_get members m ) )
            ? > sz thick { = thick sz } {}
            = m + m 1
        }
        ( __mmdl_put rank_thick r5 thick )
        ( __mmdl_put rank_pos + r5 1 + + ( __mmdl_get rank_pos r5 ) thick rank_gap )
        = r5 + r5 1
    }
    : i main_extent ? > nranks 0 - ( __mmdl_get rank_pos nranks ) rank_gap 0

    // Cross extent, normalised so the leftmost thing on the canvas starts
    // at zero. Dummies count: a routed edge's lane can sit outside every
    // node's span, and a canvas sized to the nodes alone would clip it.
    : ~ i cmin 0
    : ~ i cmax 0
    : ~ b first T
    : ~ i c1 0
    ~ < c1 nv {
        : i lo - ( __mmdl_get centre c1 ) / ( __mmdl_get vcross c1 ) 2
        : i hi + lo ( __mmdl_get vcross c1 )
        ? first { = cmin lo = cmax hi = first F } {
            ? < lo cmin { = cmin lo } {}
            ? > hi cmax { = cmax hi } {}
        }
        = c1 + c1 1
    }
    : i cross_extent - cmax cmin

    // Map (main, cross) to (x, y).
    : ( Vec MmdBox ) boxes ( vec_with_cap [MmdBox] ? > nn 0 nn 1 )
    : ~ i b0 0
    ~ < b0 nn {
        : i r6 ( __mmdl_get vrank b0 )
        : i main + ( __mmdl_get rank_pos r6 ) / ( __mmdl_get rank_thick r6 ) 2
        : i cross - ( __mmdl_get centre b0 ) cmin
        : MmdPt c ( __mmdl_place . g dir main cross main_extent )
        : MmdBox bx @ MmdBox {
            + pad - . c x / ( __mmdl_get wv b0 ) 2
            + pad - . c y / ( __mmdl_get hv b0 ) 2
            ( __mmdl_get wv b0 )
            ( __mmdl_get hv b0 )
            r6
            ( __mmdl_get order b0 )
        }
        ( vec_push [MmdBox] boxes bx )
        = b0 + b0 1
    }

    : ( Vec MmdPt ) route ( vec_new [MmdPt] )
    : ~ i rn 0
    ~ < rn ( vec_len [i] route_nodes ) {
        : i d ( __mmdl_get route_nodes rn )
        : i r7 ( __mmdl_get vrank d )
        : i main + ( __mmdl_get rank_pos r7 ) / ( __mmdl_get rank_thick r7 ) 2
        : i cross - ( __mmdl_get centre d ) cmin
        : MmdPt c ( __mmdl_place . g dir main cross main_extent )
        ( vec_push [MmdPt] route @ MmdPt { + pad . c x + pad . c y } )
        = rn + rn 1
    }

    : i width + * 2 pad ? horizontal main_extent cross_extent
    : i height + * 2 pad ? horizontal cross_extent main_extent

    ( vec_free [i] wv )
    ( vec_free [i] hv )
    ( vec_free [i] rank )
    ( vec_free [i] vrank )
    ( vec_free [i] vcross )
    ( vec_free [i] vmain )
    ( vec_free [i] sa )
    ( vec_free [i] sb )
    ( vec_free [i] route_nodes )
    ( vec_free [i] members )
    ( vec_free [i] rank_from )
    ( vec_free [i] order )
    ( vec_free [i] centre )
    ( vec_free [i] rank_pos )
    ( vec_free [i] rank_thick )

    ^ @ MmdLayout {
        boxes
        route
        route_start
        route_len
        ? > width * 2 pad width * 2 pad
        ? > height * 2 pad height * 2 pad
        nranks
    }
}
