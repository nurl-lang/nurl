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

@ _vget ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 }
}

@ _vset ( Vec i ) v i k i val → v {
    ( vec_set [i] v k val )
}

// The ladder's inner routines index their limbs through `*i` instead of
// the two accessors above. Every one of those loops is fixed-count over
// a 16- or 31-limb gf, so the bounds check is provably redundant — but
// it is a real call, and one field multiply makes about a thousand of
// them while one X25519 scalar multiply makes 1280 field multiplies.
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
    // Filled by index rather than pushed — `_M` builds a 31-limb one of
    // these per field multiply, 1280 of them per scalar multiply, and a
    // push carries a capacity check a known length does not need.
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

// A fresh 16-limb field element, all zero.
@ _gf_zero → ( Vec i ) { ^ ( _zeros_i 16 ) }

// Copy the first 16 limbs of `a` into a new gf.
@ _gf_copy ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) o ( _gf_zero )
    : *i op ( vec_data [i] o )
    : *i ap ( vec_data [i] a )
    : ~ i k 0
    ~ < k 16 { = . op k . ap k = k + k 1 }
    ^ o
}

// dst ← src (16 limbs), in place.
@ _gf_into ( Vec i ) dst ( Vec i ) src → v {
    : *i dp ( vec_data [i] dst )
    : *i sp ( vec_data [i] src )
    : ~ i k 0
    ~ < k 16 { = . dp k . sp k = k + k 1 }
}

// The constant 121665 as a gf (used in the ladder).
@ __gf_121665 → ( Vec i ) {
    : ( Vec i ) o ( _gf_zero )
    ( _vset o 0 56129 )  // 0xDB41
    ( _vset o 1 1 )
    ^ o
}

// ── carry / reduce ────────────────────────────────────────────────
// Propagate carries so each limb is back in [0, 2^16). Handles signed
// limbs via TweetNaCl's bias trick; the wrap from limb 15 folds back
// into limb 0 with the ×38 (= 2·19) reduction for 2^256 ≡ 38.
@ __car25519 ( Vec i ) o → v {
    : *i op ( vec_data [i] o )
    : ~ i i 0
    ~ < i 16 {
        : i oi + . op i 65536
        : i c >> oi 16
        ? < i 15 {
            = . op + i 1 + . op + i 1 - c 1
        } {
            = . op 0 + . op 0 * 38 - c 1
        }
        = . op i - oi << c 16
        = i + i 1
    }
}

// Constant-time conditional swap of p and q when b = 1.
@ _sel25519 ( Vec i ) p ( Vec i ) q i b → v {
    : i c - 0 b
    : *i pp ( vec_data [i] p )
    : *i qp ( vec_data [i] q )
    : ~ i i 0
    ~ < i 16 {
        : i t & c ^^ . pp i . qp i
        = . pp i ^^ . pp i t
        = . qp i ^^ . qp i t
        = i + i 1
    }
}

// Decode 32 little-endian bytes into a gf (clears the top bit).
@ _unpack25519 ( Vec u ) n → ( Vec i ) {
    : ( Vec i ) o ( _gf_zero )
    : ~ i i 0
    ~ < i 16 {
        : i lo ( _x_bget n * 2 i )
        : i hi ( _x_bget n + * 2 i 1 )
        ( _vset o i + lo << hi 8 )
        = i + i 1
    }
    ( _vset o 15 & ( _vget o 15 ) 32767 )
    ^ o
}

// Fully reduce `n` mod 2^255−19 and emit 32 little-endian bytes.
@ _pack25519 ( Vec i ) n → ( Vec u ) {
    : ( Vec i ) t ( _gf_copy n )
    ( __car25519 t )
    ( __car25519 t )
    ( __car25519 t )
    : ~ i j 0
    ~ < j 2 {
        : ( Vec i ) m ( _gf_zero )
        ( _vset m 0 - ( _vget t 0 ) 65517 )  // 0xffed
        : ~ i i 1
        ~ < i 15 {
            ( _vset m i - - ( _vget t i ) 65535 & >> ( _vget m - i 1 ) 16 1 )
            ( _vset m - i 1 & ( _vget m - i 1 ) 65535 )
            = i + i 1
        }
        ( _vset m 15 - - ( _vget t 15 ) 32767 & >> ( _vget m 14 ) 16 1 )
        : i b & >> ( _vget m 15 ) 16 1
        ( _vset m 14 & ( _vget m 14 ) 65535 )
        ( _sel25519 t m - 1 b )
        ( vec_free [i] m )
        = j + j 1
    }
    : ( Vec u ) o ( _zeros_u 32 )
    : ~ i i 0
    ~ < i 16 {
        ( _bset o * 2 i & ( _vget t i ) 255 )
        ( _bset o + * 2 i 1 & >> ( _vget t i ) 8 255 )
        = i + i 1
    }
    ( vec_free [i] t )
    ^ o
}

// ── field ops (write into dst; aliasing-safe) ─────────────────────
@ _A ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : *i op ( vec_data [i] o )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : ~ i i 0
    ~ < i 16 { = . op i + . ap i . bp i = i + i 1 }
}

@ _Z ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : *i op ( vec_data [i] o )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : ~ i i 0
    ~ < i 16 { = . op i - . ap i . bp i = i + i 1 }
}

// o ← a·b mod p. Schoolbook into a 31-limb accumulator, fold the high
// half back with ×38, then carry twice. a/b may alias o (o is written
// only from the independent accumulator t).
@ _M ( Vec i ) o ( Vec i ) a ( Vec i ) b → v {
    : ( Vec i ) t ( _zeros_i 31 )
    : *i tp ( vec_data [i] t )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : ~ i i 0
    ~ < i 16 {
        : i ai . ap i
        : ~ i j 0
        ~ < j 16 {
            = . tp + i j + . tp + i j * ai . bp j
            = j + j 1
        }
        = i + i 1
    }
    : ~ i i 0
    ~ < i 15 {
        = . tp i + . tp i * 38 . tp + i 16
        = i + i 1
    }
    : *i op ( vec_data [i] o )
    : ~ i i 0
    ~ < i 16 { = . op i . tp i = i + i 1 }
    ( __car25519 o )
    ( __car25519 o )
    ( vec_free [i] t )
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
