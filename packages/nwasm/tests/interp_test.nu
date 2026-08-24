// packages/nwasm/tests/interp_test.nu — offline tests for the decoder +
// interpreter, against hand-encoded modules whose results are cross-checked
// against the real wasmtime. Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/interp_test.nu /tmp/it && /tmp/it

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `src/module.nu`
$ `src/interp.nu`

// add(i32,i32)->i32 { a+b }
@ wasm_add → s { ^ `0061736d0100000001070160027f7f017f030201000707010361646400000a09010700200020016a0b` }
// sumto(i64)->i64 { Σ 1..n }  (block/loop/br_if + i64 ops)
@ wasm_sum → s { ^ `0061736d0100000001060160017e017e030201000709010573756d746f00000a2d012b01027e42002101420121020240034020022000550d01200120027c2101200242017c21020c000b0b20010b` }
// max(i32,i32)->i32 { a>b ? a : b }  (if/else with result)
@ wasm_max → s { ^ `0061736d0100000001070160027f7f017f03020100070701036d617800000a11010f00200020014a047f20000520010b0b` }

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

@ run1 s hex s export i a → i {
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args a )
    : i r ( ev hex export args )
    ( vec_free [i] args )
    ^ r
}

@ run2 s hex s export i a i b → i {
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args a ) ( vec_push [i] args b )
    : i r ( ev hex export args )
    ( vec_free [i] args )
    ^ r
}

@ pi s label i a i b → v {
    ( nurl_print label ) ( nurl_print_int a )
    ( nurl_print ? == a b ` == ` ` != ` ) ( nurl_print_int b ) ( nurl_print `\n` )
}

@ main → i {
    // add: locals + i32.add + call frame
    ( pi `add 2 3:       ` ( run2 ( wasm_add ) `add` 2 3 ) 5 )
    ( pi `add 40 2:      ` ( run2 ( wasm_add ) `add` 40 2 ) 42 )
    ( pi `add -1 1:      ` ( run2 ( wasm_add ) `add` -1 1 ) 0 )
    // sumto: block/loop/br_if + i64 arithmetic + locals
    ( pi `sumto 1:       ` ( run1 ( wasm_sum ) `sumto` 1 ) 1 )
    ( pi `sumto 100:     ` ( run1 ( wasm_sum ) `sumto` 100 ) 5050 )
    ( pi `sumto 1000:    ` ( run1 ( wasm_sum ) `sumto` 1000 ) 500500 )
    ( pi `sumto 100000:  ` ( run1 ( wasm_sum ) `sumto` 100000 ) 5000050000 )
    // max: if/else with a result type + i32.gt_s
    ( pi `max 7 3:       ` ( run2 ( wasm_max ) `max` 7 3 ) 7 )
    ( pi `max 3 9:       ` ( run2 ( wasm_max ) `max` 3 9 ) 9 )
    ( pi `max 5 5:       ` ( run2 ( wasm_max ) `max` 5 5 ) 5 )
    ^ 0
}
