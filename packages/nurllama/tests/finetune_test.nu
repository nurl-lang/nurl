// nurllama/tests/finetune_test.nu — M6b-1: the LoRA finetune foundation on
// a REAL model (SmolLM-135M from the local pull store; SKIPs without it).
//
//   1. ft_open lifts every GGUF weight into f64 tape-layout host tensors.
//   2. WIRING ORACLE: the tape forward's last-position logits against
//      nurllama's own verified inference engine on the same prompt — the
//      engine computes in f32 over quantised weights, the tape in f64 over
//      the dequantised copies, so agreement is a tolerance check (top-1
//      id EQUAL, relative gap on the shared top logit) — but a RoPE/GQA/
//      layout mistake shreds it completely, which is the point.
//   3. Overfit proof: LoRA (r=8, α=16) on q/k/v/o+gate/up/down of all
//      layers, trained ON THE DEVICE via gput for 40 Adam steps on one
//      sentence — the CE loss must drop by half.
//
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/finetune_test.nu /tmp/ft && /tmp/ft

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

@ model_path → String {
    : String p ?? ( env_get `HOME` ) { T h → h F → ( string_new ) }
    ( string_push_str p `/.nurllama/blobs/sha256-51d462d88ac435eb7bcda026c978538e9f90de448ebc4135fef1ad889daf42e4` )
    ^ p
}

@ main → i {
    : String mp ( model_path )
    ? ( file_exists ( string_data mp ) ) {} {
        ( nurl_print `finetune_test: SKIP (SmolLM-135M not in the pull store)\n` )
        ( string_free mp )
        ^ 0
    }

    // ── 1. load ──────────────────────────────────────────────────────
    ?? ( ft_open ( string_data mp ) ) {
        T m → {
            ( check & & == . m n_embd 576 == . m n_layer 30 == . m n_head 9 `SmolLM dims read from metadata (576/30/9)` )
            ( check == . m rope_style 0 `llama arch → NORM rope (un-permuted at load)` )

            // tokenize the prompt with the model's own tokenizer
            : ( Vec i ) ids ( vec_new [i] )
            ?? ( gguf_open ( string_data mp ) ) {
                T gg → {
                    ?? ( tok_new gg ) {
                        T tk → {
                            : ( Vec i ) enc ( tok_encode tk `The capital of France is Paris, and the capital of Italy is` T )
                            : ~ i k 0
                            ~ < k ( vec_len [i] enc ) { ( vec_push [i] ids ( _ti enc k ) ) = k + k 1 }
                            ( vec_free [i] enc )
                            ( tok_free tk )
                        }
                        F e → { ( string_free e ) }
                    }
                    ( gguf_close gg )
                }
                F e → { ( string_free e ) }
            }
            : i T2 ( vec_len [i] ids )
            ( check >= T2 8 `prompt tokenizes (>= 8 tokens)` )

            // ── 2. build the graph + the wiring oracle ──────────────
            : *GTape tp ( tape_new )
            : *u pids ( nurl_alloc * * 2 * 7 . m n_layer 8 )
            : FtG fg ( ft_graph m tp ids 8 16.0 42 pids )
            ( check ( tape_ok tp ) `full 30-layer graph builds (tape healthy)` )
            : f ce ( g_scalar tp . fg loss )
            ( nurl_print `  CE loss ` )
            ( nurl_print ( nurl_str_float ce ) )
            ( nurl_print `\n` )
            ( check & > ce 0.1 < ce 10.0 `pretrained CE loss is sane (0.1 < ce < 10)` )
            // tape top-1 at the last position
            : Tensor lg ( gvar_value tp . fg logits )
            : i V . m n_vocab
            : ~ i targ 0
            : ~ f tbest -1000000000.0
            : ~ i c 0
            ~ < c V {
                : f v ( _tf . lg data + * - T2 1 V c )
                ? > v tbest { = tbest v = targ c } {}
                = c + c 1
            }
            // the inference engine's top-1 on the same prompt
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
                    ( nurl_print `  top-1: tape ` )
                    ( nurl_print_int targ )
                    ( nurl_print ` engine ` )
                    ( nurl_print_int earg )
                    ( nurl_print `\n` )
                    ( check == targ earg `WIRING ORACLE: tape top-1 == inference engine top-1` )
                    : f fe ( llm_logit lm targ )
                    : ~ f rel / ( float_abs - tbest fe ) ? > ( float_abs fe ) 1.0 ( float_abs fe ) 1.0
                    ( nurl_print `  top logit tape ` )
                    ( nurl_print ( nurl_str_float tbest ) )
                    ( nurl_print ` engine ` )
                    ( nurl_print ( nurl_str_float fe ) )
                    ( nurl_print `\n` )
                    ( check < rel 0.05 `top logit within 5% (f32 engine vs f64 tape)` )
                    ( llm_close lm )
                }
                F e → {
                    ( nurl_print `  (llm_open failed — engine oracle skipped)\n` )
                    ( string_free e )
                }
            }

            // ── 3. train → save → merge → run the merged model ──────
            : FtTrain tr ( ft_train m ids ( vec_len [i] ids ) 8 16.0 42 60 0.002 0 F )
            ( check . tr ok `ft_train: 60 device Adam steps over 420 adapters` )
            ( nurl_print `  train CE ` )
            ( nurl_print ( nurl_str_float . tr l0 ) )
            ( nurl_print ` → ` )
            ( nurl_print ( nurl_str_float . tr l1 ) )
            ( nurl_print `\n` )
            ( check < . tr l1 * 0.1 . tr l0 `training cuts the CE loss by 10x+` )
            : ~ f drel / ( float_abs - . tr l0 ce ) ? > ( float_abs ce ) 1.0 ( float_abs ce ) 1.0
            ( check < drel 0.000001 `step-0 device loss matches the CPU build (1e-6)` )
            // adapters: save + round-trip
            : s apath `/tmp/nurl_ft_adapters.safetensors`
            : ~ b saok F
            ?? ( ft_adapters_save apath m tr 8 ) { T _ → { = saok T } F e2 → { ( string_free e2 ) } }
            ( check saok `adapters save as safetensors` )
            ?? ( st_open apath ) {
                T st → {
                    ( check == ( st_n_tensors st ) * 2 * 7 . m n_layer `adapter file holds 2 tensors per slot (420)` )
                    ( check >= ( st_find_tensor st `blk.0.q.lora_a` ) 0 `blk.0.q.lora_a present` )
                    ( st_close st )
                }
                F e2 → { ( string_free e2 ) = g_fail + g_fail 1 }
            }
            // merge + run through nurllama's --weights path
            : s mpath `/tmp/nurl_ft_merged.safetensors`
            : ~ b meok F
            ?? ( ft_merge_st mpath m tr 8 16.0 ) { T _ → { = meok T } F e2 → { ( string_free e2 ) } }
            ( check meok `merged full-model safetensors written` )
            ? meok {
                ?? ( llm_open_st ( string_data mp ) mpath 256 ) {
                    T lm2 → {
                        : ~ i hits 0
                        : ~ i t2 0
                        ~ < t2 - T2 1 {
                            ( llm_eval lm2 ( _ti ids t2 ) t2 )
                            : ~ i barg 0
                            : ~ f bbest -1000000000.0
                            : ~ i c2 0
                            ~ < c2 V {
                                : f v ( llm_logit lm2 c2 )
                                ? > v bbest { = bbest v = barg c2 } {}
                                = c2 + c2 1
                            }
                            ? == barg ( _ti ids + t2 1 ) { = hits + hits 1 } {}
                            = t2 + t2 1
                        }
                        ( nurl_print `  merged-model greedy: ` )
                        ( nurl_print_int hits )
                        ( nurl_print ` / ` )
                        ( nurl_print_int - T2 1 )
                        ( nurl_print ` positions reproduce the training targets\n` )
                        ( check >= hits - T2 2 `merged model reproduces the overfitted sentence (>= T-2 greedy hits)` )
                        ( llm_close lm2 )
                    }
                    F e2 → {
                        ( nurl_print `  llm_open_st FAILED: ` )
                        ( nurl_print ( string_data e2 ) )
                        ( nurl_print `\n` )
                        ( string_free e2 )
                        = g_fail + g_fail 1
                    }
                }
            } {}
            ( ft_train_free tr )
            // multi-window: halve the window → 2 windows round-robin; the
            // trained model must reproduce BOTH windows' targets
            : i HW / T2 2
            : FtTrain tr2 ( ft_train m ids HW 8 16.0 42 120 0.002 0 F )
            ( check . tr2 ok `multi-window ft_train runs (2 windows round-robin)` )
            ( nurl_print `  2-window CE ` )
            ( nurl_print ( nurl_str_float . tr2 l0 ) )
            ( nurl_print ` → ` )
            ( nurl_print ( nurl_str_float . tr2 l1 ) )
            ( nurl_print `\n` )
            ( check < . tr2 l1 * 0.2 . tr2 l0 `2-window training cuts the CE by 5x+` )
            ( ft_train_free tr2 )
            // the float32 device-replay path (ft_train dtype=1) is proven
            // end to end by grad's gput_f32_test (loss 1e-5, params 4e-4 vs
            // the f64 tape) and, on a real model, by the `finetune --f32`
            // CLI run in the package README — not re-run here (a fourth full
            // 30-layer training would balloon this suite's wall time).
            ( nurl_free pids )
            ( tape_free tp )
            ( vec_free [i] ids )
            ( ft_free m )
        }
        F e → {
            ( nurl_print `ft_open FAILED: ` )
            ( nurl_print ( string_data e ) )
            ( nurl_print `\n` )
            ( string_free e )
            = g_fail + g_fail 1
        }
    }
    ( string_free mp )
    ( nurl_print `finetune_test: ` )
    ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` )
    ( nurl_print_int g_fail )
    ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
