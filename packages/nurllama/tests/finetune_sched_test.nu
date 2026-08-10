// nurllama/tests/finetune_sched_test.nu — the window schedule, CPU-only.
//
// ft_win_at(st) = (st · stride) mod nwin. The properties that make the
// spread schedule safe to ship:
//   1. ft_auto_stride(nwin) is coprime with nwin for a spread of sizes
//      (including the real 4B corpus's 132163), so the schedule is a
//      PERMUTATION: nwin steps visit every window exactly once.
//   2. stride 1 reproduces the sequential legacy order bit for bit.
//   3. A short prefix of the spread schedule covers the corpus evenly:
//      its windows are not bunched at the front (max window ≥ half the
//      corpus even at 1% of an epoch).
//
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/finetune_sched_test.nu /tmp/fts && /tmp/fts

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `src/tokenizer.nu`
$ `src/finetune.nu`
$ `deps/gguf/src/gguf.nu`
$ `deps/gguf/src/dequant.nu`
$ `deps/safetensor/src/safetensor.nu`
$ `deps/safetensor/src/write.nu`
$ `deps/grad/src/grad.nu`
$ `deps/grad/src/gput.nu`
$ `deps/nn/src/nn.nu`
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

// One nwin: auto stride is coprime, and nwin steps visit every window once.
@ check_perm i nwin → v {
    : i S ( ft_auto_stride nwin )
    : ( Vec i ) seen ( vec_with_cap [i] nwin )
    : ~ i k 0
    ~ < k nwin { ( vec_push [i] seen 0 ) = k + k 1 }
    : ~ i dup 0
    = k 0
    ~ < k nwin {
        : i w ( ft_win_at k nwin S )
        ? | < w 0 >= w nwin { = dup + dup 1 } {
            ? == ( _ti seen w ) 0 { ( vec_set [i] seen w 1 ) } { = dup + dup 1 }
        }
        = k + k 1
    }
    : String lbl ( string_from `auto stride is a permutation (nwin ` )
    ( string_push_str lbl ( nurl_str_int nwin ) )
    ( string_push_str lbl ` → stride ` )
    ( string_push_str lbl ( nurl_str_int S ) )
    ( string_push_str lbl `)` )
    ( check == dup 0 ( string_data lbl ) )
    ( string_free lbl )
    ( vec_free [i] seen )
}

@ main → i {
    // 1. permutation property across sizes, the real corpus's nwin included
    ( check_perm 2 )
    ( check_perm 7 )
    ( check_perm 12 )
    ( check_perm 1000 )
    ( check_perm 132163 )

    // 2. stride 1 is the sequential legacy order
    : ~ i seqok 1
    : ~ i k 0
    ~ < k 500 {
        ? == ( ft_win_at k 132163 1 ) k {} { = seqok 0 }
        = k + k 1
    }
    ( check == seqok 1 `stride 1 reproduces the sequential order` )

    // 3. a 1%-of-an-epoch prefix still reaches deep into the corpus
    : i nwin 132163
    : i S ( ft_auto_stride nwin )
    : ~ i wmax 0
    : ~ i wmin nwin
    = k 0
    ~ < k 1322 {
        : i w ( ft_win_at k nwin S )
        ? > w wmax { = wmax w } {}
        ? < w wmin { = wmin w } {}
        = k + k 1
    }
    ( check > wmax / * nwin 9 10 `1% prefix reaches the last tenth of the corpus` )
    ( check < wmin / nwin 10 `1% prefix reaches the first tenth of the corpus` )

    // 4. degenerate sizes don't divide by zero or escape range
    ( check == ( ft_win_at 5 1 1 ) 0 `single-window corpus always picks window 0` )
    ( check == ( ft_auto_stride 1 ) 1 `auto stride of 1 window is 1` )
    ( check == ( ft_auto_stride 2 ) 1 `auto stride of 2 windows is 1` )

    ( nurl_print `finetune_sched_test: ` )
    ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` )
    ( nurl_print_int g_fail )
    ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
