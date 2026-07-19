// packages/gguf/src/quant.nu — host-side scalar quantisation encoders.
//
// The write-side mirror of dequant.nu: turn the canonical f32-LE
// buffer (the exact form gguf_dequant produces) into GGUF tensor
// payload bytes, following ggml's reference quantisers bit for bit.
// dequant.nu is the decode oracle these encoders are tested against —
// encode → decode must land within the format's own rounding.
//
//   ( gq_f16_encode f32le )  → !( Vec u ) String   f32-LE → f16-LE (RNE)
//   ( gq_bf16_encode f32le ) → !( Vec u ) String   f32-LE → bf16-LE (RNE)
//   ( gq_q8_0_encode f32le ) → !( Vec u ) String   f32-LE → Q8_0 blocks
//
// Layouts (ggml, exactly):
//   Q8_0: 34-byte block = f16 d + 32 signed bytes, d = amax/127,
//         q = roundf(x/d) — quantize_row_q8_0_ref.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/float.nu`

// f32 element idx out of the canonical little-endian buffer.
@ __gq_f32 * u P i idx → f {
    : i o * idx 4
    : i bits | | | # i . P o << # i . P + o 1 8 << # i . P + o 2 16 << # i . P + o 3 24
    ^ # f ( bits_to_f32 bits )
}

@ __gq_err s msg → !( Vec u ) String {
    ^ @ !( Vec u ) String { F ( string_from msg ) }
}

// f32-LE → f16-LE, round-to-nearest-even per element.
@ gq_f16_encode ( Vec u ) f32le → !( Vec u ) String {
    : i nb ( vec_len [u] f32le )
    ? != % nb 4 0 { ^ ( __gq_err `gguf: f16 encode input is not whole f32 elements` ) } {}
    : i n / nb 4
    : *u P ( vec_data [u] f32le )
    : ( Vec u ) out ( vec_new [u] )
    : ~ i k 0
    ~ < k n {
        : i h ( f32_bits_to_f16_bits ( f32_to_bits # f32 ( __gq_f32 P k ) ) )
        ( vec_push [u] out # u & h 255 )
        ( vec_push [u] out # u & >> h 8 255 )
        = k + k 1
    }
    ^ @ !( Vec u ) String { T out }
}

// f32-LE → bf16-LE, round-to-nearest-even per element.
@ gq_bf16_encode ( Vec u ) f32le → !( Vec u ) String {
    : i nb ( vec_len [u] f32le )
    ? != % nb 4 0 { ^ ( __gq_err `gguf: bf16 encode input is not whole f32 elements` ) } {}
    : i n / nb 4
    : *u P ( vec_data [u] f32le )
    : ( Vec u ) out ( vec_new [u] )
    : ~ i k 0
    ~ < k n {
        : i h ( f32_bits_to_bf16_bits ( f32_to_bits # f32 ( __gq_f32 P k ) ) )
        ( vec_push [u] out # u & h 255 )
        ( vec_push [u] out # u & >> h 8 255 )
        = k + k 1
    }
    ^ @ !( Vec u ) String { T out }
}

// f32-LE → Q8_0 blocks: per 32 elements, d = amax/127 stored as f16,
// then 32 bytes of roundf(x * (127/amax)) two's-complement int8.
// ggml's quantize_row_q8_0_ref, including the id = d ? 1/d : 0 guard
// (an all-zero block stores d = 0 and 32 zero quants).
@ gq_q8_0_encode ( Vec u ) f32le → !( Vec u ) String {
    : i nb ( vec_len [u] f32le )
    ? != % nb 4 0 { ^ ( __gq_err `gguf: Q8_0 encode input is not whole f32 elements` ) } {}
    : i n / nb 4
    ? != % n 32 0 { ^ ( __gq_err `gguf: Q8_0 encode needs a multiple of 32 elements` ) } {}
    : *u P ( vec_data [u] f32le )
    : i nblk / n 32
    : ( Vec u ) out ( vec_new [u] )
    ( vec_reserve [u] out * nblk 34 )
    : ~ i b 0
    ~ < b nblk {
        : i base * b 32
        : ~ f amax 0.0
        : ~ i j 0
        ~ < j 32 {
            : f a ( fabs ( __gq_f32 P + base j ) )
            ? > a amax { = amax a } {}
            = j + j 1
        }
        // d is stored (and later decoded) as f16: quantise against the
        // f32 d exactly as ggml does — the f16 rounding of d is part of
        // the format's error budget, not of the encoder's arithmetic.
        : f d / amax 127.0
        : f id ? > d 0.0 / 1.0 d 0.0
        : i dh ( f_to_f16 d )
        ( vec_push [u] out # u & dh 255 )
        ( vec_push [u] out # u & >> dh 8 255 )
        = j 0
        ~ < j 32 {
            : f q ( round * ( __gq_f32 P + base j ) id )
            : ~ i qi # i q
            ? > qi 127 { = qi 127 } {}
            ? < qi -128 { = qi -128 } {}
            ( vec_push [u] out # u & qi 255 )
            = j + j 1
        }
        = b + b 1
    }
    ^ @ !( Vec u ) String { T out }
}
