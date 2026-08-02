// stdlib/std/x25519.nu — pure-NURL X25519 (RFC 7748) ECDH.
//
// No OpenSSL, no FFI: a self-contained Montgomery-ladder scalar
// multiplication over GF(2^255 − 19), so a NURL program can do the key
// exchange for TLS 1.3 / Noise / age with nothing installed on the host.
//
// The ladder is the well-trodden TweetNaCl one (Bernstein et al.); the
// field underneath it is the classic 32-bit curve25519 representation —
// ten signed 64-bit limbs at radix 2^25.5, carried with `__car25519`.
// Every branch is data-independent (the conditional swap is a constant-
// time mask), so the ladder runs in constant time w.r.t. the scalar.
//
// Public surface:
//   ( x25519 scalar point ) → ( Vec u )   scalar·point  (both 32 bytes)
//   ( x25519_base scalar )  → ( Vec u )   scalar·basepoint  (the pubkey)
//
// All inputs/outputs are 32-byte `( Vec u )`. Scalars are clamped
// internally per RFC 7748 §5, so any 32 random bytes is a valid secret.

$ `stdlib/core/vec.nu`

// ── tiny accessors ────────────────────────────────────────────────
// vec_get returns an option; in this module every index is in range by
// construction, so an out-of-range read (which cannot happen) reads 0.

@ _vget ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 }
}

@ _vset ( Vec i ) v i k i val → v {
    ( vec_set [i] v k val )
}

// The ladder's inner routines index their limbs through `*i` instead of
// the two accessors above. Every one of those loops is fixed-count over
// a ten-limb gf, so the bounds check is provably redundant — but it is a
// real call, and one X25519 scalar multiply makes 1280 field multiplies.
// Constant time is unaffected: the trip counts are fixed and the data
// takes no branch.

@ _x_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ _bset ( Vec u ) v i k i val → v {
    ( vec_set [u] v k # u & val 255 )
}

// n zeroed i64 limbs.
@ _zeros_i i n → ( Vec i ) {
    // Filled by index rather than pushed: a push carries a capacity check
    // a known length does not need.
    : ( Vec i ) v ( vec_with_cap [i] ? > n 0 n 1 )
    : b _l ( vec_set_len [i] v ? > n 0 n 0 )
    : *i q ( vec_data [i] v )
    : ~ i k 0
    ~ < k n { = . q k 0 = k + k 1 }
    ^ v
}

// n zeroed bytes.
@ _zeros_u i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    ^ v
}

// ── the field: ten limbs at radix 2^25.5 ──────────────────────────
// A field element is ten SIGNED limbs, limb i weighing 2^ceil(25.5·i) —
// alternately 26 and 25 bits. That is the classic 32-bit curve25519
// layout, and the reason for it is the multiply: sixteen 16-bit limbs
// (the TweetNaCl shape this module used to carry) need 16×16 = 256
// products, ten need 10×10 = 100, and a 26×26 → 52-bit product still
// leaves room to accumulate ten of them, times the 2 and 19 folding
// factors, inside a signed 64-bit limb — 2^57 at the worst point of a
// real ladder, measured, against a 2^63 ceiling.

// A fresh field element, all zero.
@ _gf_zero → ( Vec i ) { ^ ( _zeros_i 10 ) }

// Copy the ten limbs of `a` into a new gf.
@ _gf_copy ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) o ( _gf_zero )
    : *i op ( vec_data [i] o )
    : *i ap ( vec_data [i] a )
    : ~ i k 0
    ~ < k 10 { = . op k . ap k = k + k 1 }
    ^ o
}

// dst ← src (ten limbs), in place.
@ _gf_into ( Vec i ) dst ( Vec i ) src → v {
    : *i dp ( vec_data [i] dst )
    : *i sp ( vec_data [i] src )
    : ~ i k 0
    ~ < k 10 { = . dp k . sp k = k + k 1 }
}

// The constant 121665 as a gf — it fits limb 0 whole.
@ __gf_121665 → ( Vec i ) {
    : ( Vec i ) o ( _gf_zero )
    ( _vset o 0 121665 )
    ^ o
}

// Propagate carries so every limb is back within its width. The order is
// the reference one: the two halves are carried in parallel so each step
// depends on the step two back, not the one before it, and limb 9 wraps
// into limb 0 with the ×19 that 2^255 ≡ 19 gives.
@ __car25519 ( Vec i ) o → v {
    : *i op ( vec_data [i] o )
    : ~ i h0 . op 0
    : ~ i h1 . op 1
    : ~ i h2 . op 2
    : ~ i h3 . op 3
    : ~ i h4 . op 4
    : ~ i h5 . op 5
    : ~ i h6 . op 6
    : ~ i h7 . op 7
    : ~ i h8 . op 8
    : ~ i h9 . op 9
    : ~ i cc >> + h0 33554432 26
    = h1 + h1 cc
    = h0 - h0 << cc 26
    = cc >> + h4 33554432 26
    = h5 + h5 cc
    = h4 - h4 << cc 26
    = cc >> + h1 16777216 25
    = h2 + h2 cc
    = h1 - h1 << cc 25
    = cc >> + h5 16777216 25
    = h6 + h6 cc
    = h5 - h5 << cc 25
    = cc >> + h2 33554432 26
    = h3 + h3 cc
    = h2 - h2 << cc 26
    = cc >> + h6 33554432 26
    = h7 + h7 cc
    = h6 - h6 << cc 26
    = cc >> + h3 16777216 25
    = h4 + h4 cc
    = h3 - h3 << cc 25
    = cc >> + h7 16777216 25
    = h8 + h8 cc
    = h7 - h7 << cc 25
    = cc >> + h4 33554432 26
    = h5 + h5 cc
    = h4 - h4 << cc 26
    = cc >> + h8 33554432 26
    = h9 + h9 cc
    = h8 - h8 << cc 26
    = cc >> + h9 16777216 25
    = h0 + h0 * 19 cc
    = h9 - h9 << cc 25
    = cc >> + h0 33554432 26
    = h1 + h1 cc
    = h0 - h0 << cc 26
    = . op 0 h0
    = . op 1 h1
    = . op 2 h2
    = . op 3 h3
    = . op 4 h4
    = . op 5 h5
    = . op 6 h6
    = . op 7 h7
    = . op 8 h8
    = . op 9 h9
}

// Constant-time conditional swap of p and q when b = 1.
@ _sel25519 ( Vec i ) p ( Vec i ) q i b → v {
    : i c - 0 b
    : *i pp ( vec_data [i] p )
    : *i qp ( vec_data [i] q )
    : ~ i i 0
    ~ < i 10 {
        : i t & c ^^ . pp i . qp i
        = . pp i ^^ . pp i t
        = . qp i ^^ . qp i t
        = i + i 1
    }
}

// Decode 32 little-endian bytes into a gf (the top bit is dropped, per
// RFC 7748 §5). Limb i is the 25-or-26 bits starting at 2^ceil(25.5·i);
// five bytes always cover one limb whatever the bit offset, and a read
// past the end yields 0.
@ _unpack25519 ( Vec u ) n → ( Vec i ) {
    : ( Vec i ) o ( _gf_zero )
    : *i op ( vec_data [i] o )
    = . op 0 & >> | | | | ( _x_bget n 0 ) << ( _x_bget n 1 ) 8 << ( _x_bget n 2 ) 16 << ( _x_bget n 3 ) 24 << ( _x_bget n 4 ) 32 0 67108863
    = . op 1 & >> | | | | ( _x_bget n 3 ) << ( _x_bget n 4 ) 8 << ( _x_bget n 5 ) 16 << ( _x_bget n 6 ) 24 << ( _x_bget n 7 ) 32 2 33554431
    = . op 2 & >> | | | | ( _x_bget n 6 ) << ( _x_bget n 7 ) 8 << ( _x_bget n 8 ) 16 << ( _x_bget n 9 ) 24 << ( _x_bget n 10 ) 32 3 67108863
    = . op 3 & >> | | | | ( _x_bget n 9 ) << ( _x_bget n 10 ) 8 << ( _x_bget n 11 ) 16 << ( _x_bget n 12 ) 24 << ( _x_bget n 13 ) 32 5 33554431
    = . op 4 & >> | | | | ( _x_bget n 12 ) << ( _x_bget n 13 ) 8 << ( _x_bget n 14 ) 16 << ( _x_bget n 15 ) 24 << ( _x_bget n 16 ) 32 6 67108863
    = . op 5 & >> | | | | ( _x_bget n 16 ) << ( _x_bget n 17 ) 8 << ( _x_bget n 18 ) 16 << ( _x_bget n 19 ) 24 << ( _x_bget n 20 ) 32 0 33554431
    = . op 6 & >> | | | | ( _x_bget n 19 ) << ( _x_bget n 20 ) 8 << ( _x_bget n 21 ) 16 << ( _x_bget n 22 ) 24 << ( _x_bget n 23 ) 32 1 67108863
    = . op 7 & >> | | | | ( _x_bget n 22 ) << ( _x_bget n 23 ) 8 << ( _x_bget n 24 ) 16 << ( _x_bget n 25 ) 24 << ( _x_bget n 26 ) 32 3 33554431
    = . op 8 & >> | | | | ( _x_bget n 25 ) << ( _x_bget n 26 ) 8 << ( _x_bget n 27 ) 16 << ( _x_bget n 28 ) 24 << ( _x_bget n 29 ) 32 4 67108863
    = . op 9 & >> | | | | ( _x_bget n 28 ) << ( _x_bget n 29 ) 8 << ( _x_bget n 30 ) 16 << ( _x_bget n 31 ) 24 << ( _x_bget n 32 ) 32 6 33554431
    ^ o
}

// Fully reduce `n` mod 2^255−19 and emit 32 little-endian bytes.
// The leading pass computes q, the number of times p divides the value
// (0 or 1 for a carried input), by running the carry chain's shifts
// against p's own limbs; adding 19·q then puts the value in [0, p) and
// a plain non-negative carry chain makes every limb canonical.
@ _pack25519 ( Vec i ) n → ( Vec u ) {
    : *i np ( vec_data [i] n )
    : ~ i h0 . np 0
    : ~ i h1 . np 1
    : ~ i h2 . np 2
    : ~ i h3 . np 3
    : ~ i h4 . np 4
    : ~ i h5 . np 5
    : ~ i h6 . np 6
    : ~ i h7 . np 7
    : ~ i h8 . np 8
    : ~ i h9 . np 9
    : ~ i q >> + * 19 h9 16777216 25
    = q >> + h0 q 26
    = q >> + h1 q 25
    = q >> + h2 q 26
    = q >> + h3 q 25
    = q >> + h4 q 26
    = q >> + h5 q 25
    = q >> + h6 q 26
    = q >> + h7 q 25
    = q >> + h8 q 26
    = q >> + h9 q 25
    = h0 + h0 * 19 q
    : ~ i cc 0
    = cc >> h0 26
    = h1 + h1 cc
    = h0 - h0 << cc 26
    = cc >> h1 25
    = h2 + h2 cc
    = h1 - h1 << cc 25
    = cc >> h2 26
    = h3 + h3 cc
    = h2 - h2 << cc 26
    = cc >> h3 25
    = h4 + h4 cc
    = h3 - h3 << cc 25
    = cc >> h4 26
    = h5 + h5 cc
    = h4 - h4 << cc 26
    = cc >> h5 25
    = h6 + h6 cc
    = h5 - h5 << cc 25
    = cc >> h6 26
    = h7 + h7 cc
    = h6 - h6 << cc 26
    = cc >> h7 25
    = h8 + h8 cc
    = h7 - h7 << cc 25
    = cc >> h8 26
    = h9 + h9 cc
    = h8 - h8 << cc 26
    = cc >> h9 25
    = h9 - h9 << cc 25
    : ( Vec u ) o ( _zeros_u 32 )
    ( _bset o 0 & >> h0 0 255 )
    ( _bset o 1 & >> h0 8 255 )
    ( _bset o 2 & >> h0 16 255 )
    ( _bset o 3 & + >> h0 24 << h1 2 255 )
    ( _bset o 4 & >> h1 6 255 )
    ( _bset o 5 & >> h1 14 255 )
    ( _bset o 6 & + >> h1 22 << h2 3 255 )
    ( _bset o 7 & >> h2 5 255 )
    ( _bset o 8 & >> h2 13 255 )
    ( _bset o 9 & + >> h2 21 << h3 5 255 )
    ( _bset o 10 & >> h3 3 255 )
    ( _bset o 11 & >> h3 11 255 )
    ( _bset o 12 & + >> h3 19 << h4 6 255 )
    ( _bset o 13 & >> h4 2 255 )
    ( _bset o 14 & >> h4 10 255 )
    ( _bset o 15 & >> h4 18 255 )
    ( _bset o 16 & >> h5 0 255 )
    ( _bset o 17 & >> h5 8 255 )
    ( _bset o 18 & >> h5 16 255 )
    ( _bset o 19 & + >> h5 24 << h6 1 255 )
    ( _bset o 20 & >> h6 7 255 )
    ( _bset o 21 & >> h6 15 255 )
    ( _bset o 22 & + >> h6 23 << h7 3 255 )
    ( _bset o 23 & >> h7 5 255 )
    ( _bset o 24 & >> h7 13 255 )
    ( _bset o 25 & + >> h7 21 << h8 4 255 )
    ( _bset o 26 & >> h8 4 255 )
    ( _bset o 27 & >> h8 12 255 )
    ( _bset o 28 & + >> h8 20 << h9 6 255 )
    ( _bset o 29 & >> h9 2 255 )
    ( _bset o 30 & >> h9 10 255 )
    ( _bset o 31 & >> h9 18 255 )
    ^ o
}

// ── field ops (write into dst; aliasing-safe) ─────────────────────
@ _A ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : *i op ( vec_data [i] o )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : ~ i i 0
    ~ < i 10 { = . op i + . ap i . bp i = i + i 1 }
}

@ _Z ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : *i op ( vec_data [i] o )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : ~ i i 0
    ~ < i 10 { = . op i - . ap i . bp i = i + i 1 }
}

// o ← a·b mod 2^255−19. Schoolbook over the ten limbs, with the two
// coefficient shapes folded into the OPERANDS instead of the terms:
//   * a product of two odd-indexed limbs lands one bit low, because
//     ceil(25.5j) + ceil(25.5k) = ceil(25.5(j+k)) + 1 when both are odd,
//     so it is taken against a pre-doubled `f`;
//   * a product that runs past limb 9 wraps by 2^255 ≡ 19, so it is
//     taken against a pre-nineteened `g`.
// Each of the hundred terms is then a single multiply, and the doublings
// and ×19s are five and ten cheap ops done once. Operands are read into
// locals before anything is written, so `o` may alias `a` or `b`.
@ _M ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : *i fp ( vec_data [i] a )
    : *i gp ( vec_data [i] b )
    : i f0 . fp 0
    : i f1 . fp 1
    : i f2 . fp 2
    : i f3 . fp 3
    : i f4 . fp 4
    : i f5 . fp 5
    : i f6 . fp 6
    : i f7 . fp 7
    : i f8 . fp 8
    : i f9 . fp 9
    : i f1_2 * 2 f1
    : i f3_2 * 2 f3
    : i f5_2 * 2 f5
    : i f7_2 * 2 f7
    : i f9_2 * 2 f9
    : i g0 . gp 0
    : i g1 . gp 1
    : i g2 . gp 2
    : i g3 . gp 3
    : i g4 . gp 4
    : i g5 . gp 5
    : i g6 . gp 6
    : i g7 . gp 7
    : i g8 . gp 8
    : i g9 . gp 9
    : i g0_19 * 19 g0
    : i g1_19 * 19 g1
    : i g2_19 * 19 g2
    : i g3_19 * 19 g3
    : i g4_19 * 19 g4
    : i g5_19 * 19 g5
    : i g6_19 * 19 g6
    : i g7_19 * 19 g7
    : i g8_19 * 19 g8
    : i g9_19 * 19 g9
    : ~ i h0 + + + + + + + + + * f0 g0 * f1_2 g9_19 * f2 g8_19 * f3_2 g7_19 * f4 g6_19 * f5_2 g5_19 * f6 g4_19 * f7_2 g3_19 * f8 g2_19 * f9_2 g1_19
    : ~ i h1 + + + + + + + + + * f0 g1 * f1 g0 * f2 g9_19 * f3 g8_19 * f4 g7_19 * f5 g6_19 * f6 g5_19 * f7 g4_19 * f8 g3_19 * f9 g2_19
    : ~ i h2 + + + + + + + + + * f0 g2 * f1_2 g1 * f2 g0 * f3_2 g9_19 * f4 g8_19 * f5_2 g7_19 * f6 g6_19 * f7_2 g5_19 * f8 g4_19 * f9_2 g3_19
    : ~ i h3 + + + + + + + + + * f0 g3 * f1 g2 * f2 g1 * f3 g0 * f4 g9_19 * f5 g8_19 * f6 g7_19 * f7 g6_19 * f8 g5_19 * f9 g4_19
    : ~ i h4 + + + + + + + + + * f0 g4 * f1_2 g3 * f2 g2 * f3_2 g1 * f4 g0 * f5_2 g9_19 * f6 g8_19 * f7_2 g7_19 * f8 g6_19 * f9_2 g5_19
    : ~ i h5 + + + + + + + + + * f0 g5 * f1 g4 * f2 g3 * f3 g2 * f4 g1 * f5 g0 * f6 g9_19 * f7 g8_19 * f8 g7_19 * f9 g6_19
    : ~ i h6 + + + + + + + + + * f0 g6 * f1_2 g5 * f2 g4 * f3_2 g3 * f4 g2 * f5_2 g1 * f6 g0 * f7_2 g9_19 * f8 g8_19 * f9_2 g7_19
    : ~ i h7 + + + + + + + + + * f0 g7 * f1 g6 * f2 g5 * f3 g4 * f4 g3 * f5 g2 * f6 g1 * f7 g0 * f8 g9_19 * f9 g8_19
    : ~ i h8 + + + + + + + + + * f0 g8 * f1_2 g7 * f2 g6 * f3_2 g5 * f4 g4 * f5_2 g3 * f6 g2 * f7_2 g1 * f8 g0 * f9_2 g9_19
    : ~ i h9 + + + + + + + + + * f0 g9 * f1 g8 * f2 g7 * f3 g6 * f4 g5 * f5 g4 * f6 g3 * f7 g2 * f8 g1 * f9 g0
    : ~ i cc >> + h0 33554432 26
    = h1 + h1 cc
    = h0 - h0 << cc 26
    = cc >> + h4 33554432 26
    = h5 + h5 cc
    = h4 - h4 << cc 26
    = cc >> + h1 16777216 25
    = h2 + h2 cc
    = h1 - h1 << cc 25
    = cc >> + h5 16777216 25
    = h6 + h6 cc
    = h5 - h5 << cc 25
    = cc >> + h2 33554432 26
    = h3 + h3 cc
    = h2 - h2 << cc 26
    = cc >> + h6 33554432 26
    = h7 + h7 cc
    = h6 - h6 << cc 26
    = cc >> + h3 16777216 25
    = h4 + h4 cc
    = h3 - h3 << cc 25
    = cc >> + h7 16777216 25
    = h8 + h8 cc
    = h7 - h7 << cc 25
    = cc >> + h4 33554432 26
    = h5 + h5 cc
    = h4 - h4 << cc 26
    = cc >> + h8 33554432 26
    = h9 + h9 cc
    = h8 - h8 << cc 26
    = cc >> + h9 16777216 25
    = h0 + h0 * 19 cc
    = h9 - h9 << cc 25
    = cc >> + h0 33554432 26
    = h1 + h1 cc
    = h0 - h0 << cc 26
    : *i op ( vec_data [i] o )
    = . op 0 h0
    = . op 1 h1
    = . op 2 h2
    = . op 3 h3
    = . op 4 h4
    = . op 5 h5
    = . op 6 h6
    = . op 7 h7
    = . op 8 h8
    = . op 9 h9
}

@ _S ( Vec i ) o ( Vec i ) a → v { ( _M o a a ) }

// io ← io^(p-2) = io^-1  (Fermat inversion, 254 squarings).
@ _inv25519 ( Vec i ) io → v {
    : ( Vec i ) inp ( _gf_copy io )
    : ( Vec i ) c ( _gf_copy io )
    : ~ i a 253
    ~ >= a 0 {
        ( _S c c )
        ? & != a 2 != a 4 { ( _M c c inp ) } {}
        = a - a 1
    }
    ( _gf_into io c )
    ( vec_free [i] inp )
    ( vec_free [i] c )
}

// ── the ladder ────────────────────────────────────────────────────
// q ← scalar · point, both 32-byte little-endian. Scalar is clamped.
@ __scalarmult ( Vec u ) scalar ( Vec u ) point → ( Vec u ) {
    : ( Vec u ) z ( _zeros_u 32 )
    : ~ i k 0
    ~ < k 32 { ( _bset z k ( _x_bget scalar k ) ) = k + k 1 }
    ( _bset z 31 | & ( _x_bget scalar 31 ) 127 64 )
    ( _bset z 0 & ( _x_bget scalar 0 ) 248 )

    : ( Vec i ) x ( _unpack25519 point )
    : ( Vec i ) a ( _gf_zero )
    : ( Vec i ) b ( _gf_copy x )
    : ( Vec i ) c ( _gf_zero )
    : ( Vec i ) d ( _gf_zero )
    : ( Vec i ) e ( _gf_zero )
    : ( Vec i ) f ( _gf_zero )
    : ( Vec i ) k121665 ( __gf_121665 )
    ( _vset a 0 1 )
    ( _vset d 0 1 )

    : ~ i i 254
    ~ >= i 0 {
        : i r & >> ( _x_bget z >> i 3 ) & i 7 1
        ( _sel25519 a b r )
        ( _sel25519 c d r )
        ( _A e a c )
        ( _Z a a c )
        ( _A c b d )
        ( _Z b b d )
        ( _S d e )
        ( _S f a )
        ( _M a c a )
        ( _M c b e )
        ( _A e a c )
        ( _Z a a c )
        ( _S b a )
        ( _Z c d f )
        ( _M a c k121665 )
        ( _A a a d )
        ( _M c c a )
        ( _M a d f )
        ( _M d b x )
        ( _S b e )
        ( _sel25519 a b r )
        ( _sel25519 c d r )
        = i - i 1
    }

    // Recover the affine X-coordinate: x2 · z2^-1. (a = x2, c = z2.)
    ( _inv25519 c )
    ( _M a a c )
    : ( Vec u ) out ( _pack25519 a )

    ( vec_free [i] x )
    ( vec_free [i] a )
    ( vec_free [i] b )
    ( vec_free [i] c )
    ( vec_free [i] d )
    ( vec_free [i] e )
    ( vec_free [i] f )
    ( vec_free [i] k121665 )
    ( vec_free [u] z )
    ^ out
}

// scalar · point — the ECDH primitive. `scalar` and `point` are 32-byte
// little-endian `( Vec u )`; the result is the 32-byte shared X-coord.
@ x25519 ( Vec u ) scalar ( Vec u ) point → ( Vec u ) {
    ^ ( __scalarmult scalar point )
}

// scalar · basepoint(9) — derive the public key from a 32-byte secret.
@ x25519_base ( Vec u ) scalar → ( Vec u ) {
    : ( Vec u ) base ( _zeros_u 32 )
    ( _bset base 0 9 )
    : ( Vec u ) out ( __scalarmult scalar base )
    ( vec_free [u] base )
    ^ out
}
