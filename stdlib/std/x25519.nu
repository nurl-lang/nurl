// stdlib/std/x25519.nu — pure-NURL X25519 (RFC 7748) ECDH.
//
// No OpenSSL, no FFI: a self-contained Montgomery-ladder scalar
// multiplication over GF(2^255 − 19), so a NURL program can do the key
// exchange for TLS 1.3 / Noise / age with nothing installed on the host.
//
// The ladder is RFC 7748's; the field underneath it is GF(2^255 − 19) in
// four saturated 64-bit words, lazily reduced. On the ADX tier its
// products are the compiler's nurl_x25519_mulm / _sqrm blocks and the
// ladder needs no swap (__scalarmult_k); elsewhere each product is one
// `nurl_mac` (__f4_mul_in). The inverse is std/modinv's divsteps. The
// public key (x25519_base) is ref10's signed-digit fixed-base method on
// the equivalent Edwards curve. Every branch is data-independent (swaps,
// picks and table reads are constant-time masks), so both run in
// constant time w.r.t. the scalar.
//
// The five-limb radix-2^51 field (_A / _Z / _M / _S, donna-c64) stays for
// std/ed25519, which is written on it.
//
// Public surface:
//   ( x25519 scalar point ) → ( Vec u )   scalar·point  (both 32 bytes)
//   ( x25519_base scalar )  → ( Vec u )   scalar·basepoint  (the pubkey)
//
// All inputs/outputs are 32-byte `( Vec u )`. Scalars are clamped
// internally per RFC 7748 §5, so any 32 random bytes is a valid secret.

$ `stdlib/core/vec.nu`
$ `stdlib/std/modinv.nu`

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
// makes ~1200 field multiplies and squarings. X25519 itself keeps its
// words in u64 locals (__f4_mul_in / __f4_sq_in) instead. Constant time is unaffected: the trip counts are fixed and
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

// ── the ladder's field: four 64-bit words ─────────────────────────
// The variable-base ladder and the fixed-base keygen keep their field
// elements as u64 locals, FOUR to an element — the saturated radix-2^64
// form — and a field operation takes its operands by value and writes the
// words of its result `inout`.
//
// Why four words and not donna's five 51-bit limbs (the _A/_Z/_M/_S
// field above, which ed25519 keeps): a multiply is 16 products and the
// reduction 4 more (2^256 ≡ 38), against 25; a square 10 + 4 against 15;
// and an element is four registers, not five, in a ladder step that keeps
// five elements live. Every product step is one `nurl_mac` — the
// backend's widening multiply with the carry threaded through the flags
// as an add/adc chain — so measured on its own the multiply ran 21 %
// faster than the five-limb one, and the ladder step lost about a third
// of its instructions. What the saturated form costs back is a carry
// chain on add and subtract (8 a step).
//
// Values are kept LAZILY reduced: any 256-bit pattern is a valid element
// (it stands for itself mod p), and every operation maps operands
// < 2^256 to a result < 2^256 by folding the carry out of bit 256 back in
// as 38. Only __f4_pack reduces to the canonical residue. Every step is a
// fixed sequence of instructions: nothing branches on the data.

// o ← a + b
inline @ __f4_add inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 u64 a0 u64 a1 u64 a2 u64 a3 u64 b0 u64 b1 u64 b2 u64 b3 → v {
    : u64 s0 ( nurl_addc_lo a0 b0 0 )
    : u64 c0 ( nurl_addc_hi a0 b0 0 )
    : u64 s1 ( nurl_addc_lo a1 b1 c0 )
    : u64 c1 ( nurl_addc_hi a1 b1 c0 )
    : u64 s2 ( nurl_addc_lo a2 b2 c1 )
    : u64 c2 ( nurl_addc_hi a2 b2 c1 )
    : u64 s3 ( nurl_addc_lo a3 b3 c2 )
    : u64 c3 ( nurl_addc_hi a3 b3 c2 )
    : u64 m * c3 38
    : u64 r0 ( nurl_addc_lo s0 m 0 )
    : u64 k0 ( nurl_addc_hi s0 m 0 )
    : u64 r1 ( nurl_addc_lo s1 0 k0 )
    : u64 k1 ( nurl_addc_hi s1 0 k0 )
    : u64 r2 ( nurl_addc_lo s2 0 k1 )
    : u64 k2 ( nurl_addc_hi s2 0 k1 )
    = o3 ( nurl_addc_lo s3 0 k2 )
    : u64 k3 ( nurl_addc_hi s3 0 k2 )
    = o0 + r0 * k3 38
    = o1 r1
    = o2 r2
}

// o ← a − b. A borrow out of bit 256 means the words hold a − b + 2^256,
// which is 38 too much: take 38 away, and if that borrows too (the words
// were < 38) the result is ≥ 2^256 − 38, so the second 38 comes off o0
// with no borrow.
inline @ __f4_sub inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 u64 a0 u64 a1 u64 a2 u64 a3 u64 b0 u64 b1 u64 b2 u64 b3 → v {
    : u64 d0 ( nurl_subb_lo a0 b0 0 )
    : u64 w0 ( nurl_subb_hi a0 b0 0 )
    : u64 d1 ( nurl_subb_lo a1 b1 w0 )
    : u64 w1 ( nurl_subb_hi a1 b1 w0 )
    : u64 d2 ( nurl_subb_lo a2 b2 w1 )
    : u64 w2 ( nurl_subb_hi a2 b2 w1 )
    : u64 d3 ( nurl_subb_lo a3 b3 w2 )
    : u64 w3 ( nurl_subb_hi a3 b3 w2 )
    : u64 m * w3 38
    : u64 r0 ( nurl_subb_lo d0 m 0 )
    : u64 k0 ( nurl_subb_hi d0 m 0 )
    : u64 r1 ( nurl_subb_lo d1 0 k0 )
    : u64 k1 ( nurl_subb_hi d1 0 k0 )
    : u64 r2 ( nurl_subb_lo d2 0 k1 )
    : u64 k2 ( nurl_subb_hi d2 0 k1 )
    = o3 ( nurl_subb_lo d3 0 k2 )
    : u64 k3 ( nurl_subb_hi d3 0 k2 )
    = o0 - r0 * k3 38
    = o1 r1
    = o2 r2
}

// The 512-bit (t0 … t7) mod p: t + 38·(the high four words), whose carry
// out is ≤ 38, then folded back.
inline @ __f4_reduce inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 u64 t0 u64 t1 u64 t2 u64 t3 u64 t4 u64 t5 u64 t6 u64 t7 → v {
    : u64 r0 ( nurl_mac_lo t4 38 t0 0 )
    : ~ u64 cr ( nurl_mac_hi t4 38 t0 0 )
    : u64 r1 ( nurl_mac_lo t5 38 t1 cr )
    = cr ( nurl_mac_hi t5 38 t1 cr )
    : u64 r2 ( nurl_mac_lo t6 38 t2 cr )
    = cr ( nurl_mac_hi t6 38 t2 cr )
    : u64 r3 ( nurl_mac_lo t7 38 t3 cr )
    = cr ( nurl_mac_hi t7 38 t3 cr )
    : u64 m * cr 38
    : u64 s0 ( nurl_addc_lo r0 m 0 )
    : u64 k0 ( nurl_addc_hi r0 m 0 )
    : u64 s1 ( nurl_addc_lo r1 0 k0 )
    : u64 k1 ( nurl_addc_hi r1 0 k0 )
    : u64 s2 ( nurl_addc_lo r2 0 k1 )
    : u64 k2 ( nurl_addc_hi r2 0 k1 )
    = o3 ( nurl_addc_lo r3 0 k2 )
    : u64 k3 ( nurl_addc_hi r3 0 k2 )
    = o0 + s0 * k3 38
    = o1 s1
    = o2 s2
}

// o ← a · b: the 4×4 schoolbook, row by row, each row one carry chain.
inline @ __f4_mul_in inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 u64 a0 u64 a1 u64 a2 u64 a3 u64 b0 u64 b1 u64 b2 u64 b3 → v {
    : ~ u64 x 0
    : ~ u64 cr ( nurl_umulhi a0 b0 )
    : u64 t0 * a0 b0
    : ~ u64 t1 ( nurl_mac_lo a1 b0 cr 0 )
    = cr ( nurl_mac_hi a1 b0 cr 0 )
    : ~ u64 t2 ( nurl_mac_lo a2 b0 cr 0 )
    = cr ( nurl_mac_hi a2 b0 cr 0 )
    : ~ u64 t3 ( nurl_mac_lo a3 b0 cr 0 )
    : ~ u64 t4 ( nurl_mac_hi a3 b0 cr 0 )
    = x ( nurl_mac_lo a0 b1 t1 0 ) = cr ( nurl_mac_hi a0 b1 t1 0 ) = t1 x
    = x ( nurl_mac_lo a1 b1 t2 cr ) = cr ( nurl_mac_hi a1 b1 t2 cr ) = t2 x
    = x ( nurl_mac_lo a2 b1 t3 cr ) = cr ( nurl_mac_hi a2 b1 t3 cr ) = t3 x
    = x ( nurl_mac_lo a3 b1 t4 cr )
    : ~ u64 t5 ( nurl_mac_hi a3 b1 t4 cr )
    = t4 x
    = x ( nurl_mac_lo a0 b2 t2 0 ) = cr ( nurl_mac_hi a0 b2 t2 0 ) = t2 x
    = x ( nurl_mac_lo a1 b2 t3 cr ) = cr ( nurl_mac_hi a1 b2 t3 cr ) = t3 x
    = x ( nurl_mac_lo a2 b2 t4 cr ) = cr ( nurl_mac_hi a2 b2 t4 cr ) = t4 x
    = x ( nurl_mac_lo a3 b2 t5 cr )
    : ~ u64 t6 ( nurl_mac_hi a3 b2 t5 cr )
    = t5 x
    = x ( nurl_mac_lo a0 b3 t3 0 ) = cr ( nurl_mac_hi a0 b3 t3 0 ) = t3 x
    = x ( nurl_mac_lo a1 b3 t4 cr ) = cr ( nurl_mac_hi a1 b3 t4 cr ) = t4 x
    = x ( nurl_mac_lo a2 b3 t5 cr ) = cr ( nurl_mac_hi a2 b3 t5 cr ) = t5 x
    = x ( nurl_mac_lo a3 b3 t6 cr )
    : u64 t7 ( nurl_mac_hi a3 b3 t6 cr )
    = t6 x
    ( __f4_reduce o0 o1 o2 o3 t0 t1 t2 t3 t4 t5 t6 t7 )
}

// o ← a²: the six cross products once, doubled by a shift, then the four
// squares on the diagonal — 10 products where the multiply takes 16.
inline @ __f4_sq_in inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 u64 a0 u64 a1 u64 a2 u64 a3 → v {
    : ~ u64 x 0
    : ~ u64 cr ( nurl_umulhi a0 a1 )
    : ~ u64 t1 * a0 a1
    : ~ u64 t2 ( nurl_mac_lo a0 a2 cr 0 )
    = cr ( nurl_mac_hi a0 a2 cr 0 )
    : ~ u64 t3 ( nurl_mac_lo a0 a3 cr 0 )
    : ~ u64 t4 ( nurl_mac_hi a0 a3 cr 0 )
    = x ( nurl_mac_lo a1 a2 t3 0 ) = cr ( nurl_mac_hi a1 a2 t3 0 ) = t3 x
    = x ( nurl_mac_lo a1 a3 t4 cr )
    : ~ u64 t5 ( nurl_mac_hi a1 a3 t4 cr )
    = t4 x
    = x ( nurl_mac_lo a2 a3 t5 0 )
    : ~ u64 t6 ( nurl_mac_hi a2 a3 t5 0 )
    = t5 x
    : u64 t7 >> t6 63
    = t6 | << t6 1 >> t5 63
    = t5 | << t5 1 >> t4 63
    = t4 | << t4 1 >> t3 63
    = t3 | << t3 1 >> t2 63
    = t2 | << t2 1 >> t1 63
    = t1 << t1 1
    : u64 h0 ( nurl_umulhi a0 a0 )
    : u64 r1 ( nurl_addc_lo t1 h0 0 )
    : u64 k1 ( nurl_addc_hi t1 h0 0 )
    : u64 r2 ( nurl_mac_lo a1 a1 t2 k1 )
    : u64 g2 ( nurl_mac_hi a1 a1 t2 k1 )
    : u64 r3 ( nurl_addc_lo t3 g2 0 )
    : u64 k3 ( nurl_addc_hi t3 g2 0 )
    : u64 r4 ( nurl_mac_lo a2 a2 t4 k3 )
    : u64 g4 ( nurl_mac_hi a2 a2 t4 k3 )
    : u64 r5 ( nurl_addc_lo t5 g4 0 )
    : u64 k5 ( nurl_addc_hi t5 g4 0 )
    : u64 r6 ( nurl_mac_lo a3 a3 t6 k5 )
    : u64 g6 ( nurl_mac_hi a3 a3 t6 k5 )
    ( __f4_reduce o0 o1 o2 o3 * a0 a0 r1 r2 r3 r4 r5 r6 + t7 g6 )
}

// o ← a · 121665 (the ladder's a24): four products, the top word < 2^17.
inline @ __f4_mul121665 inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 u64 a0 u64 a1 u64 a2 u64 a3 → v {
    : u64 l0 * a0 121665
    : ~ u64 cr ( nurl_umulhi a0 121665 )
    : u64 l1 ( nurl_mac_lo a1 121665 cr 0 )
    = cr ( nurl_mac_hi a1 121665 cr 0 )
    : u64 l2 ( nurl_mac_lo a2 121665 cr 0 )
    = cr ( nurl_mac_hi a2 121665 cr 0 )
    : u64 l3 ( nurl_mac_lo a3 121665 cr 0 )
    = cr ( nurl_mac_hi a3 121665 cr 0 )
    : u64 m * cr 38
    : u64 r0 ( nurl_addc_lo l0 m 0 )
    : u64 k0 ( nurl_addc_hi l0 m 0 )
    : u64 r1 ( nurl_addc_lo l1 0 k0 )
    : u64 k1 ( nurl_addc_hi l1 0 k0 )
    : u64 r2 ( nurl_addc_lo l2 0 k1 )
    : u64 k2 ( nurl_addc_hi l2 0 k1 )
    = o3 ( nurl_addc_lo l3 0 k2 )
    : u64 k3 ( nurl_addc_hi l3 0 k2 )
    = o0 + r0 * k3 38
    = o1 r1
    = o2 r2
}

// The multiply out of line, for the one-time table build and the
// ladder's final product — callers that are not a hot loop body.
@ __f4_mul inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 u64 a0 u64 a1 u64 a2 u64 a3 u64 b0 u64 b1 u64 b2 u64 b3 → v {
    ( __f4_mul_in o0 o1 o2 o3 a0 a1 a2 a3 b0 b1 b2 b3 )
}

// p, q ← q, p when m is all ones, unchanged when m is 0 — constant time.
inline @ __f4_cswap inout u64 p0 inout u64 p1 inout u64 p2 inout u64 p3 inout u64 q0 inout u64 q1 inout u64 q2 inout u64 q3 u64 m → v {
    : u64 t0 & m ^^ p0 q0
    = p0 ^^ p0 t0 = q0 ^^ q0 t0
    : u64 t1 & m ^^ p1 q1
    = p1 ^^ p1 t1 = q1 ^^ q1 t1
    : u64 t2 & m ^^ p2 q2
    = p2 ^^ p2 t2 = q2 ^^ q2 t2
    : u64 t3 & m ^^ p3 q3
    = p3 ^^ p3 t3 = q3 ^^ q3 t3
}

// o ← the canonical residue of a (< 2^256): fold bit 255 in as 19 (now
// a < 2^255 + 19), then a ≥ p exactly when a + 19 has bit 255 set, and
// a − p is that sum without it — chosen by mask.
inline @ __f4_canon inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 u64 a0 u64 a1 u64 a2 u64 a3 → v {
    : u64 top >> a3 63
    : u64 m * top 19
    : u64 v0 ( nurl_addc_lo a0 m 0 )
    : u64 k0 ( nurl_addc_hi a0 m 0 )
    : u64 v1 ( nurl_addc_lo a1 0 k0 )
    : u64 k1 ( nurl_addc_hi a1 0 k0 )
    : u64 v2 ( nurl_addc_lo a2 0 k1 )
    : u64 k2 ( nurl_addc_hi a2 0 k1 )
    : u64 v3 + & a3 9223372036854775807 k2
    : u64 w0 ( nurl_addc_lo v0 19 0 )
    : u64 c0 ( nurl_addc_hi v0 19 0 )
    : u64 w1 ( nurl_addc_lo v1 0 c0 )
    : u64 c1 ( nurl_addc_hi v1 0 c0 )
    : u64 w2 ( nurl_addc_lo v2 0 c1 )
    : u64 c2 ( nurl_addc_hi v2 0 c1 )
    : u64 w3 + v3 c2
    : u64 ge - # u64 0 >> w3 63
    = o0 | & ge w0 & ^^ ge 18446744073709551615 v0
    = o1 | & ge w1 & ^^ ge 18446744073709551615 v1
    = o2 | & ge w2 & ^^ ge 18446744073709551615 v2
    = o3 | & ge & w3 9223372036854775807 & ^^ ge 18446744073709551615 v3
}

// o ← 1/z (0 for 0): the divsteps of std/modinv over p = 2^255 − 19
// (−19 + 128·2^248 in signed-62 form), on z reduced first — the walk's
// bound is for z < p. Constant time, ~2.4 µs on Skylake; Fermat's chain
// (254 squarings, 11 multiplies) is a serial chain of their latencies,
// ~3.9 µs even on the ADX kernels.
@ __f4_inv inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 u64 z0 u64 z1 u64 z2 u64 z3 → v {
    : ~ u64 c0 0
    : ~ u64 c1 0
    : ~ u64 c2 0
    : ~ u64 c3 0
    ( __f4_canon c0 c1 c2 c3 z0 z1 z2 z3 )
    ( _modinv256 o0 o1 o2 o3 c0 c1 c2 c3 -19 0 0 0 128 4126245384908715493 )
}

// The canonical residue of a (< 2^256) as 32 little-endian bytes.
@ __f4_pack u64 a0 u64 a1 u64 a2 u64 a3 → ( Vec u ) {
    : ~ u64 r0 0
    : ~ u64 r1 0
    : ~ u64 r2 0
    : ~ u64 r3 0
    ( __f4_canon r0 r1 r2 r3 a0 a1 a2 a3 )
    : ( Vec u ) o ( vec_with_cap [u] 32 )
    : b _l ( vec_set_len [u] o 32 )
    : *u op ( vec_data [u] o )
    : ~ i k 0
    ~ < k 8 {
        : u64 sh # u64 * 8 k
        = . op k # u & >> r0 sh 255
        = . op + k 8 # u & >> r1 sh 255
        = . op + k 16 # u & >> r2 sh 255
        = . op + k 24 # u & >> r3 sh 255
        = k + k 1
    }
    ^ o
}

// ── the field in memory, on the compiler's kernels ────────────────
// On the ADX tier the compiler emits the multiply and the square as one
// block each (nurl_x25519_mulm / nurl_x25519_sqrm: mulx with adcx and
// adox), over four words in memory and in the lazy form above. Their
// operands come from memory, so the ladder that uses them keeps its
// elements in one buffer, and the additions here read and write it too.
// A kernel says F where there is none (no ADX, or not x86-64); each
// helper then falls back to the register form, but the ladders below are
// only entered after a T.

// Element k of a buffer of elements: four words, 32 bytes each.
inline @ __xk_at * u64 w i k → *u64 { ^ # *u64 + # i w * k 32 }

@ __xk_mul_port * u64 o * u64 a * u64 b → v {
    : ~ u64 r0 0
    : ~ u64 r1 0
    : ~ u64 r2 0
    : ~ u64 r3 0
    ( __f4_mul_in r0 r1 r2 r3 . a 0 . a 1 . a 2 . a 3 . b 0 . b 1 . b 2 . b 3 )
    = . o 0 r0 = . o 1 r1 = . o 2 r2 = . o 3 r3
}

// o ← a · b and o ← a²; o may be a or b.
inline @ __xk_mul * u64 o * u64 a * u64 b → v { ? ( nurl_x25519_mulm o a b ) {} { ( __xk_mul_port o a b ) } }

inline @ __xk_sq * u64 o * u64 a → v { ? ( nurl_x25519_sqrm o a ) {} { ( __xk_mul_port o a a ) } }

// o ← a + b and o ← a − b (__f4_add / __f4_sub over the buffer).
inline @ __xk_add * u64 o * u64 a * u64 b → v {
    : ~ u64 r0 0
    : ~ u64 r1 0
    : ~ u64 r2 0
    : ~ u64 r3 0
    ( __f4_add r0 r1 r2 r3 . a 0 . a 1 . a 2 . a 3 . b 0 . b 1 . b 2 . b 3 )
    = . o 0 r0 = . o 1 r1 = . o 2 r2 = . o 3 r3
}

inline @ __xk_sub * u64 o * u64 a * u64 b → v {
    : ~ u64 r0 0
    : ~ u64 r1 0
    : ~ u64 r2 0
    : ~ u64 r3 0
    ( __f4_sub r0 r1 r2 r3 . a 0 . a 1 . a 2 . a 3 . b 0 . b 1 . b 2 . b 3 )
    = . o 0 r0 = . o 1 r1 = . o 2 r2 = . o 3 r3
}

// o ← x where m is all ones, y where m is 0 — constant time.
inline @ __xk_mux * u64 o * u64 x * u64 y u64 m → v {
    = . o 0 ^^ . y 0 & m ^^ . x 0 . y 0
    = . o 1 ^^ . y 1 & m ^^ . x 1 . y 1
    = . o 2 ^^ . y 2 & m ^^ . x 2 . y 2
    = . o 3 ^^ . y 3 & m ^^ . x 3 . y 3
}

// o ← 121666·p + d. The sum is below 2^274; everything from bit 255 up,
// times 19, folds into word 0 with no carry out of word 3.
inline @ __xk_cmadd * u64 o * u64 p * u64 d → v {
    : u64 l0 ( nurl_mac_lo . p 0 121666 . d 0 0 )
    : ~ u64 cr ( nurl_mac_hi . p 0 121666 . d 0 0 )
    : u64 l1 ( nurl_mac_lo . p 1 121666 . d 1 cr )
    = cr ( nurl_mac_hi . p 1 121666 . d 1 cr )
    : u64 l2 ( nurl_mac_lo . p 2 121666 . d 2 cr )
    = cr ( nurl_mac_hi . p 2 121666 . d 2 cr )
    : u64 l3 ( nurl_mac_lo . p 3 121666 . d 3 cr )
    = cr ( nurl_mac_hi . p 3 121666 . d 3 cr )
    : u64 m * | << cr 1 >> l3 63 19
    : u64 r0 ( nurl_addc_lo l0 m 0 )
    : u64 k0 ( nurl_addc_hi l0 m 0 )
    : u64 r1 ( nurl_addc_lo l1 0 k0 )
    : u64 k1 ( nurl_addc_hi l1 0 k0 )
    : u64 r2 ( nurl_addc_lo l2 0 k1 )
    : u64 k2 ( nurl_addc_hi l2 0 k1 )
    = . o 0 r0 = . o 1 r1 = . o 2 r2
    = . o 3 + & l3 9223372036854775807 k2
}

// (ox : oz) ← 2·(x : z): d = (x − z)², s = (x + z)², p = s − d = 4xz,
// ox = s·d, oz = p·(d + 121666·p). d, s, p, e are scratch; (ox, oz)
// may be (x, z).
@ __xk_dbl * u64 ox * u64 oz * u64 x * u64 z * u64 d * u64 s * u64 p * u64 e → v {
    ( __xk_sub d x z )
    ( __xk_add s x z )
    ( __xk_sq d d )
    ( __xk_sq s s )
    ( __xk_sub p s d )
    ( __xk_cmadd e p d )
    ( __xk_mul ox s d )
    ( __xk_mul oz p e )
}

// o ← 1/z (0 for 0), __f4_inv over the buffer.
@ __xk_inv * u64 o * u64 z → v {
    : ~ u64 r0 0
    : ~ u64 r1 0
    : ~ u64 r2 0
    : ~ u64 r3 0
    ( __f4_inv r0 r1 r2 r3 . z 0 . z 1 . z 2 . z 3 )
    = . o 0 r0 = . o 1 r1 = . o 2 r2 = . o 3 r3
}

// The ladder on the kernels. Its two points are kept as m — the one the
// last step ADDED to — and n — the one it DOUBLED — and `swap` says
// which of them is k·P: n when the last bit was 0, m when it was 1. A
// step adds m and n (symmetric, so neither needs swapping), and doubles
// the one the next bit asks for, chosen by mask (__xk_mux) on whether
// that bit differs from `swap`; the sum goes to m, the double to n. The
// clamped scalar's bit 254 is 1 and bits 2 … 0 are 0, so the walk starts
// at m = P, n = 2P and ends with three plain doublings. Same result as
// __scalarmult's register ladder (x25519_kernel_agrees holds them to
// each other); w is a buffer of 17 zeroed elements.
@ __scalarmult_k * u64 w ( Vec u ) scalar ( Vec u ) point → ( Vec u ) {
    : *u64 xm ( __xk_at w 0 )
    : *u64 zm ( __xk_at w 1 )
    : *u64 xn ( __xk_at w 2 )
    : *u64 zn ( __xk_at w 3 )
    : *u64 dm ( __xk_at w 4 )
    : *u64 sm ( __xk_at w 5 )
    : *u64 dn ( __xk_at w 6 )
    : *u64 sn ( __xk_at w 7 )
    : *u64 d ( __xk_at w 8 )
    : *u64 sq ( __xk_at w 9 )
    : *u64 p ( __xk_at w 10 )
    : *u64 e ( __xk_at w 11 )
    : *u64 dmsn ( __xk_at w 12 )
    : *u64 dnsm ( __xk_at w 13 )
    : *u64 dpro ( __xk_at w 14 )
    : *u64 spro ( __xk_at w 15 )
    : *u64 u ( __xk_at w 16 )
    : u64 sw0 & # u64 ( _ld64u scalar 0 ) 18446744073709551608
    : u64 sw1 # u64 ( _ld64u scalar 8 )
    : u64 sw2 # u64 ( _ld64u scalar 16 )
    : u64 sw3 | & # u64 ( _ld64u scalar 24 ) 9223372036854775807 4611686018427387904
    = . u 0 # u64 ( _ld64u point 0 )
    = . u 1 # u64 ( _ld64u point 8 )
    = . u 2 # u64 ( _ld64u point 16 )
    = . u 3 & # u64 ( _ld64u point 24 ) 9223372036854775807
    // bit 254: m = (u : 1), n = 2·(u : 1)
    = . xm 0 . u 0 = . xm 1 . u 1 = . xm 2 . u 2 = . xm 3 . u 3
    = . zm 0 1 = . zm 1 0 = . zm 2 0 = . zm 3 0
    ( __xk_dbl xn zn xm zm d sq p e )
    : ~ u64 swap 1
    : ~ i i 253
    ~ >= i 3 {
        ( __xk_sub dm xm zm )
        ( __xk_add sn xn zn )
        ( __xk_sub dn xn zn )
        ( __xk_add sm xm zm )
        : u64 sw ? >= i 128 ? >= i 192 sw3 sw2 ? >= i 64 sw1 sw0
        : u64 kt & >> sw # u64 & i 63 1
        : u64 m - # u64 0 ^^ kt swap
        = swap kt
        // the point to double: m when the bit differs from swap, else n
        ( __xk_mux d dm dn m )
        ( __xk_mux sq sm sn m )
        // adding: x_m' = (dm·sn + sm·dn)², z_m' = u·(dm·sn − sm·dn)²
        ( __xk_mul dnsm sm dn )
        ( __xk_mul dmsn sn dm )
        ( __xk_sq d d )
        ( __xk_sub dpro dmsn dnsm )
        ( __xk_add spro dmsn dnsm )
        ( __xk_sq sq sq )
        ( __xk_sq dpro dpro )
        // doubling: p = s − d, e = 121666·p + d, x_n' = s·d, z_n' = p·e
        ( __xk_sub p sq d )
        ( __xk_sq xm spro )
        ( __xk_cmadd e p d )
        ( __xk_mul xn sq d )
        ( __xk_mul zn p e )
        ( __xk_mul zm dpro u )
        = i - i 1
    }
    : u64 mf - # u64 0 swap
    ( __xk_mux xn xm xn mf )
    ( __xk_mux zn zm zn mf )
    ( __xk_dbl xn zn xn zn d sq p e )
    ( __xk_dbl xn zn xn zn d sq p e )
    ( __xk_dbl xn zn xn zn d sq p e )
    // The affine u: x · z^−1 (z = 0 — a low-order point — gives 0).
    ( __xk_inv spro zn )
    ( __xk_mul d xn spro )
    ^ ( __f4_pack . d 0 . d 1 . d 2 . d 3 )
}

// ── the register ladder ───────────────────────────────────────────
// The ladder where the target has no kernels (and the reference the
// kernels' ladder is tested against).
// q ← scalar · point, both 32-byte little-endian; the scalar is clamped
// and the point's top bit dropped (RFC 7748 §5). RFC 7748's ladder step
// for step: (x2 : z2) and (x3 : z3) are k·P and (k + 1)·P for the bits
// consumed so far, and one conditional swap per bit — keyed by whether
// the bit CHANGED — keeps the step's formulas fixed. Constant time: the
// bit only ever reaches a mask.
@ __scalarmult_r ( Vec u ) scalar ( Vec u ) point → ( Vec u ) {
    : u64 sw0 & # u64 ( _ld64u scalar 0 ) 18446744073709551608
    : u64 sw1 # u64 ( _ld64u scalar 8 )
    : u64 sw2 # u64 ( _ld64u scalar 16 )
    : u64 sw3 | & # u64 ( _ld64u scalar 24 ) 9223372036854775807 4611686018427387904

    : u64 u0 # u64 ( _ld64u point 0 )
    : u64 u1 # u64 ( _ld64u point 8 )
    : u64 u2 # u64 ( _ld64u point 16 )
    : u64 u3 & # u64 ( _ld64u point 24 ) 9223372036854775807
    : ~ u64 x20 1
    : ~ u64 x21 0
    : ~ u64 x22 0
    : ~ u64 x23 0
    : ~ u64 z20 0
    : ~ u64 z21 0
    : ~ u64 z22 0
    : ~ u64 z23 0
    : ~ u64 x30 u0
    : ~ u64 x31 u1
    : ~ u64 x32 u2
    : ~ u64 x33 u3
    : ~ u64 z30 1
    : ~ u64 z31 0
    : ~ u64 z32 0
    : ~ u64 z33 0
    : ~ u64 a0 0
    : ~ u64 a1 0
    : ~ u64 a2 0
    : ~ u64 a3 0
    : ~ u64 b0 0
    : ~ u64 b1 0
    : ~ u64 b2 0
    : ~ u64 b3 0
    : ~ u64 c0 0
    : ~ u64 c1 0
    : ~ u64 c2 0
    : ~ u64 c3 0
    : ~ u64 d0 0
    : ~ u64 d1 0
    : ~ u64 d2 0
    : ~ u64 d3 0
    : ~ u64 e0 0
    : ~ u64 e1 0
    : ~ u64 e2 0
    : ~ u64 e3 0
    : ~ u64 f0 0
    : ~ u64 f1 0
    : ~ u64 f2 0
    : ~ u64 f3 0
    : ~ u64 swap 0

    : ~ i i 254
    ~ >= i 0 {
        : u64 sw ? >= i 128 ? >= i 192 sw3 sw2 ? >= i 64 sw1 sw0
        : u64 kt & >> sw # u64 & i 63 1
        : u64 m - # u64 0 ^^ swap kt
        = swap kt
        ( __f4_cswap x20 x21 x22 x23 x30 x31 x32 x33 m )
        ( __f4_cswap z20 z21 z22 z23 z30 z31 z32 z33 m )
        // A = x2 + z2, B = x2 − z2, C = x3 + z3, D = x3 − z3
        ( __f4_add a0 a1 a2 a3 x20 x21 x22 x23 z20 z21 z22 z23 )
        ( __f4_sub b0 b1 b2 b3 x20 x21 x22 x23 z20 z21 z22 z23 )
        ( __f4_add c0 c1 c2 c3 x30 x31 x32 x33 z30 z31 z32 z33 )
        ( __f4_sub d0 d1 d2 d3 x30 x31 x32 x33 z30 z31 z32 z33 )
        // DA = D·A (e), CB = C·B (f); AA = A² (c), BB = B² (d)
        ( __f4_mul_in e0 e1 e2 e3 d0 d1 d2 d3 a0 a1 a2 a3 )
        ( __f4_mul_in f0 f1 f2 f3 c0 c1 c2 c3 b0 b1 b2 b3 )
        ( __f4_sq_in c0 c1 c2 c3 a0 a1 a2 a3 )
        ( __f4_sq_in d0 d1 d2 d3 b0 b1 b2 b3 )
        // x3 = (DA + CB)², z3 = u · (DA − CB)²
        ( __f4_add a0 a1 a2 a3 e0 e1 e2 e3 f0 f1 f2 f3 )
        ( __f4_sub b0 b1 b2 b3 e0 e1 e2 e3 f0 f1 f2 f3 )
        ( __f4_sq_in x30 x31 x32 x33 a0 a1 a2 a3 )
        ( __f4_sq_in e0 e1 e2 e3 b0 b1 b2 b3 )
        ( __f4_mul_in z30 z31 z32 z33 u0 u1 u2 u3 e0 e1 e2 e3 )
        // x2 = AA·BB; E = AA − BB (f); z2 = E · (AA + a24·E)
        ( __f4_mul_in x20 x21 x22 x23 c0 c1 c2 c3 d0 d1 d2 d3 )
        ( __f4_sub f0 f1 f2 f3 c0 c1 c2 c3 d0 d1 d2 d3 )
        ( __f4_mul121665 a0 a1 a2 a3 f0 f1 f2 f3 )
        ( __f4_add b0 b1 b2 b3 a0 a1 a2 a3 c0 c1 c2 c3 )
        ( __f4_mul_in z20 z21 z22 z23 f0 f1 f2 f3 b0 b1 b2 b3 )
        = i - i 1
    }
    : u64 mf - # u64 0 swap
    ( __f4_cswap x20 x21 x22 x23 x30 x31 x32 x33 mf )
    ( __f4_cswap z20 z21 z22 z23 z30 z31 z32 z33 mf )

    // The affine u: x2 · z2^−1 (z2 = 0 — a low-order point — gives 0).
    ( __f4_inv a0 a1 a2 a3 z20 z21 z22 z23 )
    ( __f4_mul b0 b1 b2 b3 x20 x21 x22 x23 a0 a1 a2 a3 )
    ^ ( __f4_pack b0 b1 b2 b3 )
}

// The kernels' ladder where the target has the kernels (a square of the
// zeroed buffer asks), else the register ladder.
@ __scalarmult ( Vec u ) scalar ( Vec u ) point → ( Vec u ) {
    : ( Vec u64 ) kb ( vec_zeroed [u64] 68 )
    : *u64 kw ( vec_data [u64] kb )
    ? ( nurl_x25519_sqrm kw kw ) { ^ ( __scalarmult_k kw scalar point ) } {}
    ^ ( __scalarmult_r scalar point )
}

// ── for x25519_kernel_agrees: the kernels against the register form ──
// Elements are 32 little-endian bytes — any 256-bit pattern — and come
// back reduced. `over` writes the kernel's result over its first operand
// (the ladder's own `( __xk_sq d d )`).
@ __xk_load * u64 o ( Vec u ) a → v {
    = . o 0 # u64 ( _ld64u a 0 )
    = . o 1 # u64 ( _ld64u a 8 )
    = . o 2 # u64 ( _ld64u a 16 )
    = . o 3 # u64 ( _ld64u a 24 )
}

@ _x25519_mul_k ( Vec u ) a ( Vec u ) b b over → ( Vec u ) {
    : ( Vec u64 ) kb ( vec_zeroed [u64] 12 )
    : *u64 x ( vec_data [u64] kb )
    : *u64 y ( __xk_at x 1 )
    : *u64 r ? over x ( __xk_at x 2 )
    ( __xk_load x a )
    ( __xk_load y b )
    ( __xk_mul r x y )
    ^ ( __f4_pack . r 0 . r 1 . r 2 . r 3 )
}

@ _x25519_sq_k ( Vec u ) a b over → ( Vec u ) {
    : ( Vec u64 ) kb ( vec_zeroed [u64] 8 )
    : *u64 x ( vec_data [u64] kb )
    : *u64 r ? over x ( __xk_at x 1 )
    ( __xk_load x a )
    ( __xk_sq r x )
    ^ ( __f4_pack . r 0 . r 1 . r 2 . r 3 )
}

@ _x25519_mul_r ( Vec u ) a ( Vec u ) b → ( Vec u ) {
    : ~ u64 w0 0
    : ~ u64 w1 0
    : ~ u64 w2 0
    : ~ u64 w3 0
    ( __f4_mul_in w0 w1 w2 w3 # u64 ( _ld64u a 0 ) # u64 ( _ld64u a 8 ) # u64 ( _ld64u a 16 ) # u64 ( _ld64u a 24 ) # u64 ( _ld64u b 0 ) # u64 ( _ld64u b 8 ) # u64 ( _ld64u b 16 ) # u64 ( _ld64u b 24 ) )
    ^ ( __f4_pack w0 w1 w2 w3 )
}

@ _x25519_ladder_k ( Vec u ) scalar ( Vec u ) point → ( Vec u ) {
    : ( Vec u64 ) kb ( vec_zeroed [u64] 68 )
    ^ ( __scalarmult_k ( vec_data [u64] kb ) scalar point )
}

@ _x25519_ladder_r ( Vec u ) scalar ( Vec u ) point → ( Vec u ) { ^ ( __scalarmult_r scalar point ) }

@ _x25519_base_k ( Vec u ) scalar → ( Vec u ) {
    : ( Vec u64 ) kb ( vec_zeroed [u64] 52 )
    ^ ( __xe_base_k ( vec_data [u64] kb ) scalar )
}

@ _x25519_base_r ( Vec u ) scalar → ( Vec u ) { ^ ( __xe_base_r scalar ) }

// scalar · point — the ECDH primitive. `scalar` and `point` are 32-byte
// little-endian `( Vec u )`; the result is the 32-byte shared X-coord.
@ x25519 ( Vec u ) scalar ( Vec u ) point → ( Vec u ) {
    ^ ( __scalarmult scalar point )
}

// ── fixed-base: scalar · 9, on Edwards ────────────────────────────
// scalar·9 on the Montgomery curve is scalar·B on the birationally
// equivalent Ed25519 curve (B ↦ u = 9, u = (1 + y)/(1 − y)), and
// twisted-Edwards addition is COMPLETE (d is not a square), so a
// fixed-base method needs no exceptional case. This is ref10's
// ge_scalarmult_base: the clamped scalar as 64 signed radix-16 digits
// e_i ∈ [−8, 8], and a table of j·256^k·B (k < 32, 1 ≤ j ≤ 8) in affine
// niels form (y + x, y − x, 2d·x·y). Then
//
//     Σ e_i 16^i B = 16 · Σ_{i odd} e_i 16^(i−1) B + Σ_{i even} e_i 16^i B
//
// is 64 mixed additions (7M each), each against one entry chosen by a
// constant-time scan of its row's eight (negated by mask for a negative
// digit), and FOUR doublings — where the 4-tooth comb this replaces
// doubled once per window, 64 times, and scanned sixteen entries. The
// result maps back to u = (Z + Y)/(Z − Y) with one inversion.

// One table: 32 rows × 8 entries × (y + x, y − x, 2d·x·y) × 4 words —
// 24 KB, built once per process (__xe_tbl_build) and shared through
// publish-once slot 4 (registry: stdlib/std/tls_server.nu).
: ~ i g_xe_tbl 0

// 2d and the base point B = (x, 4/5), as four words.
inline @ __xe_d2 inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 → v {
    = o0 16993941304535871833 = o1 63073048630374742 = o2 1841551078520508720 = o3 2596001775599221991
}

// Extended (X : Y : Z : T), T = XY/Z: o ← p + q, add-2008-hwcd-3 (a = −1),
// complete. Table build only.
@ __xe_add * u64 o * u64 p * u64 q → v {
    : ~ u64 d20 0
    : ~ u64 d21 0
    : ~ u64 d22 0
    : ~ u64 d23 0
    ( __xe_d2 d20 d21 d22 d23 )
    : ~ u64 s0 0
    : ~ u64 s1 0
    : ~ u64 s2 0
    : ~ u64 s3 0
    : ~ u64 r0 0
    : ~ u64 r1 0
    : ~ u64 r2 0
    : ~ u64 r3 0
    : ~ u64 a0 0
    : ~ u64 a1 0
    : ~ u64 a2 0
    : ~ u64 a3 0
    : ~ u64 b0 0
    : ~ u64 b1 0
    : ~ u64 b2 0
    : ~ u64 b3 0
    : ~ u64 c0 0
    : ~ u64 c1 0
    : ~ u64 c2 0
    : ~ u64 c3 0
    : ~ u64 dd0 0
    : ~ u64 dd1 0
    : ~ u64 dd2 0
    : ~ u64 dd3 0
    // A = (Y1 − X1)(Y2 − X2), B = (Y1 + X1)(Y2 + X2)
    ( __f4_sub s0 s1 s2 s3 . p 4 . p 5 . p 6 . p 7 . p 0 . p 1 . p 2 . p 3 )
    ( __f4_sub r0 r1 r2 r3 . q 4 . q 5 . q 6 . q 7 . q 0 . q 1 . q 2 . q 3 )
    ( __f4_mul a0 a1 a2 a3 s0 s1 s2 s3 r0 r1 r2 r3 )
    ( __f4_add s0 s1 s2 s3 . p 4 . p 5 . p 6 . p 7 . p 0 . p 1 . p 2 . p 3 )
    ( __f4_add r0 r1 r2 r3 . q 4 . q 5 . q 6 . q 7 . q 0 . q 1 . q 2 . q 3 )
    ( __f4_mul b0 b1 b2 b3 s0 s1 s2 s3 r0 r1 r2 r3 )
    // C = T1 · 2d · T2, D = 2 Z1 Z2
    ( __f4_mul s0 s1 s2 s3 . p 12 . p 13 . p 14 . p 15 d20 d21 d22 d23 )
    ( __f4_mul c0 c1 c2 c3 s0 s1 s2 s3 . q 12 . q 13 . q 14 . q 15 )
    ( __f4_mul s0 s1 s2 s3 . p 8 . p 9 . p 10 . p 11 . q 8 . q 9 . q 10 . q 11 )
    ( __f4_add dd0 dd1 dd2 dd3 s0 s1 s2 s3 s0 s1 s2 s3 )
    // E = B − A, F = D − C, G = D + C, H = B + A
    : ~ u64 g0 0
    : ~ u64 g1 0
    : ~ u64 g2 0
    : ~ u64 g3 0
    : ~ u64 h0 0
    : ~ u64 h1 0
    : ~ u64 h2 0
    : ~ u64 h3 0
    ( __f4_sub s0 s1 s2 s3 b0 b1 b2 b3 a0 a1 a2 a3 )
    ( __f4_sub r0 r1 r2 r3 dd0 dd1 dd2 dd3 c0 c1 c2 c3 )
    ( __f4_add g0 g1 g2 g3 dd0 dd1 dd2 dd3 c0 c1 c2 c3 )
    ( __f4_add h0 h1 h2 h3 b0 b1 b2 b3 a0 a1 a2 a3 )
    // X = E·F, Y = G·H, Z = F·G, T = E·H
    : ~ u64 w0 0
    : ~ u64 w1 0
    : ~ u64 w2 0
    : ~ u64 w3 0
    ( __f4_mul w0 w1 w2 w3 s0 s1 s2 s3 r0 r1 r2 r3 ) = . o 0 w0 = . o 1 w1 = . o 2 w2 = . o 3 w3
    ( __f4_mul w0 w1 w2 w3 g0 g1 g2 g3 h0 h1 h2 h3 ) = . o 4 w0 = . o 5 w1 = . o 6 w2 = . o 7 w3
    ( __f4_mul w0 w1 w2 w3 r0 r1 r2 r3 g0 g1 g2 g3 ) = . o 8 w0 = . o 9 w1 = . o 10 w2 = . o 11 w3
    ( __f4_mul w0 w1 w2 w3 s0 s1 s2 s3 h0 h1 h2 h3 ) = . o 12 w0 = . o 13 w1 = . o 14 w2 = . o 15 w3
}

// The 256 table points j·256^k·B in extended coordinates, then ONE field
// inversion for all 256 Z (Montgomery's batch trick: prefix products, the
// inverse of the last, and back down), then the affine niels triples.
@ __xe_tbl_build → v {
    : ( Vec u64 ) pts ( vec_zeroed [u64] * 256 16 )
    : *u64 pp ( vec_data [u64] pts )
    : ( Vec u64 ) cur ( vec_zeroed [u64] 16 )
    : *u64 cp ( vec_data [u64] cur )
    // B: x, y = 4/5, Z = 1, T = x·y
    = . cp 0 14507833142362363162 = . cp 1 7578651490590762930 = . cp 2 13881468655802702940 = . cp 3 2407515759118799870
    = . cp 4 7378697629483820632 = . cp 5 7378697629483820646 = . cp 6 7378697629483820646 = . cp 7 7378697629483820646
    = . cp 8 1
    : ~ u64 w0 0
    : ~ u64 w1 0
    : ~ u64 w2 0
    : ~ u64 w3 0
    ( __f4_mul w0 w1 w2 w3 . cp 0 . cp 1 . cp 2 . cp 3 . cp 4 . cp 5 . cp 6 . cp 7 )
    = . cp 12 w0 = . cp 13 w1 = . cp 14 w2 = . cp 15 w3
    : ~ i k 0
    ~ < k 32 {
        // row k: 1·Q … 8·Q for Q = 256^k·B (in cur)
        : *u64 row # *u64 + # i pp * * k 8 128
        ( nurl_memcpy # s row # s cp 128 )
        : ~ i j 1
        ~ < j 8 {
            ( __xe_add # *u64 + # i row * j 128 # *u64 + # i row * - j 1 128 cp )
            = j + j 1
        }
        // Q ← 256·Q: eight doublings, as additions to itself (complete).
        : ~ i dbl 0
        ~ < dbl 8 { ( __xe_add cp cp cp ) = dbl + dbl 1 }
        = k + k 1
    }
    // Batch inversion of the 256 Z: pre[e] = Z_0 ⋯ Z_e.
    : ( Vec u64 ) pre ( vec_zeroed [u64] * 256 4 )
    : *u64 rp ( vec_data [u64] pre )
    = . rp 0 . pp 8 = . rp 1 . pp 9 = . rp 2 . pp 10 = . rp 3 . pp 11
    : ~ i e 1
    ~ < e 256 {
        : i zo + * e 16 8
        ( __f4_mul w0 w1 w2 w3 . rp * - e 1 4 . rp + * - e 1 4 1 . rp + * - e 1 4 2 . rp + * - e 1 4 3 . pp zo . pp + zo 1 . pp + zo 2 . pp + zo 3 )
        = . rp * e 4 w0 = . rp + * e 4 1 w1 = . rp + * e 4 2 w2 = . rp + * e 4 3 w3
        = e + e 1
    }
    : ~ u64 v0 0
    : ~ u64 v1 0
    : ~ u64 v2 0
    : ~ u64 v3 0
    ( __f4_inv v0 v1 v2 v3 . rp 1020 . rp 1021 . rp 1022 . rp 1023 )
    : ( Vec i ) tbl ( vec_zeroed [i] * 256 12 )
    : *u64 tp # *u64 ( vec_data [i] tbl )
    : ~ u64 d20 0
    : ~ u64 d21 0
    : ~ u64 d22 0
    : ~ u64 d23 0
    ( __xe_d2 d20 d21 d22 d23 )
    : ~ u64 zi0 0
    : ~ u64 zi1 0
    : ~ u64 zi2 0
    : ~ u64 zi3 0
    : ~ u64 x0 0
    : ~ u64 x1 0
    : ~ u64 x2 0
    : ~ u64 x3 0
    : ~ u64 y0 0
    : ~ u64 y1 0
    : ~ u64 y2 0
    : ~ u64 y3 0
    = e 255
    ~ >= e 0 {
        : i po * e 16
        // 1/Z_e = v · pre[e − 1]; then v ← v · Z_e for the entries below.
        ? > e 0 {
            : i ro * - e 1 4
            ( __f4_mul zi0 zi1 zi2 zi3 v0 v1 v2 v3 . rp ro . rp + ro 1 . rp + ro 2 . rp + ro 3 )
            ( __f4_mul w0 w1 w2 w3 v0 v1 v2 v3 . pp + po 8 . pp + po 9 . pp + po 10 . pp + po 11 )
            = v0 w0 = v1 w1 = v2 w2 = v3 w3
        } { = zi0 v0 = zi1 v1 = zi2 v2 = zi3 v3 }
        ( __f4_mul x0 x1 x2 x3 . pp po . pp + po 1 . pp + po 2 . pp + po 3 zi0 zi1 zi2 zi3 )
        ( __f4_mul y0 y1 y2 y3 . pp + po 4 . pp + po 5 . pp + po 6 . pp + po 7 zi0 zi1 zi2 zi3 )
        : i to * e 12
        ( __f4_add w0 w1 w2 w3 y0 y1 y2 y3 x0 x1 x2 x3 )
        = . tp to w0 = . tp + to 1 w1 = . tp + to 2 w2 = . tp + to 3 w3
        ( __f4_sub w0 w1 w2 w3 y0 y1 y2 y3 x0 x1 x2 x3 )
        = . tp + to 4 w0 = . tp + to 5 w1 = . tp + to 6 w2 = . tp + to 7 w3
        ( __f4_mul w0 w1 w2 w3 x0 x1 x2 x3 y0 y1 y2 y3 )
        ( __f4_mul x0 x1 x2 x3 w0 w1 w2 w3 d20 d21 d22 d23 )
        = . tp + to 8 x0 = . tp + to 9 x1 = . tp + to 10 x2 = . tp + to 11 x3
        = e - e 1
    }
    // The winner lives for the rest of the program, through the global.
    = g_xe_tbl ( vec_publish_once [i] 4 tbl )
}

@ __xe_tbl → ( Vec i ) {
    ? == g_xe_tbl 0 { ( __xe_tbl_build ) } {}
    ^ @ ( Vec i ) { # s g_xe_tbl }
}

// The clamped scalar's 64 signed radix-16 digits, e_i ∈ [−8, 8]
// (e_63 ≤ 8: bit 255 is clear and bit 254 set).
@ __xe_digits ( Vec u ) scalar → ( Vec i ) {
    : ( Vec i ) dig ( vec_zeroed [i] 64 )
    : *i dp ( vec_data [i] dig )
    : *u sb ( vec_data [u] scalar )
    : ~ i q 0
    ~ < q 32 {
        : ~ i by # i . sb q
        ? == q 0 { = by & by 248 } {}
        ? == q 31 { = by | & by 127 64 } {}
        = . dp * q 2 & by 15
        = . dp + * q 2 1 & >> by 4 15
        = q + q 1
    }
    : ~ i carry 0
    = q 0
    ~ < q 63 {
        : i ev + . dp q carry
        = carry >> + ev 8 4
        = . dp q - ev << carry 4
        = q + q 1
    }
    = . dp 63 + . dp 63 carry

    ^ dig
}

// The entry for digit ev of the row at rb (eight entries of y + x,
// y − x, 2d·x·y, 96 bytes each): every entry read, six 16-byte vectors
// at a time, and ORed in under a mask that is all ones for the one that
// is |e| — then the identity (1, 1, 0) where |e| = 0, and −(x, y) =
// (−x, y) by mask for a negative digit: y + x and y − x swapped, 2d·x·y
// negated. Constant time: the digit only reaches masks. (The vectors
// halve the scan's instructions against one word at a time.)
inline @ __xe_pick inout u64 yp0 inout u64 yp1 inout u64 yp2 inout u64 yp3 inout u64 ym0 inout u64 ym1 inout u64 ym2 inout u64 ym3 inout u64 xy0 inout u64 xy1 inout u64 xy2 inout u64 xy3 * u64 rb i ev → v {
    // |e| and its sign, branch-free
    : u64 neg >> # u64 ev 63
    : u64 ab # u64 - ev << & - 0 # i neg ev 1
    : ~ v128 v0 ( nurl_v128_zero )
    : ~ v128 v1 ( nurl_v128_zero )
    : ~ v128 v2 ( nurl_v128_zero )
    : ~ v128 v3 ( nurl_v128_zero )
    : ~ v128 v4 ( nurl_v128_zero )
    : ~ v128 v5 ( nurl_v128_zero )
    : i base # i rb
    : ~ i j 0
    ~ < j 8 {
        : u64 z ^^ ab # u64 + j 1
        : u64 m - # u64 0 >> - z 1 63
        : v128 mv ( nurl_v128_set64 # i m # i m )
        : i o + base * j 96
        = v0 ( nurl_v128_or v0 ( nurl_v128_and mv ( nurl_v128_ld # s o ) ) )
        = v1 ( nurl_v128_or v1 ( nurl_v128_and mv ( nurl_v128_ld # s + o 16 ) ) )
        = v2 ( nurl_v128_or v2 ( nurl_v128_and mv ( nurl_v128_ld # s + o 32 ) ) )
        = v3 ( nurl_v128_or v3 ( nurl_v128_and mv ( nurl_v128_ld # s + o 48 ) ) )
        = v4 ( nurl_v128_or v4 ( nurl_v128_and mv ( nurl_v128_ld # s + o 64 ) ) )
        = v5 ( nurl_v128_or v5 ( nurl_v128_and mv ( nurl_v128_ld # s + o 80 ) ) )
        = j + j 1
    }
    // |e| = 0 matched none: the identity
    : u64 one & >> - ab 1 63 1
    = yp0 | ( nurl_v128_get64 v0 0 ) one
    = yp1 ( nurl_v128_get64 v0 1 )
    = yp2 ( nurl_v128_get64 v1 0 )
    = yp3 ( nurl_v128_get64 v1 1 )
    = ym0 | ( nurl_v128_get64 v2 0 ) one
    = ym1 ( nurl_v128_get64 v2 1 )
    = ym2 ( nurl_v128_get64 v3 0 )
    = ym3 ( nurl_v128_get64 v3 1 )
    = xy0 ( nurl_v128_get64 v4 0 )
    = xy1 ( nurl_v128_get64 v4 1 )
    = xy2 ( nurl_v128_get64 v5 0 )
    = xy3 ( nurl_v128_get64 v5 1 )
    : u64 nm - # u64 0 neg
    ( __f4_cswap yp0 yp1 yp2 yp3 ym0 ym1 ym2 ym3 nm )
    : ~ u64 n0 0
    : ~ u64 n1 0
    : ~ u64 n2 0
    : ~ u64 n3 0
    ( __f4_sub n0 n1 n2 n3 0 0 0 0 xy0 xy1 xy2 xy3 )
    ( __f4_cswap xy0 xy1 xy2 xy3 n0 n1 n2 n3 nm )
}

// The register walk: scalar·B → 32-byte little-endian Montgomery u.
// Constant time in the scalar: every digit's row is scanned whole, its
// sign applied by mask, and the step sequence is fixed.
@ __xe_base_r ( Vec u ) scalar → ( Vec u ) {
    : ( Vec i ) tbl ( __xe_tbl )
    : *u64 tb # *u64 ( vec_data [i] tbl )
    : ( Vec i ) dig ( __xe_digits scalar )
    : *i dp ( vec_data [i] dig )
    // h = the identity (0 : 1 : 1 : 0)
    : ~ u64 px0 0
    : ~ u64 px1 0
    : ~ u64 px2 0
    : ~ u64 px3 0
    : ~ u64 py0 1
    : ~ u64 py1 0
    : ~ u64 py2 0
    : ~ u64 py3 0
    : ~ u64 pz0 1
    : ~ u64 pz1 0
    : ~ u64 pz2 0
    : ~ u64 pz3 0
    : ~ u64 pt0 0
    : ~ u64 pt1 0
    : ~ u64 pt2 0
    : ~ u64 pt3 0
    : ~ u64 a0 0
    : ~ u64 a1 0
    : ~ u64 a2 0
    : ~ u64 a3 0
    : ~ u64 b0 0
    : ~ u64 b1 0
    : ~ u64 b2 0
    : ~ u64 b3 0
    : ~ u64 c0 0
    : ~ u64 c1 0
    : ~ u64 c2 0
    : ~ u64 c3 0
    : ~ u64 d0 0
    : ~ u64 d1 0
    : ~ u64 d2 0
    : ~ u64 d3 0
    : ~ u64 e0 0
    : ~ u64 e1 0
    : ~ u64 e2 0
    : ~ u64 e3 0
    : ~ u64 f0 0
    : ~ u64 f1 0
    : ~ u64 f2 0
    : ~ u64 f3 0

    // Steps 0 … 31 add the odd digits, 32 … 63 the even ones; between
    // them h is multiplied by 16. The order is public.
    : ~ i st 0
    ~ < st 64 {
        ? == st 32 {
            // h ← 16·h: four doublings (dbl-2008-hwcd), 4S + 4M each.
            : ~ i dn 0
            ~ < dn 4 {
                ( __f4_sq_in a0 a1 a2 a3 px0 px1 px2 px3 )
                ( __f4_sq_in b0 b1 b2 b3 py0 py1 py2 py3 )
                ( __f4_sq_in e0 e1 e2 e3 pz0 pz1 pz2 pz3 )
                ( __f4_add c0 c1 c2 c3 e0 e1 e2 e3 e0 e1 e2 e3 )
                ( __f4_add e0 e1 e2 e3 px0 px1 px2 px3 py0 py1 py2 py3 )
                ( __f4_sq_in d0 d1 d2 d3 e0 e1 e2 e3 )
                // Y' = YY + XX, Z' = YY − XX, X' = (X + Y)² − Y', T' = 2ZZ − Z'
                ( __f4_add py0 py1 py2 py3 b0 b1 b2 b3 a0 a1 a2 a3 )
                ( __f4_sub pz0 pz1 pz2 pz3 b0 b1 b2 b3 a0 a1 a2 a3 )
                ( __f4_sub px0 px1 px2 px3 d0 d1 d2 d3 py0 py1 py2 py3 )
                ( __f4_sub pt0 pt1 pt2 pt3 c0 c1 c2 c3 pz0 pz1 pz2 pz3 )
                ( __f4_mul_in a0 a1 a2 a3 px0 px1 px2 px3 pt0 pt1 pt2 pt3 )
                ( __f4_mul_in b0 b1 b2 b3 py0 py1 py2 py3 pz0 pz1 pz2 pz3 )
                ( __f4_mul_in c0 c1 c2 c3 pz0 pz1 pz2 pz3 pt0 pt1 pt2 pt3 )
                ( __f4_mul_in pt0 pt1 pt2 pt3 px0 px1 px2 px3 py0 py1 py2 py3 )
                = px0 a0 = px1 a1 = px2 a2 = px3 a3
                = py0 b0 = py1 b1 = py2 b2 = py3 b3
                = pz0 c0 = pz1 c1 = pz2 c2 = pz3 c3
                = dn + dn 1
            }
        } {}
        : i di ? < st 32 + * st 2 1 * - st 32 2
        : ~ u64 yp0 0
        : ~ u64 yp1 0
        : ~ u64 yp2 0
        : ~ u64 yp3 0
        : ~ u64 ym0 0
        : ~ u64 ym1 0
        : ~ u64 ym2 0
        : ~ u64 ym3 0
        : ~ u64 xy0 0
        : ~ u64 xy1 0
        : ~ u64 xy2 0
        : ~ u64 xy3 0
        ( __xe_pick yp0 yp1 yp2 yp3 ym0 ym1 ym2 ym3 xy0 xy1 xy2 xy3 # *u64 + # i tb * / di 2 768 . dp di )

        // h ← h + entry (ge_madd, 7M): A = (Y + X)(y + x), B = (Y − X)(y − x),
        // C = T · 2dxy, D = 2Z; X = (A − B)(D − C), Y = (A + B)(D + C),
        // Z = (D + C)(D − C), T = (A − B)(A + B).
        ( __f4_add e0 e1 e2 e3 py0 py1 py2 py3 px0 px1 px2 px3 )
        ( __f4_mul_in a0 a1 a2 a3 e0 e1 e2 e3 yp0 yp1 yp2 yp3 )
        ( __f4_sub f0 f1 f2 f3 py0 py1 py2 py3 px0 px1 px2 px3 )
        ( __f4_mul_in b0 b1 b2 b3 f0 f1 f2 f3 ym0 ym1 ym2 ym3 )
        ( __f4_mul_in c0 c1 c2 c3 pt0 pt1 pt2 pt3 xy0 xy1 xy2 xy3 )
        ( __f4_add d0 d1 d2 d3 pz0 pz1 pz2 pz3 pz0 pz1 pz2 pz3 )
        ( __f4_sub px0 px1 px2 px3 a0 a1 a2 a3 b0 b1 b2 b3 )
        ( __f4_add py0 py1 py2 py3 a0 a1 a2 a3 b0 b1 b2 b3 )
        ( __f4_add pz0 pz1 pz2 pz3 d0 d1 d2 d3 c0 c1 c2 c3 )
        ( __f4_sub pt0 pt1 pt2 pt3 d0 d1 d2 d3 c0 c1 c2 c3 )
        ( __f4_mul_in a0 a1 a2 a3 px0 px1 px2 px3 pt0 pt1 pt2 pt3 )
        ( __f4_mul_in b0 b1 b2 b3 py0 py1 py2 py3 pz0 pz1 pz2 pz3 )
        ( __f4_mul_in c0 c1 c2 c3 pz0 pz1 pz2 pz3 pt0 pt1 pt2 pt3 )
        ( __f4_mul_in pt0 pt1 pt2 pt3 px0 px1 px2 px3 py0 py1 py2 py3 )
        = px0 a0 = px1 a1 = px2 a2 = px3 a3
        = py0 b0 = py1 b1 = py2 b2 = py3 b3
        = pz0 c0 = pz1 c1 = pz2 c2 = pz3 c3
        = st + st 1
    }

    // Birational map to Montgomery u = (Z + Y) / (Z − Y)
    ( __f4_add a0 a1 a2 a3 pz0 pz1 pz2 pz3 py0 py1 py2 py3 )
    ( __f4_sub b0 b1 b2 b3 pz0 pz1 pz2 pz3 py0 py1 py2 py3 )
    ( __f4_inv c0 c1 c2 c3 b0 b1 b2 b3 )
    ( __f4_mul d0 d1 d2 d3 a0 a1 a2 a3 c0 c1 c2 c3 )
    ^ ( __f4_pack d0 d1 d2 d3 )
}

// o ← a, one element.
inline @ __xk_cp * u64 o * u64 a → v { = . o 0 . a 0 = . o 1 . a 1 = . o 2 . a 2 = . o 3 . a 3 }

// The fixed-base walk of __xe_base_r on the kernels: h = (X : Y : Z : T)
// and the step's scratch in a buffer of 13 zeroed elements (w), the same
// formulas in the same order. x25519_kernel_agrees holds the two to each
// other.
@ __xe_base_k * u64 w ( Vec u ) scalar → ( Vec u ) {
    : ( Vec i ) tbl ( __xe_tbl )
    : *u64 tb # *u64 ( vec_data [i] tbl )
    : ( Vec i ) dig ( __xe_digits scalar )
    : *i dp ( vec_data [i] dig )
    : *u64 px ( __xk_at w 0 )
    : *u64 py ( __xk_at w 1 )
    : *u64 pz ( __xk_at w 2 )
    : *u64 pt ( __xk_at w 3 )
    : *u64 a ( __xk_at w 4 )
    : *u64 b ( __xk_at w 5 )
    : *u64 c ( __xk_at w 6 )
    : *u64 d ( __xk_at w 7 )
    : *u64 e ( __xk_at w 8 )
    : *u64 f ( __xk_at w 9 )
    : *u64 yp ( __xk_at w 10 )
    : *u64 ym ( __xk_at w 11 )
    : *u64 xy ( __xk_at w 12 )
    // h = the identity (0 : 1 : 1 : 0)
    = . py 0 1 = . pz 0 1
    : ~ i st 0
    ~ < st 64 {
        ? == st 32 {
            // h ← 16·h: four doublings (dbl-2008-hwcd), 4S + 4M each.
            : ~ i dn 0
            ~ < dn 4 {
                ( __xk_sq a px )
                ( __xk_sq b py )
                ( __xk_sq e pz )
                ( __xk_add c e e )
                ( __xk_add e px py )
                ( __xk_sq d e )
                // Y' = YY + XX, Z' = YY − XX, X' = (X + Y)² − Y', T' = 2ZZ − Z'
                ( __xk_add py b a )
                ( __xk_sub pz b a )
                ( __xk_sub px d py )
                ( __xk_sub pt c pz )
                ( __xk_mul a px pt )
                ( __xk_mul b py pz )
                ( __xk_mul c pz pt )
                ( __xk_mul pt px py )
                ( __xk_cp px a )
                ( __xk_cp py b )
                ( __xk_cp pz c )
                = dn + dn 1
            }
        } {}
        : i di ? < st 32 + * st 2 1 * - st 32 2
        : ~ u64 yp0 0
        : ~ u64 yp1 0
        : ~ u64 yp2 0
        : ~ u64 yp3 0
        : ~ u64 ym0 0
        : ~ u64 ym1 0
        : ~ u64 ym2 0
        : ~ u64 ym3 0
        : ~ u64 xy0 0
        : ~ u64 xy1 0
        : ~ u64 xy2 0
        : ~ u64 xy3 0
        ( __xe_pick yp0 yp1 yp2 yp3 ym0 ym1 ym2 ym3 xy0 xy1 xy2 xy3 # *u64 + # i tb * / di 2 768 . dp di )
        = . yp 0 yp0 = . yp 1 yp1 = . yp 2 yp2 = . yp 3 yp3
        = . ym 0 ym0 = . ym 1 ym1 = . ym 2 ym2 = . ym 3 ym3
        = . xy 0 xy0 = . xy 1 xy1 = . xy 2 xy2 = . xy 3 xy3
        // h ← h + entry (ge_madd, 7M): A = (Y + X)(y + x), B = (Y − X)(y − x),
        // C = T · 2dxy, D = 2Z; X = (A − B)(D − C), Y = (A + B)(D + C),
        // Z = (D + C)(D − C), T = (A − B)(A + B).
        ( __xk_add e py px )
        ( __xk_mul a e yp )
        ( __xk_sub f py px )
        ( __xk_mul b f ym )
        ( __xk_mul c pt xy )
        ( __xk_add d pz pz )
        ( __xk_sub px a b )
        ( __xk_add py a b )
        ( __xk_add pz d c )
        ( __xk_sub pt d c )
        ( __xk_mul a px pt )
        ( __xk_mul b py pz )
        ( __xk_mul c pz pt )
        ( __xk_mul pt px py )
        ( __xk_cp px a )
        ( __xk_cp py b )
        ( __xk_cp pz c )
        = st + st 1
    }
    // Birational map to Montgomery u = (Z + Y) / (Z − Y)
    ( __xk_add px pz py )
    ( __xk_sub pt pz py )
    ( __xk_inv py pt )
    ( __xk_mul pz px py )
    ^ ( __f4_pack . pz 0 . pz 1 . pz 2 . pz 3 )
}

// scalar·B → 32-byte little-endian Montgomery u (the X25519 public key):
// the kernels' walk where the target has the kernels (a square of the
// zeroed buffer asks), else the register one.
@ x25519_base_comb ( Vec u ) scalar → ( Vec u ) {
    : ( Vec u64 ) kb ( vec_zeroed [u64] 52 )
    : *u64 kw ( vec_data [u64] kb )
    ? ( nurl_x25519_sqrm kw kw ) { ^ ( __xe_base_k kw scalar ) } {}
    ^ ( __xe_base_r scalar )
}

@ x25519_base ( Vec u ) scalar → ( Vec u ) {
    // Fixed-base: the generator is constant, so ref10's signed-digit
    // method over a precomputed Edwards table (x25519_base_comb) beats
    // the Montgomery ladder. Same result: x25519_edge_vectors holds the
    // two to each other.
    ^ ( x25519_base_comb scalar )
}
