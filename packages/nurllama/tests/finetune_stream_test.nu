// finetune_stream_test.nu — the streamed base upload is the SAME training
// run, only cheaper in host RAM.
//
// Eagerly, ft_open lifts every base weight into f64 host tensors and the
// tape clones each into its own const, so the host peak is two copies of
// the whole model at the moment of capture — 12.7 GB for a 0.6B model,
// which puts a 4B model out of reach of a 31 GB machine. Streaming reads
// the SHAPES at open, declares each base weight as a lazy const, and fills
// it straight into its device buffer after the capture, one tensor at a
// time.
//
// The claim to prove is equivalence, not plausibility: same model, same
// window, same seed — the step-0 device loss must be BIT-IDENTICAL, because
// the bytes uploaded are identical and only the moment of upload differs.
// Anything less would mean the streamed loader disagrees with the eager one
// about layout, un-permutation or ordering.
//
//   QWEN3_GGUF=~/.nurllama/blobs/sha256-… \
//   NURL_STDLIB=<repo> ../../nurl.sh tests/finetune_stream_test.nu /tmp/fs && /tmp/fs

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
    ( nurl_print label ) ( nurl_print `\n` )
}

@ tokens s path → ( Vec i ) {
    : ( Vec i ) ids ( vec_new [i] )
    ?? ( gguf_open path ) {
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
    ^ ids
}

// One 1-step training run; writes the step-0 device loss bits into `out`.
@ run_once s path b stream i dtype * u out → b {
    ( ft_set_stream stream )
    ?? ( ft_open path ) {
        T m → {
            : ( Vec i ) ids ( tokens path )
            ? > ( vec_len [i] ids ) 4 {} {
                ( vec_free [i] ids ) ( ft_free m ) ( ft_set_stream F ) ^ F
            }
            : FtTrain tr ( ft_train m ids ( vec_len [i] ids ) 8 16.0 42 1 0.002 dtype F )
            : b ok . tr ok
            ? ok { ( nurl_poke out 0 ( f64_to_bits . tr l0 ) ) } {}
            ( ft_train_free tr )
            ( vec_free [i] ids )
            ( ft_free m )
            ( ft_set_stream F )
            ^ ok
        }
        F e → {
            ( nurl_print `  ft_open failed: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ( string_free e )
            ( ft_set_stream F )
            ^ F
        }
    }
    ^ F
}

@ main → i {
    : ~ String mp ( string_new )
    ?? ( env_get `QWEN3_GGUF` ) { T p → { ( string_free mp ) = mp p } F → {} }
    ? & > ( string_len mp ) 0 ( file_exists ( string_data mp ) ) {} {
        ( nurl_print `finetune_stream_test: SKIP (set QWEN3_GGUF)\n` )
        ( string_free mp )
        ^ 0
    }

    : *u ea ( nurl_alloc 8 )
    : *u st ( nurl_alloc 8 )
    ( nurl_poke ea 0 0 )
    ( nurl_poke st 0 1 )
    : b oks ( run_once ( string_data mp ) T 0 st )
    ( check oks `streamed run completes (shapes at open, values after capture)` )
    : b oke ( run_once ( string_data mp ) F 0 ea )
    ( check oke `eager run completes` )
    ( nurl_print `  step-0 loss eager ` )
    ( nurl_print ( nurl_str_float ( bits_to_f64 ( nurl_peek ea 0 ) ) ) )
    ( nurl_print ` streamed ` )
    ( nurl_print ( nurl_str_float ( bits_to_f64 ( nurl_peek st 0 ) ) ) )
    ( nurl_print `\n` )
    ( check == ( nurl_peek ea 0 ) ( nurl_peek st 0 )
    `step-0 device loss is BIT-IDENTICAL streamed vs eager (f64 replay)` )

    // and on the f32 replay, the one a big model actually uses
    : *u ea32 ( nurl_alloc 8 )
    : *u st32 ( nurl_alloc 8 )
    ( nurl_poke ea32 0 0 )
    ( nurl_poke st32 0 1 )
    : b oke32 ( run_once ( string_data mp ) F 1 ea32 )
    : b oks32 ( run_once ( string_data mp ) T 1 st32 )
    ( check & oke32 oks32 `f32 replay runs both ways` )
    ( check == ( nurl_peek ea32 0 ) ( nurl_peek st32 0 )
    `step-0 device loss bit-identical on the f32 replay too` )

    ( nurl_free ea ) ( nurl_free st ) ( nurl_free ea32 ) ( nurl_free st32 )
    ( string_free mp )
    ( nurl_print `\nfinetune_stream_test: ` )
    ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` )
    ( nurl_print_int g_fail )
    ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
