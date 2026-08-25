// packages/nwasm/tests/mem_test.nu — offline tests for linear memory:
// load/store round-trips, sized byte access, the data section, and memory.size.
// Hand-encoded modules, expected results cross-checked against real wasmtime.
//   NURL_STDLIB=<repo> ../../nurl.sh tests/mem_test.nu /tmp/mt && /tmp/mt

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `src/module.nu`
$ `src/interp.nu`

// roundtrip(i32)->i32 { i32.store(0,v); i32.load(0) }
@ wasm_round → s { ^ `0061736d0100000001060160017f017f030201000503010001070d0109726f756e647472697000000a10010e004100200036020041002802000b` }
// sumdata()->i32 { data [1..5]@0 ; Σ load8_u }
@ wasm_data → s { ^ `0061736d010000000105016000017f030201000503010001070b010773756d6461746100000a21011f0041002d000041002d00016a41002d00026a41002d00036a41002d00046a0b0b0b010041000b050102030405` }
// bytepoke(i32)->i32 { i32.store8(5,v); i32.load8_u(5) }  → v & 255
@ wasm_poke → s { ^ `0061736d0100000001060160017f017f030201000503010001070c010862797465706f6b6500000a10010e00410520003a000041052d00000b` }
// memsize()->i32 { memory.size }  (min 3 pages)
@ wasm_msize → s { ^ `0061736d010000000105016000017f030201000503010003070b01076d656d73697a6500000a060104003f000b` }

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

@ run1 s hex s export i x → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x ) : i r ( ev hex export a ) ( vec_free [i] a ) ^ r
}

@ pi s label i a i b → v {
    ( nurl_print label ) ( nurl_print_int a )
    ( nurl_print ? == a b ` == ` ` != ` ) ( nurl_print_int b ) ( nurl_print `\n` )
}

@ main → i {
    // Mirror the CLI's engine-mode switches so the suite exercises the
    // same tier the user runs: JIT on by default, NURL_NWASM_JIT=0 keeps
    // the pure interpreter, PIN=0 unpins, GUARD=0 keeps bounds checks.
    ?? ( env_get `NURL_NWASM_JIT` ) { T jv → { ? == 0 ( nurl_str_eq ( string_data jv ) `0` ) { ( interp_enable_jit ) } {} ( string_free jv ) } F → { ( interp_enable_jit ) } }
    ?? ( env_get `NURL_NWASM_PIN` ) { T pv → { ? != 0 ( nurl_str_eq ( string_data pv ) `0` ) { ( interp_disable_pin ) } {} ( string_free pv ) } F → {} }
    ?? ( env_get `NURL_NWASM_GUARD` ) { T gv → { ? != 0 ( nurl_str_eq ( string_data gv ) `0` ) { ( interp_disable_guard ) } {} ( string_free gv ) } F → {} }
    ( pi `roundtrip 1234:  ` ( run1 ( wasm_round ) `roundtrip` 1234 ) 1234 )
    ( pi `roundtrip 0:     ` ( run1 ( wasm_round ) `roundtrip` 0 ) 0 )
    ( pi `roundtrip -5:    ` ( run1 ( wasm_round ) `roundtrip` -5 ) -5 )
    ( pi `sumdata:         ` ( run0 ( wasm_data ) `sumdata` ) 15 )
    ( pi `bytepoke 700:    ` ( run1 ( wasm_poke ) `bytepoke` 700 ) 188 )
    ( pi `bytepoke 65:     ` ( run1 ( wasm_poke ) `bytepoke` 65 ) 65 )
    ( pi `memsize:         ` ( run0 ( wasm_msize ) `memsize` ) 3 )
    ^ 0
}
