// packages/nurllama/src/diffuse.nu — the block-diffusion decode loop
// (LLaDA2.x "JointThreshold + editing").
//
//   ( dz_generate m prompt gen_len block_len threshold edit_thr
//                 max_post temp rng ) → ( Vec i )
//
// The sequence is a template of `gen_len` mask tokens after the
// prompt, processed one `block_len` window at a time. Each denoise
// step evaluates the whole active window bidirectionally
// (llm_eval_win) and samples every position at once:
//
//   - masked positions whose confidence clears `threshold` are
//     committed (all of them; if none clears it, the single most
//     confident one is) — the parallel-decode half
//   - already-committed positions (except the prompt's) are REVISED
//     when the model now prefers a different token above `edit_thr` —
//     the LLaDA2.1 editing half
//   - the step loop ends when a pass finds no masks and makes no
//     edits, or after `max_post` post-resolution passes
//
// Completed blocks freeze: one final KV-only evaluation writes the
// block's settled content into the cache, and later windows attend to
// it without re-evaluating — the reference implementation recomputes
// the whole prefix every step; the cache makes each step O(window)
// instead of O(prefix).
//
// Generation stops early when a completed block leaves no masks and
// an EOS has appeared (eos_early_stop), and the returned ids are cut
// BEFORE the first EOS — callers get exactly the text tokens.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rng.nu`
$ `deps/gpu/src/gpu.nu`
$ `src/model.nu`

& `libm` @ exp f x → f

@ _dz_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ 0 } }
}

@ _dz_getf ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

// Sample window row `row`: greedy argmax when temp ≤ 0, else a draw
// from softmax(logits/temp). Appends the chosen id to `ids` and its
// probability under the SAME distribution to `confs` (the reference
// scores greedy confidence on the unscaled softmax).
@ __dz_sample_row * Llm m i row f temp Rng rng ( Vec i ) ids ( Vec f ) confs → v {
    : i n ( llm_n_vocab m )
    : f t ? > temp 0.0 temp 1.0
    : ~ f mx -1.0e30
    : ~ i best 0
    : ~ i k 0
    ~ < k n {
        : f v ( llm_logit_at m row k )
        ? > v mx {
            = mx v
            = best k
        } {}
        = k + k 1
    }
    : ~ f sum 0.0
    = k 0
    ~ < k n {
        = sum + sum ( exp / - ( llm_logit_at m row k ) mx t )
        = k + k 1
    }
    : ~ i chosen best
    ? > temp 0.0 {
        : f u * ( rng_u01 rng ) sum
        : ~ f acc 0.0
        : ~ b going T
        = k 0
        = chosen - n 1
        ~ & going < k n {
            = acc + acc ( exp / - ( llm_logit_at m row k ) mx t )
            ? >= acc u {
                = chosen k
                = going F
            } {}
            = k + k 1
        }
    } {}
    ( vec_push [i] ids chosen )
    ( vec_push [f] confs / ( exp / - ( llm_logit_at m row chosen ) mx t ) sum )
}

@ dz_generate * Llm m ( Vec i ) prompt i gen_len0 i block_len0 f threshold f edit_thr i max_post f temp Rng rng → ( Vec i ) {
    : i mask ( llm_mask_id m )
    : i eos ( tok_eos ( llm_tok m ) )
    : ( Vec i ) out ( vec_new [i] )
    ? < mask 0 { ^ out } {}
    : ~ i bl block_len0
    ? < bl 1 { = bl 32 } {}
    ? > bl ( llm_chunk ) { = bl ( llm_chunk ) } {}
    : i np ( vec_len [i] prompt )
    // fit prompt + gen_len into whole blocks inside the context
    : ~ i gen_len gen_len0
    : ~ i nblocks / + + np gen_len - bl 1 bl
    ~ & > gen_len 0 > * nblocks bl ( llm_n_ctx m ) {
        = gen_len - gen_len bl
        = nblocks / + + np gen_len - bl 1 bl
    }
    ? < gen_len 1 { ^ out } {}
    : i total * nblocks bl

    : ( Vec i ) x ( vec_new [i] )
    : ~ i k 0
    ~ < k total {
        ( vec_push [i] x ? < k np ( _dz_geti prompt k ) mask )
        = k + k 1
    }

    // frozen full-prompt blocks: KV only
    : i prefill / np bl
    : ~ i b2 0
    ~ < b2 prefill {
        ( llm_eval_win m x * b2 bl bl * b2 bl * + b2 1 bl F )
        = b2 + b2 1
    }

    : ~ b stop F
    : ~ i nb prefill
    ~ & ! stop < nb nblocks {
        : i bs * nb bl
        : i be + bs bl
        : ~ i post 0
        : ~ b block_done F
        // T when the LAST window eval ran on exactly the x the block
        // settles with (a pass that made no commits and no edits): the
        // K/V rows that eval wrote to the cache already ARE the frozen
        // block, so the freeze re-eval below is skipped — one whole
        // forward saved per cleanly-converged block, with an identical
        // cache to show for it.
        : ~ b kv_settled F
        ~ ! block_done {
            // masks as of THIS pass's start (the reference computes its
            // break condition on the pre-commit view)
            : ~ i n_active 0
            = k 0
            ~ < k bl {
                ? == ( _dz_geti x + bs k ) mask { = n_active + n_active 1 } {}
                = k + k 1
            }
            ? == n_active 0 { = post + post 1 } {}
            ? > post max_post { = block_done T } {
                : ( Vec i ) x0 ( vec_new [i] )
                : ( Vec f ) confs ( vec_new [f] )
                ? <= temp 0.0 {
                    // greedy: argmax + confidence reduced on the DEVICE, so
                    // only bl·(id,prob) come back — the whole-vocab softmax
                    // no longer runs on the host every step.
                    ( llm_win_greedy m x bs bl bs be )
                    = k 0
                    ~ < k bl {
                        ( vec_push [i] x0 ( llm_win_id m k ) )
                        ( vec_push [f] confs ( llm_win_prob m k ) )
                        = k + k 1
                    }
                } {
                    ( llm_eval_win m x bs bl bs be T )
                    = k 0
                    ~ < k bl {
                        ( __dz_sample_row m k temp rng x0 confs )
                        = k + k 1
                    }
                }
                // masked-position commits
                ? > n_active 0 {
                    : ~ i n_hi 0
                    = k 0
                    ~ < k bl {
                        ? & == ( _dz_geti x + bs k ) mask > ( _dz_getf confs k ) threshold { = n_hi + n_hi 1 } {}
                        = k + k 1
                    }
                    ? > n_hi 0 {
                        = k 0
                        ~ < k bl {
                            ? & == ( _dz_geti x + bs k ) mask > ( _dz_getf confs k ) threshold {
                                : b _s1 ( vec_set [i] x + bs k ( _dz_geti x0 k ) )
                            } {}
                            = k + k 1
                        }
                    } {
                        // none clears the bar: commit the single most
                        // confident masked position
                        : ~ i bi -1
                        : ~ f bv -1.0e30
                        = k 0
                        ~ < k bl {
                            ? == ( _dz_geti x + bs k ) mask {
                                ? > ( _dz_getf confs k ) bv {
                                    = bv ( _dz_getf confs k )
                                    = bi k
                                } {}
                            } {}
                            = k + k 1
                        }
                        ? >= bi 0 { : b _s2 ( vec_set [i] x + bs bi ( _dz_geti x0 bi ) ) } {}
                    }
                } {}
                // editing: revise committed non-prompt positions the
                // model now disagrees with, confidently
                : ~ b edited F
                = k 0
                ~ < k bl {
                    : i cur ( _dz_geti x + bs k )
                    ? & & & != cur mask >= + bs k np
                    > ( _dz_getf confs k ) edit_thr != ( _dz_geti x0 k ) cur {
                        : b _s3 ( vec_set [i] x + bs k ( _dz_geti x0 k ) )
                        = edited T
                    } {}
                    = k + k 1
                }
                ( vec_free [i] x0 )
                ( vec_free [f] confs )
                ? & == n_active 0 ! edited {
                    = block_done T
                    = kv_settled T
                } {}
            }
        }
        // freeze: write the settled block's K/V from its FINAL content —
        // unless the last eval already did (kv_settled)
        ? kv_settled {} { ( llm_eval_win m x bs bl bs be F ) }
        // eos_early_stop: a fully-resolved generation containing an EOS
        // has nothing left to say
        : ~ b any_mask F
        : ~ b any_eos F
        = k np
        ~ < k be {
            ? == ( _dz_geti x k ) mask { = any_mask T } {}
            ? == ( _dz_geti x k ) eos { = any_eos T } {}
            = k + k 1
        }
        ? & ! any_mask any_eos { = stop T } {}
        = nb + nb 1
    }

    // collect the generation, cut BEFORE the first EOS
    : ~ i endi + np gen_len
    ? > endi total { = endi total } {}
    = k np
    : ~ b cut F
    ~ & ! cut < k endi {
        : i id ( _dz_geti x k )
        ? == id eos { = cut T } {
            ( vec_push [i] out id )
        }
        = k + k 1
    }
    ( vec_free [i] x )
    ^ out
}
