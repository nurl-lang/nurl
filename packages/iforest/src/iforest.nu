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
//       trained forest (caller owns it → iforest_free).
//   ( iforest_score forest point )   → f   anomaly score in (0, 1] for a
//                                          ( Vec f ) of length n_cols.
//   ( iforest_score_row forest data row ) → f   score row `row` of a
//                                          row-major ( Vec f ) matrix.
//   ( iforest_avg_path n )           → f   c(n), exported for thresholding.
//   ( iforest_n_trees f ) / ( iforest_sample_size f ) → i   accessors.
//   ( iforest_free forest )          → v
//
// The trees are stored as a flat struct-of-arrays shared across the whole
// forest (one node arena, a root index per tree): no recursive ADTs, no
// Vec-of-Vec, and scoring walks raw pointers for speed.

$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`

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
    i sample_size       // psi — points subsampled per tree (clamped to n_rows)
    f c_psi             // c(psi): path-length normaliser, precomputed
    i n_cols            // dimensionality of a point
    ( Vec i ) roots     // roots[t] = node index of tree t's root
    ( Vec i ) feature   // split feature, or -1 at a leaf
    ( Vec f ) split     // split threshold (internal nodes only)
    ( Vec i ) left      // left child index, or -1
    ( Vec i ) right     // right child index, or -1
    ( Vec i ) size      // subsample size that reached this node
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
        : i j + k ( rng_below g - n k )   // pick from [k, n)
        ( vec_swap [i] all k j )
        = k + k 1
    }
    ( vec_set_len [i] all m )
    ^ all
}

// ── Tree construction ─────────────────────────────────────────────────
//
// Build one subtree from the row indices `idx` (which this call OWNS and
// frees) and return its node index. `dp` is the raw row-major data buffer;
// reading feature q of row r is dp[r*n_cols + q].
@ __build_node IForest fo *f dp i n_cols ( Vec i ) idx i depth i height_limit Rng g → i {
    : i m ( vec_len [i] idx )

    // Isolated (≤1 point) or hit the depth cap → leaf.
    ? || >= depth height_limit <= m 1 {
        : i leaf ( __push_leaf fo m )
        ( vec_free [i] idx )
        ^ leaf
    } {}

    : *i idxp ( vec_data [i] idx )
    : i q ( rng_below g n_cols )

    // Range of feature q over this subsample.
    : i r0 . idxp 0
    : i o0 + * r0 n_cols q
    : ~ f mn . dp o0
    : ~ f mx mn
    : ~ i a 1
    ~ < a m {
        : i row . idxp a
        : i off + * row n_cols q
        : f v . dp off
        ? < v mn { = mn v } {}
        ? > v mx { = mx v } {}
        = a + a 1
    }

    // Degenerate column (every value equal): nothing to split on → leaf.
    ? == mn mx {
        : i leaf ( __push_leaf fo m )
        ( vec_free [i] idx )
        ^ leaf
    } {}

    // Random threshold in [mn, mx), then partition the rows around it.
    : f p + mn * ( rng_u01 g ) - mx mn
    : ( Vec i ) li ( vec_new [i] )
    : ( Vec i ) ri ( vec_new [i] )
    : ~ i b 0
    ~ < b m {
        : i row . idxp b
        : i off2 + * row n_cols q
        : f v . dp off2
        ? < v p { ( vec_push [i] li row ) } { ( vec_push [i] ri row ) }
        = b + b 1
    }

    // Reserve this internal node (children patched in after recursion), then
    // release the parent's index list before descending.
    : i node ( __push_node fo q p -1 -1 m )
    ( vec_free [i] idx )

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
    : *f dp ( vec_data [f] data )

    : ~ i t 0
    ~ < t n_trees {
        : ( Vec i ) idx ( __subsample g n_rows psi )
        : i root ( __build_node fo dp n_cols idx 0 hlim g )
        ( vec_push [i] . fo roots root )
        = t + t 1
    }
    ( rng_free g )
    ^ fo
}

// ── Scoring ───────────────────────────────────────────────────────────
//
// Path length of `point` (raw *f, length n_cols) down one tree: walk from
// `root` comparing the node's feature to its threshold, then add c(leaf
// size) for the unbuilt subtree below where we stopped.
@ __path_len IForest fo i root *f point → f {
    : *i feat ( vec_data [i] . fo feature )
    : *f spl ( vec_data [f] . fo split )
    : *i lf ( vec_data [i] . fo left )
    : *i rt ( vec_data [i] . fo right )
    : *i sz ( vec_data [i] . fo size )

    : ~ i node root
    : ~ i depth 0
    : ~ b going T
    ~ going {
        : i fq . feat node
        ? < fq 0 {
            = going F
        } {
            : f xv . point fq
            ? < xv . spl node { = node . lf node } { = node . rt node }
            = depth + depth 1
        }
    }
    ^ + # f depth ( iforest_avg_path . sz node )
}

// Anomaly score in (0, 1] for a single point given as a ( Vec f ) of length
// n_cols. Higher = more anomalous.
@ iforest_score IForest fo ( Vec f ) point → f {
    : *f pp ( vec_data [f] point )
    ^ ( __score_ptr fo pp )
}

// Score row `row` of a row-major ( Vec f ) matrix without copying it out.
@ iforest_score_row IForest fo ( Vec f ) data i row → f {
    : *f dp ( vec_data [f] data )
    : i base + # i dp * * row . fo n_cols 8
    : *f pp # *f base
    ^ ( __score_ptr fo pp )
}

// Mean path length over the forest → score. `point` is a raw *f of n_cols.
@ __score_ptr IForest fo *f point → f {
    : i nt ( vec_len [i] . fo roots )
    ? <= nt 0 { ^ 0.0 } {}
    : f cpsi . fo c_psi
    ? <= cpsi 0.0 { ^ 0.5 } {}

    : *i rts ( vec_data [i] . fo roots )
    : ~ f total 0.0
    : ~ i k 0
    ~ < k nt {
        = total + total ( __path_len fo . rts k point )
        = k + k 1
    }
    : f avg / total # f nt
    ^ ( float_pow 2.0 - 0.0 / avg cpsi )
}

// ── Accessors / cleanup ───────────────────────────────────────────────

@ iforest_n_trees IForest fo → i { ^ . fo n_trees }

@ iforest_sample_size IForest fo → i { ^ . fo sample_size }

@ iforest_free IForest fo → v {
    ( vec_free [i] . fo roots )
    ( vec_free [i] . fo feature )
    ( vec_free [f] . fo split )
    ( vec_free [i] . fo left )
    ( vec_free [i] . fo right )
    ( vec_free [i] . fo size )
}
