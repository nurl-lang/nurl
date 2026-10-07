// packages/nwasm/tests/semantics_test.nu — spec-semantics edge cases,
// hand-authored in WAT, compiled with wasm-tools, and cross-checked against
// the reference wasmtime (every expected value below was produced by it).
// Covers: multi-value blocks/branches, integer div/rem traps, trapping and
// saturating float→int truncation, unsigned i64 conversions, NaN-correct
// comparisons and min/max, call_indirect signature checks, table.* ops,
// passive segments + memory.init/data.drop, memory.copy/fill, memory.grow
// limits, division by constants, bit tests and shifts, reinterprets,
// null reference locals, narrowed i64 arithmetic, and the start
// section. Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/semantics_test.nu /tmp/st && /tmp/st

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/env.nu`
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

// Constant-expression regression module: f64/f32 globals whose bit
// patterns contain 0x0b bytes (a scanner that stops at the first 0x0b
// desyncs the whole section), plus ref.func / ref.null inits, an i64 and
// two i32 globals AFTER them as desync canaries, and a two-result
// function. Exports b0 b1 b2 g3 g4 g5 ge callf mv; every expectation
// from the reference wasmtime.
@ wasm_gconst → s { ^ `0061736d01000000010e036000017f6000017e6000027f7e030b0a00010100010000000002040401700001063f087c004400000000000004400b7c00440b0b0b0b0b0b0b400b7d0043b0b0300b0b7e00428b96acd8000b7f0141e8070b7000d2000b6f00d06f0b7f00412a0b07310902623000010262310002026232000302673300040267340005026735000602676500070563616c6c660008026d760009090501030001000a420a0400410a0b05002300bd0b05002301bd0b05002302bc0b040023030b040023040b040023070b05002306d10b0d0041002305260041001100000b0600410742770b0030046e616d65010601000374656e0721080002673001026731020267320302673304026734050267660602676507026735` }

// (table 3 externref): decodes, sizes, entries read as null.
@ wasm_exttab → s { ^ `0061736d010000000105016000017f03030200000404016f000307110205746e756c6c0000057473697a6500010a0f02070041012500d10b0500fc10000b` }

// start section sets a global to 99; export g reads it back
@ wasm_start → s { ^ `0061736d010000000108026000006000017f03030200010606017f0141000b070501016700010801000a0e02070041e30024000b040023000b0011046e616d65010401000173070401000167` }

// tests/wat/copyfill.wat: memory.copy / memory.fill — both overlap
// directions, adjacent and empty ranges, the memory's last bytes, every
// operand out of bounds (negative i32s included), a freshly grown page,
// values live across the operations, and a hot loop mixing the inline
// copy with the runtime's backward one. Exports cp fl cpend cpz cpgrow
// live loopcp; every expectation from the reference wasmtime.
@ wasm_copyfill → s { ^ `0061736d0100000001150460037f7f7f017e6000017f6000017e60017f017f03080700000101020303050401010102073207026370000002666c0001056370656e6400020363707a000306637067726f770004046c6976650005066c6f6f70637000060aaf02071100200020012002fc0a000041002903000b1000200020012002fc0b0041002903000b150041fcff0341004104fc0a000041fcff032802000b1d0041808004418080044100fc0a00004180800441004100fc0b0041070b1a00410140001a4188800441004108fc0a0000418880042903000b5b03037f017e017c200041016a2101200041036c2102200041d5007321032000ac21042000b7210541e40041004108fc0a000041c80120014103fc0b00200120026a20032004a76a6a41c9012d00002005aa41e7002d00006a6a6a0b5f01027f034041102001360200411141104104fc0a0000412041114104fc0a0000412841294107fc0a0000413020012001fc0b002002412028020041282802006a6a2102200241302d00006a2102200141016a210120012000490d000b20020b0b0e010041000b084142434445464748002f046e616d65022002050600016101017802017903017a040177050166060300016e010169020173030601060100014c` }

// Integer division and remainder by constants (both widths, both
// signednesses, powers of two, an add-indicator magic, a u32 remainder
// above 2^31 read back through i64.extend_i32_s): each export is
// `x OP K` for one K; the JIT turns these into shifts and multiplies.
// The exhaustive sweep is tests/divconst_diff.sh.
@ wasm_divk → s { ^ `0061736d01000000010b0260017f017e60017e017e03111000000000000000000001010101010101079401100775333264313630000007753332723136300001057533326437000207753332726269670003057333326437000406733332646d330005067333327231300006057333326438000707733332726d31360008067336346431300009087336347231303030000a057536346437000b06753634723130000c06733634646d38000d0775363464703430000e06733634726d37000f0a9201100900200041a0016eac0b0900200041a00170ac0b0800200041076eac0b08002000417e70ac0b0800200041076dac0b08002000417d6dac0b08002000410a6fac0b0800200041086dac0b0800200041706fac0b07002000420a7f0b0800200042e807810b070020004207800b07002000420a820b0700200042787f0b0c00200042808080808020800b070020004279810b` }

// Branches on a bit or a mask (the JIT's bt / test fusion), variable
// shifts with counts past the width (BMI2 or cl), the bit counts, and a
// loop keeping many values live through bit tests and selects.
@ wasm_flags → s { ^ `0061736d0100000001270760027e7e017f60017e017f60017f017f60027f7f017e60027e7e017e60017e017e60017f017e03111000010201030303040404040202050506077c100362747600000362746b0001057473743332000205747374363400030573686c33320004057368723332000505736172333200060573686c36340007057368723634000805736172363400090673656c667368000a05636c7a3332000b0563747a3332000c05636c7a3634000d0563747a3634000e036d6978000f0aa702101300200020018842018350047f410a0541140b0b1500027f41072000423f88420183a70d001a41030b0b1300200041818080807871047f41010541000b0b10002000427e8350047f41010541000b0b08002000200174ac0b08002000200176ac0b08002000200175ac0b070020002001860b070020002001880b070020002001870b0b002000200186210120010b05002000670b05002000680b05002000790b050020007a0b7f02017f057e4295f8a9fa97b7de9b9e7f21020340200242adfed5e4d485fda8d8007e42cf829ebbefefde82147c210220022001ad88420183500440200320027c210305200420028521040b2003200420032004561b2105200620052002423f83867c2106200141016a210120012000490d000b200320047c200520067c7c0b002c046e616d650218010f0700016e010169020178030161040162050163060164030b0201010001620f0100014c` }

// i64 arithmetic whose high half nobody reads (the JIT then computes it
// with 32-bit instructions): an LCG masked to 32 bits and read in full,
// chains read only through wraps, i64.store32/16, shl by constants on both
// sides of 32 and by a variable count past it, (a + b) & low masks, a
// product read both ways, a loop-carried value read only through a wrap,
// an and the zero-extension makes redundant, the fused pairs, an and with
// a mask above 2^32, shift counts computed in i64, and a two-def web.
@ wasm_narrow → s { ^ `0061736d01000000011f0560027e7f017e60027e7e017e60017e017e60027f7e017e60037e7e7e017e0313120001020101010100030404010101010101000503010001079c0112076c63676d61736b00000977726170636861696e00010473686c6b00020473686c760003076164646d61736b0004086164646d61736b320005056d697865640006097068696e6172726f770007067a786d61736b000806786f726d756c000906667573656477000a0473756272000b05616e646869000c0473687266000d03636e74000e04616e647a000f047374333200100674776f64656600110ab703123501017f03402000428dcce5007e42dfe6bbe3037c42ffffffff0f832200420d882000852100200241016a22022001490d000b20000b0f00200020017e20008520017da7ac0b1c002000421f86a7ad2000422886a7ad7c200042218620007ca7ad7c0b09002000200186a7ac0b0e00200020017c42ffffffff0f830b0e00200020017c428180808008830b1301017e200020017e2202a7ad2002422088850b3a02017e027f20002102034020024295f8a9fa97b7de9b9e7f7e20024207867c210220042002a7732104200341016a22032001490d000b2004ac0b0f002000ad42ffffffff0f8320017c0b0c00200020018520027ea7ac0b1e00200020017c20027e200020017c20027c85200020027e20017c7da7ac0b0900200020017da7ac0b0e00200020017c42ffffffff1f830b1500200042288820018320004203882001857ca7ac0b0e00200020014280808080107c860b0d00200020017e42ff018350ad0b2f004100427f3703004108427f3703004100200020017e3e02004108200020017c3d010041002903004108290300850b2301017e4110200037030020010440200020007c210205411029030021020b2002a7ac0b00bd01046e616d6502a80112000300017301016e02016b01020001610101620201000161030200016101016e040200016101016205020001610101620603000161010162020170070500016101016e02017803016b0403616363080200016101016209030001610101620201630a030001610101620201630b020001610101620c020001610101620d020001610101620e0200016101016e0f0200016101016210020001610101621103000161010163020178030b02000100016c070100016c` }

// i32.reinterpret_f32 yields a canonical i32 (read back through the
// i64.extend_i32_s the predecoder drops), demote/promote whose source
// dies into the result's register, and reference-typed locals that
// start out null — on a fresh frame and on a recycled one.
@ wasm_rint → s { ^ `0061736d010000000109026000017e6000017f030b0a0000010001010101010104040170000207450904726e656700000472696e6600010664666c6f6f7200020670666c6f6f72000305666269747300040365787400050366756e0006056d69786564000705616761696e00090907010041000b01080a9e010a0900430000c0bfbcac0b0e0044be74af13e4f1b2efb6bcac0b0e0044be74af13e4f1b2ef9cb6bc0b0a0043000020c08ebbbd0b100041808080fe7bbe430000803f92bc0b0701016f2000d10b070101702000d10b1a05017e016f017c0170017f2001d12003d16a2000a720046a6a0b0d0101702000d14100250021000b1f01027f0340200110086a2101200041016a2100200041e400490d000b20010b001e046e616d650104010801670209010902000169010173030601090100014c` }

// Run `export` with the given i64-cell args; returns the top of the value
// stack, or `traps` (out-param via sentinel −77777) when the module traps.
@ ev s hex s export ( Vec i ) args b want_trap → i {
    : !( Vec u ) ParseErr dr ( bytes_from_hex hex )
    : ~ i r -999999
    ?? dr {
        T bytes → {
            : Module m ( module_decode bytes )
            ? ( module_ok m ) {
                : i fidx ( module_export_func m export )
                ? >= fidx 0 {
                    : Interp it ( interp_new m )
                    ( interp_run_start it )
                    : i na ( vec_len [i] args )
                    : ~ i k 0
                    ~ < k na { ( vec_push [i] ( interp_stack it ) ?? ( vec_get [i] args k ) { T x → x F → 0 } ) = k + k 1 }
                    ( exec_func it fidx )
                    ? want_trap {
                        = r ? ( interp_trapped it ) 1 0
                    } {
                        ? ! ( interp_trapped it ) {
                            : i n ( vec_len [i] ( interp_stack it ) )
                            ? > n 0 { = r ?? ( vec_get [i] ( interp_stack it ) - n 1 ) { T x → x F → 0 } } {}
                        } {}
                    }
                } {}
            } {}
        }
        F → {}
    }
    ^ r
}

@ ev0 s hex s export → i {
    : ( Vec i ) a ( vec_new [i] ) : i r ( ev hex export a F ) ^ r
}

@ ev1 s hex s export i x → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x )
    : i r ( ev hex export a F ) ^ r
}

@ ev2 s hex s export i x i y → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x ) ( vec_push [i] a y )
    : i r ( ev hex export a F ) ^ r
}

// No-arg call, SECOND-from-top of the result stack (multi-value order).
@ ev0b s hex s export → i {
    : !( Vec u ) ParseErr dr ( bytes_from_hex hex )
    : ~ i r -999999
    ?? dr {
        T bytes → {
            : Module m ( module_decode bytes )
            ? ( module_ok m ) {
                : i fidx ( module_export_func m export )
                ? >= fidx 0 {
                    : Interp it ( interp_new m )
                    ( interp_run_start it )
                    ( exec_func it fidx )
                    ? ! ( interp_trapped it ) {
                        : i n ( vec_len [i] ( interp_stack it ) )
                        ? > n 1 { = r ?? ( vec_get [i] ( interp_stack it ) - n 2 ) { T x → x F → 0 } } {}
                    } {}
                } {}
            } {}
        }
        F → {}
    }
    ^ r
}

// 1 if the call traps, 0 if not.
@ trap0 s hex s export → i {
    : ( Vec i ) a ( vec_new [i] ) : i r ( ev hex export a T ) ^ r
}

@ ev3 s hex s export i x i y i z → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x ) ( vec_push [i] a y ) ( vec_push [i] a z )
    : i r ( ev hex export a F ) ^ r
}

@ trap3 s hex s export i x i y i z → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x ) ( vec_push [i] a y ) ( vec_push [i] a z )
    : i r ( ev hex export a T ) ^ r
}

@ trap1 s hex s export i x → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x )
    : i r ( ev hex export a T ) ^ r
}

@ trap2 s hex s export i x i y → i {
    : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a x ) ( vec_push [i] a y )
    : i r ( ev hex export a T ) ^ r
}

: ~ i g_fail 0

@ ck s label i got i want → v {
    ( nurl_print label ) ( nurl_println_int got )
    ? == got want { ( nurl_print ` == ` ) } { ( nurl_print ` != ` ) = g_fail + g_fail 1 }
    ( nurl_println_int want )
}

@ main → i {
    // Mirror the CLI's engine-mode switches so the suite exercises the
    // same tier the user runs: JIT on by default, NURL_NWASM_JIT=0 keeps
    // the pure interpreter, PIN=0 unpins, GUARD=0 keeps bounds checks.
    ?? ( env_get `NURL_NWASM_JIT` ) { T jv → { ? == 0 ( nurl_str_eq ( string_data jv ) `0` ) { ( interp_enable_jit ) } {} } F → { ( interp_enable_jit ) } }
    ?? ( env_get `NURL_NWASM_PIN` ) { T pv → { ? != 0 ( nurl_str_eq ( string_data pv ) `0` ) { ( interp_disable_pin ) } {} } F → {} }
    ?? ( env_get `NURL_NWASM_RJIT` ) { T rv → { ? != 0 ( nurl_str_eq ( string_data rv ) `0` ) { ( interp_disable_rjit ) } {} } F → {} }
    ?? ( env_get `NURL_NWASM_BMI2` ) { T bv → { ? != 0 ( nurl_str_eq ( string_data bv ) `0` ) { ( interp_disable_bmi2 ) } {} } F → {} }
    ?? ( env_get `NURL_NWASM_GUARD` ) { T gv → { ? != 0 ( nurl_str_eq ( string_data gv ) `0` ) { ( interp_disable_guard ) } {} } F → {} }
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

    // ── memory.copy / memory.fill: overlap, bounds, live values ──
    : s cf ( wasm_copyfill )
    ( ck `copy d>s overlap:` ( ev3 cf `cp` 2 0 6 ) 5063528411713061441 )
    ( ck `copy d<s overlap:` ( ev3 cf `cp` 0 2 6 ) 5208210965036090435 )
    ( ck `copy d==s:      ` ( ev3 cf `cp` 0 0 8 ) 5208208757389214273 )
    ( ck `copy n=0:       ` ( ev3 cf `cp` 1 0 0 ) 5208208757389214273 )
    ( ck `copy adjacent:  ` ( ev3 cf `cp` 4 0 4 ) 4918848066104279617 )
    ( ck `copy overlap 1: ` ( ev3 cf `cp` 3 0 4 ) 5207361020988965441 )
    ( ck `copy 0 @ end:   ` ( ev3 cf `cp` 65536 0 0 ) 5208208757389214273 )
    ( ck `copy to end:    ` ( ev3 cf `cp` 65528 0 8 ) 5208208757389214273 )
    ( ck `copy dst oob:   ` ( trap3 cf `cp` 65534 0 4 ) 1 )
    ( ck `copy src oob:   ` ( trap3 cf `cp` 0 65534 4 ) 1 )
    ( ck `copy dst -1:    ` ( trap3 cf `cp` -1 0 1 ) 1 )
    ( ck `copy src -1:    ` ( trap3 cf `cp` 0 -1 1 ) 1 )
    ( ck `copy n -1:      ` ( trap3 cf `cp` 0 0 -1 ) 1 )
    ( ck `copy 0 past end:` ( trap3 cf `cp` 65537 0 0 ) 1 )
    ( ck `fill low byte:  ` ( ev3 cf `fl` 1 4660 3 ) 5208208757119792193 )
    ( ck `fill -1:        ` ( ev3 cf `fl` 0 -1 2 ) 5208208757389262847 )
    ( ck `fill 0 @ end:   ` ( ev3 cf `fl` 65536 7 0 ) 5208208757389214273 )
    ( ck `fill to end:    ` ( ev3 cf `fl` 65534 1 2 ) 5208208757389214273 )
    ( ck `fill oob:       ` ( trap3 cf `fl` 65535 0 2 ) 1 )
    ( ck `fill dst -1:    ` ( trap3 cf `fl` -1 0 1 ) 1 )
    ( ck `fill n -1:      ` ( trap3 cf `fl` 0 0 -1 ) 1 )
    ( ck `fill 0 past end:` ( trap3 cf `fl` 65537 7 0 ) 1 )
    ( ck `copy last bytes:` ( ev0 cf `cpend` ) 1145258561 )
    ( ck `copy+fill empty:` ( ev0 cf `cpz` ) 7 )
    ( ck `copy grown page:` ( ev0 cf `cpgrow` ) 5208208757389214273 )
    ( ck `live across:    ` ( ev1 cf `live` 10 ) 235 )
    ( ck `copy loop 300:  ` ( ev1 cf `loopcp` 300 ) 78436 )

    // ── bit / mask branches, variable shifts, bit counts ──
    : s fl ( wasm_flags )
    ( ck `btv #0:         ` ( ev2 fl `btv` -1 0 ) 20 )
    ( ck `btv #1:         ` ( ev2 fl `btv` -1 63 ) 20 )
    ( ck `btv #2:         ` ( ev2 fl `btv` 5 64 ) 20 )
    ( ck `btv #3:         ` ( ev2 fl `btv` 5 65 ) 10 )
    ( ck `btv #4:         ` ( ev2 fl `btv` 4611686018427387904 62 ) 20 )
    ( ck `btv #5:         ` ( ev2 fl `btv` 1 -1 ) 10 )
    ( ck `btv #6:         ` ( ev2 fl `btv` -9223372036854775808 -1 ) 20 )
    ( ck `btv #7:         ` ( ev2 fl `btv` 2 1 ) 20 )
    ( ck `btk #0:         ` ( ev1 fl `btk` -1 ) 7 )
    ( ck `btk #1:         ` ( ev1 fl `btk` 1 ) 3 )
    ( ck `btk #2:         ` ( ev1 fl `btk` -9223372036854775808 ) 7 )
    ( ck `btk #3:         ` ( ev1 fl `btk` 0 ) 3 )
    ( ck `tst32 #0:       ` ( ev1 fl `tst32` 0 ) 0 )
    ( ck `tst32 #1:       ` ( ev1 fl `tst32` 1 ) 1 )
    ( ck `tst32 #2:       ` ( ev1 fl `tst32` -2147483648 ) 1 )
    ( ck `tst32 #3:       ` ( ev1 fl `tst32` 2 ) 0 )
    ( ck `tst32 #4:       ` ( ev1 fl `tst32` -1 ) 1 )
    ( ck `tst64 #0:       ` ( ev1 fl `tst64` 0 ) 1 )
    ( ck `tst64 #1:       ` ( ev1 fl `tst64` 1 ) 1 )
    ( ck `tst64 #2:       ` ( ev1 fl `tst64` 2 ) 0 )
    ( ck `tst64 #3:       ` ( ev1 fl `tst64` -1 ) 0 )
    ( ck `tst64 #4:       ` ( ev1 fl `tst64` -9223372036854775808 ) 0 )
    ( ck `shl32 #0:       ` ( ev2 fl `shl32` 1 31 ) -2147483648 )
    ( ck `shl32 #1:       ` ( ev2 fl `shl32` 1 32 ) 1 )
    ( ck `shl32 #2:       ` ( ev2 fl `shl32` 1 33 ) 2 )
    ( ck `shl32 #3:       ` ( ev2 fl `shl32` -1 -1 ) -2147483648 )
    ( ck `shl32 #4:       ` ( ev2 fl `shl32` 1073741824 1 ) -2147483648 )
    ( ck `shl32 #5:       ` ( ev2 fl `shl32` 3 -31 ) 6 )
    ( ck `shr32 #0:       ` ( ev2 fl `shr32` -1 1 ) 2147483647 )
    ( ck `shr32 #1:       ` ( ev2 fl `shr32` -1 32 ) -1 )
    ( ck `shr32 #2:       ` ( ev2 fl `shr32` -2147483648 31 ) 1 )
    ( ck `shr32 #3:       ` ( ev2 fl `shr32` -2147483648 -1 ) 1 )
    ( ck `shr32 #4:       ` ( ev2 fl `shr32` 5 33 ) 2 )
    ( ck `sar32 #0:       ` ( ev2 fl `sar32` -2147483648 31 ) -1 )
    ( ck `sar32 #1:       ` ( ev2 fl `sar32` -2147483648 32 ) -2147483648 )
    ( ck `sar32 #2:       ` ( ev2 fl `sar32` -1 7 ) -1 )
    ( ck `sar32 #3:       ` ( ev2 fl `sar32` 1073741824 -2 ) 1 )
    ( ck `shl64 #0:       ` ( ev2 fl `shl64` 1 63 ) -9223372036854775808 )
    ( ck `shl64 #1:       ` ( ev2 fl `shl64` 1 64 ) 1 )
    ( ck `shl64 #2:       ` ( ev2 fl `shl64` 1 -1 ) -9223372036854775808 )
    ( ck `shl64 #3:       ` ( ev2 fl `shl64` 3 65 ) 6 )
    ( ck `shl64 #4:       ` ( ev2 fl `shl64` -1 32 ) -4294967296 )
    ( ck `shr64 #0:       ` ( ev2 fl `shr64` -1 1 ) 9223372036854775807 )
    ( ck `shr64 #1:       ` ( ev2 fl `shr64` -1 64 ) -1 )
    ( ck `shr64 #2:       ` ( ev2 fl `shr64` -9223372036854775808 63 ) 1 )
    ( ck `shr64 #3:       ` ( ev2 fl `shr64` -1 -1 ) 1 )
    ( ck `shr64 #4:       ` ( ev2 fl `shr64` 7 129 ) 3 )
    ( ck `sar64 #0:       ` ( ev2 fl `sar64` -9223372036854775808 63 ) -1 )
    ( ck `sar64 #1:       ` ( ev2 fl `sar64` -9223372036854775808 64 ) -9223372036854775808 )
    ( ck `sar64 #2:       ` ( ev2 fl `sar64` -2 -1 ) -1 )
    ( ck `sar64 #3:       ` ( ev2 fl `sar64` 1 1 ) 0 )
    ( ck `selfsh #0:      ` ( ev2 fl `selfsh` 3 4 ) 48 )
    ( ck `selfsh #1:      ` ( ev2 fl `selfsh` -1 63 ) -9223372036854775808 )
    ( ck `selfsh #2:      ` ( ev2 fl `selfsh` 5 64 ) 5 )
    ( ck `clz32 #0:       ` ( ev1 fl `clz32` 0 ) 32 )
    ( ck `clz32 #1:       ` ( ev1 fl `clz32` 1 ) 31 )
    ( ck `clz32 #2:       ` ( ev1 fl `clz32` -1 ) 0 )
    ( ck `clz32 #3:       ` ( ev1 fl `clz32` 65536 ) 15 )
    ( ck `ctz32 #0:       ` ( ev1 fl `ctz32` 0 ) 32 )
    ( ck `ctz32 #1:       ` ( ev1 fl `ctz32` 1 ) 0 )
    ( ck `ctz32 #2:       ` ( ev1 fl `ctz32` -2147483648 ) 31 )
    ( ck `ctz32 #3:       ` ( ev1 fl `ctz32` 65536 ) 16 )
    ( ck `clz64 #0:       ` ( ev1 fl `clz64` 0 ) 64 )
    ( ck `clz64 #1:       ` ( ev1 fl `clz64` 1 ) 63 )
    ( ck `clz64 #2:       ` ( ev1 fl `clz64` -1 ) 0 )
    ( ck `clz64 #3:       ` ( ev1 fl `clz64` 4294967296 ) 31 )
    ( ck `ctz64 #0:       ` ( ev1 fl `ctz64` 0 ) 64 )
    ( ck `ctz64 #1:       ` ( ev1 fl `ctz64` -9223372036854775808 ) 63 )
    ( ck `ctz64 #2:       ` ( ev1 fl `ctz64` 4294967296 ) 32 )
    ( ck `ctz64 #3:       ` ( ev1 fl `ctz64` 6 ) 1 )
    ( ck `mix #0:         ` ( ev1 fl `mix` 1000 ) -7772899469867135293 )
    ( ck `mix #1:         ` ( ev1 fl `mix` 1 ) -8736760740920937472 )

    // ── i64 arithmetic whose high half nobody reads ──
    : s nr ( wasm_narrow )
    ( ck `lcgmask #0:     ` ( ev2 nr `lcgmask` 123456789 1000 ) 3848359177 )
    ( ck `lcgmask #1:     ` ( ev2 nr `lcgmask` -1 7 ) 3010282294 )
    ( ck `lcgmask #2:     ` ( ev2 nr `lcgmask` 1311768467463790320 33 ) 832811405 )
    ( ck `wrapchain #0:   ` ( ev2 nr `wrapchain` 1311768467463790320 -3 ) -1250574909 )
    ( ck `wrapchain #1:   ` ( ev2 nr `wrapchain` -1 -1 ) -1 )
    ( ck `wrapchain #2:   ` ( ev2 nr `wrapchain` 81985529216486895 9223372036854775807 ) -1 )
    ( ck `shlk #0:        ` ( ev1 nr `shlk` 1311768467463790320 ) 2596069104 )
    ( ck `shlk #1:        ` ( ev1 nr `shlk` -1 ) 6442450943 )
    ( ck `shlk #2:        ` ( ev1 nr `shlk` 3 ) 2147483651 )
    ( ck `shlv #0:        ` ( ev2 nr `shlv` 1311768467463790320 33 ) 0 )
    ( ck `shlv #1:        ` ( ev2 nr `shlv` 1311768467463790320 31 ) 0 )
    ( ck `shlv #2:        ` ( ev2 nr `shlv` -1 64 ) -1 )
    ( ck `shlv #3:        ` ( ev2 nr `shlv` 5 96 ) 0 )
    ( ck `addmask #0:     ` ( ev2 nr `addmask` 4294967295 1 ) 0 )
    ( ck `addmask #1:     ` ( ev2 nr `addmask` -1 -1 ) 4294967294 )
    ( ck `addmask #2:     ` ( ev2 nr `addmask` 1311768467463790320 81985529216486895 ) 610839775 )
    ( ck `addmask2 #0:    ` ( ev2 nr `addmask2` 4294967295 2 ) 1 )
    ( ck `addmask2 #1:    ` ( ev2 nr `addmask2` -2 3 ) 1 )
    ( ck `mixed #0:       ` ( ev2 nr `mixed` 1311768467463790320 81985529216486895 ) 3312743065 )
    ( ck `mixed #1:       ` ( ev2 nr `mixed` -1 -1 ) 1 )
    ( ck `phinarrow #0:   ` ( ev2 nr `phinarrow` 1311768467463790320 100 ) -1720186624 )
    ( ck `phinarrow #1:   ` ( ev2 nr `phinarrow` -1 3 ) 1877237887 )
    ( ck `zxmask #0:      ` ( ev2 nr `zxmask` -1 5 ) 4294967300 )
    ( ck `zxmask #1:      ` ( ev2 nr `zxmask` 7 -1 ) 6 )
    ( ck `xormul #0:      ` ( ev3 nr `xormul` 1311768467463790320 -3 81985529216486895 ) 1406288931 )
    ( ck `fusedw #0:      ` ( ev3 nr `fusedw` 1311768467463790320 -3 81985529216486895 ) 1193538194 )
    ( ck `fusedw #1:      ` ( ev3 nr `fusedw` -1 -1 -1 ) -1 )
    ( ck `subr #0:        ` ( ev2 nr `subr` 3 1311768467463790320 ) 1698898195 )
    ( ck `subr #1:        ` ( ev2 nr `subr` -1311768467463790320 7 ) 1698898185 )
    ( ck `andhi #0:       ` ( ev2 nr `andhi` -1 -1 ) 8589934590 )
    ( ck `andhi #1:       ` ( ev2 nr `andhi` 4294967295 4294967297 ) 0 )
    ( ck `shrf #0:        ` ( ev2 nr `shrf` 1311768467463790320 -81985529216486895 ) 1695799775 )
    ( ck `cnt #0:         ` ( ev2 nr `cnt` 3 4 ) 48 )
    ( ck `cnt #1:         ` ( ev2 nr `cnt` 1311768467463790320 -1 ) 0 )
    ( ck `andz #0:        ` ( ev2 nr `andz` 256 1 ) 1 )
    ( ck `andz #1:        ` ( ev2 nr `andz` 1311768467463790320 81985529216486895 ) 0 )
    ( ck `andz #2:        ` ( ev2 nr `andz` 16 16 ) 1 )
    ( ck `st32 #0:        ` ( ev2 nr `st32` 1311768467463790320 81985529216486895 ) 4040556239 )
    ( ck `st32 #1:        ` ( ev2 nr `st32` -1 -1 ) 4294967295 )
    ( ck `twodef #0:      ` ( ev2 nr `twodef` 1311768467463790320 1 ) 897170912 )
    ( ck `twodef #1:      ` ( ev2 nr `twodef` 1311768467463790320 0 ) -1698898192 )
    ( ck `twodef #2:      ` ( ev2 nr `twodef` -3 1 ) -6 )

    // ── reinterprets, demote/promote, null reference locals ──
    : s ri ( wasm_rint )
    ( ck `rneg:           ` ( ev0 ri `rneg` ) -1077936128 )
    ( ck `rinf:           ` ( ev0 ri `rinf` ) -8388608 )
    ( ck `dfloor:         ` ( ev0 ri `dfloor` ) -8388608 )
    ( ck `pfloor:         ` ( ev0 ri `pfloor` ) -4609434218613702656 )
    ( ck `fbits:          ` ( ev0 ri `fbits` ) -1090519040 )
    ( ck `ext:            ` ( ev0 ri `ext` ) 1 )
    ( ck `fun:            ` ( ev0 ri `fun` ) 1 )
    ( ck `mixed:          ` ( ev0 ri `mixed` ) 2 )
    ( ck `again:          ` ( ev0 ri `again` ) 100 )

    // ── division / remainder by a constant ──
    : s dk ( wasm_divk )
    ( ck `u32d160 x0:     ` ( ev1 dk `u32d160` 2147483647 ) 13421772 )
    ( ck `u32d160 x1:     ` ( ev1 dk `u32d160` -2147483648 ) 13421772 )
    ( ck `u32d160 x2:     ` ( ev1 dk `u32d160` -1 ) 26843545 )
    ( ck `u32d160 x3:     ` ( ev1 dk `u32d160` 12345 ) 77 )
    ( ck `u32r160 x0:     ` ( ev1 dk `u32r160` 2147483647 ) 127 )
    ( ck `u32r160 x1:     ` ( ev1 dk `u32r160` -2147483648 ) 128 )
    ( ck `u32r160 x2:     ` ( ev1 dk `u32r160` -1 ) 95 )
    ( ck `u32r160 x3:     ` ( ev1 dk `u32r160` 12345 ) 25 )
    ( ck `u32d7 x0:       ` ( ev1 dk `u32d7` 2147483647 ) 306783378 )
    ( ck `u32d7 x1:       ` ( ev1 dk `u32d7` -2147483648 ) 306783378 )
    ( ck `u32d7 x2:       ` ( ev1 dk `u32d7` -1 ) 613566756 )
    ( ck `u32d7 x3:       ` ( ev1 dk `u32d7` 12345 ) 1763 )
    ( ck `u32rbig x0:     ` ( ev1 dk `u32rbig` 2147483647 ) 2147483647 )
    ( ck `u32rbig x1:     ` ( ev1 dk `u32rbig` -2147483648 ) -2147483648 )
    ( ck `u32rbig x2:     ` ( ev1 dk `u32rbig` -1 ) 1 )
    ( ck `u32rbig x3:     ` ( ev1 dk `u32rbig` 12345 ) 12345 )
    ( ck `s32d7 x0:       ` ( ev1 dk `s32d7` 2147483647 ) 306783378 )
    ( ck `s32d7 x1:       ` ( ev1 dk `s32d7` -2147483648 ) -306783378 )
    ( ck `s32d7 x2:       ` ( ev1 dk `s32d7` -1 ) 0 )
    ( ck `s32d7 x3:       ` ( ev1 dk `s32d7` 12345 ) 1763 )
    ( ck `s32dm3 x0:      ` ( ev1 dk `s32dm3` 2147483647 ) -715827882 )
    ( ck `s32dm3 x1:      ` ( ev1 dk `s32dm3` -2147483648 ) 715827882 )
    ( ck `s32dm3 x2:      ` ( ev1 dk `s32dm3` -1 ) 0 )
    ( ck `s32dm3 x3:      ` ( ev1 dk `s32dm3` 12345 ) -4115 )
    ( ck `s32r10 x0:      ` ( ev1 dk `s32r10` 2147483647 ) 7 )
    ( ck `s32r10 x1:      ` ( ev1 dk `s32r10` -2147483648 ) -8 )
    ( ck `s32r10 x2:      ` ( ev1 dk `s32r10` -1 ) -1 )
    ( ck `s32r10 x3:      ` ( ev1 dk `s32r10` 12345 ) 5 )
    ( ck `s32d8 x0:       ` ( ev1 dk `s32d8` 2147483647 ) 268435455 )
    ( ck `s32d8 x1:       ` ( ev1 dk `s32d8` -2147483648 ) -268435456 )
    ( ck `s32d8 x2:       ` ( ev1 dk `s32d8` -1 ) 0 )
    ( ck `s32d8 x3:       ` ( ev1 dk `s32d8` 12345 ) 1543 )
    ( ck `s32rm16 x0:     ` ( ev1 dk `s32rm16` 2147483647 ) 15 )
    ( ck `s32rm16 x1:     ` ( ev1 dk `s32rm16` -2147483648 ) 0 )
    ( ck `s32rm16 x2:     ` ( ev1 dk `s32rm16` -1 ) -1 )
    ( ck `s32rm16 x3:     ` ( ev1 dk `s32rm16` 12345 ) 9 )
    ( ck `s64d10 x0:      ` ( ev1 dk `s64d10` -9223372036854775808 ) -922337203685477580 )
    ( ck `s64d10 x1:      ` ( ev1 dk `s64d10` 9223372036854775807 ) 922337203685477580 )
    ( ck `s64d10 x2:      ` ( ev1 dk `s64d10` -1 ) 0 )
    ( ck `s64d10 x3:      ` ( ev1 dk `s64d10` -123456789 ) -12345678 )
    ( ck `s64r1000 x0:    ` ( ev1 dk `s64r1000` -9223372036854775808 ) -808 )
    ( ck `s64r1000 x1:    ` ( ev1 dk `s64r1000` 9223372036854775807 ) 807 )
    ( ck `s64r1000 x2:    ` ( ev1 dk `s64r1000` -1 ) -1 )
    ( ck `s64r1000 x3:    ` ( ev1 dk `s64r1000` -123456789 ) -789 )
    ( ck `u64d7 x0:       ` ( ev1 dk `u64d7` -9223372036854775808 ) 1317624576693539401 )
    ( ck `u64d7 x1:       ` ( ev1 dk `u64d7` 9223372036854775807 ) 1317624576693539401 )
    ( ck `u64d7 x2:       ` ( ev1 dk `u64d7` -1 ) 2635249153387078802 )
    ( ck `u64d7 x3:       ` ( ev1 dk `u64d7` -123456789 ) 2635249153369442118 )
    ( ck `u64r10 x0:      ` ( ev1 dk `u64r10` -9223372036854775808 ) 8 )
    ( ck `u64r10 x1:      ` ( ev1 dk `u64r10` 9223372036854775807 ) 7 )
    ( ck `u64r10 x2:      ` ( ev1 dk `u64r10` -1 ) 5 )
    ( ck `u64r10 x3:      ` ( ev1 dk `u64r10` -123456789 ) 7 )
    ( ck `s64dm8 x0:      ` ( ev1 dk `s64dm8` -9223372036854775808 ) 1152921504606846976 )
    ( ck `s64dm8 x1:      ` ( ev1 dk `s64dm8` 9223372036854775807 ) -1152921504606846975 )
    ( ck `s64dm8 x2:      ` ( ev1 dk `s64dm8` -1 ) 0 )
    ( ck `s64dm8 x3:      ` ( ev1 dk `s64dm8` -123456789 ) 15432098 )
    ( ck `u64dp40 x0:     ` ( ev1 dk `u64dp40` -9223372036854775808 ) 8388608 )
    ( ck `u64dp40 x1:     ` ( ev1 dk `u64dp40` 9223372036854775807 ) 8388607 )
    ( ck `u64dp40 x2:     ` ( ev1 dk `u64dp40` -1 ) 16777215 )
    ( ck `u64dp40 x3:     ` ( ev1 dk `u64dp40` -123456789 ) 16777215 )
    ( ck `s64rm7 x0:      ` ( ev1 dk `s64rm7` -9223372036854775808 ) -1 )
    ( ck `s64rm7 x1:      ` ( ev1 dk `s64rm7` 9223372036854775807 ) 0 )
    ( ck `s64rm7 x2:      ` ( ev1 dk `s64rm7` -1 ) -1 )
    ( ck `s64rm7 x3:      ` ( ev1 dk `s64rm7` -123456789 ) -1 )

    // ── start section runs at instantiation ──
    ( ck `start section:  ` ( ev0 ( wasm_start ) `g` ) 99 )

    // ── const-expr immediates: every kind, 0x0b-byte patterns included ──
    ( ck `f64 global 2.5: ` ( ev0 ( wasm_gconst ) `b0` ) 4612811918334230528 )
    ( ck `f64 0x0b bytes: ` ( ev0 ( wasm_gconst ) `b1` ) 4614794385229024011 )
    ( ck `f32 0x0b bytes: ` ( ev0 ( wasm_gconst ) `b2` ) 187740336 )
    ( ck `i64 after refs: ` ( ev0 ( wasm_gconst ) `g3` ) 185273099 )
    ( ck `mut i32 1000:   ` ( ev0 ( wasm_gconst ) `g4` ) 1000 )
    ( ck `i32 after refs: ` ( ev0 ( wasm_gconst ) `g5` ) 42 )
    ( ck `externref null: ` ( ev0 ( wasm_gconst ) `ge` ) 1 )
    ( ck `ref.func init:  ` ( ev0 ( wasm_gconst ) `callf` ) 10 )
    ( ck `mv top:         ` ( ev0 ( wasm_gconst ) `mv` ) -9 )
    ( ck `mv second:      ` ( ev0b ( wasm_gconst ) `mv` ) 7 )

    // ── externref table decodes and holds null ──
    ( ck `extern tnull:   ` ( ev0 ( wasm_exttab ) `tnull` ) 1 )
    ( ck `extern tsize:   ` ( ev0 ( wasm_exttab ) `tsize` ) 3 )

    // ── the address add folded into the load ──
    ( ck `fold fires:     ` ( ev1 ( wasm_addrfold ) `fused` 0 ) 4 )
    ( ck `fold declined:  ` ( ev1 ( wasm_addrfold ) `kept` 0 ) 7 )
    ( ck `fold at loop t0:` ( ev1 ( wasm_addrfold ) `loopfuse` 0 ) 10 )
    ( ck `fold + memarg:  ` ( ev1 ( wasm_addrfold ) `off` 0 ) 4 )
    ( ck `fold oob traps: ` ( trap1 ( wasm_addrfold ) `oob` 1 ) 1 )

    ? > g_fail 0 { ( nurl_print `FAILURES: ` ) ( nurl_println_int g_fail ) ^ 1 } {}
    ( nurl_print `all semantics tests passed\n` )
    ^ 0
}
