// floatbits.nu — IEEE-754 bit reinterpretation + binary float I/O
// (stdlib/std/floatbits.nu). Constants verified against struct.pack.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/floatbits.nu`

@ pb s label b ok → v { ( nurl_print label ) ( nurl_print ? ok `YES\n` `NO\n` ) }

@ main → i {
    // f64 → bit pattern (exact, known constants)
    ( pb `f64 0.0  bits==0:   ` == ( f64_to_bits 0.0 ) 0 )
    ( pb `f64 1.0  bits:      ` == ( f64_to_bits 1.0 ) 4607182418800017408 )
    ( pb `f64 2.0  bits:      ` == ( f64_to_bits 2.0 ) 4611686018427387904 )
    ( pb `f64 0.5  bits:      ` == ( f64_to_bits 0.5 ) 4602678819172646912 )
    ( pb `f64 -2.0 bits:      ` == ( f64_to_bits -2.0 ) -4611686018427387904 )
    // f64 round-trips bit-exactly (covers any pattern)
    ( pb `f64 roundtrip:      ` == ( f64_to_bits ( bits_to_f64 4614256650576692846 ) ) 4614256650576692846 )
    // bits_to_f64 then arithmetic: 2.0 + 2.0 = 4.0
    ( pb `bits_to_f64 arith:  ` == ( f64_to_bits + ( bits_to_f64 4611686018427387904 ) ( bits_to_f64 4611686018427387904 ) ) ( f64_to_bits 4.0 ) )
    // f32 → bit pattern
    ( pb `f32 1.0  bits:      ` == ( f32_to_bits # f32 1.0 ) 1065353216 )
    ( pb `f32 2.0  bits:      ` == ( f32_to_bits # f32 2.0 ) 1073741824 )
    ( pb `f32 roundtrip:      ` == ( f32_to_bits ( bits_to_f32 1065353216 ) ) 1065353216 )

    // binary I/O: push 2.0 big-endian, first byte is 0x40 = 64
    : ( Vec u ) be ( vec_new [u] )
    ( bytes_push_f64_be be 2.0 )
    ( pb `f64_be first byte:  ` == ?? ( vec_get [u] be 0 ) { T x → # i x F → -1 } 64 )
    ( pb `f64_be read-back:   ` ?? ( bytes_read_f64_be be 0 ) { T x → == ( f64_to_bits x ) 4611686018427387904 F → F } )
    // little-endian: last byte is 0x40
    : ( Vec u ) le ( vec_new [u] )
    ( bytes_push_f64_le le 2.0 )
    ( pb `f64_le last byte:   ` == ?? ( vec_get [u] le 7 ) { T x → # i x F → -1 } 64 )
    ( pb `f64_le read-back:   ` ?? ( bytes_read_f64_le le 0 ) { T x → == ( f64_to_bits x ) 4611686018427387904 F → F } )
    // f32 binary round-trip
    : ( Vec u ) f32b ( vec_new [u] )
    ( bytes_push_f32_le f32b # f32 2.0 )
    ( pb `f32_le read-back:   ` ?? ( bytes_read_f32_le f32b 0 ) { T x → == ( f32_to_bits x ) 1073741824 F → F } )
    ^ 0
}
