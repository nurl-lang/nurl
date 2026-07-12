// packages/nurllama/src/sample.nu — host-side sampling over the logits.
//
//   ( sample_greedy m )                → i   argmax
//   ( sample_next m rng temp topk topp ) → i softmax(T) → top-k → top-p → draw
//
// temp ≤ 0 collapses to greedy. top-k ≤ 0 disables the k filter;
// topp ≥ 1 disables the nucleus filter. Deterministic under a seeded Rng.

$ `stdlib/core/vec.nu`
$ `stdlib/std/rng.nu`
$ `deps/gpu/src/gpu.nu`
$ `src/model.nu`

@ sample_greedy * Llm m → i {
    : i n ( llm_n_vocab m )
    : ~ i best 0
    : ~ f bv ( llm_logit m 0 )
    : ~ i k 1
    ~ < k n {
        : f v ( llm_logit m k )
        ? > v bv {
            = best k
            = bv v
        } {}
        = k + k 1
    }
    ^ best
}

// host-side softmax needs exp — bind libm directly, the stdlib idiom
& `libm` @ exp f x → f

@ sample_next * Llm m Rng rng f temp i topk f topp → i {
    ? <= temp 0.0 { ^ ( sample_greedy m ) } {}
    : i n ( llm_n_vocab m )

    // copy logits, apply temperature, track max for stable softmax
    : ( Vec f ) p ( vec_with_cap [f] n )
    : ~ f mx -1.0e30
    : ~ i k 0
    ~ < k n {
        : f v / ( llm_logit m k ) temp
        ( vec_push [f] p v )
        ? > v mx { = mx v } {}
        = k + k 1
    }
    : ( Vec i ) idx ( vec_iota 0 n )

    // top-k: partial selection sort of the k largest (k is small)
    : ~ i keep n
    ? & > topk 0 < topk n { = keep topk } {}
    : ~ i a 0
    ~ < a keep {
        : ~ i bi a
        : ~ f bvv -1.0e30
        : ~ i j a
        ~ < j n {
            : i ij ( __lm_geti idx j )
            ?? ( vec_get [f] p ij ) {
                T v → {
                    ? > v bvv {
                        = bvv v
                        = bi j
                    } {}
                }
                F → {}
            }
            = j + j 1
        }
        : b _sw ( vec_swap [i] idx a bi )
        = a + a 1
    }

    // softmax over the kept prefix
    : ( Vec f ) w ( vec_with_cap [f] keep )
    : ~ f sum 0.0
    = a 0
    ~ < a keep {
        : i ia ( __lm_geti idx a )
        : ~ f v 0.0
        ?? ( vec_get [f] p ia ) { T x → { = v x } F → {} }
        : f e ( exp - v mx )
        ( vec_push [f] w e )
        = sum + sum e
        = a + a 1
    }

    // top-p: walk the (sorted) prefix until cumulative mass ≥ topp
    : ~ i last keep
    ? & > topp 0.0 < topp 1.0 {
        : ~ f acc 0.0
        : ~ i b2 0
        = last 0
        ~ & < b2 keep < acc * topp sum {
            ?? ( vec_get [f] w b2 ) { T x → { = acc + acc x } F → {} }
            = b2 + b2 1
            = last b2
        }
        ? < last 1 { = last 1 } {}
    } {}

    // draw
    : ~ f psum 0.0
    = a 0
    ~ < a last {
        ?? ( vec_get [f] w a ) { T x → { = psum + psum x } F → {} }
        = a + a 1
    }
    : f r * ( rng_u01 rng ) psum
    : ~ f acc2 0.0
    : ~ i pick ( __lm_geti idx 0 )
    : ~ b found F
    = a 0
    ~ & < a last ! found {
        ?? ( vec_get [f] w a ) { T x → { = acc2 + acc2 x } F → {} }
        ? >= acc2 r {
            = pick ( __lm_geti idx a )
            = found T
        } {}
        = a + a 1
    }
    ( vec_free [f] p )
    ( vec_free [f] w )
    ( vec_free [i] idx )
    ^ pick
}
