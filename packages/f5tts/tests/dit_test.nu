// dit_test.nu — the transformer against PyTorch, tensor by tensor.
//
// tests/ref_dit.py runs one forward of the deployed Finnish checkpoint under
// the reference implementation and writes every intermediate as raw f32.
// This reruns the same forward here and compares. The inputs are fixed, so a
// disagreement is a disagreement about the model, not about sampling.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/dit_test.nu /tmp/d5
//   /tmp/d5 <checkpoint.safetensors> <vocab.txt> <refdir>

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `src/model.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ __d_check b ok s label → v {
    ? ok { ( nurl_print `  ok   ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_println label )
}

@ __d_path s dir s name → String {
    : String p ( string_from dir )
    ( string_push_char p 47 )
    ( string_push_str p name )
    ^ p
}

@ __d_read_f32 s dir s name → ( Vec f ) {
    : String p ( __d_path dir name )
    : ( Vec f ) out ( vec_new [f] )
    ?? ( read_file_bytes ( string_data p ) ) {
        T bs → {
            : i n / ( vec_len [u] bs ) 4
            : ~ i k 0
            ~ < k n {
                ?? ( bytes_read_f32_le bs * k 4 ) { T x → { ( vec_push [f] out # f x ) } F → {} }
                = k + k 1
            }
            ( vec_free [u] bs )
        }
        F _e → { ( nurl_eprint `cannot read ` ) ( nurl_eprintln ( string_data p ) ) }
    }
    ( string_free p )
    ^ out
}

@ __d_read_i32 s dir s name → ( Vec i ) {
    : String p ( __d_path dir name )
    : ( Vec i ) out ( vec_new [i] )
    ?? ( read_file_bytes ( string_data p ) ) {
        T bs → {
            : i n / ( vec_len [u] bs ) 4
            : ~ i k 0
            ~ < k n {
                ?? ( bytes_read_u32_le bs * k 4 ) { T x → { ( vec_push [i] out # i x ) } F → {} }
                = k + k 1
            }
            ( vec_free [u] bs )
        }
        F _e → { ( nurl_eprint `cannot read ` ) ( nurl_eprintln ( string_data p ) ) }
    }
    ( string_free p )
    ^ out
}

@ __d_get ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

// Relative agreement: the largest absolute difference against the reference's
// own largest magnitude. A transformer's activations grow through the depth,
// so an absolute tolerance would be meaningless by layer twenty.
@ __d_cmp ( Vec f ) got ( Vec f ) want s label f tol → v {
    : i n ( vec_len [f] want )
    : i gn ( vec_len [f] got )
    ? != n gn {
        ( nurl_print `  FAIL ` ) ( nurl_print label )
        ( nurl_print ` — length ` ) ( nurl_print_int gn )
        ( nurl_print ` but the reference has ` ) ( nurl_print_int n )
        ( nurl_print `\n` )
        = g_fail + g_fail 1
        ^ v
    } {}
    : ~ f md 0.0
    : ~ f mx 1.0e-12
    : ~ i k 0
    ~ < k n {
        : f w ( __d_get want k )
        : f d ( fabs - ( __d_get got k ) w )
        ? > d md { = md d } {}
        ? > ( fabs w ) mx { = mx ( fabs w ) } {}
        = k + k 1
    }
    : f rel / md mx
    : String m ( string_from label )
    ( string_push_str m `  max |Δ| ` )
    ( string_push_float m md )
    ( string_push_str m `  relative ` )
    ( string_push_float m rel )
    ( __d_check < rel tol ( string_data m ) )
    ( string_free m )
}

@ main → i {
    ? < ( nurl_argv_count ) 4 {
        ( nurl_eprintln `usage: dit_test <checkpoint.safetensors> <vocab.txt> <refdir>` )
        ^ 2
    } {}
    : s ckpt ( nurl_argv_get 1 )
    : s vocab ( nurl_argv_get 2 )
    : s dir ( nurl_argv_get 3 )

    : ( Vec i ) ids ( __d_read_i32 dir `text_ids.i32` )
    : ( Vec f ) xin ( __d_read_f32 dir `x.f32` )
    : ( Vec f ) condin ( __d_read_f32 dir `cond.f32` )
    : ( Vec f ) tin ( __d_read_f32 dir `t.f32` )
    : ( Vec f ) want_txt ( __d_read_f32 dir `text_embed.f32` )
    : ( Vec f ) want_out ( __d_read_f32 dir `out.f32` )
    : i n / ( vec_len [f] xin ) 100
    ? > n 0 {} { ( nurl_eprintln `dit_test: the reference dump is empty` ) ^ 1 }

    ?? ( f5_open ckpt vocab -1 ) {
        T m → {
            ( nurl_print `model — vocab ` )
            ( nurl_print_int ( f5_vocab_n m ) )
            ( nurl_print `, n ` )
            ( nurl_print_int n )
            ( nurl_print `, text ` )
            ( nurl_print_int ( vec_len [i] ids ) )
            ( nurl_print ` characters\n` )

            ? ( f5_alloc m n 1 ) {} {
                ( nurl_eprintln `dit_test: cannot allocate the forward's buffers` )
                ( f5_close m )
                ^ 1
            }
            ? ( f5_rope m ) {} { ( nurl_eprintln `rope tables failed` ) ( f5_close m ) ^ 1 }
            ? ( f5_text_encode m ids F 0 ) {} {
                ( nurl_eprintln `text encoder failed` ) ( f5_close m ) ^ 1
            }
            : ( Vec f ) got_txt ( vec_with_cap [f] * n 512 )
            ( f5_download m ( f5_buf_txt m ) got_txt * n 512 )
            ( __d_cmp got_txt want_txt `text encoder (4 ConvNeXt blocks)` 2.0e-5 )

            ? ( f5_set_x m xin ) {} { ( nurl_eprintln `x upload failed` ) ( f5_close m ) ^ 1 }
            ? ( f5_set_cond m condin ) {} { ( nurl_eprintln `cond upload failed` ) ( f5_close m ) ^ 1 }
            ? ( f5_set_time m ( __d_get tin 0 ) ) {} {
                ( nurl_eprintln `timestep failed` ) ( f5_close m ) ^ 1
            }
            ? ( f5_forward m ) {} { ( nurl_eprintln `forward failed` ) ( f5_close m ) ^ 1 }
            : ( Vec f ) got_out ( vec_with_cap [f] * n 100 )
            ( f5_download m ( f5_buf_pred m ) got_out * n 100 )
            ( __d_cmp got_out want_out `the whole forward (22 blocks)` 1.0e-4 )

            ( vec_free [f] got_txt )
            ( vec_free [f] got_out )
            ( f5_close m )
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ^ 1
        }
    }
    ( vec_free [i] ids )
    ( vec_free [f] xin )
    ( vec_free [f] condin )
    ( vec_free [f] tin )
    ( vec_free [f] want_txt )
    ( vec_free [f] want_out )

    ( nurl_print `\npassed ` )
    ( nurl_print_int g_pass )
    ( nurl_print `, failed ` )
    ( nurl_print_int g_fail )
    ( nurl_print `\n` )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
