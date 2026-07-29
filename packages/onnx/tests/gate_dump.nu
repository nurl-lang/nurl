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

& `c` @ nurl_poke_f32 *u base i idx f val → v

& `c` @ nurl_peek_i32 *u base i idx → i32

& `c` @ nurl_poke_i32 *u base i idx i32 val → v

@ args i k → String {
    : ( Vec String ) av ( env_args_list )
    ^ ?? ( vec_get [String] av k ) { T x → x F _ → ( string_new ) }
}

@ argi i k i dflt → i {
    : ( Vec String ) av ( env_args_list )
    ^ ?? ( vec_get [String] av k ) { T x → ( nurl_str_to_int ( string_data x ) ) F _ → dflt }
}

@ synth i n → *u {
    : *u h ( nurl_alloc * n 4 )
    : ~ i k 0
    ~ < k n {
        : f v / # f % * k 37 256 255.0
        ( nurl_poke_f32 h k v )
        = k + k 1
    }
    ^ h
}

// Read a whole file into a fresh malloc'd buffer (caller frees).
@ load_bytes s path * u pcell → *u {
    ?? ( read_file_bytes path ) {
        T bytes → {
            : i n ( vec_len [u] bytes )
            : *u host ( nurl_alloc ? > n 0 { n } { 1 } )
            : *u src ( vec_data [u] bytes )
            : ~ i k 0
            ~ < k / n 4 {
                ( nurl_poke_i32 host k ( nurl_peek_i32 src k ) )
                = k + k 1
            }
            ( vec_free [u] bytes )
            ( nurl_poke pcell 0 n )
            ^ host
        }
        F _ → { ( nurl_poke pcell 0 0 ) ^ # *u 0 }
    }
}

@ dump_out * Engine e RTensor t s path → i {
    ? > . t nelem 0 {} { ( nurl_print `EMPTY output\n` ) ^ 1 }
    : *u host ( rt_download e t )
    : i nb * . t nelem 4
    : ( Vec u ) out ( vec_with_cap [u] nb )
    : *u dst ( vec_data [u] out )
    : ~ i k 0
    ~ < k . t nelem { ( nurl_poke_i32 dst k ( nurl_peek_i32 host k ) ) = k + k 1 }
    : b _lok ( vec_set_len [u] out nb )
    : ~ i rc 0
    ?? ( write_file_bytes path out ) { T _ → {} F _ → { = rc 1 } }
    ( vec_free [u] out )
    ( nurl_free host )
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
    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes ( string_data mp ) ) {
        T mb → { = g ( onnx_parse mb ) }
        F _ → { ( nurl_print `model read fail\n` ) ^ 1 }
    }
    : *Engine e ( rt_open 0 )
    ? ( rt_ok e ) {} { ( nurl_print `no device\n` ) ^ 1 }
    : ~ i rc 0
    ? ( nurl_str_eq ( string_data mode ) `img` ) {
        : i d0 ( argi 3 1 )
        : i d1 ( argi 4 3 )
        : i d2 ( argi 5 640 )
        : i d3 ( argi 6 640 )
        : i n * * * d0 d1 d2 d3
        : *u input ( synth n )
        : RTensor out ( rt_run_shaped e g input ( shape4g d0 d1 d2 d3 ) )
        = rc ( dump_out e out ( string_data ( args 7 ) ) )
        : String o1 ( args 8 )
        ? > ( nurl_str_len ( string_data o1 ) ) 0 {
            : RTensor out1 ( rt_output1 e )
            = rc + rc ( dump_out e out1 ( string_data o1 ) )
        } {}
        ( nurl_free input )
    } {
        ? ( nurl_str_eq ( string_data mode ) `tok` ) {
            : *u pc ( nurl_alloc 8 )
            : *u tok ( load_bytes ( string_data ( args 3 ) ) pc )
            ( nurl_free pc )
            : i nrow ( argi 4 3 )
            : i ncol ( argi 5 77 )
            : RTensor out ( rt_run_tokens e g tok nrow ncol )
            = rc ( dump_out e out ( string_data ( args 6 ) ) )
            ( nurl_free tok )
        } {
            ? ( nurl_str_eq ( string_data mode ) `two` ) {
                : i d0 ( argi 3 1 )
                : i d1 ( argi 4 3 )
                : i d2 ( argi 5 640 )
                : i d3 ( argi 6 640 )
                : i n * * * d0 d1 d2 d3
                : *u img ( synth n )
                : *u pc ( nurl_alloc 8 )
                : *u tpe ( load_bytes ( string_data ( args 7 ) ) pc )
                ( nurl_free pc )
                : i kk ( argi 8 32 )
                : RTensor out ( rt_run_two e g `images` img ( shape4g d0 d1 d2 d3 ) `tpe` tpe ( shape3g 1 kk 512 ) )
                = rc ( dump_out e out ( string_data ( args 9 ) ) )
                : String o1 ( args 10 )
                ? > ( nurl_str_len ( string_data o1 ) ) 0 {
                    : RTensor out1 ( rt_output1 e )
                    = rc + rc ( dump_out e out1 ( string_data o1 ) )
                } {}
                ( nurl_free img )
                ( nurl_free tpe )
            } {
                ? ( nurl_str_eq ( string_data mode ) `imgf` ) {
                    // imgf <model> <in.f32.bin> <d0..d3> <out.bin> — a real
                    // input from a file, for oracle comparisons.
                    : *u pc ( nurl_alloc 8 )
                    : *u input ( load_bytes ( string_data ( args 3 ) ) pc )
                    ( nurl_free pc )
                    : i d0 ( argi 4 1 )
                    : i d1 ( argi 5 3 )
                    : i d2 ( argi 6 320 )
                    : i d3 ( argi 7 320 )
                    : RTensor out ( rt_run_shaped e g input ( shape4g d0 d1 d2 d3 ) )
                    = rc ( dump_out e out ( string_data ( args 8 ) ) )
                    ( nurl_free input )
                } { ( nurl_print `usage: gate_dump img|imgf|tok|two ...\n` ) = rc 2 }
            }
        }
    }
    ( rt_close e )
    ^ rc
}
