// tests/embed_shapes.nu — the operational invariant this package's
// serving behaviour rests on: embedding texts of MANY DISTINCT LENGTHS
// must stop allocating device memory and stop compiling kernels.
//
// Before the padded/bucketed forward, every new sequence length was a
// new set of buffer sizes (gpukit pools by exact byte size) and a new
// shape-specialised permute kernel (gkd_perm bakes its dims into the
// kernel name). The pool and the kernel cache both grew without bound,
// and the NVRTC compile made every new length a ~350 ms request in a
// server whose warm requests were 36 ms.
//
//   embed_shapes <model-dir>
//
// Prints the pool/kernel counts after a warm-up and after a long sweep
// of distinct lengths; exits non-zero if either kept growing.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `src/model.nu`

@ __words i nw → String {
    : String s ( string_new )
    : ~ i k 0
    ~ < k nw {
        ? > k 0 { ( string_push_char s 32 ) } {}
        ( string_push_str s `sana` )
        ( string_push_int s k )
        = k + k 1
    }
    ^ s
}

@ __kernels * Embed e → i { ^ ( vec_len [GkKernelEntry] . . e kit cache ) }

// Embed one text of `nw` words; T on success.
@ __run * Embed e i nw ( Vec f ) out → b {
    : String w ( __words nw )
    : b r ( embed_encode e ( string_data w ) out )
    ( string_free w )
    ^ r
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? >= ( vec_len [String] av ) 2 {} { ( nurl_print `usage: embed_shapes <model-dir>\n` ) ^ 2 }
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F → ( string_new ) }
    : ~ i rc 0
    ?? ( embed_open ( string_data mp ) ) {
        T e → {
            : ( Vec f ) out ( vec_new [f] )
            : ~ b ok T
            // warm-up: enough distinct lengths to have visited the
            // buckets the sweep will land in
            : ~ i nw 1
            ~ & ok < nw 120 { = ok ( __run e nw out ) = nw + nw 3 }
            : i pool0 ( gk_pool_count )
            : i kern0 ( __kernels e )
            // the sweep: every length in between, none of it new work
            = nw 1
            ~ & ok < nw 120 { = ok ( __run e nw out ) = nw + nw 1 }
            : i pool1 ( gk_pool_count )
            : i kern1 ( __kernels e )
            ( nurl_print `  pool blocks ` ) ( nurl_print ( nurl_str_int pool0 ) )
            ( nurl_print ` -> ` ) ( nurl_print ( nurl_str_int pool1 ) )
            ( nurl_print `, kernels ` ) ( nurl_print ( nurl_str_int kern0 ) )
            ( nurl_print ` -> ` ) ( nurl_print ( nurl_str_int kern1 ) )
            ( nurl_print `\n` )
            ? ok {} { ( nurl_print `  FAIL: an encode failed\n` ) = rc 1 }
            ? == pool1 pool0 {} {
                ( nurl_print `  FAIL: the device-buffer pool kept growing\n` )
                = rc 1
            }
            ? == kern1 kern0 {} {
                ( nurl_print `  FAIL: kernels were still being compiled\n` )
                = rc 1
            }
            ( vec_free [f] out )
            ( embed_close e )
        }
        F err → {
            ( nurl_print `open fail: ` ) ( nurl_print ( string_data err ) ) ( nurl_print `\n` )
            ( string_free err )
            = rc 1
        }
    }
    : ~ i k 0
    ~ < k ( vec_len [String] av ) {
        ?? ( vec_get [String] av k ) { T s2 → { ( string_free s2 ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] av )
    ^ rc
}
