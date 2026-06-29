// packages/wasmtime/tests/float_test.nu — offline tests for f32/f64 ops and
// int↔float conversions. Args/results are passed as IEEE-754 bit patterns
// (via std/floatbits) so checks are exact; the expected bit constants are
// cross-checked against struct.pack and the reference wasmtime.
//   NURL_STDLIB=<repo> ../../nurl.sh tests/float_test.nu /tmp/ft && /tmp/ft

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `src/module.nu`
$ `src/interp.nu`

@ wasm_fadd → s { ^ `0061736d0100000001070160027c7c017c03020100070801046661646400000a0901070020002001a00b` }

@ wasm_fmul → s { ^ `0061736d0100000001070160027c7c017c0302010007080104666d756c00000a0901070020002001a20b` }

@ wasm_fsqrt → s { ^ `0061736d0100000001060160017c017c0302010007090105667371727400000a0701050020009f0b` }

@ wasm_f2i → s { ^ `0061736d0100000001060160017c017f030201000707010366326900000a070105002000aa0b` }

@ wasm_i2f → s { ^ `0061736d0100000001060160017f017c030201000707010369326600000a070105002000b70b` }

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
                    ? ! . it trap {
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

@ run1 s hex s export i x → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x ) : i r ( ev hex export a ) ( vec_free [i] a ) ^ r
}

@ run2 s hex s export i x i y → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x ) ( vec_push [i] a y ) : i r ( ev hex export a ) ( vec_free [i] a ) ^ r
}

@ pi s label i a i b → v {
    ( nurl_print label ) ( nurl_print_int a )
    ( nurl_print ? == a b ` == ` ` != ` ) ( nurl_print_int b ) ( nurl_print `\n` )
}

@ main → i {
    // bit patterns: 1.5, 2.25, 3.75, 3.375, 2.0, sqrt2, 7.9, 7.0
    // f64.add(1.5, 2.25) → 3.75
    ( pi `fadd 1.5+2.25:  ` ( run2 ( wasm_fadd ) `fadd` 4609434218613702656 4612248968380809216 ) 4615626668101337088 )
    // f64.mul(1.5, 2.25) → 3.375
    ( pi `fmul 1.5*2.25:  ` ( run2 ( wasm_fmul ) `fmul` 4609434218613702656 4612248968380809216 ) 4614782243171205120 )
    // f64.sqrt(2.0) → 1.41421356…
    ( pi `fsqrt 2.0:      ` ( run1 ( wasm_fsqrt ) `fsqrt` 4611686018427387904 ) 4609047870845172685 )
    // i32.trunc_f64_s(7.9) → 7
    ( pi `f2i 7.9:        ` ( run1 ( wasm_f2i ) `f2i` 4620580627691444634 ) 7 )
    // f64.convert_i32_s(7) → 7.0
    ( pi `i2f 7:          ` ( run1 ( wasm_i2f ) `i2f` 7 ) 4619567317775286272 )
    ^ 0
}
