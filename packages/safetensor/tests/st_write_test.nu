// st_write_test.nu — the writer's round-trip gate: build a multi-tensor,
// multi-dtype file in memory, parse it back with the reader, and check the
// tensor set, shapes, dtypes, and (bit-exactly for F32/I64) the values. The
// cross-implementation check against the reference `safetensors` Python
// library lives in st_write_oracle.sh.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/st_write_test.nu /tmp/stw && /tmp/stw

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/floatbits.nu`
$ `src/safetensor.nu`
$ `src/write.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label ) ( nurl_print `\n` )
}

@ gf ( Vec f ) v i k → f { ?? ( vec_get [f] v k ) { T x → x F → 0.0 } }

@ shp i a i b → ( Vec i ) {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s a )
    ? > b 0 { ( vec_push [i] s b ) } {}
    ^ s
}

// dtype + shape of a parsed tensor by name
@ tinfo * St s s name * u dt * u nd * u d0 * u d1 * u ne → b {
    : i idx ( st_find_tensor s name )
    ? >= idx 0 {} { ^ F }
    ?? ( vec_get [StTensor] . s tensors idx ) {
        T t → {
            ( nurl_poke dt 0 . t dtype )
            ( nurl_poke nd 0 . t nd )
            ( nurl_poke d0 0 . t d0 )
            ( nurl_poke d1 0 . t d1 )
            ( nurl_poke ne 0 . t nelems )
            ^ T
        }
        F → { ^ F }
    }
    ^ F
}

@ main → i {
    // build a file with F32 [2,3], F64 [4], I64 [2,2]
    : *StWriter w ( stw_new )
    : ( Vec f ) af ( vec_new [f] )
    : ~ i k 0
    ~ < k 6 { ( vec_push [f] af * 0.5 - # f k 2.5 ) = k + k 1 }
    : ( Vec i ) s1 ( shp 2 3 )
    ( stw_add_f32 w `wf32` s1 af )
    : ( Vec f ) bf ( vec_new [f] )
    ( vec_push [f] bf 3.141592653589793 ) ( vec_push [f] bf -2.0 )
    ( vec_push [f] bf 0.000000001 ) ( vec_push [f] bf 42.0 )
    : ( Vec i ) s2 ( shp 4 0 )
    ( stw_add_f64 w `wf64` s2 bf )
    : ( Vec i ) iv ( vec_new [i] )
    ( vec_push [i] iv 7 ) ( vec_push [i] iv -3 ) ( vec_push [i] iv 1000000 ) ( vec_push [i] iv 0 )
    : ( Vec i ) s3 ( shp 2 2 )
    ( stw_add_i64 w `wi64` s3 iv )
    : ( Vec u ) bytes ( stw_finish w )
    ( check > ( vec_len [u] bytes ) 8 `file has content` )

    // parse it back
    ?? ( st_parse_bytes bytes ) {
        T st → {
            ( check == ( st_n_tensors st ) 3 `3 tensors round-trip` )
            : *u dt ( nurl_alloc 8 )
            : *u nd ( nurl_alloc 8 )
            : *u d0 ( nurl_alloc 8 )
            : *u d1 ( nurl_alloc 8 )
            : *u ne ( nurl_alloc 8 )
            // F32
            ( check ( tinfo st `wf32` dt nd d0 d1 ne ) `wf32 present` )
            ( check & & & == ( nurl_peek dt 0 ) ST_F32 == ( nurl_peek nd 0 ) 2 == ( nurl_peek d0 0 ) 2 == ( nurl_peek d1 0 ) 3 `wf32 dtype/shape [2,3] F32` )
            // dequant → f32 bytes, compare bit-exact to our own f32 encoding
            ?? ( st_dequant st ( st_find_tensor st `wf32` ) ) {
                T got → {
                    : ( Vec u ) want ( vec_new [u] )
                    = k 0
                    ~ < k 6 { ( bytes_push_f32_le want # f32 ( gf af k ) ) = k + k 1 }
                    : ~ b eq == ( vec_len [u] got ) ( vec_len [u] want )
                    : ~ i b 0
                    ~ & < b ( vec_len [u] want ) eq {
                        ? == ?? ( vec_get [u] got b ) { T x → x F → # u 0 } ?? ( vec_get [u] want b ) { T x → x F → # u 1 } {} { = eq F }
                        = b + b 1
                    }
                    ( check eq `wf32 values bit-exact through st_dequant` )
                    ( vec_free [u] got ) ( vec_free [u] want )
                }
                F e → { ( check F `wf32 dequant` ) ( string_free e ) }
            }
            // F64
            ( check ( tinfo st `wf64` dt nd d0 d1 ne ) `wf64 present` )
            ( check & & == ( nurl_peek dt 0 ) ST_F64 == ( nurl_peek nd 0 ) 1 == ( nurl_peek d0 0 ) 4 `wf64 dtype/shape [4] F64` )
            // I64
            ( check ( tinfo st `wi64` dt nd d0 d1 ne ) `wi64 present` )
            ( check & & & == ( nurl_peek dt 0 ) ST_I64 == ( nurl_peek nd 0 ) 2 == ( nurl_peek d0 0 ) 2 == ( nurl_peek ne 0 ) 4 `wi64 dtype/shape [2,2] I64` )
            ( nurl_free dt ) ( nurl_free nd ) ( nurl_free d0 ) ( nurl_free d1 ) ( nurl_free ne )
            ( st_close st )
        }
        F e → {
            ( nurl_print `PARSE FAILED: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ( string_free e )
            = g_fail + g_fail 1
        }
    }
    ( vec_free [u] bytes )
    ( stw_free w )
    ( vec_free [f] af ) ( vec_free [f] bf ) ( vec_free [i] iv )
    ( nurl_print `st_write_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
