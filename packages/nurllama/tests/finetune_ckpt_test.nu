// nurllama/tests/finetune_ckpt_test.nu — checkpoint/resume for the LoRA
// trainer (SmolLM-135M from the local pull store; SKIPs without it).
//
// The claim under test: a run interrupted at step K and resumed replays
// the uninterrupted run EXACTLY. The checkpoint stores the device's own
// precision (F64 here — dtype 0), so the comparison is bit-equality of
// every adapter value, not a tolerance:
//
//   A. train 40 steps straight, no checkpoint            → reference
//   B. train 20 steps, checkpointing (the "crashed" run)
//   C. train 40 steps with --resume off B's checkpoint   → == A, bitwise
//
// Plus the refusal path: resuming that checkpoint under a different LoRA
// rank must fail loudly instead of training over it.
//
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/finetune_ckpt_test.nu /tmp/ftc && /tmp/ftc

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

// Element count of exact mismatches between two flat vectors (or -1 on a
// length mismatch — which is its own failure).
@ vec_diff ( Vec f ) a ( Vec f ) b2 → i {
    ? == ( vec_len [f] a ) ( vec_len [f] b2 ) {} { ^ -1 }
    : ~ i bad 0
    : ~ i k 0
    ~ < k ( vec_len [f] a ) {
        ? == ( _tf a k ) ( _tf b2 k ) {} { = bad + bad 1 }
        = k + k 1
    }
    ^ bad
}

@ main → i {
    : String mp ( model_path )
    ? ( file_exists ( string_data mp ) ) {} {
        ( nurl_print `finetune_ckpt_test: SKIP (SmolLM-135M not in the pull store)\n` )
        ( string_free mp )
        ^ 0
    }
    : s ckpt `/tmp/nurl_ft_ckpt_test.st`
    ?? ( ft_open ( string_data mp ) ) {
        T m → {
            // tokenize one sentence with the model's own tokenizer
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
            : i HW / T2 2

            // A: the uninterrupted reference (2 windows round-robin)
            : FtTrain trA ( ft_train m ids HW 8 16.0 42 40 0.002 0 F )
            ( check . trA ok `A: 40 straight steps (reference)` )

            // B: 20 steps with checkpointing — the run that "crashes"
            : FtTrain trB ( ft_train_ck m ids HW 8 16.0 42 20 0.002 0 F ckpt 10 F )
            ( check . trB ok `B: 20 steps, checkpoint every 10` )
            ( check ( file_exists ckpt ) `B: checkpoint file exists` )

            // C: resume B's checkpoint and finish to 40
            : FtTrain trC ( ft_train_ck m ids HW 8 16.0 42 40 0.002 0 F ckpt 10 T )
            ( check . trC ok `C: resumed to 40 steps` )
            : i abad ( vec_diff . trA aflat . trC aflat )
            : i bbad ( vec_diff . trA bflat . trC bflat )
            ( nurl_print `  A-vs-C mismatched elements: lora_a ` )
            ( nurl_print_int abad )
            ( nurl_print ` lora_b ` )
            ( nurl_print_int bbad )
            ( nurl_print `\n` )
            ( check == abad 0 `resumed lora_a BIT-IDENTICAL to the straight run` )
            ( check == bbad 0 `resumed lora_b BIT-IDENTICAL to the straight run` )
            ( check == . trA l1 . trC l1 `final loss identical` )

            // refusal: same checkpoint, different rank → must fail, not train
            : FtTrain trX ( ft_train_ck m ids HW 4 16.0 42 40 0.002 0 F ckpt 10 T )
            ( check == . trX ok F `rank mismatch refuses to resume (ok=F)` )

            ( ft_train_free trA )
            ( ft_train_free trB )
            ( ft_train_free trC )
            ( ft_train_free trX )
            ( vec_free [i] ids )
            ( ft_free m )
            ?? ( file_delete ckpt ) { T _ → {} F _ → {} }
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
    ( nurl_print `finetune_ckpt_test: ` )
    ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` )
    ( nurl_print_int g_fail )
    ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
