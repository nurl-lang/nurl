// iforest — Isolation Forest anomaly detection for NURL.
//
// An Isolation Forest (Liu, Ting & Zhou, 2008) detects anomalies by
// *isolating* points rather than profiling normal data. It builds an
// ensemble of random binary trees (iTrees); each tree repeatedly splits a
// random feature at a random threshold until every point is isolated.
// Anomalies — being few and different — sit in sparse regions and get
// isolated near the root, so their average path length over the forest is
// short. The score maps that path length to (0, 1]:
//
//   s(x) = 2 ^ ( -E[h(x)] / c(psi) )
//
//   ≈ 1.0   almost certainly an anomaly (isolated very quickly)
//   ≈ 0.5   no clear signal (path length ≈ the average)
//   < 0.5   deep in the tree — a normal, "crowded" point
//
// where E[h(x)] is the mean path length of x across the trees and c(psi)
// is the expected path length of an unsuccessful BST search over a
// subsample of size psi (the normalising constant).
//
// This package lives in the NURL registry (it is NOT part of the core
// stdlib). It is pure NURL: a seedable PRNG (std/rng) drives the random
// splits, so a fixed seed gives a byte-identical forest on every platform.
//
// Surface:
//   ( iforest_train data n_rows n_cols n_trees sample_size seed ) → IForest
//       `data` is a row-major ( Vec f ) of n_rows*n_cols values. Returns a
//       trained forest (an owning struct: released with its owner).
//   ( iforest_score forest point )   → f   anomaly score in (0, 1] for a
//                                          ( Vec f ) of length n_cols.
//   ( iforest_score_row forest data row ) → f   score row `row` of a
//                                          row-major ( Vec f ) matrix.
//   ( iforest_avg_path n )           → f   c(n), exported for thresholding.
//   ( iforest_n_trees f ) / ( iforest_sample_size f ) → i   accessors.
//   ( iforest_free forest )          → v   early release (optional)
//
// The trees are stored as a flat struct-of-arrays shared across the whole
// forest (one node arena, a root index per tree): no recursive ADTs, no
// Vec-of-Vec, and scoring walks raw pointers for speed.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/par.nu`
$ `stdlib/std/arc.nu`

// Euler–Mascheroni constant, for the harmonic-number approximation in c(n).
: f GAMMA 0.5772156649015329

// ── Types ─────────────────────────────────────────────────────────────
//
// Every node of every tree lives in the same parallel arrays. A node is
// an index into them. Internal nodes carry a split (feature, threshold)
// and two child indices; leaves carry feature = -1 and `size` = the number
// of training points that reached them (used for the path-length estimate).

: IForest {
    i n_trees
    i sample_size  // psi — points subsampled per tree (clamped to n_rows)
    f c_psi  // c(psi): path-length normaliser, precomputed
    i n_cols  // dimensionality of a point
    ( Vec i ) roots  // roots[t] = node index of tree t's root
    ( Vec i ) feature  // split feature, or -1 at a leaf
    ( Vec f ) split  // split threshold (internal nodes only)
    ( Vec i ) left  // left child index, or -1
    ( Vec i ) right  // right child index, or -1
    ( Vec i ) size  // subsample size that reached this node
}

// ── Path-length normaliser c(n) ───────────────────────────────────────
//
// c(n) = 2*H(n-1) - 2*(n-1)/n, the average path length of an unsuccessful
// search in a binary search tree of n nodes, with H(i) ≈ ln(i) + γ. This
// is both the per-leaf adjustment for the unbuilt subtree below a depth
// cap and the forest-wide normaliser c(psi).
@ iforest_avg_path i n → f {
    ? <= n 1 { ^ 0.0 } {}
    ? == n 2 { ^ 1.0 } {}
    : f fn # f n
    : f h + ( float_log - fn 1.0 ) GAMMA
    ^ - * 2.0 h / * 2.0 - fn 1.0 fn
}

// Height cap for a single tree: ceil(log2(psi)). Past this depth a point
// is treated as isolated and its remaining path estimated by c(leaf size).
@ __height_limit i psi → i {
    ? <= psi 1 { ^ 0 } {}
    ^ # i ( float_ceil ( float_log2 # f psi ) )
}

// ── Node arena helpers ────────────────────────────────────────────────

// Append a node to the shared arena and return its index.
@ __push_node IForest fo i feature f split i left i right i size → i {
    : i id ( vec_len [i] . fo feature )
    ( vec_push [i] . fo feature feature )
    ( vec_push [f] . fo split split )
    ( vec_push [i] . fo left left )
    ( vec_push [i] . fo right right )
    ( vec_push [i] . fo size size )
    ^ id
}

@ __push_leaf IForest fo i size → i {
    ^ ( __push_node fo -1 0.0 -1 -1 size )
}

// ── Subsampling ───────────────────────────────────────────────────────
//
// Draw `psi` distinct row indices from [0, n) without replacement via a
// partial Fisher–Yates shuffle, then truncate. Returns an owned ( Vec i ).
@ __subsample Rng g i n i psi → ( Vec i ) {
    : ( Vec i ) all ( vec_iota 0 n )
    : ~ i m psi
    ? > m n { = m n } {}
    : ~ i k 0
    ~ < k m {
        : i j + k ( rng_below g - n k )  // pick from [k, n)
        ( vec_swap [i] all k j )
        = k + k 1
    }
    : b _t ( vec_truncate [i] all m )
    ^ all
}

// ── Tree construction ─────────────────────────────────────────────────
//
// Build one subtree from the row indices `idx` (which this call OWNS: they
// go when it returns — at most depth × psi indices are alive at once, a
// few KB at the default psi of 256) and return its node index. `dp` is the
// row-major data; feature q of row r is dp[r*n_cols + q].
@ __build_node IForest fo ( Slice f ) dp i n_cols sink ( Vec i ) idx i depth i height_limit Rng g → i {
    : i m ( vec_len [i] idx )

    // Isolated (≤1 point) or hit the depth cap → leaf.
    ? || >= depth height_limit <= m 1 {
        : i leaf ( __push_leaf fo m )
        ^ leaf
    } {}

    : ( Slice i ) idxp ( slice_from_vec [i] idx )

    // Pick a feature that actually varies over this subsample. A column
    // every row agrees on (a one-hot category nobody sent, a sensor stuck
    // at one value, a rare category absent from this subsample) cannot be
    // split; ending the subtree there would leave m points in one leaf
    // with a short path — every point below looks isolated, and the
    // forest's discrimination drops with each constant column it carries.
    // So a degenerate draw is redrawn, uniformly among all columns, up to
    // 2·n_cols times: only when nothing varies (identical rows) is the
    // node a leaf.
    : ~ i q -1
    : ~ f mn 0.0
    : ~ f mx 0.0
    : ~ i tries 0
    : i max_tries * 2 n_cols
    ~ & < q 0 < tries max_tries {
        : i cand ( rng_below g n_cols )
        : i r0 ( slice_at [i] idxp 0 )
        : ~ f lo ( slice_at [f] dp + * r0 n_cols cand )
        : ~ f hi lo
        : ~ i a 1
        ~ < a m {
            : f v ( slice_at [f] dp + * ( slice_at [i] idxp a ) n_cols cand )
            ? < v lo { = lo v } {}
            ? > v hi { = hi v } {}
            = a + a 1
        }
        ? < lo hi {
            = q cand
            = mn lo
            = mx hi
        } {}
        = tries + tries 1
    }
    ? < q 0 {
        : i leaf ( __push_leaf fo m )
        ^ leaf
    } {}

    // Random threshold in [mn, mx), then partition the rows around it.
    : f p + mn * ( rng_u01 g ) - mx mn
    : ( Vec i ) li ( vec_new [i] )
    : ( Vec i ) ri ( vec_new [i] )
    : ~ i b 0
    ~ < b m {
        : i row ( slice_at [i] idxp b )
        : f v ( slice_at [f] dp + * row n_cols q )
        ? < v p { ( vec_push [i] li row ) } { ( vec_push [i] ri row ) }
        = b + b 1
    }

    // Reserve this internal node (children patched in after recursion).
    : i node ( __push_node fo q p -1 -1 m )

    : i d1 + depth 1
    : i lc ( __build_node fo dp n_cols li d1 height_limit g )
    : i rc ( __build_node fo dp n_cols ri d1 height_limit g )
    ( vec_set [i] . fo left node lc )
    ( vec_set [i] . fo right node rc )
    ^ node
}

// ── Training ──────────────────────────────────────────────────────────

@ iforest_train ( Vec f ) data i n_rows i n_cols i n_trees i sample_size i seed → IForest {
    : ~ i psi sample_size
    ? > psi n_rows { = psi n_rows } {}
    ? < psi 1 { = psi 1 } {}

    : IForest fo @ IForest {
        n_trees
        psi
        ( iforest_avg_path psi )
        n_cols
        ( vec_new [i] )
        ( vec_new [i] )
        ( vec_new [f] )
        ( vec_new [i] )
        ( vec_new [i] )
        ( vec_new [i] )
    }

    : i hlim ( __height_limit psi )
    : Rng g ( rng_seed seed )
    : ( Slice f ) dp ( slice_from_vec [f] data )

    : ~ i t 0
    ~ < t n_trees {
        : ( Vec i ) idx ( __subsample g n_rows psi )
        : i root ( __build_node fo dp n_cols idx 0 hlim g )
        ( vec_push [i] . fo roots root )
        = t + t 1
    }
    ^ fo
}

// ── Scoring ───────────────────────────────────────────────────────────
//
// The forest's node columns, cut to one length so a walk checks each
// node index once (slice_prefix).
: IfCols { ( Slice i ) feat ( Slice f ) spl ( Slice i ) lf ( Slice i ) rt ( Slice i ) sz }

@ __if_cols IForest fo → IfCols {
    : i n ( vec_len [i] . fo feature )
    ^ @ IfCols {
        ( slice_prefix [i] ( slice_from_vec [i] . fo feature ) n )
        ( slice_prefix [f] ( slice_from_vec [f] . fo split ) n )
        ( slice_prefix [i] ( slice_from_vec [i] . fo left ) n )
        ( slice_prefix [i] ( slice_from_vec [i] . fo right ) n )
        ( slice_prefix [i] ( slice_from_vec [i] . fo size ) n )
    }
}

// Path length of the point at `base` of `xs` (n_cols values) down one
// tree: walk from `root` comparing the node's feature to its threshold,
// then add c(leaf size) for the unbuilt subtree below where we stopped.
inline @ __path_len IfCols c i root ( Slice f ) xs i base → f {
    : ~ i node root
    : ~ i depth 0
    : ~ b going T
    ~ going {
        : i fq ( slice_at [i] . c feat node )
        ? < fq 0 {
            = going F
        } {
            : f xv ( slice_at [f] xs + base fq )
            ? < xv ( slice_at [f] . c spl node ) { = node ( slice_at [i] . c lf node ) } { = node ( slice_at [i] . c rt node ) }
            = depth + depth 1
        }
    }
    ^ + # f depth ( iforest_avg_path ( slice_at [i] . c sz node ) )
}

// Anomaly score in (0, 1] for a single point given as a ( Vec f ) of length
// n_cols. Higher = more anomalous. A point of any other length is not a
// point this forest can judge and scores 0.5 — the score of an average
// path, "no information" — rather than being read past its end: a
// forest trained on two columns handed an empty point once walked its
// trees over whatever lay at address zero.
@ iforest_score IForest fo ( Vec f ) point → f {
    ? == ( vec_len [f] point ) . fo n_cols {} { ^ 0.5 }
    ^ ( __score_at fo ( slice_from_vec [f] point ) 0 )
}

// Score row `row` of a row-major ( Vec f ) matrix without copying it out.
// A row the matrix does not hold scores 0.5, as above.
@ iforest_score_row IForest fo ( Vec f ) data i row → f {
    ? & >= row 0 <= * + row 1 . fo n_cols ( vec_len [f] data ) {} { ^ 0.5 }
    ^ ( __score_at fo ( slice_from_vec [f] data ) * row . fo n_cols )
}

// Mean path length over the forest → score, for the n_cols values at
// `base` of `xs`.
@ __score_at IForest fo ( Slice f ) xs i base → f {
    : i nt ( vec_len [i] . fo roots )
    ? <= nt 0 { ^ 0.0 } {}
    : f cpsi . fo c_psi
    ? <= cpsi 0.0 { ^ 0.5 } {}

    : ( Slice i ) rts ( slice_from_vec [i] . fo roots )
    : IfCols cols ( __if_cols fo )
    : ~ f total 0.0
    : ~ i k 0
    ~ < k nt {
        = total + total ( __path_len cols ( slice_at [i] rts k ) xs base )
        = k + k 1
    }
    : f avg / total # f nt
    ^ ( float_pow 2.0 - 0.0 / avg cpsi )
}

// ── Batch scoring ─────────────────────────────────────────────────────
//
// iforest_score_row computes c(leaf size) — a log — at every leaf it
// reaches, once per tree per row. A batch computes it once per NODE
// (`cleaf`) and adds the table entry instead: the same values summed in
// the same order, so every score is bit-identical to the per-row one.

@ __if_cleaf IForest fo → ( Vec f ) {
    : i n ( vec_len [i] . fo size )
    : ( Vec f ) out ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] out ( iforest_avg_path ( vec_at [i] . fo size k ) ) ) = k + k 1 }
    ^ out
}

inline @ __path_len_c IfCols c ( Slice f ) cl i root ( Slice f ) xs i base → f {
    : ~ i node root
    : ~ i depth 0
    : ~ b going T
    ~ going {
        : i fq ( slice_at [i] . c feat node )
        ? < fq 0 {
            = going F
        } {
            : f xv ( slice_at [f] xs + base fq )
            ? < xv ( slice_at [f] . c spl node ) { = node ( slice_at [i] . c lf node ) } { = node ( slice_at [i] . c rt node ) }
            = depth + depth 1
        }
    }
    ^ + # f depth ( slice_at [f] cl node )
}

// Scores of rows [lo, hi) of `data` into `out`.
@ __if_score_span IForest fo ( Vec f ) cleaf ( Vec f ) data i lo i hi ( Vec f ) out → v {
    : i nt ( vec_len [i] . fo roots )
    : f cpsi . fo c_psi
    : i nc . fo n_cols
    : ( Slice i ) rts ( slice_from_vec [i] . fo roots )
    : IfCols cols ( __if_cols fo )
    : ( Slice f ) cl ( slice_from_vec [f] cleaf )
    : ( Slice f ) xs ( slice_from_vec [f] data )
    : ~ i r lo
    ~ < r hi {
        ? | <= nt 0 <= cpsi 0.0 { ( vec_push [f] out ? <= nt 0 0.0 0.5 ) } {
            : ~ f total 0.0
            : ~ i k 0
            ~ < k nt {
                = total + total ( __path_len_c cols cl ( slice_at [i] rts k ) xs * r nc )
                = k + k 1
            }
            ( vec_push [f] out ( float_pow 2.0 - 0.0 / / total # f nt cpsi ) )
        }
        = r + r 1
    }
}

// The scores of the first `n_rows` rows of `data` (n_cols values each),
// equal to iforest_score_row's for each; a row past the data scores 0.5.
@ iforest_score_rows IForest fo ( Vec f ) data i n_rows → ( Vec f ) {
    : i have / ( vec_len [f] data ) ? > . fo n_cols 0 . fo n_cols 1
    : i n ? > n_rows have have n_rows
    : ( Vec f ) out ( vec_with_cap [f] n_rows )
    ( __if_score_span fo ( __if_cleaf fo ) data 0 n out )
    : ~ i r n
    ~ < r n_rows { ( vec_push [f] out 0.5 ) = r + r 1 }
    ^ out
}

: __IfJob { IForest fo ( Vec f ) cleaf ( Vec f ) data i n i per }

// iforest_score_rows over `nt` worker threads (the rows split into
// chunks; the same scores, in order). Below a few thousand rows the
// threads cost more than they save, and it scores on this one.
@ iforest_score_rows_par IForest fo ( Vec f ) data i n_rows i nt → ( Vec f ) {
    ? | <= nt 1 < n_rows 4096 { ^ ( iforest_score_rows fo data n_rows ) } {}
    : i have / ( vec_len [f] data ) ? > . fo n_cols 0 . fo n_cols 1
    : i n ? > n_rows have have n_rows
    : i nch * nt 8
    : i per / + n - nch 1 nch
    : ( Arc __IfJob ) ja ( arc_new [__IfJob] @ __IfJob { fo ( __if_cleaf fo ) ( vec_clone [f] data ) n per } )
    : ( Vec ( Vec f ) ) parts ( par_map_index [( Vec f )] nch nt \ i c → ( Vec f ) {
        : __IfJob j ( arc_get [__IfJob] ja )
        : i lo * c . j per
        : ~ i hi + lo . j per
        ? > hi . j n { = hi . j n } {}
        : ( Vec f ) o ( vec_new [f] )
        ? < lo hi { ( __if_score_span . j fo . j cleaf . j data lo hi o ) } {}
        ^ o
    } )
    : ( Vec f ) out ( vec_with_cap [f] n_rows )
    : ~ i c 0
    ~ < c nch { ( vec_extend [f] out ( vec_at [( Vec f )] parts c ) ) = c + c 1 }
    : ~ i r n
    ~ < r n_rows { ( vec_push [f] out 0.5 ) = r + r 1 }
    ^ out
}

// ── Accessors / cleanup ───────────────────────────────────────────────

@ iforest_n_trees IForest fo → i { ^ . fo n_trees }

@ iforest_sample_size IForest fo → i { ^ . fo sample_size }

// Let go of `fo` now rather than at the end of its owner's scope. An
// IForest owns its node arrays and releases them with its owner.
@ iforest_free sink IForest fo → v {}
