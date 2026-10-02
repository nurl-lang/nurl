// nurllama/tests/finetune_qwen3_test.nu — the qwen3 shape through the
// TRAINING tape, on a real Qwen3-0.6B GGUF.
//
// qwen3 is the llama shape with NEOX rope, no Q/K/V bias, a head_dim that
// is STATED rather than n_embd/n_head (0.6B: 16 heads × 128 = 2048 against
// an n_embd of 1024), and a per-head RMSNorm on Q and K before the
// rotation. Every one of those is silent when wrong: the model still runs
// and still produces fluent-looking tokens.
//
//   1. the hyperparameters come from the file, not from arithmetic
//      (head_dim 128, NOT 1024/16 = 64), and every layer carries its
//      attn_q_norm / attn_k_norm weight
//   2. WIRING ORACLE: the tape forward's last-position top-1 against
//      nurllama's own inference engine on the same prompt. The engine is
//      itself checked against an independent numpy implementation
//      (tests/qwen3_ref.py), so this closes the chain numpy → engine →
//      tape. Drop the Q/K norm from either side and the top-1 diverges.
//   3. LoRA still learns on this shape: the CE loss drops.
//
// Point it at a Qwen3 GGUF; SKIPs without one:
//   QWEN3_GGUF=~/.nurllama/blobs/sha256-… \
//   NURL_STDLIB=<repo> ../../nurl.sh tests/finetune_qwen3_test.nu /tmp/ftq && /tmp/ftq

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/env.nu`
$ `src/finetune.nu`
$ `src/model.nu`
$ `src/tokenizer.nu`
$ `deps/gguf/src/gguf.nu`
$ `deps/safetensor/src/safetensor.nu`
$ `deps/grad/src/grad.nu`
$ `deps/grad/src/opt.nu`
$ `deps/grad/src/gput.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label )
    ( nurl_print `\n` )
}

// Every layer's q_norm and k_norm must be present — an absent one is how
// a missing per-head norm would slip through as "just skip it".
@ norms_present FtModel m → b {
    : ~ b all T
    : ~ i L 0
    ~ < L ( ft_n_layer m ) {
        ? ( ft_has_qk_norm m L ) {} { = all F }
        = L + L 1
    }
    ^ all
}

@ main → i {
    : ~ String mp ( string_new )
    ?? ( env_get `QWEN3_GGUF` ) {
        T p → { = mp p }
        F → {}
    }
    ? & > ( string_len mp ) 0 ( file_exists ( string_data mp ) ) {} {
        ( nurl_print `finetune_qwen3_test: SKIP (set QWEN3_GGUF to a Qwen3 GGUF)\n` )
        ^ 0
    }

    // ── 1. the shape comes from the file ─────────────────────────────
    ?? ( ft_open ( string_data mp ) ) {
        T m → {
            ( nurl_print `  n_embd ` ) ( nurl_print_int ( ft_n_embd m ) )
            ( nurl_print ` n_layer ` ) ( nurl_print_int ( ft_n_layer m ) )
            ( nurl_print ` n_head ` ) ( nurl_print_int ( ft_n_head m ) )
            ( nurl_print ` n_kv ` ) ( nurl_print_int ( ft_n_kv m ) )
            ( nurl_print ` head_dim ` ) ( nurl_println_int ( ft_head_dim m ) )
            ( check == ( ft_rope_style m ) 1 `qwen3 → NEOX rope` )
            ( check != ( ft_head_dim m ) / ( ft_n_embd m ) ( ft_n_head m )
            `head_dim is READ (key_length), not n_embd/n_head` )
            ( check == * ( ft_n_head m ) ( ft_head_dim m ) * 2 ( ft_n_embd m )
            `Qwen3-0.6B: q_dim 2048 against n_embd 1024` )
            ( check ( norms_present m ) `every layer carries attn_q_norm + attn_k_norm` )

            : ( Vec i ) ids ( vec_new [i] )
            ?? ( gguf_open ( string_data mp ) ) {
                T gg → {
                    ?? ( tok_new gg ) {
                        T tk → {
                            : ( Vec i ) enc ( tok_encode tk `The capital of France is Paris, and the capital of Italy is` T )
                            : ~ i k 0
                            ~ < k ( vec_len [i] enc ) { ( vec_push [i] ids ( _ti enc k ) ) = k + k 1 }
                        }
                        F _e → {}
                    }
                }
                F _e → {}
            }
            : i T2 ( vec_len [i] ids )
            ( check >= T2 8 `prompt tokenizes (>= 8 tokens)` )

            // ── 2. the wiring oracle ───────────────────────────────
            : GTape tp ( tape_new )
            : ( Vec i ) pids ( vec_new [i] )
            : FtG fg ( ft_graph m tp ids 8 16.0 42 pids )
            ( check ( tape_ok tp ) `the whole qwen3 graph builds (tape healthy)` )
            : f ce ( g_scalar tp . fg loss )
            ( nurl_print `  CE loss ` ) ( nurl_print ( nurl_str_float ce ) ) ( nurl_print `\n` )
            ( check & > ce 0.1 < ce 10.0 `pretrained CE loss is sane (0.1 < ce < 10)` )
            : Tensor lg ( gvar_value tp . fg logits )
            : i V ( ft_n_vocab m )
            : ~ i targ 0
            : ~ f tbest -1000000000.0
            : ~ i c 0
            ~ < c V {
                : f v ( _tf . lg data + * - T2 1 V c )
                ? > v tbest { = tbest v = targ c } {}
                = c + c 1
            }
            ?? ( llm_open ( string_data mp ) 256 ) {
                T lm → {
                    : ~ i t 0
                    ~ < t T2 { ( llm_eval lm ( _ti ids t ) t ) = t + t 1 }
                    : ~ i earg 0
                    : ~ f ebest -1000000000.0
                    = c 0
                    ~ < c V {
                        : f v ( llm_logit lm c )
                        ? > v ebest { = ebest v = earg c } {}
                        = c + c 1
                    }
                    ( nurl_print `  top-1: tape ` ) ( nurl_print_int targ )
                    ( nurl_print ` engine ` ) ( nurl_println_int earg )
                    ( check == targ earg `WIRING ORACLE: tape top-1 == inference engine top-1` )
                    : f fe ( llm_logit lm targ )
                    : ~ f rel / ( float_abs - tbest fe ) ? > ( float_abs fe ) 1.0 ( float_abs fe ) 1.0
                    ( nurl_print `  top logit tape ` ) ( nurl_print ( nurl_str_float tbest ) )
                    ( nurl_print ` engine ` ) ( nurl_print ( nurl_str_float fe ) ) ( nurl_print `\n` )
                    ( check < rel 0.05 `top logit within 5% (f32 engine vs f64 tape)` )
                }
                F e → {
                    ( nurl_print `  (llm_open failed — engine oracle skipped)\n` )
                    = g_fail + g_fail 1
                }
            }
            // early release: the oracle's tape holds an f64 copy of every
            // weight; training below builds its own, and two at once is the
            // host peak this test must not double
            ( tape_free tp )

            // ── 3. LoRA still learns on this shape ─────────────────
            : FtTrain tr ( ft_train m ids ( vec_len [i] ids ) 8 16.0 42 30 0.002 0 F )
            ( check . tr ok `ft_train: 30 device Adam steps` )
            ( nurl_print `  train CE ` ) ( nurl_print ( nurl_str_float . tr l0 ) )
            ( nurl_print ` → ` ) ( nurl_print ( nurl_str_float . tr l1 ) ) ( nurl_print `\n` )
            ( check < . tr l1 * 0.5 . tr l0 `training halves the CE loss` )
            : ~ f drel / ( float_abs - . tr l0 ce ) ? > ( float_abs ce ) 1.0 ( float_abs ce ) 1.0
            ( check < drel 0.000001 `step-0 device loss matches the CPU build (1e-6)` )
        }
        F e → {
            ( nurl_print `  ft_open failed: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            = g_fail + g_fail 1
        }
    }

    ( nurl_print `\nfinetune_qwen3_test: ` )
    ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` )
    ( nurl_print_int g_fail )
    ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
