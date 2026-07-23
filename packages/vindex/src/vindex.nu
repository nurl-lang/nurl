// vindex.nu — a vector index: search the k nearest of n d-dim vectors by
// cosine or L2. Two builders share one search surface:
//
//   EXACT     — brute force over every vector (the ground truth).
//   IVF-flat  — a k-means coarse quantiser (nlist centroids) with inverted
//               lists; a query scores only the nprobe nearest clusters,
//               trading recall for speed on a knob.
//
// Cosine precomputes each vector's L2 norm, so a candidate costs one dot
// product. Scores are "smaller = nearer" (cosine: 1 − cossim; L2: squared
// distance), so the same top-k machinery serves both. The index serialises
// to one .vix byte blob and loads back to identical results.
//
//   ( vx_build_exact data n dim metric )              → *VIndex
//   ( vx_build_ivf data n dim metric nlist niter seed ) → *VIndex
//   ( vx_search idx q k nprobe out_ids out_dists )    → i   (results found)
//   ( vx_free idx )                                   → v
//   ( vx_save idx )                                   → ( Vec u )
//   ( vx_load bytes )                                 → !*VIndex String
//
// metric: VX_COSINE (0) or VX_L2 (1).

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`

: i VX_COSINE 0

: i VX_L2 1

@ __vx_gf ( Vec f ) v i k → f { ?? ( vec_get [f] v k ) { T x → x F → 0.0 } }

@ __vx_gi ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → x F → 0 } }

: VIndex {
    ( Vec f ) data  // n·dim, row-major
    ( Vec f ) norm  // n L2 norms (for cosine)
    i n
    i dim
    i metric
    i nlist  // 0 = exact
    ( Vec f ) cent  // nlist·dim centroids
    ( Vec f ) cnorm  // nlist norms
    ( Vec i ) list_off  // nlist+1 CSR offsets into members
    ( Vec i ) members  // n vector ids grouped by cluster
}

// L2 norm of the dim-vector at data[off..].
@ __vx_norm ( Vec f ) data i off i dim → f {
    : ~ f s 0.0
    : ~ i c 0
    ~ < c dim { : f x ( __vx_gf data + off c ) = s + s * x x = c + c 1 }
    ^ ( float_sqrt s )
}

// Fill `out` (length n) with each row's L2 norm.
@ __vx_fill_norms ( Vec f ) data i n i dim ( Vec f ) out → v {
    : ~ i i2 0
    ~ < i2 n { ( vec_push [f] out ( __vx_norm data * i2 dim dim ) ) = i2 + i2 1 }
}

// Dot product of query q[0..dim] with row `id`.
@ __vx_dot ( Vec f ) data i id i dim ( Vec f ) q → f {
    : ~ f s 0.0
    : i off * id dim
    : ~ i c 0
    ~ < c dim { = s + s * ( __vx_gf data + off c ) ( __vx_gf q c ) = c + c 1 }
    ^ s
}

// Squared L2 distance of query q to row `id`.
@ __vx_l2 ( Vec f ) data i id i dim ( Vec f ) q → f {
    : ~ f s 0.0
    : i off * id dim
    : ~ i c 0
    ~ < c dim { : f dd - ( __vx_gf data + off c ) ( __vx_gf q c ) = s + s * dd dd = c + c 1 }
    ^ s
}

// Score of stored vector `id` against query q (with precomputed qnorm for
// cosine). Smaller = nearer.
@ __vx_score * VIndex idx i id ( Vec f ) q f qnorm → f {
    ? == . idx metric VX_L2 { ^ ( __vx_l2 . idx data id . idx dim q ) } {}
    : f dn * ( __vx_gf . idx norm id ) qnorm
    ? > dn 0.0 {} { ^ 1.0 }
    ^ - 1.0 / ( __vx_dot . idx data id . idx dim q ) dn
}

// ── top-k accumulator (parallel id/dist arrays, kept sorted ascending) ──

@ __vx_topk_insert ( Vec i ) ids ( Vec f ) dist i k i id f d → v {
    : i cur ( vec_len [i] ids )
    // reject if full and not better than the worst
    ? & >= cur k >= d ( __vx_gf dist - cur 1 ) { ^ v } {}
    // find insertion point
    : ~ i p cur
    ~ & > p 0 > ( __vx_gf dist - p 1 ) d { = p - p 1 }
    // grow by one (append then shift), unless at cap where we drop the worst
    ? < cur k {
        ( vec_push [i] ids 0 )
        ( vec_push [f] dist 0.0 )
        : ~ i q ( vec_len [i] ids )
        = q - q 1
        ~ > q p {
            ( vec_set [i] ids q ( __vx_gi ids - q 1 ) )
            ( vec_set [f] dist q ( __vx_gf dist - q 1 ) )
            = q - q 1
        }
    } {
        : ~ i q - cur 1
        ~ > q p {
            ( vec_set [i] ids q ( __vx_gi ids - q 1 ) )
            ( vec_set [f] dist q ( __vx_gf dist - q 1 ) )
            = q - q 1
        }
    }
    ( vec_set [i] ids p id )
    ( vec_set [f] dist p d )
}

// ── build: exact ────────────────────────────────────────────────────────

@ vx_build_exact ( Vec f ) data i n i dim i metric → *VIndex {
    : *VIndex idx # *VIndex ( nurl_alloc Z VIndex )
    = . idx data data
    = . idx n n
    = . idx dim dim
    = . idx metric metric
    = . idx nlist 0
    : ( Vec f ) nrm ( vec_new [f] )
    ( __vx_fill_norms data n dim nrm )
    = . idx norm nrm
    = . idx cent ( vec_new [f] )
    = . idx cnorm ( vec_new [f] )
    = . idx list_off ( vec_new [i] )
    = . idx members ( vec_new [i] )
    ^ idx
}

// ── build: IVF-flat (k-means coarse quantiser + inverted lists) ─────────

// Nearest centroid (L2) of row `id`.
@ __vx_nearest_cent ( Vec f ) data i id i dim ( Vec f ) cent i nlist → i {
    : ~ i best 0
    : ~ f bd 1000000000000000000.0
    : ~ i c 0
    ~ < c nlist {
        : ~ f s 0.0
        : i doff * id dim
        : i coff * c dim
        : ~ i j 0
        ~ < j dim { : f dd - ( __vx_gf data + doff j ) ( __vx_gf cent + coff j ) = s + s * dd dd = j + j 1 }
        ? < s bd { = bd s = best c } {}
        = c + c 1
    }
    ^ best
}

@ vx_build_ivf ( Vec f ) data i n i dim i metric i nlist i niter i seed → *VIndex {
    : *VIndex idx # *VIndex ( nurl_alloc Z VIndex )
    = . idx data data
    = . idx n n
    = . idx dim dim
    = . idx metric metric
    : ~ i nl nlist
    ? > nl n { = nl n } {}
    ? < nl 1 { = nl 1 } {}
    = . idx nlist nl
    : ( Vec f ) nrm ( vec_new [f] )
    ( __vx_fill_norms data n dim nrm )
    = . idx norm nrm
    // init centroids: nl distinct-ish random rows
    : ( Vec f ) cent ( vec_with_cap [f] * nl dim )
    : Rng g ( rng_seed ? > seed 0 seed 1 )
    : ~ i c 0
    ~ < c nl {
        : i pick ( rng_below g n )
        : i off * pick dim
        : ~ i j 0
        ~ < j dim { ( vec_push [f] cent ( __vx_gf data + off j ) ) = j + j 1 }
        = c + c 1
    }
    ( rng_free g )
    // Lloyd iterations
    : ( Vec i ) assign ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n { ( vec_push [i] assign 0 ) = k + k 1 }
    : ~ i it 0
    ~ < it niter {
        = k 0
        ~ < k n { ( vec_set [i] assign k ( __vx_nearest_cent data k dim cent nl ) ) = k + k 1 }
        // recompute centroids = cluster means (keep old on empty)
        : ( Vec f ) sum ( vec_with_cap [f] * nl dim )
        : ( Vec i ) cnt ( vec_with_cap [i] nl )
        = k 0
        ~ < k * nl dim { ( vec_push [f] sum 0.0 ) = k + k 1 }
        = k 0
        ~ < k nl { ( vec_push [i] cnt 0 ) = k + k 1 }
        = k 0
        ~ < k n {
            : i a ( __vx_gi assign k )
            : i doff * k dim
            : i soff * a dim
            : ~ i j 0
            ~ < j dim { ( vec_set [f] sum + soff j + ( __vx_gf sum + soff j ) ( __vx_gf data + doff j ) ) = j + j 1 }
            ( vec_set [i] cnt a + 1 ( __vx_gi cnt a ) )
            = k + k 1
        }
        = c 0
        ~ < c nl {
            : i cc ( __vx_gi cnt c )
            ? > cc 0 {
                : i coff * c dim
                : ~ i j 0
                ~ < j dim { ( vec_set [f] cent + coff j / ( __vx_gf sum + coff j ) # f cc ) = j + j 1 }
            } {}
            = c + c 1
        }
        ( vec_free [f] sum ) ( vec_free [i] cnt )
        = it + it 1
    }
    // final assignment + inverted lists (CSR)
    = k 0
    ~ < k n { ( vec_set [i] assign k ( __vx_nearest_cent data k dim cent nl ) ) = k + k 1 }
    : ( Vec i ) cnt ( vec_with_cap [i] nl )
    = k 0
    ~ < k nl { ( vec_push [i] cnt 0 ) = k + k 1 }
    = k 0
    ~ < k n { : i a ( __vx_gi assign k ) ( vec_set [i] cnt a + 1 ( __vx_gi cnt a ) ) = k + k 1 }
    : ( Vec i ) loff ( vec_with_cap [i] + nl 1 )
    ( vec_push [i] loff 0 )
    : ~ i acc 0
    = c 0
    ~ < c nl { = acc + acc ( __vx_gi cnt c ) ( vec_push [i] loff acc ) = c + c 1 }
    : ( Vec i ) members ( vec_with_cap [i] n )
    = k 0
    ~ < k n { ( vec_push [i] members 0 ) = k + k 1 }
    : ( Vec i ) fillp ( vec_with_cap [i] nl )
    = c 0
    ~ < c nl { ( vec_push [i] fillp ( __vx_gi loff c ) ) = c + c 1 }
    = k 0
    ~ < k n {
        : i a ( __vx_gi assign k )
        : i p ( __vx_gi fillp a )
        ( vec_set [i] members p k )
        ( vec_set [i] fillp a + p 1 )
        = k + k 1
    }
    ( vec_free [i] fillp ) ( vec_free [i] cnt ) ( vec_free [i] assign )
    : ( Vec f ) cnrm ( vec_new [f] )
    ( __vx_fill_norms cent nl dim cnrm )
    = . idx cent cent
    = . idx cnorm cnrm
    = . idx list_off loff
    = . idx members members
    ^ idx
}

// ── search ──────────────────────────────────────────────────────────────

// Fill out_ids/out_dists (cleared first) with the k nearest of query q.
// nprobe is ignored for an exact index. Returns the number found.
@ vx_search * VIndex idx ( Vec f ) q i k i nprobe ( Vec i ) out_ids ( Vec f ) out_dists → i {
    : b _c1 ( vec_set_len [i] out_ids 0 )
    : b _c2 ( vec_set_len [f] out_dists 0 )
    : f qn ( __vx_norm q 0 . idx dim )
    ? == . idx nlist 0 {
        : ~ i id 0
        ~ < id . idx n {
            ( __vx_topk_insert out_ids out_dists k id ( __vx_score idx id q qn ) )
            = id + id 1
        }
        ^ ( vec_len [i] out_ids )
    } {}
    // IVF: nprobe nearest centroids by L2
    : ~ i np nprobe
    ? < np 1 { = np 1 } {}
    ? > np . idx nlist { = np . idx nlist } {}
    : ( Vec i ) cids ( vec_new [i] )
    : ( Vec f ) cds ( vec_new [f] )
    : ~ i c 0
    ~ < c . idx nlist {
        : ~ f s 0.0
        : i coff * c . idx dim
        : ~ i j 0
        ~ < j . idx dim { : f dd - ( __vx_gf . idx cent + coff j ) ( __vx_gf q j ) = s + s * dd dd = j + j 1 }
        ( __vx_topk_insert cids cds np c s )
        = c + c 1
    }
    : ~ i pi 0
    ~ < pi ( vec_len [i] cids ) {
        : i cl ( __vx_gi cids pi )
        : i lo ( __vx_gi . idx list_off cl )
        : i hi ( __vx_gi . idx list_off + cl 1 )
        : ~ i m lo
        ~ < m hi {
            : i id ( __vx_gi . idx members m )
            ( __vx_topk_insert out_ids out_dists k id ( __vx_score idx id q qn ) )
            = m + m 1
        }
        = pi + pi 1
    }
    ( vec_free [i] cids ) ( vec_free [f] cds )
    ^ ( vec_len [i] out_ids )
}

@ vx_n * VIndex idx → i { ^ . idx n }

@ vx_dim * VIndex idx → i { ^ . idx dim }

@ vx_nlist * VIndex idx → i { ^ . idx nlist }

@ vx_free * VIndex idx → v {
    ( vec_free [f] . idx data )
    ( vec_free [f] . idx norm )
    ( vec_free [f] . idx cent )
    ( vec_free [f] . idx cnorm )
    ( vec_free [i] . idx list_off )
    ( vec_free [i] . idx members )
    ( nurl_free # s idx )
}

// ── serialisation (.vix) ────────────────────────────────────────────────
// 'V' 'I' 'X' '1' | u64 n | u64 dim | u64 metric | u64 nlist |
//   data(n·dim f64) | [nlist>0: cent(nlist·dim f64) | list_off(nlist+1 i64)
//   | members(n i64)]

@ vx_save * VIndex idx → ( Vec u ) {
    : ( Vec u ) o ( vec_new [u] )
    ( vec_push [u] o # u 86 ) ( vec_push [u] o # u 73 )
    ( vec_push [u] o # u 88 ) ( vec_push [u] o # u 49 )
    ( bytes_push_u64_le o # u64 . idx n )
    ( bytes_push_u64_le o # u64 . idx dim )
    ( bytes_push_u64_le o # u64 . idx metric )
    ( bytes_push_u64_le o # u64 . idx nlist )
    : ~ i k 0
    ~ < k * . idx n . idx dim { ( bytes_push_f64_le o ( __vx_gf . idx data k ) ) = k + k 1 }
    ? > . idx nlist 0 {
        = k 0
        ~ < k * . idx nlist . idx dim { ( bytes_push_f64_le o ( __vx_gf . idx cent k ) ) = k + k 1 }
        = k 0
        ~ < k + . idx nlist 1 { ( bytes_push_u64_le o # u64 ( __vx_gi . idx list_off k ) ) = k + k 1 }
        = k 0
        ~ < k . idx n { ( bytes_push_u64_le o # u64 ( __vx_gi . idx members k ) ) = k + k 1 }
    } {}
    ^ o
}

@ vx_load ( Vec u ) b → !*VIndex String {
    ? >= ( vec_len [u] b ) 36 {} { ^ @ !*VIndex String { F ( string_from `vindex: truncated .vix` ) } }
    : ~ b magic T
    ? == ?? ( vec_get [u] b 0 ) { T x → x F → # u 0 } # u 86 {} { = magic F }
    ? == ?? ( vec_get [u] b 1 ) { T x → x F → # u 0 } # u 73 {} { = magic F }
    ? == ?? ( vec_get [u] b 2 ) { T x → x F → # u 0 } # u 88 {} { = magic F }
    ? == ?? ( vec_get [u] b 3 ) { T x → x F → # u 0 } # u 49 {} { = magic F }
    ? magic {} { ^ @ !*VIndex String { F ( string_from `vindex: bad .vix magic` ) } }
    : i n # i ?? ( bytes_read_u64_le b 4 ) { T v → v F → # u64 0 }
    : i dim # i ?? ( bytes_read_u64_le b 12 ) { T v → v F → # u64 0 }
    : i metric # i ?? ( bytes_read_u64_le b 20 ) { T v → v F → # u64 0 }
    : i nlist # i ?? ( bytes_read_u64_le b 28 ) { T v → v F → # u64 0 }
    : ~ i off 36
    : ( Vec f ) data ( vec_with_cap [f] * n dim )
    : ~ i k 0
    ~ < k * n dim { ( vec_push [f] data ?? ( bytes_read_f64_le b off ) { T v → v F → 0.0 } ) = off + off 8 = k + k 1 }
    : *VIndex idx # *VIndex ( nurl_alloc Z VIndex )
    = . idx data data
    = . idx n n
    = . idx dim dim
    = . idx metric metric
    = . idx nlist nlist
    : ( Vec f ) nrm ( vec_new [f] )
    ( __vx_fill_norms data n dim nrm )
    = . idx norm nrm
    : ( Vec f ) cent ( vec_new [f] )
    : ( Vec f ) cnorm ( vec_new [f] )
    : ( Vec i ) loff ( vec_new [i] )
    : ( Vec i ) members ( vec_new [i] )
    ? > nlist 0 {
        = k 0
        ~ < k * nlist dim { ( vec_push [f] cent ?? ( bytes_read_f64_le b off ) { T v → v F → 0.0 } ) = off + off 8 = k + k 1 }
        = k 0
        ~ < k + nlist 1 { ( vec_push [i] loff # i ?? ( bytes_read_u64_le b off ) { T v → v F → # u64 0 } ) = off + off 8 = k + k 1 }
        = k 0
        ~ < k n { ( vec_push [i] members # i ?? ( bytes_read_u64_le b off ) { T v → v F → # u64 0 } ) = off + off 8 = k + k 1 }
        ( __vx_fill_norms cent nlist dim cnorm )
    } {}
    = . idx cent cent
    = . idx cnorm cnorm
    = . idx list_off loff
    = . idx members members
    ^ @ !*VIndex String { T idx }
}
