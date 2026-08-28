// packages/nwasm/tests/table_test.nu — offline tests for globals and
// call_indirect (tables + element segments). Hand-encoded modules, expected
// results cross-checked against the reference wasmtime.
//   NURL_STDLIB=<repo> ../../nurl.sh tests/table_test.nu /tmp/tt && /tmp/tt

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `src/module.nu`
$ `src/interp.nu`

// bump()->i32 : mutable global g=10; g+=1; return g
@ wasm_bump → s { ^ `0061736d010000000105016000017f030201000606017f01410a0b0708010462756d7000000a0d010b00230041016a240023000b` }
// dispatch(sel,a,b)->i32 : table[sel](a,b); table=[add,sub]  (call_indirect)
@ wasm_disp → s { ^ `0061736d01000000010e0260027f7f017f60037f7f7f017f030403000001040401700002070c0108646973706174636800020908010041000b0200010a1d030700200020016a0b0700200020016b0b0b002001200220001100000b` }

@ ev s hex s export ( Vec i ) args → i {
    : !( Vec u ) ParseErr dr ( bytes_from_hex hex )
    : ~ i r -999999
    ?? dr {
        T bytes → {
            : *Module m ( module_decode bytes )
            ? . m ok {
                : i fidx ( module_export_func m export )
                ? >= fidx 0 {
                    : *Interp it ( interp_new m )
                    : i na ( vec_len [i] args )
                    : ~ i k 0
                    ~ < k na { ( vec_push [i] . it vs ?? ( vec_get [i] args k ) { T x → x F → 0 } ) = k + k 1 }
                    ( exec_func it fidx )
                    ? ! ( interp_trapped it ) {
                        : i n ( vec_len [i] . it vs )
                        ? > n 0 { = r ?? ( vec_get [i] . it vs - n 1 ) { T x → x F → 0 } } {}
                    } {}
                    ( interp_free it )
                } {}
            } {}
            ( module_free m )
        }
        F → {}
    }
    ^ r
}

@ run0 s hex s export → i {
    : ( Vec i ) a ( vec_new [i] ) : i r ( ev hex export a ) ( vec_free [i] a ) ^ r
}

@ run3 s hex s export i x i y i z → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a x ) ( vec_push [i] a y ) ( vec_push [i] a z )
    : i r ( ev hex export a ) ( vec_free [i] a ) ^ r
}

@ pi s label i a i b → v {
    ( nurl_print label ) ( nurl_println_int a )
    ( nurl_print ? == a b ` == ` ` != ` ) ( nurl_println_int b )
}

@ main → i {
    // Mirror the CLI's engine-mode switches so the suite exercises the
    // same tier the user runs: JIT on by default, NURL_NWASM_JIT=0 keeps
    // the pure interpreter, PIN=0 unpins, GUARD=0 keeps bounds checks.
    ?? ( env_get `NURL_NWASM_JIT` ) { T jv → { ? == 0 ( nurl_str_eq ( string_data jv ) `0` ) { ( interp_enable_jit ) } {} ( string_free jv ) } F → { ( interp_enable_jit ) } }
    ?? ( env_get `NURL_NWASM_PIN` ) { T pv → { ? != 0 ( nurl_str_eq ( string_data pv ) `0` ) { ( interp_disable_pin ) } {} ( string_free pv ) } F → {} }
    ?? ( env_get `NURL_NWASM_GUARD` ) { T gv → { ? != 0 ( nurl_str_eq ( string_data gv ) `0` ) { ( interp_disable_guard ) } {} ( string_free gv ) } F → {} }
    // global.get / global.set + const init
    ( pi `bump:           ` ( run0 ( wasm_bump ) `bump` ) 11 )
    // call_indirect through the table: table[0]=add, table[1]=sub
    ( pi `dispatch 0 7 3:  ` ( run3 ( wasm_disp ) `dispatch` 0 7 3 ) 10 )
    ( pi `dispatch 1 7 3:  ` ( run3 ( wasm_disp ) `dispatch` 1 7 3 ) 4 )
    ( pi `dispatch 0 20 5: ` ( run3 ( wasm_disp ) `dispatch` 0 20 5 ) 25 )
    ( pi `dispatch 1 20 5: ` ( run3 ( wasm_disp ) `dispatch` 1 20 5 ) 15 )
    ^ 0
}
