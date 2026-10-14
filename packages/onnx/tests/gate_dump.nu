// packages/onnx/tests/gate_dump.nu — the byte-identity gate's dump tool.
//
// Runs a model on a DETERMINISTIC input and writes the raw output bytes to
// a file. Run once with the old executor to capture references, then after
// every migration step and `cmp` — any byte diff means the step changed
// numerics and must be root-caused. (dev tool; models are not committed)
//
//   gate_dump img <model> <d0> <d1> <d2> <d3> <out0.bin> [<out1.bin>]
//       f32 input of shape (d0,d1,d2,d3), values (k·37 mod 256)/255
//   gate_dump tok <model> <tokens.i64> <nrow> <ncol> <out0.bin>
//       INT64 token matrix read from file, uploaded as-is
//   gate_dump two <model> <d0..d3> <tpe.f32> <K> <out0.bin> [<out1.bin>]
//       images (d0..d3, synthetic as in img) + `tpe` (1,K,512) from file

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `src/pb.nu`
$ `src/model.nu`
$ `src/runtime.nu`

$ `stdlib/std/floatbits.nu`

@ args i k → String {
    : ( Vec String ) av ( env_args_list )
    ^ ?? ( vec_get [String] av k ) { T x → x F _ → ( string_new ) }
}

@ argi i k i dflt → i {
    : ( Vec String ) av ( env_args_list )
    ^ ?? ( vec_get [String] av k ) { T x → ( nurl_str_to_int ( string_data x ) ) F _ → dflt }
}

@ synth i n → ( Vec u ) {
    : ( Vec u ) hb ( vec_zeroed [u] * n 4 )
    : ( Slice u ) h ( slice_from_vec [u] hb )
    : ~ i k 0
    ~ < k n {
        : f v / # f % * k 37 256 255.0
        ( slice_put_u32_le h * k 4 ( f32_to_bits # f32 v ) )
        = k + k 1
    }
    ^ hb
}

// A whole file's bytes (at least one, so its address is a real one).
@ load_bytes s path → ( Vec u ) {
    ?? ( read_file_bytes path ) {
        T bytes → {
            ? == ( vec_len [u] bytes ) 0 { ( vec_push [u] bytes # u 0 ) } {}
            ^ bytes
        }
        F _ → { ^ ( vec_zeroed [u] 1 ) }
    }
}

@ dump_out Engine e RTensor t s path → i {
    ? > . t nelem 0 {} { ( nurl_print `EMPTY output\n` ) ^ 1 }
    : GpuHost host ( rt_download e t )
    : i nb * . t nelem 4
    : ( Vec u ) out ( slice_to_vec [u] ( slice_window [u] ( gpu_host_u8 host ) 0 nb ) )
    : ~ i rc 0
    ?? ( write_file_bytes path out ) { T _ → {} F _ → { = rc 1 } }
    ( nurl_print path ) ( nurl_print ` ` )
    ( nurl_print ( nurl_str_int . t nelem ) ) ( nurl_print ` floats\n` )
    ^ rc
}

@ shape4g i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d )
    ^ v
}

@ shape3g i a i b i c → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c )
    ^ v
}

@ main → i {
    : String mode ( args 1 )
    : String mp ( args 2 )
    : ~ OGraph g ( onnx_empty_graph )
    ?? ( read_file_bytes ( string_data mp ) ) {
        T mb → { = g ( onnx_parse mb ) }
        F _ → { ( nurl_print `model read fail\n` ) ^ 1 }
    }
    : Engine e ( rt_open 0 )
    ? ( rt_ok e ) {} { ( nurl_print `no device\n` ) ^ 1 }
    : ~ i rc 0
    ? ( nurl_str_eq ( string_data mode ) `img` ) {
        : i d0 ( argi 3 1 )
        : i d1 ( argi 4 3 )
        : i d2 ( argi 5 640 )
        : i d3 ( argi 6 640 )
        : i n * * * d0 d1 d2 d3
        : ( Vec u ) input__b ( synth n )
        : ( Slice u ) input ( slice_from_vec [u] input__b )
        : RTensor out ( rt_run_shaped e g input ( shape4g d0 d1 d2 d3 ) )
        = rc ( dump_out e out ( string_data ( args 7 ) ) )
        : String o1 ( args 8 )
        ? > ( nurl_str_len ( string_data o1 ) ) 0 {
            : RTensor out1 ( rt_output1 e )
            = rc + rc ( dump_out e out1 ( string_data o1 ) )
        } {}
    } {
        ? ( nurl_str_eq ( string_data mode ) `tok` ) {
            : ( Vec u ) tok__b ( load_bytes ( string_data ( args 3 ) ) )
            : ( Slice u ) tok ( slice_from_vec [u] tok__b )
            : i nrow ( argi 4 3 )
            : i ncol ( argi 5 77 )
            : RTensor out ( rt_run_tokens e g tok nrow ncol )
            = rc ( dump_out e out ( string_data ( args 6 ) ) )
        } {
            ? ( nurl_str_eq ( string_data mode ) `two` ) {
                : i d0 ( argi 3 1 )
                : i d1 ( argi 4 3 )
                : i d2 ( argi 5 640 )
                : i d3 ( argi 6 640 )
                : i n * * * d0 d1 d2 d3
                : ( Vec u ) img__b ( synth n )
                : ( Slice u ) img ( slice_from_vec [u] img__b )
                : ( Vec u ) tpe__b ( load_bytes ( string_data ( args 7 ) ) )
                : ( Slice u ) tpe ( slice_from_vec [u] tpe__b )
                : i kk ( argi 8 32 )
                : RTensor out ( rt_run_two e g `images` img ( shape4g d0 d1 d2 d3 ) `tpe` tpe ( shape3g 1 kk 512 ) )
                = rc ( dump_out e out ( string_data ( args 9 ) ) )
                : String o1 ( args 10 )
                ? > ( nurl_str_len ( string_data o1 ) ) 0 {
                    : RTensor out1 ( rt_output1 e )
                    = rc + rc ( dump_out e out1 ( string_data o1 ) )
                } {}
            } {
                ? ( nurl_str_eq ( string_data mode ) `imgf` ) {
                    // imgf <model> <in.f32.bin> <d0..d3> <out.bin> — a real
                    // input from a file, for oracle comparisons.
                    : ( Vec u ) input__b ( load_bytes ( string_data ( args 3 ) ) )
                    : ( Slice u ) input ( slice_from_vec [u] input__b )
                    : i d0 ( argi 4 1 )
                    : i d1 ( argi 5 3 )
                    : i d2 ( argi 6 320 )
                    : i d3 ( argi 7 320 )
                    : RTensor out ( rt_run_shaped e g input ( shape4g d0 d1 d2 d3 ) )
                    = rc ( dump_out e out ( string_data ( args 8 ) ) )
                } { ( nurl_print `usage: gate_dump img|imgf|tok|two ...\n` ) = rc 2 }
            }
        }
    }
    ^ rc
}
