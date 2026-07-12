// Test: f16 / bf16 bit conversion (stdlib/std/floatbits.nu).
// Known IEEE pairs (subnormals, ±inf, NaN, -0), round-to-nearest-even
// narrowing cases, and the strongest property available: EXHAUSTIVE
// widen→narrow round-trip identity over all 65536 bit patterns of
// both formats (every f16/bf16 value is exactly representable in f32,
// so RNE back must reproduce the original bits — NaN payloads too).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/floatbits.nu`

@ ck b ok s name → v {
    ? ok { ( nurl_print `PASS ` ) } { ( nurl_print `FAIL ` ) }
    ( nurl_print name )
    ( nurl_print `\n` )
}

@ main → i {
    // widen: hand-checked pairs
    : ~ b w T
    ? == ( f16_bits_to_f32_bits 0 ) 0 {} { = w F }
    ? == ( f16_bits_to_f32_bits 15360 ) 1065353216 {} { = w F }
    ? == ( f16_bits_to_f32_bits 49152 ) 3221225472 {} { = w F }
    ? == ( f16_bits_to_f32_bits 1 ) 864026624 {} { = w F }
    ? == ( f16_bits_to_f32_bits 1023 ) 947896320 {} { = w F }
    ? == ( f16_bits_to_f32_bits 31744 ) 2139095040 {} { = w F }
    ? == ( f16_bits_to_f32_bits 64512 ) 4286578688 {} { = w F }
    ? == ( f16_bits_to_f32_bits 32768 ) 2147483648 {} { = w F }
    ( ck w `f16 → f32: 0 / 1.0 / -2.0 / subnormals / ±inf / -0` )
    ( ck == ( bf16_bits_to_f32_bits 16256 ) 1065353216 `bf16 → f32: 1.0` )

    // narrow RNE: 1.0 exact; nextafter cases tie to even; overflow → inf;
    // tiny → subnormal; f64-level conveniences agree
    : ~ b r T
    ? == ( f_to_f16 1.0 ) 15360 {} { = r F }
    ? == ( f_to_f16 65504.0 ) 31743 {} { = r F }
    ? == ( f_to_f16 65520.0 ) 31744 {} { = r F }
    ? == ( f_to_f16 -65520.0 ) 64512 {} { = r F }
    ? == ( f_to_f16 0.00006103515625 ) 1024 {} { = r F }
    ? == ( f_to_f16 0.000000059604644775390625 ) 1 {} { = r F }
    ? == ( f_to_f16 1.0009765625 ) 15361 {} { = r F }
    ? == ( f_to_f16 1.00048828125 ) 15360 {} { = r F }
    ? == ( f_to_f16 1.00146484375 ) 15362 {} { = r F }
    ( ck r `f32 → f16 RNE: max/overflow/subnormal/ties-to-even` )
    : ~ b rb T
    ? == ( f_to_bf16 1.0 ) 16256 {} { = rb F }
    ? == ( f_to_bf16 -2.0 ) 49152 {} { = rb F }
    // 1 + 1/256 is EXACTLY halfway between bf16 0x3F80 and 0x3F81 —
    // ties go to the even mantissa, i.e. DOWN here
    ? == ( f_to_bf16 1.00390625 ) 16256 {} { = rb F }
    ? == ( f_to_bf16 1.001953125 ) 16256 {} { = rb F }
    // 1 + 3/256: tie again, but the lower neighbour 0x3F81 is odd —
    // even means rounding UP to 0x3F82
    ? == ( f_to_bf16 1.01171875 ) 16258 {} { = rb F }
    ( ck rb `f32 → bf16 RNE: exact + ties-to-even` )

    // exhaustive round-trips: 65536 patterns each way
    : ~ i bad16 0
    : ~ i h 0
    ~ < h 65536 {
        ? == ( f32_bits_to_f16_bits ( f16_bits_to_f32_bits h ) ) h {} { = bad16 + bad16 1 }
        = h + h 1
    }
    ( ck == bad16 0 `f16 → f32 → f16 identity over all 65536 patterns` )
    : ~ i badb 0
    = h 0
    ~ < h 65536 {
        ? == ( f32_bits_to_bf16_bits ( bf16_bits_to_f32_bits h ) ) h {} { = badb + badb 1 }
        = h + h 1
    }
    ( ck == badb 0 `bf16 → f32 → bf16 identity over all 65536 patterns` )
    ^ 0
}
