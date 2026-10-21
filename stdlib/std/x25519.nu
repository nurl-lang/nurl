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

// The gf routines below (_A / _Z / _M / _S, _gf_copy, _sel25519, …)
// index their limbs through `*i` instead of the two accessors above.
// Every one of those loops is fixed-count over a five-limb gf, so the
// bounds check is provably redundant — but it is a real call, and one
// fixed-base X25519 (the comb behind x25519_base, inversion included)
// makes ~1200 field multiplies and squarings. The variable-base ladder
// (__scalarmult) keeps its limbs in u64 locals (__fe_mul / __fe_sq)
// instead. Constant time is unaffected: the trip counts are fixed and
// the data takes no branch.

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
inline @ _ld64u ( Vec u ) n i off → i {
    : *u p ( vec_data [u] n )
    : i b0 # i . p off
    : i b1 # i . p + off 1
    : i b2 # i . p + off 2
    : i b3 # i . p + off 3
    : i b4 # i . p + off 4
    : i b5 # i . p + off 5
    : i b6 # i . p + off 6
    : i b7 # i . p + off 7
    : i lo | | | b0 << b1 8 << b2 16 << b3 24
    : i hi | | | b4 << b5 8 << b6 16 << b7 24
    ^ | lo << hi 32
}

// Fully reduce 5 scalar limbs mod 2^255−19 and emit 32 little-endian bytes.
inline @ __fe_pack u64 a0 u64 a1 u64 a2 u64 a3 u64 a4 → ( Vec u ) {
    : ~ u64 h0 a0
    : ~ u64 h1 a1
    : ~ u64 h2 a2
    : ~ u64 h3 a3
    : ~ u64 h4 a4
    = h1 + h1 >> h0 51 = h0 & h0 2251799813685247
    = h2 + h2 >> h1 51 = h1 & h1 2251799813685247
    = h3 + h3 >> h2 51 = h2 & h2 2251799813685247
    = h4 + h4 >> h3 51 = h3 & h3 2251799813685247
    = h0 + h0 * 19 >> h4 51 = h4 & h4 2251799813685247
    = h1 + h1 >> h0 51 = h0 & h0 2251799813685247
    = h2 + h2 >> h1 51 = h1 & h1 2251799813685247
    = h3 + h3 >> h2 51 = h2 & h2 2251799813685247
    = h4 + h4 >> h3 51 = h3 & h3 2251799813685247
    = h0 + h0 * 19 >> h4 51 = h4 & h4 2251799813685247
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
    : u64 w0 | h0 << h1 51
    : u64 w1 | >> h1 13 << h2 38
    : u64 w2 | >> h2 26 << h3 25
    : u64 w3 | >> h3 39 << h4 12
    : ( Vec u ) o ( vec_with_cap [u] 32 )
    : b _l ( vec_set_len [u] o 32 )
    : *u op ( vec_data [u] o )
    : ~ i k 0
    ~ < k 8 {
        = . op k # u & >> w0 # u64 * 8 k 255
        = . op + k 8 # u & >> w1 # u64 * 8 k 255
        = . op + k 16 # u & >> w2 # u64 * 8 k 255
        = . op + k 24 # u & >> w3 # u64 * 8 k 255
        = k + k 1
    }
    ^ o
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
    // t0 = r0·s0 + f4·s1 + f1·s4 + f2·s3 + f3·s2
    : ~ u64 l0 * r0 s0
    : ~ u64 h0 ( nurl_umulhi r0 s0 )
    = h0 + h0 ( nurl_mac_hi f4 s1 l0 0 ) = l0 ( nurl_mac_lo f4 s1 l0 0 )
    = h0 + h0 ( nurl_mac_hi f1 s4 l0 0 ) = l0 ( nurl_mac_lo f1 s4 l0 0 )
    = h0 + h0 ( nurl_mac_hi f2 s3 l0 0 ) = l0 ( nurl_mac_lo f2 s3 l0 0 )
    = h0 + h0 ( nurl_mac_hi f3 s2 l0 0 ) = l0 ( nurl_mac_lo f3 s2 l0 0 )
    // t1 = r0·s1 + r1·s0 + f4·s2 + f2·s4 + f3·s3
    : ~ u64 l1 * r0 s1
    : ~ u64 h1 ( nurl_umulhi r0 s1 )
    = h1 + h1 ( nurl_mac_hi r1 s0 l1 0 ) = l1 ( nurl_mac_lo r1 s0 l1 0 )
    = h1 + h1 ( nurl_mac_hi f4 s2 l1 0 ) = l1 ( nurl_mac_lo f4 s2 l1 0 )
    = h1 + h1 ( nurl_mac_hi f2 s4 l1 0 ) = l1 ( nurl_mac_lo f2 s4 l1 0 )
    = h1 + h1 ( nurl_mac_hi f3 s3 l1 0 ) = l1 ( nurl_mac_lo f3 s3 l1 0 )
    // t2 = r0·s2 + r1·s1 + r2·s0 + f4·s3 + f3·s4
    : ~ u64 l2 * r0 s2
    : ~ u64 h2 ( nurl_umulhi r0 s2 )
    = h2 + h2 ( nurl_mac_hi r1 s1 l2 0 ) = l2 ( nurl_mac_lo r1 s1 l2 0 )
    = h2 + h2 ( nurl_mac_hi r2 s0 l2 0 ) = l2 ( nurl_mac_lo r2 s0 l2 0 )
    = h2 + h2 ( nurl_mac_hi f4 s3 l2 0 ) = l2 ( nurl_mac_lo f4 s3 l2 0 )
    = h2 + h2 ( nurl_mac_hi f3 s4 l2 0 ) = l2 ( nurl_mac_lo f3 s4 l2 0 )
    // t3 = r0·s3 + r1·s2 + r2·s1 + r3·s0 + f4·s4
    : ~ u64 l3 * r0 s3
    : ~ u64 h3 ( nurl_umulhi r0 s3 )
    = h3 + h3 ( nurl_mac_hi r1 s2 l3 0 ) = l3 ( nurl_mac_lo r1 s2 l3 0 )
    = h3 + h3 ( nurl_mac_hi r2 s1 l3 0 ) = l3 ( nurl_mac_lo r2 s1 l3 0 )
    = h3 + h3 ( nurl_mac_hi r3 s0 l3 0 ) = l3 ( nurl_mac_lo r3 s0 l3 0 )
    = h3 + h3 ( nurl_mac_hi f4 s4 l3 0 ) = l3 ( nurl_mac_lo f4 s4 l3 0 )
    // t4 = r0·s4 + r1·s3 + r2·s2 + r3·s1 + r4·s0
    : ~ u64 l4 * r0 s4
    : ~ u64 h4 ( nurl_umulhi r0 s4 )
    = h4 + h4 ( nurl_mac_hi r1 s3 l4 0 ) = l4 ( nurl_mac_lo r1 s3 l4 0 )
    = h4 + h4 ( nurl_mac_hi r2 s2 l4 0 ) = l4 ( nurl_mac_lo r2 s2 l4 0 )
    = h4 + h4 ( nurl_mac_hi r3 s1 l4 0 ) = l4 ( nurl_mac_lo r3 s1 l4 0 )
    = h4 + h4 ( nurl_mac_hi r4 s0 l4 0 ) = l4 ( nurl_mac_lo r4 s0 l4 0 )
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
    // t0 = r0·r0 + d4·r1 + d2·r3
    : ~ u64 l0 * r0 r0
    : ~ u64 h0 ( nurl_umulhi r0 r0 )
    = h0 + h0 ( nurl_mac_hi d4 r1 l0 0 ) = l0 ( nurl_mac_lo d4 r1 l0 0 )
    = h0 + h0 ( nurl_mac_hi d2 r3 l0 0 ) = l0 ( nurl_mac_lo d2 r3 l0 0 )
    // t1 = d0·r1 + d4·r2 + r3·(r3·19)
    : ~ u64 l1 * d0 r1
    : ~ u64 h1 ( nurl_umulhi d0 r1 )
    = h1 + h1 ( nurl_mac_hi d4 r2 l1 0 ) = l1 ( nurl_mac_lo d4 r2 l1 0 )
    = h1 + h1 ( nurl_mac_hi r3 r319 l1 0 ) = l1 ( nurl_mac_lo r3 r319 l1 0 )
    // t2 = d0·r2 + r1·r1 + d4·r3
    : ~ u64 l2 * d0 r2
    : ~ u64 h2 ( nurl_umulhi d0 r2 )
    = h2 + h2 ( nurl_mac_hi r1 r1 l2 0 ) = l2 ( nurl_mac_lo r1 r1 l2 0 )
    = h2 + h2 ( nurl_mac_hi d4 r3 l2 0 ) = l2 ( nurl_mac_lo d4 r3 l2 0 )
    // t3 = d0·r3 + d1·r2 + r4·d419
    : ~ u64 l3 * d0 r3
    : ~ u64 h3 ( nurl_umulhi d0 r3 )
    = h3 + h3 ( nurl_mac_hi d1 r2 l3 0 ) = l3 ( nurl_mac_lo d1 r2 l3 0 )
    = h3 + h3 ( nurl_mac_hi r4 d419 l3 0 ) = l3 ( nurl_mac_lo r4 d419 l3 0 )
    // t4 = d0·r4 + d1·r3 + r2·r2
    : ~ u64 l4 * d0 r4
    : ~ u64 h4 ( nurl_umulhi d0 r4 )
    = h4 + h4 ( nurl_mac_hi d1 r3 l4 0 ) = l4 ( nurl_mac_lo d1 r3 l4 0 )
    = h4 + h4 ( nurl_mac_hi r2 r2 l4 0 ) = l4 ( nurl_mac_lo r2 r2 l4 0 )
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
// io ← io^(2^n) — n back-to-back squarings.
@ _sqn25519 ( Vec i ) io i n → v {
    : ~ i k 0
    ~ < k n { ( _S io io ) = k + k 1 }
}

@ _inv25519 ( Vec i ) io → v {
    // io ← io^(p−2), p = 2^255−19 — Fermat, via the standard ref10
    // addition chain: 254 squarings + 11 multiplies. The old
    // tweetnacl-style ladder multiplied on every exponent bit — 254 S
    // + 252 M for the same PUBLIC exponent, so 241 of those multiplies
    // bought nothing: the schedule depends only on the constant p−2,
    // and the data path stays branch-free either way. Verified against
    // the RFC 7748 vectors and the x25519/TLS corpus tests.
    : ( Vec i ) z ( _gf_copy io )
    : ( Vec i ) z2 ( _gf_zero )
    : ( Vec i ) z9 ( _gf_zero )
    : ( Vec i ) z11 ( _gf_zero )
    : ( Vec i ) z5 ( _gf_zero )
    : ( Vec i ) z10 ( _gf_zero )
    : ( Vec i ) z50 ( _gf_zero )
    : ( Vec i ) t ( _gf_zero )
    ( _S z2 z )  // z^2
    ( _S z9 z2 ) ( _S z9 z9 ) ( _M z9 z9 z )  // z^9
    ( _M z11 z9 z2 )  // z^11
    ( _S z5 z11 ) ( _M z5 z5 z9 )  // z^(2^5−1)
    ( _gf_into z10 z5 ) ( _sqn25519 z10 5 )
    ( _M z10 z10 z5 )  // z^(2^10−1)
    ( _gf_into t z10 ) ( _sqn25519 t 10 )
    ( _M t t z10 )  // z^(2^20−1)
    ( _gf_into z50 t ) ( _sqn25519 z50 20 )
    ( _M z50 z50 t )  // z^(2^40−1)
    ( _sqn25519 z50 10 )
    ( _M z50 z50 z10 )  // z^(2^50−1)
    ( _gf_into t z50 ) ( _sqn25519 t 50 )
    ( _M t t z50 )  // z^(2^100−1)
    ( _gf_into z10 t ) ( _sqn25519 z10 100 )
    ( _M z10 z10 t )  // z^(2^200−1)
    ( _sqn25519 z10 50 )
    ( _M z10 z10 z50 )  // z^(2^250−1)
    ( _sqn25519 z10 5 )
    ( _M z10 z10 z11 )  // z^(2^255−21)
    ( _gf_into io z10 )
}

// ── the ladder's field, on scalar limbs ───────────────────────────
// The variable-base ladder keeps its field elements as u64 locals, five
// to an element; a field operation takes its operands by value and writes
// the limbs of its result `inout`. A `( Vec i )` element lives behind a
// pointer the optimiser cannot see through: each _M/_S/_A/_Z stored its
// five limbs and the next operation loaded them back. The arithmetic is
// _A/_Z/_M/_S's, limb for limb.
//
// The multiply and the square stay functions of their own (only the
// add, subtract and swap inline). Inlined too, with the ladder in an
// x86-64-v3 clone for mulx, one scalar multiply ran 30 % faster still —
// but the ladder became one function of some ten thousand i128-heavy IR
// instructions, InstCombine and the SLP vectoriser took seconds over it,
// and every program that does TLS compiled about three seconds slower.
// Out of line, a TLS program builds about as fast as with the Vec form.

// o ← a + b (_A)
inline @ __fe_add inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 inout u64 o4 u64 a0 u64 a1 u64 a2 u64 a3 u64 a4 u64 b0 u64 b1 u64 b2 u64 b3 u64 b4 → v {
    = o0 + a0 b0
    = o1 + a1 b1
    = o2 + a2 b2
    = o3 + a3 b3
    = o4 + a4 b4
}

// o ← a − b + 2p (_Z)
inline @ __fe_sub inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 inout u64 o4 u64 a0 u64 a1 u64 a2 u64 a3 u64 a4 u64 b0 u64 b1 u64 b2 u64 b3 u64 b4 → v {
    = o0 - + a0 4503599627370458 b0
    = o1 - + a1 4503599627370494 b1
    = o2 - + a2 4503599627370494 b2
    = o3 - + a3 4503599627370494 b3
    = o4 - + a4 4503599627370494 b4
}

// o ← a · b mod p (_M), inlined for the ladder loop body
inline @ __fe_mul_in inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 inout u64 o4 u64 a0 u64 a1 u64 a2 u64 a3 u64 a4 u64 b0 u64 b1 u64 b2 u64 b3 u64 b4 → v {
    : u64 f1 * a1 19
    : u64 f2 * a2 19
    : u64 f3 * a3 19
    : u64 f4 * a4 19
    : ~ u64 l0 * a0 b0
    : ~ u64 h0 ( nurl_umulhi a0 b0 )
    = h0 + h0 ( nurl_mac_hi f4 b1 l0 0 ) = l0 ( nurl_mac_lo f4 b1 l0 0 )
    = h0 + h0 ( nurl_mac_hi f1 b4 l0 0 ) = l0 ( nurl_mac_lo f1 b4 l0 0 )
    = h0 + h0 ( nurl_mac_hi f2 b3 l0 0 ) = l0 ( nurl_mac_lo f2 b3 l0 0 )
    = h0 + h0 ( nurl_mac_hi f3 b2 l0 0 ) = l0 ( nurl_mac_lo f3 b2 l0 0 )
    : ~ u64 l1 * a0 b1
    : ~ u64 h1 ( nurl_umulhi a0 b1 )
    = h1 + h1 ( nurl_mac_hi a1 b0 l1 0 ) = l1 ( nurl_mac_lo a1 b0 l1 0 )
    = h1 + h1 ( nurl_mac_hi f4 b2 l1 0 ) = l1 ( nurl_mac_lo f4 b2 l1 0 )
    = h1 + h1 ( nurl_mac_hi f2 b4 l1 0 ) = l1 ( nurl_mac_lo f2 b4 l1 0 )
    = h1 + h1 ( nurl_mac_hi f3 b3 l1 0 ) = l1 ( nurl_mac_lo f3 b3 l1 0 )
    : ~ u64 l2 * a0 b2
    : ~ u64 h2 ( nurl_umulhi a0 b2 )
    = h2 + h2 ( nurl_mac_hi a1 b1 l2 0 ) = l2 ( nurl_mac_lo a1 b1 l2 0 )
    = h2 + h2 ( nurl_mac_hi a2 b0 l2 0 ) = l2 ( nurl_mac_lo a2 b0 l2 0 )
    = h2 + h2 ( nurl_mac_hi f4 b3 l2 0 ) = l2 ( nurl_mac_lo f4 b3 l2 0 )
    = h2 + h2 ( nurl_mac_hi f3 b4 l2 0 ) = l2 ( nurl_mac_lo f3 b4 l2 0 )
    : ~ u64 l3 * a0 b3
    : ~ u64 h3 ( nurl_umulhi a0 b3 )
    = h3 + h3 ( nurl_mac_hi a1 b2 l3 0 ) = l3 ( nurl_mac_lo a1 b2 l3 0 )
    = h3 + h3 ( nurl_mac_hi a2 b1 l3 0 ) = l3 ( nurl_mac_lo a2 b1 l3 0 )
    = h3 + h3 ( nurl_mac_hi a3 b0 l3 0 ) = l3 ( nurl_mac_lo a3 b0 l3 0 )
    = h3 + h3 ( nurl_mac_hi f4 b4 l3 0 ) = l3 ( nurl_mac_lo f4 b4 l3 0 )
    : ~ u64 l4 * a0 b4
    : ~ u64 h4 ( nurl_umulhi a0 b4 )
    = h4 + h4 ( nurl_mac_hi a1 b3 l4 0 ) = l4 ( nurl_mac_lo a1 b3 l4 0 )
    = h4 + h4 ( nurl_mac_hi a2 b2 l4 0 ) = l4 ( nurl_mac_lo a2 b2 l4 0 )
    = h4 + h4 ( nurl_mac_hi a3 b1 l4 0 ) = l4 ( nurl_mac_lo a3 b1 l4 0 )
    = h4 + h4 ( nurl_mac_hi a4 b0 l4 0 ) = l4 ( nurl_mac_lo a4 b0 l4 0 )
    ( __fe_carry o0 o1 o2 o3 o4 l0 h0 l1 h1 l2 h2 l3 h3 l4 h4 )
}

// o ← a · 121665 mod p: 5 scalar products instead of 25
inline @ __fe_mul121665 inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 inout u64 o4 u64 a0 u64 a1 u64 a2 u64 a3 u64 a4 → v {
    : u64 l0 * a0 121665
    : u64 h0 ( nurl_umulhi a0 121665 )
    : u64 l1 * a1 121665
    : u64 h1 ( nurl_umulhi a1 121665 )
    : u64 l2 * a2 121665
    : u64 h2 ( nurl_umulhi a2 121665 )
    : u64 l3 * a3 121665
    : u64 h3 ( nurl_umulhi a3 121665 )
    : u64 l4 * a4 121665
    : u64 h4 ( nurl_umulhi a4 121665 )
    ( __fe_carry o0 o1 o2 o3 o4 l0 h0 l1 h1 l2 h2 l3 h3 l4 h4 )
}

// o ← a² mod p (_S), inlined for the ladder loop body
inline @ __fe_sq_in inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 inout u64 o4 u64 a0 u64 a1 u64 a2 u64 a3 u64 a4 → v {
    : u64 d0 * a0 2
    : u64 d1 * a1 2
    : u64 d2 * a2 38
    : u64 d419 * a4 19
    : u64 d4 * d419 2
    : u64 a319 * a3 19
    : ~ u64 l0 * a0 a0
    : ~ u64 h0 ( nurl_umulhi a0 a0 )
    = h0 + h0 ( nurl_mac_hi d4 a1 l0 0 ) = l0 ( nurl_mac_lo d4 a1 l0 0 )
    = h0 + h0 ( nurl_mac_hi d2 a3 l0 0 ) = l0 ( nurl_mac_lo d2 a3 l0 0 )
    : ~ u64 l1 * d0 a1
    : ~ u64 h1 ( nurl_umulhi d0 a1 )
    = h1 + h1 ( nurl_mac_hi d4 a2 l1 0 ) = l1 ( nurl_mac_lo d4 a2 l1 0 )
    = h1 + h1 ( nurl_mac_hi a3 a319 l1 0 ) = l1 ( nurl_mac_lo a3 a319 l1 0 )
    : ~ u64 l2 * d0 a2
    : ~ u64 h2 ( nurl_umulhi d0 a2 )
    = h2 + h2 ( nurl_mac_hi a1 a1 l2 0 ) = l2 ( nurl_mac_lo a1 a1 l2 0 )
    = h2 + h2 ( nurl_mac_hi d4 a3 l2 0 ) = l2 ( nurl_mac_lo d4 a3 l2 0 )
    : ~ u64 l3 * d0 a3
    : ~ u64 h3 ( nurl_umulhi d0 a3 )
    = h3 + h3 ( nurl_mac_hi d1 a2 l3 0 ) = l3 ( nurl_mac_lo d1 a2 l3 0 )
    = h3 + h3 ( nurl_mac_hi a4 d419 l3 0 ) = l3 ( nurl_mac_lo a4 d419 l3 0 )
    : ~ u64 l4 * d0 a4
    : ~ u64 h4 ( nurl_umulhi d0 a4 )
    = h4 + h4 ( nurl_mac_hi d1 a3 l4 0 ) = l4 ( nurl_mac_lo d1 a3 l4 0 )
    = h4 + h4 ( nurl_mac_hi a2 a2 l4 0 ) = l4 ( nurl_mac_lo a2 a2 l4 0 )
    ( __fe_carry o0 o1 o2 o3 o4 l0 h0 l1 h1 l2 h2 l3 h3 l4 h4 )
}

// o ← a · b mod p (_M)
@ __fe_mul inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 inout u64 o4 u64 a0 u64 a1 u64 a2 u64 a3 u64 a4 u64 b0 u64 b1 u64 b2 u64 b3 u64 b4 → v {
    ( __fe_mul_in o0 o1 o2 o3 o4 a0 a1 a2 a3 a4 b0 b1 b2 b3 b4 )
}

// o ← a² mod p (_S)
@ __fe_sq inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 inout u64 o4 u64 a0 u64 a1 u64 a2 u64 a3 u64 a4 → v {
    ( __fe_sq_in o0 o1 o2 o3 o4 a0 a1 a2 a3 a4 )
}

// five 128-bit column sums (lo, hi) → five 51-bit limbs (__mul_carry_out)
inline @ __fe_carry inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 inout u64 o4 u64 pl0 u64 ph0 u64 pl1 u64 ph1 u64 pl2 u64 ph2 u64 pl3 u64 ph3 u64 pl4 u64 ph4 → v {
    : ~ u64 l1 pl1
    : ~ u64 h1 ph1
    : ~ u64 l2 pl2
    : ~ u64 h2 ph2
    : ~ u64 l3 pl3
    : ~ u64 h3 ph3
    : ~ u64 l4 pl4
    : ~ u64 h4 ph4
    : ~ u64 g0 & pl0 2251799813685247
    : ~ u64 c | << ph0 13 >> pl0 51
    = l1 + l1 c = h1 + h1 ? < l1 c 1 0
    : ~ u64 g1 & l1 2251799813685247
    = c | << h1 13 >> l1 51
    = l2 + l2 c = h2 + h2 ? < l2 c 1 0
    : u64 g2 & l2 2251799813685247
    = c | << h2 13 >> l2 51
    = l3 + l3 c = h3 + h3 ? < l3 c 1 0
    = o3 & l3 2251799813685247
    = c | << h3 13 >> l3 51
    = l4 + l4 c = h4 + h4 ? < l4 c 1 0
    = o4 & l4 2251799813685247
    = c | << h4 13 >> l4 51
    = g0 + g0 * c 19
    = c >> g0 51
    = o0 & g0 2251799813685247
    = g1 + g1 c
    = c >> g1 51
    = o1 & g1 2251799813685247
    = o2 + g2 c
}

// p, q ← q, p when m is all ones, unchanged when m is 0 — in constant time (_sel25519)
inline @ __fe_cswap inout u64 p0 inout u64 p1 inout u64 p2 inout u64 p3 inout u64 p4 inout u64 q0 inout u64 q1 inout u64 q2 inout u64 q3 inout u64 q4 u64 m → v {
    : u64 t0 & m ^^ p0 q0
    = p0 ^^ p0 t0 = q0 ^^ q0 t0
    : u64 t1 & m ^^ p1 q1
    = p1 ^^ p1 t1 = q1 ^^ q1 t1
    : u64 t2 & m ^^ p2 q2
    = p2 ^^ p2 t2 = q2 ^^ q2 t2
    : u64 t3 & m ^^ p3 q3
    = p3 ^^ p3 t3 = q3 ^^ q3 t3
    : u64 t4 & m ^^ p4 q4
    = p4 ^^ p4 t4 = q4 ^^ q4 t4
}

// o ← o^(2^n): n back-to-back squarings (_sqn25519)
@ __fe_sqn inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 inout u64 o4 i n → v {
    : ~ u64 t0 0
    : ~ u64 t1 0
    : ~ u64 t2 0
    : ~ u64 t3 0
    : ~ u64 t4 0
    : ~ i k 0
    ~ < k n { ( __fe_sq_in t0 t1 t2 t3 t4 o0 o1 o2 o3 o4 ) = o0 t0 = o1 t1 = o2 t2 = o3 t3 = o4 t4 = k + k 1 }
}

// o ← z^(p−2) = 1/z — _inv25519's ref10 addition chain on scalar limbs
@ __fe_inv inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 inout u64 o4 u64 z0 u64 z1 u64 z2 u64 z3 u64 z4 → v {
    : ~ u64 q0 0
    : ~ u64 q1 0
    : ~ u64 q2 0
    : ~ u64 q3 0
    : ~ u64 q4 0
    : ~ u64 n0 0
    : ~ u64 n1 0
    : ~ u64 n2 0
    : ~ u64 n3 0
    : ~ u64 n4 0
    : ~ u64 j0 0
    : ~ u64 j1 0
    : ~ u64 j2 0
    : ~ u64 j3 0
    : ~ u64 j4 0
    : ~ u64 f0 0
    : ~ u64 f1 0
    : ~ u64 f2 0
    : ~ u64 f3 0
    : ~ u64 f4 0
    : ~ u64 g0 0
    : ~ u64 g1 0
    : ~ u64 g2 0
    : ~ u64 g3 0
    : ~ u64 g4 0
    : ~ u64 t0 0
    : ~ u64 t1 0
    : ~ u64 t2 0
    : ~ u64 t3 0
    : ~ u64 t4 0
    : ~ u64 y0 0
    : ~ u64 y1 0
    : ~ u64 y2 0
    : ~ u64 y3 0
    : ~ u64 y4 0
    : ~ u64 w0 0
    : ~ u64 w1 0
    : ~ u64 w2 0
    : ~ u64 w3 0
    : ~ u64 w4 0
    ( __fe_sq q0 q1 q2 q3 q4 z0 z1 z2 z3 z4 )
    // z^2
    ( __fe_sq n0 n1 n2 n3 n4 q0 q1 q2 q3 q4 )
    ( __fe_sq w0 w1 w2 w3 w4 n0 n1 n2 n3 n4 ) = n0 w0 = n1 w1 = n2 w2 = n3 w3 = n4 w4
    ( __fe_mul w0 w1 w2 w3 w4 n0 n1 n2 n3 n4 z0 z1 z2 z3 z4 ) = n0 w0 = n1 w1 = n2 w2 = n3 w3 = n4 w4
    // z^9
    ( __fe_mul j0 j1 j2 j3 j4 n0 n1 n2 n3 n4 q0 q1 q2 q3 q4 )
    // z^11
    ( __fe_sq f0 f1 f2 f3 f4 j0 j1 j2 j3 j4 )
    ( __fe_mul w0 w1 w2 w3 w4 f0 f1 f2 f3 f4 n0 n1 n2 n3 n4 ) = f0 w0 = f1 w1 = f2 w2 = f3 w3 = f4 w4
    // z^(2^5−1)
    = g0 f0 = g1 f1 = g2 f2 = g3 f3 = g4 f4
    ( __fe_sqn g0 g1 g2 g3 g4 5 )
    ( __fe_mul w0 w1 w2 w3 w4 g0 g1 g2 g3 g4 f0 f1 f2 f3 f4 ) = g0 w0 = g1 w1 = g2 w2 = g3 w3 = g4 w4
    // z^(2^10−1)
    = t0 g0 = t1 g1 = t2 g2 = t3 g3 = t4 g4
    ( __fe_sqn t0 t1 t2 t3 t4 10 )
    ( __fe_mul w0 w1 w2 w3 w4 t0 t1 t2 t3 t4 g0 g1 g2 g3 g4 ) = t0 w0 = t1 w1 = t2 w2 = t3 w3 = t4 w4
    // z^(2^20−1)
    = y0 t0 = y1 t1 = y2 t2 = y3 t3 = y4 t4
    ( __fe_sqn y0 y1 y2 y3 y4 20 )
    ( __fe_mul w0 w1 w2 w3 w4 y0 y1 y2 y3 y4 t0 t1 t2 t3 t4 ) = y0 w0 = y1 w1 = y2 w2 = y3 w3 = y4 w4
    // z^(2^40−1)
    ( __fe_sqn y0 y1 y2 y3 y4 10 )
    ( __fe_mul w0 w1 w2 w3 w4 y0 y1 y2 y3 y4 g0 g1 g2 g3 g4 ) = y0 w0 = y1 w1 = y2 w2 = y3 w3 = y4 w4
    // z^(2^50−1)
    = t0 y0 = t1 y1 = t2 y2 = t3 y3 = t4 y4
    ( __fe_sqn t0 t1 t2 t3 t4 50 )
    ( __fe_mul w0 w1 w2 w3 w4 t0 t1 t2 t3 t4 y0 y1 y2 y3 y4 ) = t0 w0 = t1 w1 = t2 w2 = t3 w3 = t4 w4
    // z^(2^100−1)
    = g0 t0 = g1 t1 = g2 t2 = g3 t3 = g4 t4
    ( __fe_sqn g0 g1 g2 g3 g4 100 )
    ( __fe_mul w0 w1 w2 w3 w4 g0 g1 g2 g3 g4 t0 t1 t2 t3 t4 ) = g0 w0 = g1 w1 = g2 w2 = g3 w3 = g4 w4
    // z^(2^200−1)
    ( __fe_sqn g0 g1 g2 g3 g4 50 )
    ( __fe_mul w0 w1 w2 w3 w4 g0 g1 g2 g3 g4 y0 y1 y2 y3 y4 ) = g0 w0 = g1 w1 = g2 w2 = g3 w3 = g4 w4
    // z^(2^250−1)
    ( __fe_sqn g0 g1 g2 g3 g4 5 )
    ( __fe_mul o0 o1 o2 o3 o4 g0 g1 g2 g3 g4 j0 j1 j2 j3 j4 )
    // z^(2^255−21)
}

// ── the ladder ────────────────────────────────────────────────────
// q ← scalar · point, both 32-byte little-endian. Scalar is clamped.
// TweetNaCl's ladder step for step, on the scalar-limb field above:
// a, c are x2, z2 and b, d are x3, z3; t is scratch for a product whose
// destination is also one of its operands.
simd @ __scalarmult ( Vec u ) scalar ( Vec u ) point → ( Vec u ) {
    : u64 sw0 & # u64 ( _ld64u scalar 0 ) 18446744073709551608
    : u64 sw1 # u64 ( _ld64u scalar 8 )
    : u64 sw2 # u64 ( _ld64u scalar 16 )
    : u64 sw3 | & # u64 ( _ld64u scalar 24 ) 9223372036854775807 4611686018427387904

    : u64 x0 & # u64 ( _ld64u point 0 ) 2251799813685247
    : u64 x1 & >> # u64 ( _ld64u point 6 ) 3 2251799813685247
    : u64 x2 & >> # u64 ( _ld64u point 12 ) 6 2251799813685247
    : u64 x3 & >> # u64 ( _ld64u point 19 ) 1 2251799813685247
    : u64 x4 & >> # u64 ( _ld64u point 24 ) 12 2251799813685247
    : ~ u64 a0 1
    : ~ u64 a1 0
    : ~ u64 a2 0
    : ~ u64 a3 0
    : ~ u64 a4 0
    : ~ u64 b0 x0
    : ~ u64 b1 x1
    : ~ u64 b2 x2
    : ~ u64 b3 x3
    : ~ u64 b4 x4
    : ~ u64 c0 0
    : ~ u64 c1 0
    : ~ u64 c2 0
    : ~ u64 c3 0
    : ~ u64 c4 0
    : ~ u64 d0 1
    : ~ u64 d1 0
    : ~ u64 d2 0
    : ~ u64 d3 0
    : ~ u64 d4 0
    : ~ u64 e0 0
    : ~ u64 e1 0
    : ~ u64 e2 0
    : ~ u64 e3 0
    : ~ u64 e4 0
    : ~ u64 f0 0
    : ~ u64 f1 0
    : ~ u64 f2 0
    : ~ u64 f3 0
    : ~ u64 f4 0
    : ~ u64 t0 0
    : ~ u64 t1 0
    : ~ u64 t2 0
    : ~ u64 t3 0
    : ~ u64 t4 0

    : ~ i i 254
    ~ >= i 0 {
        : u64 sw ? >= i 128 ? >= i 192 sw3 sw2 ? >= i 64 sw1 sw0
        : u64 m - # u64 0 & >> sw # u64 & i 63 1
        ( __fe_cswap a0 a1 a2 a3 a4 b0 b1 b2 b3 b4 m )
        ( __fe_cswap c0 c1 c2 c3 c4 d0 d1 d2 d3 d4 m )
        = e0 + a0 c0 = e1 + a1 c1 = e2 + a2 c2 = e3 + a3 c3 = e4 + a4 c4
        = a0 - + a0 4503599627370458 c0 = a1 - + a1 4503599627370494 c1 = a2 - + a2 4503599627370494 c2 = a3 - + a3 4503599627370494 c3 = a4 - + a4 4503599627370494 c4
        = c0 + b0 d0 = c1 + b1 d1 = c2 + b2 d2 = c3 + b3 d3 = c4 + b4 d4
        = b0 - + b0 4503599627370458 d0 = b1 - + b1 4503599627370494 d1 = b2 - + b2 4503599627370494 d2 = b3 - + b3 4503599627370494 d3 = b4 - + b4 4503599627370494 d4
        ( __fe_sq_in d0 d1 d2 d3 d4 e0 e1 e2 e3 e4 )
        ( __fe_sq_in f0 f1 f2 f3 f4 a0 a1 a2 a3 a4 )
        ( __fe_mul_in t0 t1 t2 t3 t4 c0 c1 c2 c3 c4 a0 a1 a2 a3 a4 ) = a0 t0 = a1 t1 = a2 t2 = a3 t3 = a4 t4
        ( __fe_mul_in c0 c1 c2 c3 c4 b0 b1 b2 b3 b4 e0 e1 e2 e3 e4 )
        = e0 + a0 c0 = e1 + a1 c1 = e2 + a2 c2 = e3 + a3 c3 = e4 + a4 c4
        = a0 - + a0 4503599627370458 c0 = a1 - + a1 4503599627370494 c1 = a2 - + a2 4503599627370494 c2 = a3 - + a3 4503599627370494 c3 = a4 - + a4 4503599627370494 c4
        ( __fe_sq_in b0 b1 b2 b3 b4 a0 a1 a2 a3 a4 )
        = c0 - + d0 4503599627370458 f0 = c1 - + d1 4503599627370494 f1 = c2 - + d2 4503599627370494 f2 = c3 - + d3 4503599627370494 f3 = c4 - + d4 4503599627370494 f4
        ( __fe_mul121665 a0 a1 a2 a3 a4 c0 c1 c2 c3 c4 )
        = a0 + a0 d0 = a1 + a1 d1 = a2 + a2 d2 = a3 + a3 d3 = a4 + a4 d4
        ( __fe_mul_in t0 t1 t2 t3 t4 c0 c1 c2 c3 c4 a0 a1 a2 a3 a4 ) = c0 t0 = c1 t1 = c2 t2 = c3 t3 = c4 t4
        ( __fe_mul_in a0 a1 a2 a3 a4 d0 d1 d2 d3 d4 f0 f1 f2 f3 f4 )
        ( __fe_mul_in d0 d1 d2 d3 d4 b0 b1 b2 b3 b4 x0 x1 x2 x3 x4 )
        ( __fe_sq_in b0 b1 b2 b3 b4 e0 e1 e2 e3 e4 )
        ( __fe_cswap a0 a1 a2 a3 a4 b0 b1 b2 b3 b4 m )
        ( __fe_cswap c0 c1 c2 c3 c4 d0 d1 d2 d3 d4 m )
        = i - i 1
    }

    // Recover the affine X-coordinate: x2 · z2^-1. (a = x2, c = z2.)
    : ~ u64 v0 0
    : ~ u64 v1 0
    : ~ u64 v2 0
    : ~ u64 v3 0
    : ~ u64 v4 0
    ( __fe_inv v0 v1 v2 v3 v4 c0 c1 c2 c3 c4 )
    ( __fe_mul t0 t1 t2 t3 t4 a0 a1 a2 a3 a4 v0 v1 v2 v3 v4 )
    ^ ( __fe_pack t0 t1 t2 t3 t4 )
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

// ── niels-form comb table + dedicated double/madd (keygen fast path) ──
//
// The comb used to run a generic 9-_M complete addition twice per
// iteration — once as a doubling, once to add a table entry whose Z is
// 1 by construction. The dedicated shapes below are the ref10/EFD ones:
// an extended-coordinate doubling (dbl-2008-hwcd, a = −1) at 4M+4S and
// a mixed addition against a precomputed NIELS entry (y+x, y−x, 2d·t)
// at 7M. The niels table (16 entries × 15 limbs) is derived ONCE per
// process from the baked affine table and cached in a global — the old
// path re-materialised the 320-limb table on every keygen. Two first
// callers may both build: publish-once slot 4 picks one, and the other
// copy is dropped (slot registry: stdlib/std/tls_server.nu).
: ~ i g_xe_ntbl 0

@ __xe_ntbl_build → v {
    : ( Vec i ) src ( __xe_comb_table )
    : ( Vec i ) d2 ( __xe_d2 )
    : ( Vec i ) ntbl ( vec_with_cap [i] 240 )
    : b _l ( vec_set_len [i] ntbl 240 )
    : *i np ( vec_data [i] ntbl )
    : ( Vec i ) x ( _gf_zero )
    : ( Vec i ) y ( _gf_zero )
    : ( Vec i ) t ( _gf_zero )
    : ( Vec i ) yp ( _gf_zero )
    : ( Vec i ) ym ( _gf_zero )
    : ( Vec i ) t2d ( _gf_zero )
    : *i sp ( vec_data [i] src )
    : *i xp ( vec_data [i] x )
    : *i yq ( vec_data [i] y )
    : *i tp ( vec_data [i] t )
    : *i ypp ( vec_data [i] yp )
    : *i ymp ( vec_data [i] ym )
    : *i tdp ( vec_data [i] t2d )
    : ~ i e 0
    ~ < e 16 {
        : i base * e 20
        : ~ i j 0
        ~ < j 5 {
            = . xp j . sp + base j
            = . yq j . sp + + base 5 j
            = . tp j . sp + + base 15 j
            = j + j 1
        }
        ( _A yp y x )
        ( _Z ym y x )
        ( _M t2d t d2 )
        : i nb * e 15
        = j 0
        ~ < j 5 {
            = . np + nb j . ypp j
            = . np + + nb 5 j . ymp j
            = . np + + nb 10 j . tdp j
            = j + j 1
        }
        = e + e 1
    }
    // The winner lives for the rest of the program, through the global.
    = g_xe_ntbl ( vec_publish_once [i] 4 ntbl )
}

@ __xe_ntbl → ( Vec i ) {
    ? == g_xe_ntbl 0 { ( __xe_ntbl_build ) } {}
    ^ @ ( Vec i ) { # s g_xe_ntbl }
}

// scalar·B via the comb → 32-byte little-endian Montgomery u (the X25519
// public key). Constant-time; no per-call table build or Vec allocations.
simd @ x25519_base_comb ( Vec u ) scalar → ( Vec u ) {
    : u64 sw0 & # u64 ( _ld64u scalar 0 ) 18446744073709551608
    : u64 sw1 # u64 ( _ld64u scalar 8 )
    : u64 sw2 # u64 ( _ld64u scalar 16 )
    : u64 sw3 | & # u64 ( _ld64u scalar 24 ) 9223372036854775807 4611686018427387904

    : ( Vec i ) tbl ( __xe_ntbl )
    : *i tb ( vec_data [i] tbl )
    : ~ u64 px0 0
    : ~ u64 px1 0
    : ~ u64 px2 0
    : ~ u64 px3 0
    : ~ u64 px4 0
    : ~ u64 py0 1
    : ~ u64 py1 0
    : ~ u64 py2 0
    : ~ u64 py3 0
    : ~ u64 py4 0
    : ~ u64 pz0 1
    : ~ u64 pz1 0
    : ~ u64 pz2 0
    : ~ u64 pz3 0
    : ~ u64 pz4 0
    : ~ u64 pt0 0
    : ~ u64 pt1 0
    : ~ u64 pt2 0
    : ~ u64 pt3 0
    : ~ u64 pt4 0
    : ~ u64 a0 0
    : ~ u64 a1 0
    : ~ u64 a2 0
    : ~ u64 a3 0
    : ~ u64 a4 0
    : ~ u64 b0 0
    : ~ u64 b1 0
    : ~ u64 b2 0
    : ~ u64 b3 0
    : ~ u64 b4 0
    : ~ u64 c0 0
    : ~ u64 c1 0
    : ~ u64 c2 0
    : ~ u64 c3 0
    : ~ u64 c4 0
    : ~ u64 e0 0
    : ~ u64 e1 0
    : ~ u64 e2 0
    : ~ u64 e3 0
    : ~ u64 e4 0
    : ~ u64 f0 0
    : ~ u64 f1 0
    : ~ u64 f2 0
    : ~ u64 f3 0
    : ~ u64 f4 0
    : ~ u64 g0 0
    : ~ u64 g1 0
    : ~ u64 g2 0
    : ~ u64 g3 0
    : ~ u64 g4 0
    : ~ u64 h0 0
    : ~ u64 h1 0
    : ~ u64 h2 0
    : ~ u64 h3 0
    : ~ u64 h4 0

    : ~ i i 63
    ~ >= i 0 {
        // __xe_dbl: extended-coordinate doubling (4M + 4S)
        ( __fe_sq_in a0 a1 a2 a3 a4 px0 px1 px2 px3 px4 )
        ( __fe_sq_in b0 b1 b2 b3 b4 py0 py1 py2 py3 py4 )
        ( __fe_sq_in c0 c1 c2 c3 c4 pz0 pz1 pz2 pz3 pz4 )
        = c0 + c0 c0 = c1 + c1 c1 = c2 + c2 c2 = c3 + c3 c3 = c4 + c4 c4
        : ~ u64 cy >> c0 51
        = c0 & c0 2251799813685247
        = c1 + c1 cy = cy >> c1 51 = c1 & c1 2251799813685247
        = c2 + c2 cy = cy >> c2 51 = c2 & c2 2251799813685247
        = c3 + c3 cy = cy >> c3 51 = c3 & c3 2251799813685247
        = c4 + c4 cy = cy >> c4 51 = c4 & c4 2251799813685247
        = c0 + c0 * 19 cy
        = e0 + px0 py0 = e1 + px1 py1 = e2 + px2 py2 = e3 + px3 py3 = e4 + px4 py4
        ( __fe_sq_in f0 f1 f2 f3 f4 e0 e1 e2 e3 e4 )
        ( __fe_sub g0 g1 g2 g3 g4 f0 f1 f2 f3 f4 a0 a1 a2 a3 a4 )
        ( __fe_sub e0 e1 e2 e3 e4 g0 g1 g2 g3 g4 b0 b1 b2 b3 b4 )
        ( __fe_sub g0 g1 g2 g3 g4 b0 b1 b2 b3 b4 a0 a1 a2 a3 a4 )
        ( __fe_sub f0 f1 f2 f3 f4 g0 g1 g2 g3 g4 c0 c1 c2 c3 c4 )
        ( __fe_sub c0 c1 c2 c3 c4 0 0 0 0 0 a0 a1 a2 a3 a4 )
        ( __fe_sub h0 h1 h2 h3 h4 c0 c1 c2 c3 c4 b0 b1 b2 b3 b4 )
        ( __fe_mul_in px0 px1 px2 px3 px4 e0 e1 e2 e3 e4 f0 f1 f2 f3 f4 )
        ( __fe_mul_in py0 py1 py2 py3 py4 g0 g1 g2 g3 g4 h0 h1 h2 h3 h4 )
        ( __fe_mul_in pt0 pt1 pt2 pt3 pt4 e0 e1 e2 e3 e4 h0 h1 h2 h3 h4 )
        ( __fe_mul_in pz0 pz1 pz2 pz3 pz4 f0 f1 f2 f3 f4 g0 g1 g2 g3 g4 )

        // 4-bit comb digit from clamped scalar words
        : u64 sh # u64 i
        : u64 digit | | | & >> sw0 sh 1 << & >> sw1 sh 1 1 << & >> sw2 sh 1 2 << & >> sw3 sh 1 3

        // Constant-time scan of 16 niels entries (15 limbs each)
        : ~ u64 yp0 0
        : ~ u64 yp1 0
        : ~ u64 yp2 0
        : ~ u64 yp3 0
        : ~ u64 yp4 0
        : ~ u64 ym0 0
        : ~ u64 ym1 0
        : ~ u64 ym2 0
        : ~ u64 ym3 0
        : ~ u64 ym4 0
        : ~ u64 td0 0
        : ~ u64 td1 0
        : ~ u64 td2 0
        : ~ u64 td3 0
        : ~ u64 td4 0
        : ~ i e 0
        ~ < e 16 {
            : u64 z ^^ # u64 e digit
            : u64 mask - # u64 0 >> - z 1 63
            : i base * e 15
            = yp0 | yp0 & mask # u64 . tb base
            = yp1 | yp1 & mask # u64 . tb + base 1
            = yp2 | yp2 & mask # u64 . tb + base 2
            = yp3 | yp3 & mask # u64 . tb + base 3
            = yp4 | yp4 & mask # u64 . tb + base 4
            = ym0 | ym0 & mask # u64 . tb + base 5
            = ym1 | ym1 & mask # u64 . tb + base 6
            = ym2 | ym2 & mask # u64 . tb + base 7
            = ym3 | ym3 & mask # u64 . tb + base 8
            = ym4 | ym4 & mask # u64 . tb + base 9
            = td0 | td0 & mask # u64 . tb + base 10
            = td1 | td1 & mask # u64 . tb + base 11
            = td2 | td2 & mask # u64 . tb + base 12
            = td3 | td3 & mask # u64 . tb + base 13
            = td4 | td4 & mask # u64 . tb + base 14
            = e + e 1
        }

        // __xe_madd: mixed addition with niels entry (7M, Z2 = 1)
        ( __fe_sub e0 e1 e2 e3 e4 py0 py1 py2 py3 py4 px0 px1 px2 px3 px4 )
        ( __fe_mul_in a0 a1 a2 a3 a4 e0 e1 e2 e3 e4 ym0 ym1 ym2 ym3 ym4 )
        = f0 + py0 px0 = f1 + py1 px1 = f2 + py2 px2 = f3 + py3 px3 = f4 + py4 px4
        ( __fe_mul_in b0 b1 b2 b3 b4 f0 f1 f2 f3 f4 yp0 yp1 yp2 yp3 yp4 )
        ( __fe_mul_in c0 c1 c2 c3 c4 pt0 pt1 pt2 pt3 pt4 td0 td1 td2 td3 td4 )
        : u64 d0 + pz0 pz0
        : u64 d1 + pz1 pz1
        : u64 d2 + pz2 pz2
        : u64 d3 + pz3 pz3
        : u64 d4 + pz4 pz4
        ( __fe_sub e0 e1 e2 e3 e4 b0 b1 b2 b3 b4 a0 a1 a2 a3 a4 )
        ( __fe_sub f0 f1 f2 f3 f4 d0 d1 d2 d3 d4 c0 c1 c2 c3 c4 )
        = g0 + d0 c0 = g1 + d1 c1 = g2 + d2 c2 = g3 + d3 c3 = g4 + d4 c4
        = h0 + b0 a0 = h1 + b1 a1 = h2 + b2 a2 = h3 + b3 a3 = h4 + b4 a4
        ( __fe_mul_in px0 px1 px2 px3 px4 e0 e1 e2 e3 e4 f0 f1 f2 f3 f4 )
        ( __fe_mul_in py0 py1 py2 py3 py4 g0 g1 g2 g3 g4 h0 h1 h2 h3 h4 )
        ( __fe_mul_in pz0 pz1 pz2 pz3 pz4 g0 g1 g2 g3 g4 f0 f1 f2 f3 f4 )
        ( __fe_mul_in pt0 pt1 pt2 pt3 pt4 e0 e1 e2 e3 e4 h0 h1 h2 h3 h4 )

        = i - i 1
    }

    // Birational map to Montgomery u = (Z + Y) / (Z - Y)
    = a0 + pz0 py0 = a1 + pz1 py1 = a2 + pz2 py2 = a3 + pz3 py3 = a4 + pz4 py4
    ( __fe_sub b0 b1 b2 b3 b4 pz0 pz1 pz2 pz3 pz4 py0 py1 py2 py3 py4 )
    ( __fe_inv c0 c1 c2 c3 c4 b0 b1 b2 b3 b4 )
    ( __fe_mul e0 e1 e2 e3 e4 a0 a1 a2 a3 a4 c0 c1 c2 c3 c4 )
    ^ ( __fe_pack e0 e1 e2 e3 e4 )
}

@ x25519_base ( Vec u ) scalar → ( Vec u ) {
    // Fixed-base: the generator is constant, so a precomputed Edwards comb
    // (x25519_base_comb) beats the Montgomery ladder. Same result, verified
    // against the ladder for the RFC 7748 vectors.
    ^ ( x25519_base_comb scalar )
}
