// packages/nurllama/src/sample.nu — host-side sampling over the logits.
//
//   ( sample_greedy m )                → i   argmax
//   ( sample_next m rng temp topk topp ) → i softmax(T) → top-k → top-p → draw
//
// temp ≤ 0 collapses to greedy. top-k ≤ 0 disables the k filter;
// topp ≥ 1 disables the nucleus filter. Deterministic under a seeded Rng.

$ `stdlib/core/vec.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/float.nu`  // exp
$ `stdlib/std/sort.nu`
$ `deps/gpu/src/gpu.nu`
$ `model.nu`

@ sample_greedy Llm m → i {
    : i n ( llm_n_vocab m )
    : ( Vec f ) lg ( llm_logits m )
    : ~ i best 0
    : ~ f bv ( vec_at [f] lg 0 )
    : ~ i k 1
    ~ < k n {
        : f v ( vec_at [f] lg k )
        ? > v bv {
            = best k
            = bv v
        } {}
        = k + k 1
    }
    ^ best
}

// A token the draw may pick: its temperature-scaled logit and its id.
: SCand {
    f v
    i id
}

// Best first; equal logits in id order, so the draw is the same however
// the sort moved them.
@ __sm_by_logit SCand a SCand b → i {
    ? > . a v . b v { ^ -1 } {}
    ? < . a v . b v { ^ 1 } {}
    ^ ? < . a id . b id -1 ? > . a id . b id 1 0
}

@ sample_next Llm m Rng rng f temp i topk f topp → i {
    ? <= temp 0.0 { ^ ( sample_greedy m ) } {}
    : i n ( llm_n_vocab m )
    : ( Vec f ) lg ( llm_logits m )

    // the candidates: logits over temperature, and the max for a stable
    // softmax
    : ( Vec SCand ) c ( vec_with_cap [SCand] n )
    : ~ f mx -1.0e30
    : ~ i k 0
    ~ < k n {
        : f v / ( vec_at [f] lg k ) temp
        ( vec_push [SCand] c @ SCand { v k } )
        ? > v mx { = mx v } {}
        = k + k 1
    }

    // Only a filter needs the candidates in order — top-k keeps the k best,
    // top-p walks them best first — and then one O(n log n) sort serves
    // both. Without either, the draw takes them as they come. (This was a
    // selection sort of the k best, O(n·k): fine for k = 40, but with no
    // top-k — OpenAI's default — that is O(n²), 2.4·10¹⁰ steps a token over
    // a 155k vocabulary.)
    : b ktop & > topk 0 < topk n
    : b ptop & > topp 0.0 < topp 1.0
    ? | ktop ptop { ( sort_by [SCand] c \ SCand a SCand b → i { ^ ( __sm_by_logit a b ) } ) } {}
    : i keep ? ktop topk n

    // softmax over the kept prefix
    : ( Vec f ) w ( vec_with_cap [f] keep )
    : ~ f sum 0.0
    : ~ i a 0
    ~ < a keep {
        : f e ( exp - . ( vec_at [SCand] c a ) v mx )
        ( vec_push [f] w e )
        = sum + sum e
        = a + a 1
    }

    // top-p: walk the (sorted) prefix until cumulative mass ≥ topp
    : ~ i last keep
    ? ptop {
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
    : ~ i pick . ( vec_at [SCand] c 0 ) id
    : ~ b found F
    = a 0
    ~ & < a last ! found {
        ?? ( vec_get [f] w a ) { T x → { = acc2 + acc2 x } F → {} }
        ? >= acc2 r {
            = pick . ( vec_at [SCand] c a ) id
            = found T
        } {}
        = a + a 1
    }
    ^ pick
}
