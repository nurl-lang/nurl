// packages/nwasm/tests/atomics_test.nu — the threads proposal's 0xfe
// atomics, hand-authored in WAT and assembled with wasm-tools. Covers the
// shared-memory declaration, atomic load/store, every read-modify-write
// group at every width, cmpxchg (taken and not), wait/notify's three
// answers, atomic.fence, and the two traps an atomic has of its own
// (unaligned, out of bounds).
//
// The expected values are derived from the spec and checked by hand —
// binaryen's wasm-shell cannot parse a shared memory, so unlike
// semantics_test these are not cross-checked against another runtime.
// What each one asserts is written next to it.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/atomics_test.nu /tmp/at && /tmp/at

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `src/module.nu`
$ `src/interp.nu`

// (memory 1 1 shared) + one export per case; see the WAT in the PR.
@ wasm_atomics → s { ^ `0061736d010000000109026000017f6000017e030f0e0000000000010000000000000000050401030101077e0e076164646c6f61640000066361737365710001066361736f6c640002066e6172726f770003096e6172726f776f6c6400040477696465000505737562313600060478636867000706776169746e6500080677616974746f0009076e6f7469667930000a09756e616c69676e6564000b036f6f62000c0566656e6365000d0aa7020e1a0041004105fe1e02001a41004125fe1e02001a4100fe1002000b280041044107fe1702004104410641e400fe4802001a4104410741e400fe4802001a4104fe1002000b150041044107fe1702004104410741e400fe4802000b1d00410841c4e6888901fe1702004108410ffe2e00001a4108fe1002000b1600410841c4e6888901fe1702004108410ffe2e00000b2100411042888e98a8c0e0808101fe1803004110427ffe3b03001a4110fe1103000b1d004118418082b4de7afe17020041184101fe2801001a4118fe1002000b1200411c4105fe170200411c4109fe4102000b0c004120412a427ffe0102000b0e004120410042c0843dfe0102000b0a0041204101fe0002000b08004101fe1002000b0a0041808004fe1002000b0800fe030041e3000b` }

@ ev s hex s export b want_trap → i {
    : !( Vec u ) ParseErr dr ( bytes_from_hex hex )
    : ~ i r -999999
    ?? dr {
        T bytes → {
            : *Module m ( module_decode bytes )
            ? . m ok {
                : i fidx ( module_export_func m export )
                ? >= fidx 0 {
                    : *Interp it ( interp_new m )
                    ( interp_run_start it )
                    ( exec_func it fidx )
                    ? want_trap {
                        = r ? ( interp_trapped it ) 1 0
                    } {
                        ? ! ( interp_trapped it ) {
                            : i n ( vec_len [i] . it vs )
                            ? > n 0 { = r ?? ( vec_get [i] . it vs - n 1 ) { T x → x F → 0 } } {}
                        } {}
                    }
                    ( interp_free it )
                } {}
            } { ( nurl_print `decode failed: ` ) ( nurl_print ( string_data ( bytes_to_str . m err ) ) ) ( nurl_print `\n` ) }
            ( module_free m )
        }
        F → {}
    }
    ^ r
}

@ ev0 s export → i { ^ ( ev ( wasm_atomics ) export F ) }

@ trap0 s export → i { ^ ( ev ( wasm_atomics ) export T ) }

: ~ i g_fail 0

@ ck s label i got i want → v {
    ( nurl_print label ) ( nurl_print_int got )
    ? == got want { ( nurl_print ` == ` ) } { ( nurl_print ` != ` ) = g_fail + g_fail 1 }
    ( nurl_print_int want ) ( nurl_print `\n` )
}

@ main → i {
    // Mirror the CLI's engine-mode switches so the suite exercises the
    // same tier the user runs: JIT on by default, NURL_NWASM_JIT=0 keeps
    // the pure interpreter, PIN=0 unpins, GUARD=0 keeps bounds checks.
    ?? ( env_get `NURL_NWASM_JIT` ) { T jv → { ? == 0 ( nurl_str_eq ( string_data jv ) `0` ) { ( interp_enable_jit ) } {} ( string_free jv ) } F → { ( interp_enable_jit ) } }
    ?? ( env_get `NURL_NWASM_PIN` ) { T pv → { ? != 0 ( nurl_str_eq ( string_data pv ) `0` ) { ( interp_disable_pin ) } {} ( string_free pv ) } F → {} }
    ?? ( env_get `NURL_NWASM_GUARD` ) { T gv → { ? != 0 ( nurl_str_eq ( string_data gv ) `0` ) { ( interp_disable_guard ) } {} ( string_free gv ) } F → {} }
    // rmw.add twice into the same cell, then read it back
    ( ck `add 5+37:       ` ( ev0 `addload` ) 42 )
    // cmpxchg: the mismatching one leaves the cell, the matching one swaps
    ( ck `cmpxchg value:  ` ( ev0 `casseq` ) 100 )
    // …and it answers the OLD value either way
    ( ck `cmpxchg old:    ` ( ev0 `casold` ) 7 )
    // rmw8.and_u touches one byte of a word: 0x11223344 & ..0f → 0x11223304
    ( ck `rmw8 value:     ` ( ev0 `narrow` ) 287453956 )
    ( ck `rmw8 old:       ` ( ev0 `narrowold` ) 68 )
    // i64 rmw.xor with -1 flips every bit of 0x0102030405060708
    ( ck `i64 xor:        ` ( ev0 `wide` ) -72623859790382857 )
    // rmw16.sub_u borrows inside the low half only: 0x0100-1 → 0x00ff
    ( ck `rmw16 sub:      ` ( ev0 `sub16` ) 2882339071 )
    ( ck `xchg old:       ` ( ev0 `xchg` ) 5 )
    // wait's three answers: 1 = the value already differs, 2 = timed out,
    // and notify with no sleepers wakes nobody
    ( ck `wait mismatch:  ` ( ev0 `waitne` ) 1 )
    ( ck `wait timeout:   ` ( ev0 `waitto` ) 2 )
    ( ck `notify nobody:  ` ( ev0 `notify0` ) 0 )
    ( ck `fence:          ` ( ev0 `fence` ) 99 )
    // an atomic must be naturally aligned and in bounds — both trap
    ( ck `unaligned traps:` ( trap0 `unaligned` ) 1 )
    ( ck `oob traps:      ` ( trap0 `oob` ) 1 )

    ? == g_fail 0 { ( nurl_print `atomics: all checks passed\n` ) ^ 0 } {}
    ( nurl_print `atomics: ` ) ( nurl_print_int g_fail ) ( nurl_print ` FAILED\n` )
    ^ 1
}
