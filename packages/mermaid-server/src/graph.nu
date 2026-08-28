// mermaid-server/src/graph.nu — the parsed diagram IR.
//
// One flowchart is a `MmdGraph`: a direction, a node table, an edge table
// and a list of parse warnings. Nodes are addressed by INDEX everywhere
// downstream (layout, render) — `mmd_node_index` interns an id on first
// mention, so a forward reference (`A --> B` before `B[Label]`) resolves to
// the same slot the later declaration fills in.
//
// Shapes and link kinds are integer constants rather than enum variants:
// they are keys into the theme (`node.diamond.fill`, …) and into the
// renderer's shape dispatch, and an integer is what both want.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── Node shapes ──────────────────────────────────────────────────────
//
// The mermaid spelling that produces each one is in the comment; the
// renderer draws it and the theme can override any token per shape under
// `[node.<name>]`.

: i MMD_SHAPE_RECT 0  // A[label]
: i MMD_SHAPE_ROUND 1  // A(label)
: i MMD_SHAPE_STADIUM 2  // A([label])
: i MMD_SHAPE_SUBROUTINE 3  // A[[label]]
: i MMD_SHAPE_CYLINDER 4  // A[(label)]
: i MMD_SHAPE_CIRCLE 5  // A((label))
: i MMD_SHAPE_DIAMOND 6  // A{label}
: i MMD_SHAPE_HEXAGON 7  // A{{label}}
: i MMD_SHAPE_PARALLELOGRAM 8  // A[/label/]
: i MMD_SHAPE_PARALLELOGRAM_ALT 9  // A[\label\]
: i MMD_SHAPE_TRAPEZOID 10  // A[/label\]
: i MMD_SHAPE_TRAPEZOID_ALT 11  // A[\label/]
: i MMD_SHAPE_FLAG 12  // A>label]

// Line styles.
: i MMD_LINE_SOLID 0  // ---  -->
: i MMD_LINE_DOTTED 1  // -.-  -.->
: i MMD_LINE_THICK 2  // ===  ==>

// Arrow heads (`head` = the target end, `tail` = the source end).
: i MMD_ARROW_NONE 0
: i MMD_ARROW_POINT 1  // >
: i MMD_ARROW_CIRCLE 2  // o
: i MMD_ARROW_CROSS 3  // x

// Rank directions.
: i MMD_DIR_TD 0  // graph TD / TB — top to bottom
: i MMD_DIR_LR 1  // graph LR      — left to right
: i MMD_DIR_BT 2  // graph BT      — bottom to top
: i MMD_DIR_RL 3  // graph RL      — right to left

@ mmd_shape_name i shape → s {
    ? == shape MMD_SHAPE_ROUND { ^ `round` } {}
    ? == shape MMD_SHAPE_STADIUM { ^ `stadium` } {}
    ? == shape MMD_SHAPE_SUBROUTINE { ^ `subroutine` } {}
    ? == shape MMD_SHAPE_CYLINDER { ^ `cylinder` } {}
    ? == shape MMD_SHAPE_CIRCLE { ^ `circle` } {}
    ? == shape MMD_SHAPE_DIAMOND { ^ `diamond` } {}
    ? == shape MMD_SHAPE_HEXAGON { ^ `hexagon` } {}
    ? == shape MMD_SHAPE_PARALLELOGRAM { ^ `parallelogram` } {}
    ? == shape MMD_SHAPE_PARALLELOGRAM_ALT { ^ `parallelogram-alt` } {}
    ? == shape MMD_SHAPE_TRAPEZOID { ^ `trapezoid` } {}
    ? == shape MMD_SHAPE_TRAPEZOID_ALT { ^ `trapezoid-alt` } {}
    ? == shape MMD_SHAPE_FLAG { ^ `flag` } {}
    ^ `rect`
}

@ mmd_line_name i line → s {
    ? == line MMD_LINE_DOTTED { ^ `dotted` } {}
    ? == line MMD_LINE_THICK { ^ `thick` } {}
    ^ `solid`
}

@ mmd_dir_name i dir → s {
    ? == dir MMD_DIR_LR { ^ `LR` } {}
    ? == dir MMD_DIR_BT { ^ `BT` } {}
    ? == dir MMD_DIR_RL { ^ `RL` } {}
    ^ `TD`
}

// `TD`/`TB`/`LR`/`BT`/`RL`, case-insensitively. -1 when unrecognised.
@ mmd_dir_parse s raw → i {
    // Bind the copy before upper-casing it: an allocation handed straight
    // to another call is owned by nothing and leaks (docs/MEMORY.md §1).
    : String src ( string_from raw )
    : String up ( string_to_upper src )
    ( string_free src )
    : s u ( string_data up )
    : ~ i d - 0 1
    ? != 0 ( nurl_str_eq u `TD` ) { = d MMD_DIR_TD } {}
    ? != 0 ( nurl_str_eq u `TB` ) { = d MMD_DIR_TD } {}
    ? != 0 ( nurl_str_eq u `LR` ) { = d MMD_DIR_LR } {}
    ? != 0 ( nurl_str_eq u `BT` ) { = d MMD_DIR_BT } {}
    ? != 0 ( nurl_str_eq u `RL` ) { = d MMD_DIR_RL } {}
    ( string_free up )
    ^ d
}

// ── The IR ───────────────────────────────────────────────────────────
//
// `label` holds the display text with `<br/>` already turned into `\n`;
// the renderer splits it into tspans. `declared` is F for a node that so
// far exists only because an edge mentioned it — a later `A[Label]`
// upgrades it in place.

: MmdNode {
    String id
    String label
    i shape
    b declared
}

: MmdEdge {
    i from
    i to
    String label
    i line
    i head
    i tail
}

: MmdGraph {
    i dir
    ( Vec MmdNode ) nodes
    ( Vec MmdEdge ) edges
    ( Vec String ) warnings
}

@ mmd_graph_new → MmdGraph {
    ^ @ MmdGraph {
        MMD_DIR_TD
        ( vec_new [MmdNode] )
        ( vec_new [MmdEdge] )
        ( vec_new [String] )
    }
}

@ mmd_graph_free MmdGraph g → v {
    : i nn ( vec_len [MmdNode] . g nodes )
    : ~ i i 0
    ~ < i nn {
        ?? ( vec_get [MmdNode] . g nodes i ) {
            T n → {
                ( string_free . n id )
                ( string_free . n label )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [MmdNode] . g nodes )

    : i ne ( vec_len [MmdEdge] . g edges )
    : ~ i k 0
    ~ < k ne {
        ?? ( vec_get [MmdEdge] . g edges k ) {
            T e → ( string_free . e label )
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [MmdEdge] . g edges )

    : i nw ( vec_len [String] . g warnings )
    : ~ i w 0
    ~ < w nw {
        ?? ( vec_get [String] . g warnings w ) {
            T s → ( string_free s )
            F _ → {}
        }
        = w + w 1
    }
    ( vec_free [String] . g warnings )
}

@ mmd_node_count MmdGraph g → i { ^ ( vec_len [MmdNode] . g nodes ) }

@ mmd_edge_count MmdGraph g → i { ^ ( vec_len [MmdEdge] . g edges ) }

// Index of the node with this id, or -1.
@ mmd_find_node MmdGraph g s id → i {
    : i n ( vec_len [MmdNode] . g nodes )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [MmdNode] . g nodes i ) {
            T nd → {
                ? != 0 ( nurl_str_eq ( string_data . nd id ) id ) { ^ i } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ - 0 1
}

// Intern `id`: return its index, appending an undeclared placeholder node
// (label = id, shape = rect) when this is the first mention.
@ mmd_node_index MmdGraph g s id → i {
    : i found ( mmd_find_node g id )
    ? >= found 0 { ^ found } {}
    : MmdNode nd @ MmdNode {
        ( string_from id )
        ( string_from id )
        MMD_SHAPE_RECT
        F
    }
    ( vec_push [MmdNode] . g nodes nd )
    ^ - ( vec_len [MmdNode] . g nodes ) 1
}

// Give node `idx` an explicit label + shape. CONSUMES `label`.
@ mmd_node_declare MmdGraph g i idx String label i shape → v {
    ?? ( vec_get [MmdNode] . g nodes idx ) {
        T old → {
            : MmdNode nd @ MmdNode { . old id label shape T }
            ( string_free . old label )
            ( vec_set [MmdNode] . g nodes idx nd )
        }
        F _ → ( string_free label )
    }
}

// CONSUMES `label` (pass an empty String for an unlabelled link).
@ mmd_add_edge MmdGraph g i from i to String label i line i head i tail → v {
    : MmdEdge e @ MmdEdge { from to label line head tail }
    ( vec_push [MmdEdge] . g edges e )
}

@ mmd_warn MmdGraph g s text → v {
    ( vec_push [String] . g warnings ( string_from text ) )
}
