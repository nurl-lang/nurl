// stdlib/std/x25519.nu — pure-NURL X25519 (RFC 7748) ECDH.
//
// No OpenSSL, no FFI: a self-contained Montgomery-ladder scalar
// multiplication over GF(2^255 − 19), so a NURL program can do the key
// exchange for TLS 1.3 / Noise / age with nothing installed on the host.
//
// The field arithmetic is a direct port of the well-trodden TweetNaCl
// reference (Bernstein et al.): a field element ("gf") is 16 signed
// 64-bit limbs, each holding ~16 bits, carried with `__car25519`. Every
// branch is data-independent (the conditional swap is a constant-time
// mask), so the ladder runs in constant time w.r.t. the scalar.
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

@ __vget ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 }
}

@ __vset ( Vec i ) v i k i val → v {
    ( vec_set [i] v k val )
}

@ __bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ __bset ( Vec u ) v i k i val → v {
    ( vec_set [u] v k # u & val 255 )
}

// n zeroed i64 limbs.
@ __zeros_i i n → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v 0 ) = k + k 1 }
    ^ v
}

// n zeroed bytes.
@ __zeros_u i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    ^ v
}

// A fresh 16-limb field element, all zero.
@ __gf_zero → ( Vec i ) { ^ ( __zeros_i 16 ) }

// Copy the first 16 limbs of `a` into a new gf.
@ __gf_copy ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) o ( __gf_zero )
    : ~ i k 0
    ~ < k 16 { ( __vset o k ( __vget a k ) ) = k + k 1 }
    ^ o
}

// dst ← src (16 limbs), in place.
@ __gf_into ( Vec i ) dst ( Vec i ) src → v {
    : ~ i k 0
    ~ < k 16 { ( __vset dst k ( __vget src k ) ) = k + k 1 }
}

// The constant 121665 as a gf (used in the ladder).
@ __gf_121665 → ( Vec i ) {
    : ( Vec i ) o ( __gf_zero )
    ( __vset o 0 56129 )  // 0xDB41
    ( __vset o 1 1 )
    ^ o
}

// ── carry / reduce ────────────────────────────────────────────────
// Propagate carries so each limb is back in [0, 2^16). Handles signed
// limbs via TweetNaCl's bias trick; the wrap from limb 15 folds back
// into limb 0 with the ×38 (= 2·19) reduction for 2^256 ≡ 38.
@ __car25519 ( Vec i ) o → v {
    : ~ i i 0
    ~ < i 16 {
        : i oi + ( __vget o i ) 65536
        : i c >> oi 16
        ? < i 15 {
            ( __vset o + i 1 + ( __vget o + i 1 ) - c 1 )
        } {
            ( __vset o 0 + ( __vget o 0 ) * 38 - c 1 )
        }
        ( __vset o i - oi << c 16 )
        = i + i 1
    }
}

// Constant-time conditional swap of p and q when b = 1.
@ __sel25519 ( Vec i ) p ( Vec i ) q i b → v {
    : i c - 0 b
    : ~ i i 0
    ~ < i 16 {
        : i t & c ^^ ( __vget p i ) ( __vget q i )
        ( __vset p i ^^ ( __vget p i ) t )
        ( __vset q i ^^ ( __vget q i ) t )
        = i + i 1
    }
}

// Decode 32 little-endian bytes into a gf (clears the top bit).
@ __unpack25519 ( Vec u ) n → ( Vec i ) {
    : ( Vec i ) o ( __gf_zero )
    : ~ i i 0
    ~ < i 16 {
        : i lo ( __bget n * 2 i )
        : i hi ( __bget n + * 2 i 1 )
        ( __vset o i + lo << hi 8 )
        = i + i 1
    }
    ( __vset o 15 & ( __vget o 15 ) 32767 )
    ^ o
}

// Fully reduce `n` mod 2^255−19 and emit 32 little-endian bytes.
@ __pack25519 ( Vec i ) n → ( Vec u ) {
    : ( Vec i ) t ( __gf_copy n )
    ( __car25519 t )
    ( __car25519 t )
    ( __car25519 t )
    : ~ i j 0
    ~ < j 2 {
        : ( Vec i ) m ( __gf_zero )
        ( __vset m 0 - ( __vget t 0 ) 65517 )  // 0xffed
        : ~ i i 1
        ~ < i 15 {
            ( __vset m i - - ( __vget t i ) 65535 & >> ( __vget m - i 1 ) 16 1 )
            ( __vset m - i 1 & ( __vget m - i 1 ) 65535 )
            = i + i 1
        }
        ( __vset m 15 - - ( __vget t 15 ) 32767 & >> ( __vget m 14 ) 16 1 )
        : i b & >> ( __vget m 15 ) 16 1
        ( __vset m 14 & ( __vget m 14 ) 65535 )
        ( __sel25519 t m - 1 b )
        ( vec_free [i] m )
        = j + j 1
    }
    : ( Vec u ) o ( __zeros_u 32 )
    : ~ i i 0
    ~ < i 16 {
        ( __bset o * 2 i & ( __vget t i ) 255 )
        ( __bset o + * 2 i 1 & >> ( __vget t i ) 8 255 )
        = i + i 1
    }
    ( vec_free [i] t )
    ^ o
}

// ── field ops (write into dst; aliasing-safe) ─────────────────────
@ __A ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : ~ i i 0
    ~ < i 16 { ( __vset o i + ( __vget a i ) ( __vget b i ) ) = i + i 1 }
}

@ __Z ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : ~ i i 0
    ~ < i 16 { ( __vset o i - ( __vget a i ) ( __vget b i ) ) = i + i 1 }
}

// o ← a·b mod p. Schoolbook into a 31-limb accumulator, fold the high
// half back with ×38, then carry twice. a/b may alias o (o is written
// only from the independent accumulator t).
@ __M ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : ( Vec i ) t ( __zeros_i 31 )
    : ~ i i 0
    ~ < i 16 {
        : ~ i j 0
        ~ < j 16 {
            ( __vset t + i j + ( __vget t + i j ) * ( __vget a i ) ( __vget b j ) )
            = j + j 1
        }
        = i + i 1
    }
    : ~ i i 0
    ~ < i 15 {
        ( __vset t i + ( __vget t i ) * 38 ( __vget t + i 16 ) )
        = i + i 1
    }
    : ~ i i 0
    ~ < i 16 { ( __vset o i ( __vget t i ) ) = i + i 1 }
    ( __car25519 o )
    ( __car25519 o )
    ( vec_free [i] t )
}

@ __S ( Vec i ) o ( Vec i ) a → v { ( __M o a a ) }

// io ← io^(p-2) = io^-1  (Fermat inversion, 254 squarings).
@ __inv25519 ( Vec i ) io → v {
    : ( Vec i ) inp ( __gf_copy io )
    : ( Vec i ) c ( __gf_copy io )
    : ~ i a 253
    ~ >= a 0 {
        ( __S c c )
        ? & != a 2 != a 4 { ( __M c c inp ) } {}
        = a - a 1
    }
    ( __gf_into io c )
    ( vec_free [i] inp )
    ( vec_free [i] c )
}

// ── the ladder ────────────────────────────────────────────────────
// q ← scalar · point, both 32-byte little-endian. Scalar is clamped.
@ __scalarmult ( Vec u ) scalar ( Vec u ) point → ( Vec u ) {
    : ( Vec u ) z ( __zeros_u 32 )
    : ~ i k 0
    ~ < k 32 { ( __bset z k ( __bget scalar k ) ) = k + k 1 }
    ( __bset z 31 | & ( __bget scalar 31 ) 127 64 )
    ( __bset z 0 & ( __bget scalar 0 ) 248 )

    : ( Vec i ) x ( __unpack25519 point )
    : ( Vec i ) a ( __gf_zero )
    : ( Vec i ) b ( __gf_copy x )
    : ( Vec i ) c ( __gf_zero )
    : ( Vec i ) d ( __gf_zero )
    : ( Vec i ) e ( __gf_zero )
    : ( Vec i ) f ( __gf_zero )
    : ( Vec i ) k121665 ( __gf_121665 )
    ( __vset a 0 1 )
    ( __vset d 0 1 )

    : ~ i i 254
    ~ >= i 0 {
        : i r & >> ( __bget z >> i 3 ) & i 7 1
        ( __sel25519 a b r )
        ( __sel25519 c d r )
        ( __A e a c )
        ( __Z a a c )
        ( __A c b d )
        ( __Z b b d )
        ( __S d e )
        ( __S f a )
        ( __M a c a )
        ( __M c b e )
        ( __A e a c )
        ( __Z a a c )
        ( __S b a )
        ( __Z c d f )
        ( __M a c k121665 )
        ( __A a a d )
        ( __M c c a )
        ( __M a d f )
        ( __M d b x )
        ( __S b e )
        ( __sel25519 a b r )
        ( __sel25519 c d r )
        = i - i 1
    }

    // Recover the affine X-coordinate: x2 · z2^-1. (a = x2, c = z2.)
    ( __inv25519 c )
    ( __M a a c )
    : ( Vec u ) out ( __pack25519 a )

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
    : ( Vec u ) base ( __zeros_u 32 )
    ( __bset base 0 9 )
    : ( Vec u ) out ( __scalarmult scalar base )
    ( vec_free [u] base )
    ^ out
}
