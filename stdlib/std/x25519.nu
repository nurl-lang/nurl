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
@ x25519_base ( Vec u ) scalar → ( Vec u ) {
    : ( Vec u ) base ( _zeros_u 32 )
    ( _bset base 0 9 )
    : ( Vec u ) out ( __scalarmult scalar base )
    ( vec_free [u] base )
    ^ out
}
