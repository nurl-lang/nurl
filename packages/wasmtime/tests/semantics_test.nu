// packages/wasmtime/tests/semantics_test.nu — spec-semantics edge cases,
// hand-authored in WAT, compiled with wasm-tools, and cross-checked against
// the reference wasmtime (every expected value below was produced by it).
// Covers: multi-value blocks/branches, integer div/rem traps, trapping and
// saturating float→int truncation, unsigned i64 conversions, NaN-correct
// comparisons and min/max, call_indirect signature checks, table.* ops,
// passive segments + memory.init/data.drop, memory.grow limits, and the
// start section. Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/semantics_test.nu /tmp/st && /tmp/st

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `src/module.nu`
$ `src/interp.nu`

// (module (func mvblock: block(→i32 i32) 3 4 end; add)
//         (func mvloop(n): Σ 1..n) (func mvbr: br out of 2-result block))
@ wasm_mv → s { ^ `0061736d01000000010f036000027f7f6000017f60017f017f030403010201071b03076d76626c6f636b0000066d766c6f6f700001046d76627200020a40030a000200410341040b6a0b2501027f20002102024003402002450d01200120026a2101200241016b21020c000b0b20010b0d000200410a41140c00000b6a0b0026046e616d65020b0101020103616363020169030b01010200036f757401016c04050100027032` }

// div/rem/trunc/convert/NaN edge-case module (see the WAT in the test's
// authoring notes; exports div0 rems div64 truncf64 truncsat truncsat_u64
// divu64 cvtu nane minz ovf32 remneg satneg udivmax cvtumax ovf64 nanef
// naneq minnan)
@ wasm_traps → s { ^ `0061736d01000000012a0860027f7f017f60027e7e017e60017c017f60017c017e60017e017c60027c7c017f6000017e6000017f0314130000010202030104050607070706060607070607a90113046469763000000472656d7300010564697636340002087472756e636636340003087472756e6373617400040c7472756e637361745f753634000506646976753634000604637674750007046e616e650008046d696e7a0009056f76663332000a0672656d6e6567000b067361746e6567000c07756469766d6178000d07637674756d6178000e056f76663634000f056e616e65660010056e616e65710011066d696e6e616e00120ae301130700200020016d0b0700200020016f0b0700200020017f0b05002000aa0b06002000fc020b06002000fc070b070020002001800b05002000ba0b070020002001620b1600440000000000000080440000000000000000a4bd0b0b00418080808078417f6d0b0b00418080808078417f6f0b0d0044000000c00b5ae6c1fc020b0700427f4202800b0600427fbabd0b1000428080808080808080807f427f7f0b150044000000000000f87f44000000000000f87f620b150044000000000000f87f44000000000000f87f610b160044000000000000f87f44000000000000f03fa4bd0b` }

// table 4..8 + active elem [inc inc] + passive elem [inc null]; exports
// callok callbad tsize tgrow tinit tnull (call_indirect type check, table.*)
@ wasm_table → s { ^ `0061736d01000000010e0360017f017f6000017e6000017f0309080001000102000202040501700104080734060663616c6c6f6b00020763616c6c6261640003057473697a650004057467726f7700050574696e6974000605746e756c6c00070911020041000b020000057002d2000bd0700b0a4c080700200041016a0b040042070b0900200041001100000b070041001101000b0500fc10000b0900d0702000fc0f000b1300410241004102fc0c0100412941021100000b070041032500d10b0024046e616d65010b020003696e6301036c3634040802000269690101760806010103706173` }

// memory 1..2 + active data "ACTIVE"@8 + passive "PASSIVE!"; exports
// init active0 activeb drop2 grow size (memory.init/data.drop/grow limits)
@ wasm_bulk → s { ^ `0061736d01000000010a026000017f60017f017f03070600000000010005040101010207320604696e6974000007616374697665300001076163746976656200020564726f703200030467726f7700040473697a6500050c01020a4406130041e40041004104fc08010041e4002d00000b070041002d00000b070041082d00000b1200fc090141c80141004101fc08010041000b0600200040000b04003f000b0b16020041080b0641435449564501085041535349564521000b046e616d65090401010170` }

// memory 1 + data 01..08 @0; exports fused kept loopfuse off oob — the
// address-add fold (`__fuse_addr`): the case it fires on, the case it must
// decline because the address is also a local, the case where the add is a
// loop body's first record, a folded address under a memarg offset, and a
// folded address that still has to fail the bounds check.
@ wasm_addrfold → s { ^ `0061736d01000000010b0260017f017f60017f017e030605000000010005030100010727050566757365640000046b6570740001086c6f6f70667573650002036f66660003036f6f6200040a62050a00200041036a2d00000b1301017f200041036a210120012d000020016a0b2901027f0240034020014104460d012002200020016a2d00006a2102200141016a21010c000b0b20020b0a00200041016a3100020b0c00200041ffff036a2d00000b0b0e010041000b0801020304050607080012046e616d65030b01020200036f757401016c` }

// start section sets a global to 99; export g reads it back
@ wasm_start → s { ^ `0061736d010000000108026000006000017f03030200010606017f0141000b070501016700010801000a0e02070041e30024000b040023000b0011046e616d65010401000173070401000167` }

// Run `export` with the given i64-cell args; returns the top of the value
// stack, or `traps` (out-param via sentinel −77777) when the module traps.
@ ev s hex s export ( Vec i ) args b want_trap → i {
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
                    : i na ( vec_len [i] args )
                    : ~ i k 0
                    ~ < k na { ( vec_push [i] . it vs ?? ( vec_get [i] args k ) { T x → x F → 0 } ) = k + k 1 }
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
            } {}
            ( module_free m )
        }
        F → {}
    }
    ^ r
}

@ ev0 s hex s export → i {
    : ( Vec i ) a ( vec_new [i] ) : i r ( ev hex export a F ) ( vec_free [i] a ) ^ r
}

@ ev1 s hex s export i x → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x )
    : i r ( ev hex export a F ) ( vec_free [i] a ) ^ r
}

@ ev2 s hex s export i x i y → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x ) ( vec_push [i] a y )
    : i r ( ev hex export a F ) ( vec_free [i] a ) ^ r
}

// 1 if the call traps, 0 if not.
@ trap0 s hex s export → i {
    : ( Vec i ) a ( vec_new [i] ) : i r ( ev hex export a T ) ( vec_free [i] a ) ^ r
}

@ trap1 s hex s export i x → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x )
    : i r ( ev hex export a T ) ( vec_free [i] a ) ^ r
}

@ trap2 s hex s export i x i y → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x ) ( vec_push [i] a y )
    : i r ( ev hex export a T ) ( vec_free [i] a ) ^ r
}

: ~ i g_fail 0

@ ck s label i got i want → v {
    ( nurl_print label ) ( nurl_print_int got )
    ? == got want { ( nurl_print ` == ` ) } { ( nurl_print ` != ` ) = g_fail + g_fail 1 }
    ( nurl_print_int want ) ( nurl_print `\n` )
}

@ main → i {
    // ── multi-value blocks / branches ──
    ( ck `mvblock:        ` ( ev0 ( wasm_mv ) `mvblock` ) 7 )
    ( ck `mvloop 10:      ` ( ev1 ( wasm_mv ) `mvloop` 10 ) 55 )
    ( ck `mvbr:           ` ( ev0 ( wasm_mv ) `mvbr` ) 30 )

    // ── integer division traps + defined edges ──
    ( ck `div 7/2:        ` ( ev2 ( wasm_traps ) `div0` 7 2 ) 3 )
    ( ck `div0 traps:     ` ( trap2 ( wasm_traps ) `div0` 7 0 ) 1 )
    ( ck `ovf32 traps:    ` ( trap0 ( wasm_traps ) `ovf32` ) 1 )
    ( ck `ovf64 traps:    ` ( trap0 ( wasm_traps ) `ovf64` ) 1 )
    ( ck `INTMIN rem -1:  ` ( ev0 ( wasm_traps ) `remneg` ) 0 )
    ( ck `u64max/2:       ` ( ev0 ( wasm_traps ) `udivmax` ) 9223372036854775807 )

    // ── float→int truncation: trapping + saturating ──
    : i nan_bits ( f64_to_bits ( bits_to_f64 9221120237041090560 ) )
    ( ck `trunc 2.5:      ` ( ev1 ( wasm_traps ) `truncf64` ( f64_to_bits 2.5 ) ) 2 )
    ( ck `trunc nan trap: ` ( trap1 ( wasm_traps ) `truncf64` nan_bits ) 1 )
    ( ck `trunc 3e9 trap: ` ( trap1 ( wasm_traps ) `truncf64` ( f64_to_bits 3000000000.0 ) ) 1 )
    ( ck `sat nan:        ` ( ev1 ( wasm_traps ) `truncsat` nan_bits ) 0 )
    ( ck `sat 3e9:        ` ( ev1 ( wasm_traps ) `truncsat` ( f64_to_bits 3000000000.0 ) ) 2147483647 )
    ( ck `sat -3e9:       ` ( ev0 ( wasm_traps ) `satneg` ) -2147483648 )
    ( ck `sat_u64 1e30:   ` ( ev1 ( wasm_traps ) `truncsat_u64` 5055640609639927018 ) -1 )

    // ── unsigned i64 → float ──
    ( ck `cvtu u64max:    ` ( ev0 ( wasm_traps ) `cvtumax` ) 4895412794951729152 )

    // ── NaN-correct comparisons and min/max ──
    ( ck `nan != nan:     ` ( ev0 ( wasm_traps ) `nanef` ) 1 )
    ( ck `nan == nan:     ` ( ev0 ( wasm_traps ) `naneq` ) 0 )
    ( ck `min(nan,1):     ` ( ev0 ( wasm_traps ) `minnan` ) 9221120237041090560 )
    ( ck `min(-0,+0):     ` ( ev0 ( wasm_traps ) `minz` ) -9223372036854775808 )

    // ── call_indirect type check + table.* ──
    ( ck `callok 5:       ` ( ev1 ( wasm_table ) `callok` 5 ) 6 )
    ( ck `callbad traps:  ` ( trap0 ( wasm_table ) `callbad` ) 1 )
    ( ck `table.size:     ` ( ev0 ( wasm_table ) `tsize` ) 4 )
    ( ck `table.grow 2:   ` ( ev1 ( wasm_table ) `tgrow` 2 ) 4 )
    ( ck `table.grow 10:  ` ( ev1 ( wasm_table ) `tgrow` 10 ) -1 )
    ( ck `table.init:     ` ( ev0 ( wasm_table ) `tinit` ) 42 )
    ( ck `null after init:` ( ev0 ( wasm_table ) `tnull` ) 1 )

    // ── passive data + memory.init / data.drop / grow limits ──
    ( ck `memory.init:    ` ( ev0 ( wasm_bulk ) `init` ) 80 )
    ( ck `passive not @0: ` ( ev0 ( wasm_bulk ) `active0` ) 0 )
    ( ck `active @8:      ` ( ev0 ( wasm_bulk ) `activeb` ) 65 )
    ( ck `init post-drop: ` ( trap0 ( wasm_bulk ) `drop2` ) 1 )
    ( ck `grow 1 (max 2): ` ( ev1 ( wasm_bulk ) `grow` 1 ) 1 )
    ( ck `grow 5 → -1:    ` ( ev1 ( wasm_bulk ) `grow` 5 ) -1 )
    ( ck `size:           ` ( ev0 ( wasm_bulk ) `size` ) 1 )

    // ── start section runs at instantiation ──
    ( ck `start section:  ` ( ev0 ( wasm_start ) `g` ) 99 )

    // ── the address add folded into the load ──
    ( ck `fold fires:     ` ( ev1 ( wasm_addrfold ) `fused` 0 ) 4 )
    ( ck `fold declined:  ` ( ev1 ( wasm_addrfold ) `kept` 0 ) 7 )
    ( ck `fold at loop t0:` ( ev1 ( wasm_addrfold ) `loopfuse` 0 ) 10 )
    ( ck `fold + memarg:  ` ( ev1 ( wasm_addrfold ) `off` 0 ) 4 )
    ( ck `fold oob traps: ` ( trap1 ( wasm_addrfold ) `oob` 1 ) 1 )

    ? > g_fail 0 { ( nurl_print `FAILURES: ` ) ( nurl_print_int g_fail ) ( nurl_print `\n` ) ^ 1 } {}
    ( nurl_print `all semantics tests passed\n` )
    ^ 0
}
