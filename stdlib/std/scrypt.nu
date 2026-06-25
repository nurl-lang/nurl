// stdlib/std/scrypt.nu — pure-NURL scrypt (RFC 7914), no OpenSSL. The
// Salsa20/8 core, BlockMix and ROMix are implemented here; the surrounding
// key stretching reuses pbkdf2_hmac_sha256.
//
//   ( scrypt_pure password salt N r p dklen ) → ( Vec u )   dklen bytes
//
// N must be a power of two > 1. password / salt are ( Vec u ).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/pbkdf2.nu`

@ __sc_bget ( Vec u ) v i k → i { ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 } }

@ __scg ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 } }

@ __scs ( Vec i ) v i k i val → v { : b _o ( vec_set [i] v k val ) }

@ __sc_zeros_u i n → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] o # u 0 ) = k + k 1 }
    ^ o
}

// little-endian 32-bit load / store
@ __sc_ld ( Vec u ) v i off → i {
    ^ & | | | ( __sc_bget v off ) << ( __sc_bget v + off 1 ) 8 << ( __sc_bget v + off 2 ) 16 << ( __sc_bget v + off 3 ) 24 4294967295
}

@ __sc_st ( Vec u ) v i off i w → v {
    ( vec_set [u] v off # u & w 255 )
    ( vec_set [u] v + off 1 # u & >> w 8 255 )
    ( vec_set [u] v + off 2 # u & >> w 16 255 )
    ( vec_set [u] v + off 3 # u & >> w 24 255 )
}

// rotate-left a 32-bit word
@ __sc_rotl i x i b → i {
    ^ & | & << x b 4294967295 >> & x 4294967295 - 32 b 4294967295
}

// copy n bytes of src starting at off into a fresh Vec
@ __sc_slice_n ( Vec u ) src i off i n → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] o # u ( __sc_bget src + off k ) ) = k + k 1 }
    ^ o
}
// copy n bytes of src into dst starting at off
@ __sc_put_n ( Vec u ) dst i off ( Vec u ) src i n → v {
    : ~ i k 0
    ~ < k n { ( vec_set [u] dst + off k # u ( __sc_bget src k ) ) = k + k 1 }
}
// fresh Vec of a[0..n] XOR b[boff..boff+n]
@ __sc_xor_n ( Vec u ) a ( Vec u ) b i boff i n → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] o # u & ^^ ( __sc_bget a k ) ( __sc_bget b + boff k ) 255 ) = k + k 1 }
    ^ o
}

// ── Salsa20/8 core on a 64-byte block ──────────────────────────────
// x[d] ^= rotl(x[a] + x[b], s)
@ __sc_qr ( Vec i ) x i d i a i b i s → v {
    : i v & + ( __scg x a ) ( __scg x b ) 4294967295
    ( __scs x d ^^ ( __scg x d ) ( __sc_rotl v s ) )
}

@ __salsa20_8 ( Vec u ) inb → ( Vec u ) {
    : ( Vec i ) x ( vec_with_cap [i] 16 )
    : ~ i i 0
    ~ < i 16 { ( vec_push [i] x ( __sc_ld inb * i 4 ) ) = i + i 1 }
    : ( Vec i ) orig ( vec_with_cap [i] 16 )
    = i 0
    ~ < i 16 { ( vec_push [i] orig ( __scg x i ) ) = i + i 1 }

    : ~ i round 0
    ~ < round 4 {
        ( __sc_qr x 4 0 12 7 ) ( __sc_qr x 8 4 0 9 ) ( __sc_qr x 12 8 4 13 ) ( __sc_qr x 0 12 8 18 )
        ( __sc_qr x 9 5 1 7 ) ( __sc_qr x 13 9 5 9 ) ( __sc_qr x 1 13 9 13 ) ( __sc_qr x 5 1 13 18 )
        ( __sc_qr x 14 10 6 7 ) ( __sc_qr x 2 14 10 9 ) ( __sc_qr x 6 2 14 13 ) ( __sc_qr x 10 6 2 18 )
        ( __sc_qr x 3 15 11 7 ) ( __sc_qr x 7 3 15 9 ) ( __sc_qr x 11 7 3 13 ) ( __sc_qr x 15 11 7 18 )
        ( __sc_qr x 1 0 3 7 ) ( __sc_qr x 2 1 0 9 ) ( __sc_qr x 3 2 1 13 ) ( __sc_qr x 0 3 2 18 )
        ( __sc_qr x 6 5 4 7 ) ( __sc_qr x 7 6 5 9 ) ( __sc_qr x 4 7 6 13 ) ( __sc_qr x 5 4 7 18 )
        ( __sc_qr x 11 10 9 7 ) ( __sc_qr x 8 11 10 9 ) ( __sc_qr x 9 8 11 13 ) ( __sc_qr x 10 9 8 18 )
        ( __sc_qr x 12 15 14 7 ) ( __sc_qr x 13 12 15 9 ) ( __sc_qr x 14 13 12 13 ) ( __sc_qr x 15 14 13 18 )
        = round + round 1
    }

    : ( Vec u ) out ( __sc_zeros_u 64 )
    = i 0
    ~ < i 16 { ( __sc_st out * i 4 & + ( __scg x i ) ( __scg orig i ) 4294967295 ) = i + i 1 }
    ( vec_free [i] x ) ( vec_free [i] orig )
    ^ out
}

// ── BlockMix over 2r 64-byte blocks (128r bytes) ───────────────────
@ __blockmix ( Vec u ) b i r → ( Vec u ) {
    : i blocks * 2 r
    : ~ ( Vec u ) x ( __sc_slice_n b * - blocks 1 64 64 )
    : ( Vec u ) out ( __sc_zeros_u * blocks 64 )
    : ~ i i 0
    ~ < i blocks {
        : ( Vec u ) t ( __sc_xor_n x b * i 64 64 )
        : ( Vec u ) nx ( __salsa20_8 t )
        ( vec_free [u] t ) ( vec_free [u] x )
        = x nx
        : i pos ? == % i 2 0 / i 2 + r / - i 1 2
        ( __sc_put_n out * pos 64 x 64 )
        = i + i 1
    }
    ( vec_free [u] x )
    ^ out
}

// ── ROMix over a 128r-byte block ───────────────────────────────────
@ __sc_integerify ( Vec u ) x i blen → i { ^ ( __sc_ld x - blen 64 ) }

@ __romix ( Vec u ) b i n i r → ( Vec u ) {
    : i blen * 128 r
    : ~ ( Vec u ) x ( __sc_slice_n b 0 blen )
    : ( Vec u ) v ( __sc_zeros_u * n blen )
    : ~ i i 0
    ~ < i n {
        ( __sc_put_n v * i blen x blen )
        : ( Vec u ) nx ( __blockmix x r )
        ( vec_free [u] x )
        = x nx
        = i + i 1
    }
    = i 0
    ~ < i n {
        : i j & ( __sc_integerify x blen ) - n 1
        : ( Vec u ) t ( __sc_xor_n x v * j blen blen )
        : ( Vec u ) nx ( __blockmix t r )
        ( vec_free [u] t ) ( vec_free [u] x )
        = x nx
        = i + i 1
    }
    ( vec_free [u] v )
    ^ x
}

// ── scrypt ─────────────────────────────────────────────────────────
@ scrypt_pure ( Vec u ) password ( Vec u ) salt i n i r i p i dklen → ( Vec u ) {
    : i blen * 128 r
    : ( Vec u ) b ( pbkdf2_hmac_sha256 password salt 1 * p blen )
    : ~ i i 0
    ~ < i p {
        : ( Vec u ) bi ( __sc_slice_n b * i blen blen )
        : ( Vec u ) mixed ( __romix bi n r )
        ( __sc_put_n b * i blen mixed blen )
        ( vec_free [u] bi ) ( vec_free [u] mixed )
        = i + i 1
    }
    : ( Vec u ) dk ( pbkdf2_hmac_sha256 password b 1 dklen )
    ( vec_free [u] b )
    ^ dk
}
