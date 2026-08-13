// stdlib/std/x25519.nu — pure-NURL X25519 (RFC 7748) ECDH.
//
// No OpenSSL, no FFI: a self-contained Montgomery-ladder scalar
// multiplication over GF(2^255 − 19), so a NURL program can do the key
// exchange for TLS 1.3 / Noise / age with nothing installed on the host.
//
// The ladder is the well-trodden TweetNaCl one (Bernstein et al.); the
// field underneath it is curve25519-donna-c64 — five unsigned 64-bit
// limbs at radix 2^51, each product a full 64×64→128 multiply via
// nurl_umulhi. Every branch is data-independent (the conditional swap is
// a constant-time mask), so the ladder runs in constant time w.r.t. the
// scalar.
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

// ── the field: five limbs at radix 2^51 ───────────────────────────
// A field element is FIVE unsigned limbs, limb i weighing 2^(51·i). This
// is curve25519-donna-c64 (Bernstein/Langley): each limb·limb term is a
// full 64×64→128 product (nurl_umulhi gives the high half NURL's `*`
// drops), so the multiply is 5×5 = 25 products against the 10×10 = 100
// the old radix-2^25.5 form ran, and the square 15. The reduction folds
// 2^255 ≡ 19 straight into the product limbs. Values stay below ~2^54, so
// each limb sits in an i64 as a plain non-negative bit pattern; the
// multiply reads them back as u64.
//
// M51 = 2^51−1 = 2251799813685247 recurs as the limb mask throughout.

// A fresh field element, all zero.
@ _gf_zero → ( Vec i ) { ^ ( _zeros_i 5 ) }

// Copy the five limbs of `a` into a new gf.
@ _gf_copy ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) o ( _gf_zero )
    : *i op ( vec_data [i] o )
    : *i ap ( vec_data [i] a )
    : ~ i k 0
    ~ < k 5 { = . op k . ap k = k + k 1 }
    ^ o
}

// dst ← src (five limbs), in place.
@ _gf_into ( Vec i ) dst ( Vec i ) src → v {
    : *i dp ( vec_data [i] dst )
    : *i sp ( vec_data [i] src )
    : ~ i k 0
    ~ < k 5 { = . dp k . sp k = k + k 1 }
}

// The constant 121665 as a gf — it fits limb 0 whole. The ladder's
// `( _M a c k121665 )` is a full field multiply by this element, which is
// exactly a·121665, so keeping it as a gf leaves the ladder untouched.
@ __gf_121665 → ( Vec i ) {
    : ( Vec i ) o ( _gf_zero )
    ( _vset o 0 121665 )
    ^ o
}

// Constant-time conditional swap of p and q when b = 1.
@ _sel25519 ( Vec i ) p ( Vec i ) q i b → v {
    : i c - 0 b
    : *i pp ( vec_data [i] p )
    : *i qp ( vec_data [i] q )
    : ~ i i 0
    ~ < i 5 {
        : i t & c ^^ . pp i . qp i
        = . pp i ^^ . pp i t
        = . qp i ^^ . qp i t
        = i + i 1
    }
}

// Little-endian 64-bit load of the 8 bytes at n[off..off+7].
@ _ld64u ( Vec u ) n i off → i {
    : i lo | | | ( _x_bget n off ) << ( _x_bget n + off 1 ) 8 << ( _x_bget n + off 2 ) 16 << ( _x_bget n + off 3 ) 24
    : i hi | | | ( _x_bget n + off 4 ) << ( _x_bget n + off 5 ) 8 << ( _x_bget n + off 6 ) 16 << ( _x_bget n + off 7 ) 24
    ^ | lo << hi 32
}

// Decode 32 little-endian bytes into a gf (top bit dropped, per RFC 7748
// §5). Five overlapping 64-bit loads, each shifted to its limb boundary
// and masked to 51 bits (donna-c64 fexpand).
@ _unpack25519 ( Vec u ) n → ( Vec i ) {
    : ( Vec i ) o ( _gf_zero )
    : *i op ( vec_data [i] o )
    = . op 0 # i & # u64 ( _ld64u n 0 ) 2251799813685247
    = . op 1 # i & >> # u64 ( _ld64u n 6 ) 3 2251799813685247
    = . op 2 # i & >> # u64 ( _ld64u n 12 ) 6 2251799813685247
    = . op 3 # i & >> # u64 ( _ld64u n 19 ) 1 2251799813685247
    = . op 4 # i & >> # u64 ( _ld64u n 24 ) 12 2251799813685247
    ^ o
}

// Fully reduce `n` mod 2^255−19 and emit 32 little-endian bytes
// (donna-c64 fcontract). Two fold-carries bring the value below 2^255;
// adding 19 then (2^255 − 19) resolves the single "is it ≥ p" case in
// constant time; the final carry has no ×19 fold, so masking limb 4 drops
// the 2^255 bit and leaves the canonical residue. The five 51-bit limbs
// are then repacked into four 64-bit words and emitted as bytes.
@ _pack25519 ( Vec i ) n → ( Vec u ) {
    : *i np ( vec_data [i] n )
    : ~ u64 h0 # u64 . np 0
    : ~ u64 h1 # u64 . np 1
    : ~ u64 h2 # u64 . np 2
    : ~ u64 h3 # u64 . np 3
    : ~ u64 h4 # u64 . np 4
    : ~ i pass 0
    ~ < pass 2 {
        = h1 + h1 >> h0 51 = h0 & h0 2251799813685247
        = h2 + h2 >> h1 51 = h1 & h1 2251799813685247
        = h3 + h3 >> h2 51 = h2 & h2 2251799813685247
        = h4 + h4 >> h3 51 = h3 & h3 2251799813685247
        = h0 + h0 * 19 >> h4 51 = h4 & h4 2251799813685247
        = pass + pass 1
    }
    = h0 + h0 19
    = h1 + h1 >> h0 51 = h0 & h0 2251799813685247
    = h2 + h2 >> h1 51 = h1 & h1 2251799813685247
    = h3 + h3 >> h2 51 = h2 & h2 2251799813685247
    = h4 + h4 >> h3 51 = h3 & h3 2251799813685247
    = h0 + h0 * 19 >> h4 51 = h4 & h4 2251799813685247
    = h0 + h0 2251799813685229
    = h1 + h1 2251799813685247
    = h2 + h2 2251799813685247
    = h3 + h3 2251799813685247
    = h4 + h4 2251799813685247
    = h1 + h1 >> h0 51 = h0 & h0 2251799813685247
    = h2 + h2 >> h1 51 = h1 & h1 2251799813685247
    = h3 + h3 >> h2 51 = h2 & h2 2251799813685247
    = h4 + h4 >> h3 51 = h3 & h3 2251799813685247
    = h4 & h4 2251799813685247
    // Repack the five 51-bit limbs into four 64-bit words (u64 shifts wrap
    // to the correct low bits), then emit each word little-endian.
    : u64 w0 | h0 << h1 51
    : u64 w1 | >> h1 13 << h2 38
    : u64 w2 | >> h2 26 << h3 25
    : u64 w3 | >> h3 39 << h4 12
    : ( Vec u ) o ( _zeros_u 32 )
    : ~ i k 0
    ~ < k 8 {
        ( _bset o k # i & >> w0 * 8 k 255 )
        ( _bset o + k 8 # i & >> w1 * 8 k 255 )
        ( _bset o + k 16 # i & >> w2 * 8 k 255 )
        ( _bset o + k 24 # i & >> w3 * 8 k 255 )
        = k + k 1
    }
    ^ o
}

// ── field ops (write into dst; aliasing-safe) ─────────────────────
// _A / _Z read every operand limb before writing dst, so dst may alias a
// or b. _M / _S read all inputs into locals first, same guarantee.

// o ← a + b (limbwise; limbs grow, the next multiply carries them).
@ _A ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : *i op ( vec_data [i] o )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : ~ i i 0
    ~ < i 5 { = . op i + . ap i . bp i = i + i 1 }
}

// o ← a − b mod p. Add 2p limbwise before subtracting so no limb goes
// negative (donna-c64 fdifference_backwards): 2p = [2^52−38, 2^52−2, …].
@ _Z ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : *i op ( vec_data [i] o )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    = . op 0 - + . ap 0 4503599627370458 . bp 0
    = . op 1 - + . ap 1 4503599627370494 . bp 1
    = . op 2 - + . ap 2 4503599627370494 . bp 2
    = . op 3 - + . ap 3 4503599627370494 . bp 3
    = . op 4 - + . ap 4 4503599627370494 . bp 4
}

// o ← a · b mod 2^255−19. Schoolbook over the five limbs; each t[i] is a
// 128-bit sum of products held as an (lo, hi) pair (nurl_umulhi high
// half), with the 2^255 ≡ 19 wrap folded into the r1..r4 factors. Then
// one carry pass reduces the ten 128-bit words back to five 51-bit limbs.
@ _M ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : u64 r0 # u64 . ap 0
    : u64 r1 # u64 . ap 1
    : u64 r2 # u64 . ap 2
    : u64 r3 # u64 . ap 3
    : u64 r4 # u64 . ap 4
    : u64 s0 # u64 . bp 0
    : u64 s1 # u64 . bp 1
    : u64 s2 # u64 . bp 2
    : u64 s3 # u64 . bp 3
    : u64 s4 # u64 . bp 4
    : u64 f1 * r1 19
    : u64 f2 * r2 19
    : u64 f3 * r3 19
    : u64 f4 * r4 19
    : ~ u64 pl 0
    : ~ u64 ph 0
    // t0 = r0·s0 + f4·s1 + f1·s4 + f2·s3 + f3·s2
    : ~ u64 l0 * r0 s0
    : ~ u64 h0 ( nurl_umulhi r0 s0 )
    = pl * f4 s1 = ph ( nurl_umulhi f4 s1 ) = l0 + l0 pl = h0 + + h0 ph ? < l0 pl 1 0
    = pl * f1 s4 = ph ( nurl_umulhi f1 s4 ) = l0 + l0 pl = h0 + + h0 ph ? < l0 pl 1 0
    = pl * f2 s3 = ph ( nurl_umulhi f2 s3 ) = l0 + l0 pl = h0 + + h0 ph ? < l0 pl 1 0
    = pl * f3 s2 = ph ( nurl_umulhi f3 s2 ) = l0 + l0 pl = h0 + + h0 ph ? < l0 pl 1 0
    // t1 = r0·s1 + r1·s0 + f4·s2 + f2·s4 + f3·s3
    : ~ u64 l1 * r0 s1
    : ~ u64 h1 ( nurl_umulhi r0 s1 )
    = pl * r1 s0 = ph ( nurl_umulhi r1 s0 ) = l1 + l1 pl = h1 + + h1 ph ? < l1 pl 1 0
    = pl * f4 s2 = ph ( nurl_umulhi f4 s2 ) = l1 + l1 pl = h1 + + h1 ph ? < l1 pl 1 0
    = pl * f2 s4 = ph ( nurl_umulhi f2 s4 ) = l1 + l1 pl = h1 + + h1 ph ? < l1 pl 1 0
    = pl * f3 s3 = ph ( nurl_umulhi f3 s3 ) = l1 + l1 pl = h1 + + h1 ph ? < l1 pl 1 0
    // t2 = r0·s2 + r1·s1 + r2·s0 + f4·s3 + f3·s4
    : ~ u64 l2 * r0 s2
    : ~ u64 h2 ( nurl_umulhi r0 s2 )
    = pl * r1 s1 = ph ( nurl_umulhi r1 s1 ) = l2 + l2 pl = h2 + + h2 ph ? < l2 pl 1 0
    = pl * r2 s0 = ph ( nurl_umulhi r2 s0 ) = l2 + l2 pl = h2 + + h2 ph ? < l2 pl 1 0
    = pl * f4 s3 = ph ( nurl_umulhi f4 s3 ) = l2 + l2 pl = h2 + + h2 ph ? < l2 pl 1 0
    = pl * f3 s4 = ph ( nurl_umulhi f3 s4 ) = l2 + l2 pl = h2 + + h2 ph ? < l2 pl 1 0
    // t3 = r0·s3 + r1·s2 + r2·s1 + r3·s0 + f4·s4
    : ~ u64 l3 * r0 s3
    : ~ u64 h3 ( nurl_umulhi r0 s3 )
    = pl * r1 s2 = ph ( nurl_umulhi r1 s2 ) = l3 + l3 pl = h3 + + h3 ph ? < l3 pl 1 0
    = pl * r2 s1 = ph ( nurl_umulhi r2 s1 ) = l3 + l3 pl = h3 + + h3 ph ? < l3 pl 1 0
    = pl * r3 s0 = ph ( nurl_umulhi r3 s0 ) = l3 + l3 pl = h3 + + h3 ph ? < l3 pl 1 0
    = pl * f4 s4 = ph ( nurl_umulhi f4 s4 ) = l3 + l3 pl = h3 + + h3 ph ? < l3 pl 1 0
    // t4 = r0·s4 + r1·s3 + r2·s2 + r3·s1 + r4·s0
    : ~ u64 l4 * r0 s4
    : ~ u64 h4 ( nurl_umulhi r0 s4 )
    = pl * r1 s3 = ph ( nurl_umulhi r1 s3 ) = l4 + l4 pl = h4 + + h4 ph ? < l4 pl 1 0
    = pl * r2 s2 = ph ( nurl_umulhi r2 s2 ) = l4 + l4 pl = h4 + + h4 ph ? < l4 pl 1 0
    = pl * r3 s1 = ph ( nurl_umulhi r3 s1 ) = l4 + l4 pl = h4 + + h4 ph ? < l4 pl 1 0
    = pl * r4 s0 = ph ( nurl_umulhi r4 s0 ) = l4 + l4 pl = h4 + + h4 ph ? < l4 pl 1 0
    ( __mul_carry_out o l0 h0 l1 h1 l2 h2 l3 h3 l4 h4 )
}

// o ← a² mod 2^255−19. donna-c64 fsquare: the cross terms are doubled
// once via d0..d4 instead of appearing twice, so 15 products, not 25.
@ _S ( Vec i ) o ( Vec i ) a → v {
    : *i ap ( vec_data [i] a )
    : u64 r0 # u64 . ap 0
    : u64 r1 # u64 . ap 1
    : u64 r2 # u64 . ap 2
    : u64 r3 # u64 . ap 3
    : u64 r4 # u64 . ap 4
    : u64 d0 * r0 2
    : u64 d1 * r1 2
    : u64 d2 * r2 38
    : u64 d419 * r4 19
    : u64 d4 * d419 2
    : u64 r319 * r3 19
    : ~ u64 pl 0
    : ~ u64 ph 0
    // t0 = r0·r0 + d4·r1 + d2·r3
    : ~ u64 l0 * r0 r0
    : ~ u64 h0 ( nurl_umulhi r0 r0 )
    = pl * d4 r1 = ph ( nurl_umulhi d4 r1 ) = l0 + l0 pl = h0 + + h0 ph ? < l0 pl 1 0
    = pl * d2 r3 = ph ( nurl_umulhi d2 r3 ) = l0 + l0 pl = h0 + + h0 ph ? < l0 pl 1 0
    // t1 = d0·r1 + d4·r2 + r3·(r3·19)
    : ~ u64 l1 * d0 r1
    : ~ u64 h1 ( nurl_umulhi d0 r1 )
    = pl * d4 r2 = ph ( nurl_umulhi d4 r2 ) = l1 + l1 pl = h1 + + h1 ph ? < l1 pl 1 0
    = pl * r3 r319 = ph ( nurl_umulhi r3 r319 ) = l1 + l1 pl = h1 + + h1 ph ? < l1 pl 1 0
    // t2 = d0·r2 + r1·r1 + d4·r3
    : ~ u64 l2 * d0 r2
    : ~ u64 h2 ( nurl_umulhi d0 r2 )
    = pl * r1 r1 = ph ( nurl_umulhi r1 r1 ) = l2 + l2 pl = h2 + + h2 ph ? < l2 pl 1 0
    = pl * d4 r3 = ph ( nurl_umulhi d4 r3 ) = l2 + l2 pl = h2 + + h2 ph ? < l2 pl 1 0
    // t3 = d0·r3 + d1·r2 + r4·d419
    : ~ u64 l3 * d0 r3
    : ~ u64 h3 ( nurl_umulhi d0 r3 )
    = pl * d1 r2 = ph ( nurl_umulhi d1 r2 ) = l3 + l3 pl = h3 + + h3 ph ? < l3 pl 1 0
    = pl * r4 d419 = ph ( nurl_umulhi r4 d419 ) = l3 + l3 pl = h3 + + h3 ph ? < l3 pl 1 0
    // t4 = d0·r4 + d1·r3 + r2·r2
    : ~ u64 l4 * d0 r4
    : ~ u64 h4 ( nurl_umulhi d0 r4 )
    = pl * d1 r3 = ph ( nurl_umulhi d1 r3 ) = l4 + l4 pl = h4 + + h4 ph ? < l4 pl 1 0
    = pl * r2 r2 = ph ( nurl_umulhi r2 r2 ) = l4 + l4 pl = h4 + + h4 ph ? < l4 pl 1 0
    ( __mul_carry_out o l0 h0 l1 h1 l2 h2 l3 h3 l4 h4 )
}

// Shared reduction tail: five 128-bit accumulators (lo,hi) → five 51-bit
// limbs, carrying c = t[i] >> 51 up the chain and folding the top ×19.
@ __mul_carry_out ( Vec i ) o u64 pl0 u64 ph0 u64 pl1 u64 ph1 u64 pl2 u64 ph2 u64 pl3 u64 ph3 u64 pl4 u64 ph4 → v {
    : ~ u64 l0 pl0
    : ~ u64 h0 ph0
    : ~ u64 l1 pl1
    : ~ u64 h1 ph1
    : ~ u64 l2 pl2
    : ~ u64 h2 ph2
    : ~ u64 l3 pl3
    : ~ u64 h3 ph3
    : ~ u64 l4 pl4
    : ~ u64 h4 ph4
    : ~ u64 c 0
    : ~ u64 g0 & l0 2251799813685247
    = c | << h0 13 >> l0 51
    = l1 + l1 c = h1 + h1 ? < l1 c 1 0
    : ~ u64 g1 & l1 2251799813685247
    = c | << h1 13 >> l1 51
    = l2 + l2 c = h2 + h2 ? < l2 c 1 0
    : ~ u64 g2 & l2 2251799813685247
    = c | << h2 13 >> l2 51
    = l3 + l3 c = h3 + h3 ? < l3 c 1 0
    : ~ u64 g3 & l3 2251799813685247
    = c | << h3 13 >> l3 51
    = l4 + l4 c = h4 + h4 ? < l4 c 1 0
    : ~ u64 g4 & l4 2251799813685247
    = c | << h4 13 >> l4 51
    = g0 + g0 * c 19
    = c >> g0 51 = g0 & g0 2251799813685247
    = g1 + g1 c
    = c >> g1 51 = g1 & g1 2251799813685247
    = g2 + g2 c
    : *i op ( vec_data [i] o )
    = . op 0 # i g0
    = . op 1 # i g1
    = . op 2 # i g2
    = . op 3 # i g3
    = . op 4 # i g4
}

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
// ── fixed-base comb for the keygen basepoint (X25519 public key) ──────
// scalar·9 on the Montgomery curve equals scalar·B on the birationally
// equivalent Ed25519 curve (B ↦ u=9), and the twisted-Edwards complete
// addition makes a constant-time fixed-base comb clean where the
// Montgomery x-only ladder cannot. So the ephemeral public key is
// scalar·B on Edwards via a 4-tooth comb (baked table, no per-call
// build), then u = (Z+Y)/(Z−Y). Verified against the ladder for the
// RFC 7748 vectors. Fixed-base only — the variable-base
// x25519(scalar, peer) ECDH stays on the Montgomery ladder above.

: XEP { ( Vec i ) x ( Vec i ) y ( Vec i ) z ( Vec i ) t }
: XEScr { ( Vec i ) a ( Vec i ) b ( Vec i ) c ( Vec i ) d ( Vec i ) e ( Vec i ) f ( Vec i ) g ( Vec i ) h ( Vec i ) tt }

@ __xe_pt → XEP { ^ @ XEP { ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) } }

@ __xe_pt_free XEP p → v { ( vec_free [i] . p x ) ( vec_free [i] . p y ) ( vec_free [i] . p z ) ( vec_free [i] . p t ) }

@ __xe_scr → XEScr { ^ @ XEScr { ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) } }

@ __xe_scr_free XEScr s → v {
    ( vec_free [i] . s a ) ( vec_free [i] . s b ) ( vec_free [i] . s c ) ( vec_free [i] . s d ) ( vec_free [i] . s e )
    ( vec_free [i] . s f ) ( vec_free [i] . s g ) ( vec_free [i] . s h ) ( vec_free [i] . s tt )
}

// 2d, the Ed25519 addition constant, baked as five 2^51 limbs.
@ __xe_d2 → ( Vec i ) {
    : ( Vec i ) v ( _gf_zero )
    : *i q ( vec_data [i] v )
    = . q 0 # i 1859910466990425 = . q 1 # i 932731440258426 = . q 2 # i 1072319116312658
    = . q 3 # i 1815898335770999 = . q 4 # i 633789495995903
    ^ v
}

@ __xe_comb_table → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 320 )
    : b _l ( vec_set_len [i] v 320 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0 = . q 1 # i 0 = . q 2 # i 0 = . q 3 # i 0
    = . q 4 # i 0 = . q 5 # i 1 = . q 6 # i 0 = . q 7 # i 0
    = . q 8 # i 0 = . q 9 # i 0 = . q 10 # i 1 = . q 11 # i 0
    = . q 12 # i 0 = . q 13 # i 0 = . q 14 # i 0 = . q 15 # i 0
    = . q 16 # i 0 = . q 17 # i 0 = . q 18 # i 0 = . q 19 # i 0
    = . q 20 # i 1738742601995546 = . q 21 # i 1146398526822698 = . q 22 # i 2070867633025821 = . q 23 # i 562264141797630
    = . q 24 # i 587772402128613 = . q 25 # i 1801439850948184 = . q 26 # i 1351079888211148 = . q 27 # i 450359962737049
    = . q 28 # i 900719925474099 = . q 29 # i 1801439850948198 = . q 30 # i 1 = . q 31 # i 0
    = . q 32 # i 0 = . q 33 # i 0 = . q 34 # i 0 = . q 35 # i 1841354044333475
    = . q 36 # i 16398895984059 = . q 37 # i 755974180946558 = . q 38 # i 900171276175154 = . q 39 # i 1821297809914039
    = . q 40 # i 962690963841538 = . q 41 # i 2210719638316993 = . q 42 # i 706068330177389 = . q 43 # i 1384191282407386
    = . q 44 # i 1726421572252383 = . q 45 # i 1964103625364243 = . q 46 # i 307116021699043 = . q 47 # i 120882883216088
    = . q 48 # i 20816463754899 = . q 49 # i 55369446368493 = . q 50 # i 1 = . q 51 # i 0
    = . q 52 # i 0 = . q 53 # i 0 = . q 54 # i 0 = . q 55 # i 1568907369646169
    = . q 56 # i 514127314339263 = . q 57 # i 40774287502072 = . q 58 # i 1976251032040224 = . q 59 # i 1733588893334842
    = . q 60 # i 7041092221858 = . q 61 # i 1794296929354574 = . q 62 # i 1237236946531720 = . q 63 # i 2250546736920861
    = . q 64 # i 259111526187668 = . q 65 # i 1617510425255494 = . q 66 # i 1984488342256828 = . q 67 # i 1321950222407495
    = . q 68 # i 2136088219447137 = . q 69 # i 425530124582567 = . q 70 # i 1 = . q 71 # i 0
    = . q 72 # i 0 = . q 73 # i 0 = . q 74 # i 0 = . q 75 # i 922449501748080
    = . q 76 # i 782850774712250 = . q 77 # i 75404956566566 = . q 78 # i 1540981272636625 = . q 79 # i 999254495388672
    = . q 80 # i 78814272546852 = . q 81 # i 343446598238096 = . q 82 # i 1469662686845463 = . q 83 # i 446722075312752
    = . q 84 # i 1339733442806879 = . q 85 # i 770831939905131 = . q 86 # i 1066752177064823 = . q 87 # i 855905013023480
    = . q 88 # i 1194941381303059 = . q 89 # i 1674322643330780 = . q 90 # i 1 = . q 91 # i 0
    = . q 92 # i 0 = . q 93 # i 0 = . q 94 # i 0 = . q 95 # i 2025065385374602
    = . q 96 # i 84441031851324 = . q 97 # i 1769310306558354 = . q 98 # i 26295680040963 = . q 99 # i 99051874860870
    = . q 100 # i 841304234563226 = . q 101 # i 288336583122812 = . q 102 # i 859273953516464 = . q 103 # i 641862895460166
    = . q 104 # i 1942073973586062 = . q 105 # i 1453985943769243 = . q 106 # i 866246220448934 = . q 107 # i 1936536679015493
    = . q 108 # i 1230582470035868 = . q 109 # i 989307346767029 = . q 110 # i 1 = . q 111 # i 0
    = . q 112 # i 0 = . q 113 # i 0 = . q 114 # i 0 = . q 115 # i 194323669222313
    = . q 116 # i 1986849483265063 = . q 117 # i 1940458793072969 = . q 118 # i 1262977539333204 = . q 119 # i 1255393699631181
    = . q 120 # i 860244430014981 = . q 121 # i 689939600126334 = . q 122 # i 1756444480111041 = . q 123 # i 604611337970161
    = . q 124 # i 1934228889371123 = . q 125 # i 1115840552254004 = . q 126 # i 1042279514255678 = . q 127 # i 1769279693616433
    = . q 128 # i 1033836220221303 = . q 129 # i 1695643946154600 = . q 130 # i 1 = . q 131 # i 0
    = . q 132 # i 0 = . q 133 # i 0 = . q 134 # i 0 = . q 135 # i 1926874165278898
    = . q 136 # i 592675951759993 = . q 137 # i 1086762887648803 = . q 138 # i 1624474402714719 = . q 139 # i 1415896675539756
    = . q 140 # i 1625679944571491 = . q 141 # i 1175657876638287 = . q 142 # i 1157221053353163 = . q 143 # i 528230055263805
    = . q 144 # i 878345893388895 = . q 145 # i 442279965111911 = . q 146 # i 692289219476686 = . q 147 # i 1388532760188106
    = . q 148 # i 447879249267108 = . q 149 # i 1078013435304617 = . q 150 # i 1 = . q 151 # i 0
    = . q 152 # i 0 = . q 153 # i 0 = . q 154 # i 0 = . q 155 # i 1070778974337849
    = . q 156 # i 1967157437419015 = . q 157 # i 1898027052522780 = . q 158 # i 811855559975557 = . q 159 # i 1378799308038890
    = . q 160 # i 798540852548237 = . q 161 # i 1186388878089071 = . q 162 # i 554557418141563 = . q 163 # i 2038592377592718
    = . q 164 # i 488711206961541 = . q 165 # i 833812069173299 = . q 166 # i 646939731425630 = . q 167 # i 1538221673810424
    = . q 168 # i 2137163637965756 = . q 169 # i 1721356815521377 = . q 170 # i 1 = . q 171 # i 0
    = . q 172 # i 0 = . q 173 # i 0 = . q 174 # i 0 = . q 175 # i 76009751102151
    = . q 176 # i 1911895294413367 = . q 177 # i 1262509771121608 = . q 178 # i 1445197895593765 = . q 179 # i 460973337299855
    = . q 180 # i 1403677045712952 = . q 181 # i 1315744170250425 = . q 182 # i 1615520137472717 = . q 183 # i 283275291933293
    = . q 184 # i 48798388170078 = . q 185 # i 109354245315004 = . q 186 # i 1914127539105944 = . q 187 # i 844338193600501
    = . q 188 # i 526428908480878 = . q 189 # i 1176068453980819 = . q 190 # i 1 = . q 191 # i 0
    = . q 192 # i 0 = . q 193 # i 0 = . q 194 # i 0 = . q 195 # i 1017297571599653
    = . q 196 # i 1154767515845140 = . q 197 # i 2116819467069976 = . q 198 # i 1446526646935216 = . q 199 # i 281522550596263
    = . q 200 # i 823269648550439 = . q 201 # i 486037302993554 = . q 202 # i 1474864517748821 = . q 203 # i 1908169744179899
    = . q 204 # i 1994942704125518 = . q 205 # i 279331970100678 = . q 206 # i 1934337290044654 = . q 207 # i 960630481011071
    = . q 208 # i 960576887927161 = . q 209 # i 1638226956763142 = . q 210 # i 1 = . q 211 # i 0
    = . q 212 # i 0 = . q 213 # i 0 = . q 214 # i 0 = . q 215 # i 680913469064949
    = . q 216 # i 1801805553396661 = . q 217 # i 40715869468621 = . q 218 # i 411457628042078 = . q 219 # i 1291678746780570
    = . q 220 # i 1967955306114879 = . q 221 # i 25861803287777 = . q 222 # i 1825226422722195 = . q 223 # i 134464352348952
    = . q 224 # i 1071891513128430 = . q 225 # i 1004361961630985 = . q 226 # i 581618394920088 = . q 227 # i 1253980602882423
    = . q 228 # i 1065221446170931 = . q 229 # i 1110744382390146 = . q 230 # i 1 = . q 231 # i 0
    = . q 232 # i 0 = . q 233 # i 0 = . q 234 # i 0 = . q 235 # i 1200200636115096
    = . q 236 # i 193524975104322 = . q 237 # i 1019915809956827 = . q 238 # i 2195869670433558 = . q 239 # i 2058901671612867
    = . q 240 # i 955325879284177 = . q 241 # i 1898787560239826 = . q 242 # i 1749051654153895 = . q 243 # i 470747919996685
    = . q 244 # i 2084763994715858 = . q 245 # i 1315908902790139 = . q 246 # i 560089107386794 = . q 247 # i 2039185471139212
    = . q 248 # i 1490075862619589 = . q 249 # i 241729012591394 = . q 250 # i 1 = . q 251 # i 0
    = . q 252 # i 0 = . q 253 # i 0 = . q 254 # i 0 = . q 255 # i 2050838256499573
    = . q 256 # i 732903749070741 = . q 257 # i 427507250779307 = . q 258 # i 218878215232455 = . q 259 # i 1093251084113008
    = . q 260 # i 706993755603636 = . q 261 # i 132871503799025 = . q 262 # i 884316320977938 = . q 263 # i 1386218864925745
    = . q 264 # i 1930913408590715 = . q 265 # i 2125059702603352 = . q 266 # i 2033567999166737 = . q 267 # i 1166281397275359
    = . q 268 # i 183129527335258 = . q 269 # i 2006112367853226 = . q 270 # i 1 = . q 271 # i 0
    = . q 272 # i 0 = . q 273 # i 0 = . q 274 # i 0 = . q 275 # i 1282967945218923
    = . q 276 # i 1656449878990546 = . q 277 # i 959308575661592 = . q 278 # i 559944928652340 = . q 279 # i 1525862227975859
    = . q 280 # i 658059562747718 = . q 281 # i 788771745829185 = . q 282 # i 953707210284919 = . q 283 # i 1970332484779637
    = . q 284 # i 858969908771858 = . q 285 # i 1316342944925958 = . q 286 # i 93365034066043 = . q 287 # i 55307526446706
    = . q 288 # i 1237317543906585 = . q 289 # i 1032567107538987 = . q 290 # i 1 = . q 291 # i 0
    = . q 292 # i 0 = . q 293 # i 0 = . q 294 # i 0 = . q 295 # i 312585254076678
    = . q 296 # i 1594982147435131 = . q 297 # i 1689148640964514 = . q 298 # i 150204140210568 = . q 299 # i 1387777698046063
    = . q 300 # i 862075999903728 = . q 301 # i 2163902595352333 = . q 302 # i 2014073000973098 = . q 303 # i 1166175156245786
    = . q 304 # i 1767804173463569 = . q 305 # i 1085602682198079 = . q 306 # i 1965932390587234 = . q 307 # i 205988781173318
    = . q 308 # i 1051733436703390 = . q 309 # i 652575881366654 = . q 310 # i 1 = . q 311 # i 0
    = . q 312 # i 0 = . q 313 # i 0 = . q 314 # i 0 = . q 315 # i 356077903060975
    = . q 316 # i 2076605496446737 = . q 317 # i 1233138407901684 = . q 318 # i 1272668747979945 = . q 319 # i 71529050535104
    ^ v
}

// p ← p + q, extended twisted-Edwards (a = −1). p may equal q (doubling):
// every operand is read into the scratch before any of p's coords is set.
@ __xe_add XEScr sc XEP p XEP q ( Vec i ) d2 → v {
    ( _Z . sc a . p y . p x )
    ( _Z . sc tt . q y . q x )
    ( _M . sc a . sc a . sc tt )
    ( _A . sc b . p x . p y )
    ( _A . sc tt . q x . q y )
    ( _M . sc b . sc b . sc tt )
    ( _M . sc c . p t . q t )
    ( _M . sc c . sc c d2 )
    ( _M . sc d . p z . q z )
    ( _A . sc d . sc d . sc d )
    ( _Z . sc e . sc b . sc a )
    ( _Z . sc f . sc d . sc c )
    ( _A . sc g . sc d . sc c )
    ( _A . sc h . sc b . sc a )
    ( _M . p x . sc e . sc f )
    ( _M . p y . sc h . sc g )
    ( _M . p z . sc g . sc f )
    ( _M . p t . sc e . sc h )
}

// Constant-time read of entry `digit` (0..15) into dst from the flat baked
// table (stride 20): all 16 entries scanned, merged under a match mask.
@ __xe_tbl_get ( Vec i ) tbl i digit XEP dst → v {
    : *i tb ( vec_data [i] tbl )
    : *i dx ( vec_data [i] . dst x ) : *i dy ( vec_data [i] . dst y )
    : *i dz ( vec_data [i] . dst z ) : *i dt ( vec_data [i] . dst t )
    : ~ i k 0
    ~ < k 5 { = . dx k 0 = . dy k 0 = . dz k 0 = . dt k 0 = k + k 1 }
    : ~ i e 0
    ~ < e 16 {
        : u64 z ^^ # u64 e # u64 digit
        : i mask - 0 # i >> - z 1 63
        : i base * e 20
        : ~ i j 0
        ~ < j 5 {
            = . dx j | . dx j & mask . tb + base j
            = . dy j | . dy j & mask . tb + + base 5 j
            = . dz j | . dz j & mask . tb + + base 10 j
            = . dt j | . dt j & mask . tb + + base 15 j
            = j + j 1
        }
        = e + e 1
    }
}

// scalar·B via the comb → 32-byte little-endian Montgomery u (the X25519
// public key). Constant-time; no per-call table build.
@ x25519_base_comb ( Vec u ) scalar → ( Vec u ) {
    : ( Vec u ) sc ( _zeros_u 32 )
    : ~ i k 0
    ~ < k 32 { ( _bset sc k ( _x_bget scalar k ) ) = k + k 1 }
    ( _bset sc 31 | & ( _x_bget scalar 31 ) 127 64 )
    ( _bset sc 0 & ( _x_bget scalar 0 ) 248 )

    : XEScr scr ( __xe_scr )
    : ( Vec i ) d2 ( __xe_d2 )
    : ( Vec i ) tbl ( __xe_comb_table )
    : XEP acc ( __xe_pt )
    : *i ay ( vec_data [i] . acc y ) : *i az ( vec_data [i] . acc z )
    = . ay 0 1 = . az 0 1
    : XEP selp ( __xe_pt )
    : ~ i i 63
    ~ >= i 0 {
        ( __xe_add scr acc acc d2 )
        : ~ i idx 0
        : ~ i j 0
        ~ < j 4 {
            : i bitpos + * 64 j i
            : i bit & 1 >> ( _x_bget sc >> bitpos 3 ) & bitpos 7
            = idx | idx << bit j
            = j + j 1
        }
        ( __xe_tbl_get tbl idx selp )
        ( __xe_add scr acc selp d2 )
        = i - i 1
    }

    : ( Vec i ) num ( _gf_zero )
    : ( Vec i ) den ( _gf_zero )
    ( _A num . acc z . acc y )
    ( _Z den . acc z . acc y )
    ( _inv25519 den )
    : ( Vec i ) uf ( _gf_zero )
    ( _M uf num den )
    : ( Vec u ) out ( _pack25519 uf )

    ( __xe_scr_free scr ) ( vec_free [i] d2 ) ( vec_free [i] tbl )
    ( __xe_pt_free acc ) ( __xe_pt_free selp )
    ( vec_free [u] sc ) ( vec_free [i] num ) ( vec_free [i] den ) ( vec_free [i] uf )
    ^ out
}

@ x25519_base ( Vec u ) scalar → ( Vec u ) {
    // Fixed-base: the generator is constant, so a precomputed Edwards comb
    // (x25519_base_comb) beats the Montgomery ladder. Same result, verified
    // against the ladder for the RFC 7748 vectors.
    ^ ( x25519_base_comb scalar )
}
