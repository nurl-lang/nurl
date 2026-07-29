// stdlib/std/chacha20poly1305.nu — pure-NURL ChaCha20, Poly1305, and the
// ChaCha20-Poly1305 AEAD (RFC 8439). No OpenSSL, no FFI.
//
// This is the record-protection half of a pure TLS 1.3 stack (the
// TLS_CHACHA20_POLY1305_SHA256 cipher suite), and is equally usable for
// Noise / age / any AEAD need on a host with nothing installed.
//
// ChaCha20 words are kept in i64 limbs masked to 32 bits (`__m32`);
// Poly1305 is a port of the well-trodden poly1305-donna radix-2^26
// reference, whose partial products stay well under 2^63 so plain i64
// arithmetic suffices.
//
// Public surface:
//   ( chacha20_block key counter nonce )      → ( Vec u )  64-byte block
//   ( chacha20_xor key counter nonce data )   → ( Vec u )  stream cipher
//   ( poly1305_mac otk msg )                  → ( Vec u )  16-byte tag
//   ( aead_encrypt key nonce aad plaintext )  → ( Vec u )  ciphertext||tag
//   ( aead_decrypt key nonce aad ct_and_tag ) → ?( Vec u ) None if forged
//
//   key  = 32 bytes, nonce = 12 bytes, counter = i (block counter).

$ `stdlib/core/vec.nu`

// ── byte / word helpers ───────────────────────────────────────────
@ __cc_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ __push_le32 ( Vec u ) out i w → v {
    ( vec_push [u] out # u & w 255 )
    ( vec_push [u] out # u & >> w 8 255 )
    ( vec_push [u] out # u & >> w 16 255 )
    ( vec_push [u] out # u & >> w 24 255 )
}

// 4 little-endian bytes at offset → i (0 .. 2^32-1).
@ __ld32 ( Vec u ) v i off → i {
    ^ | | | ( __cc_bget v off ) << ( __cc_bget v + off 1 ) 8 << ( __cc_bget v + off 2 ) 16 << ( __cc_bget v + off 3 ) 24
}

@ __m32 i x → i { ^ & x 4294967295 }

// 32-bit rotate left.
@ __rotl32 i x i n → i {
    ^ & | << & x 4294967295 n >> & x 4294967295 - 32 n 4294967295
}

@ __wget ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 }
}

@ __wset ( Vec i ) v i k i val → v { ( vec_set [i] v k val ) }

// ── ChaCha20 ──────────────────────────────────────────────────────
// One quarter-round, mutating state words a,b,c,d in place.
@ __qr ( Vec i ) s i a i b i c i d → v {
    ( __wset s a ( __m32 + ( __wget s a ) ( __wget s b ) ) )
    ( __wset s d ( __rotl32 ^^ ( __wget s d ) ( __wget s a ) 16 ) )
    ( __wset s c ( __m32 + ( __wget s c ) ( __wget s d ) ) )
    ( __wset s b ( __rotl32 ^^ ( __wget s b ) ( __wget s c ) 12 ) )
    ( __wset s a ( __m32 + ( __wget s a ) ( __wget s b ) ) )
    ( __wset s d ( __rotl32 ^^ ( __wget s d ) ( __wget s a ) 8 ) )
    ( __wset s c ( __m32 + ( __wget s c ) ( __wget s d ) ) )
    ( __wset s b ( __rotl32 ^^ ( __wget s b ) ( __wget s c ) 7 ) )
}

// Build the 16-word initial state for (key, counter, nonce).
@ __chacha_state ( Vec u ) key i counter ( Vec u ) nonce → ( Vec i ) {
    : ( Vec i ) s ( vec_with_cap [i] 16 )
    ( vec_push [i] s 1634760805 )  // "expa"
    ( vec_push [i] s 857760878 )  // "nd 3"
    ( vec_push [i] s 2036477234 )  // "2-by"
    ( vec_push [i] s 1797285236 )  // "te k"
    : ~ i k 0
    ~ < k 8 { ( vec_push [i] s ( __ld32 key * 4 k ) ) = k + k 1 }
    ( vec_push [i] s ( __m32 counter ) )
    ( vec_push [i] s ( __ld32 nonce 0 ) )
    ( vec_push [i] s ( __ld32 nonce 4 ) )
    ( vec_push [i] s ( __ld32 nonce 8 ) )
    ^ s
}

// The 64-byte keystream block for (key, counter, nonce).
@ chacha20_block ( Vec u ) key i counter ( Vec u ) nonce → ( Vec u ) {
    : ( Vec i ) s ( __chacha_state key counter nonce )
    : ( Vec i ) w ( vec_with_cap [i] 16 )
    : ~ i k 0
    ~ < k 16 { ( vec_push [i] w ( __wget s k ) ) = k + k 1 }
    : ~ i r 0
    ~ < r 10 {
        ( __qr w 0 4 8 12 )
        ( __qr w 1 5 9 13 )
        ( __qr w 2 6 10 14 )
        ( __qr w 3 7 11 15 )
        ( __qr w 0 5 10 15 )
        ( __qr w 1 6 11 12 )
        ( __qr w 2 7 8 13 )
        ( __qr w 3 4 9 14 )
        = r + r 1
    }
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    : ~ i i 0
    ~ < i 16 {
        ( __push_le32 out ( __m32 + ( __wget w i ) ( __wget s i ) ) )
        = i + i 1
    }
    ( vec_free [i] s )
    ( vec_free [i] w )
    ^ out
}

// Encrypt / decrypt `data` with the ChaCha20 keystream beginning at the
// given block counter. (XOR is its own inverse.)
//
// This is the whole cost of a TLS transfer, so it is written for the
// register allocator: the sixteen state words are LOCALS (the previous
// version made ~960 bounds-checked Vec accessor calls per 64-byte
// block), the key/nonce words are hoisted out of the block loop, the
// output is written through raw pointers, and a block allocates
// nothing. Measured on one core this is ~9x the accessor version, and
// it is what takes a pure-NURL TLS download from ~27 MB/s to well over
// 100.
@ chacha20_xor ( Vec u ) key i counter ( Vec u ) nonce ( Vec u ) data → ( Vec u ) {
    : i n ( vec_len [u] data )
    : ( Vec u ) out ( vec_with_cap [u] ? > n 0 n 1 )
    : b _ol ( vec_set_len [u] out n )
    ? == n 0 { ^ out } {}
    : *u dp ( vec_data [u] data )
    : *u op ( vec_data [u] out )
    : i k0 ( __ld32 key 0 )
    : i k1 ( __ld32 key 4 )
    : i k2 ( __ld32 key 8 )
    : i k3 ( __ld32 key 12 )
    : i k4 ( __ld32 key 16 )
    : i k5 ( __ld32 key 20 )
    : i k6 ( __ld32 key 24 )
    : i k7 ( __ld32 key 28 )
    : i n0 ( __ld32 nonce 0 )
    : i n1 ( __ld32 nonce 4 )
    : i n2 ( __ld32 nonce 8 )
    : *u ks # *u ( nurl_zalloc 64 )
    : ~ i ctr counter
    : ~ i off 0
    ~ < off n {
        : ~ i x0 1634760805
        : ~ i x1 857760878
        : ~ i x2 2036477234
        : ~ i x3 1797285236
        : ~ i x4 k0
        : ~ i x5 k1
        : ~ i x6 k2
        : ~ i x7 k3
        : ~ i x8 k4
        : ~ i x9 k5
        : ~ i x10 k6
        : ~ i x11 k7
        : ~ i x12 & ctr 4294967295
        : ~ i x13 n0
        : ~ i x14 n1
        : ~ i x15 n2
        : ~ i rr 0
        ~ < rr 10 {
            = x0 & + x0 x4 4294967295
            = x12 ^^ x12 x0
            = x12 & | << x12 16 >> x12 16 4294967295
            = x8 & + x8 x12 4294967295
            = x4 ^^ x4 x8
            = x4 & | << x4 12 >> x4 20 4294967295
            = x0 & + x0 x4 4294967295
            = x12 ^^ x12 x0
            = x12 & | << x12 8 >> x12 24 4294967295
            = x8 & + x8 x12 4294967295
            = x4 ^^ x4 x8
            = x4 & | << x4 7 >> x4 25 4294967295
            = x1 & + x1 x5 4294967295
            = x13 ^^ x13 x1
            = x13 & | << x13 16 >> x13 16 4294967295
            = x9 & + x9 x13 4294967295
            = x5 ^^ x5 x9
            = x5 & | << x5 12 >> x5 20 4294967295
            = x1 & + x1 x5 4294967295
            = x13 ^^ x13 x1
            = x13 & | << x13 8 >> x13 24 4294967295
            = x9 & + x9 x13 4294967295
            = x5 ^^ x5 x9
            = x5 & | << x5 7 >> x5 25 4294967295
            = x2 & + x2 x6 4294967295
            = x14 ^^ x14 x2
            = x14 & | << x14 16 >> x14 16 4294967295
            = x10 & + x10 x14 4294967295
            = x6 ^^ x6 x10
            = x6 & | << x6 12 >> x6 20 4294967295
            = x2 & + x2 x6 4294967295
            = x14 ^^ x14 x2
            = x14 & | << x14 8 >> x14 24 4294967295
            = x10 & + x10 x14 4294967295
            = x6 ^^ x6 x10
            = x6 & | << x6 7 >> x6 25 4294967295
            = x3 & + x3 x7 4294967295
            = x15 ^^ x15 x3
            = x15 & | << x15 16 >> x15 16 4294967295
            = x11 & + x11 x15 4294967295
            = x7 ^^ x7 x11
            = x7 & | << x7 12 >> x7 20 4294967295
            = x3 & + x3 x7 4294967295
            = x15 ^^ x15 x3
            = x15 & | << x15 8 >> x15 24 4294967295
            = x11 & + x11 x15 4294967295
            = x7 ^^ x7 x11
            = x7 & | << x7 7 >> x7 25 4294967295
            = x0 & + x0 x5 4294967295
            = x15 ^^ x15 x0
            = x15 & | << x15 16 >> x15 16 4294967295
            = x10 & + x10 x15 4294967295
            = x5 ^^ x5 x10
            = x5 & | << x5 12 >> x5 20 4294967295
            = x0 & + x0 x5 4294967295
            = x15 ^^ x15 x0
            = x15 & | << x15 8 >> x15 24 4294967295
            = x10 & + x10 x15 4294967295
            = x5 ^^ x5 x10
            = x5 & | << x5 7 >> x5 25 4294967295
            = x1 & + x1 x6 4294967295
            = x12 ^^ x12 x1
            = x12 & | << x12 16 >> x12 16 4294967295
            = x11 & + x11 x12 4294967295
            = x6 ^^ x6 x11
            = x6 & | << x6 12 >> x6 20 4294967295
            = x1 & + x1 x6 4294967295
            = x12 ^^ x12 x1
            = x12 & | << x12 8 >> x12 24 4294967295
            = x11 & + x11 x12 4294967295
            = x6 ^^ x6 x11
            = x6 & | << x6 7 >> x6 25 4294967295
            = x2 & + x2 x7 4294967295
            = x13 ^^ x13 x2
            = x13 & | << x13 16 >> x13 16 4294967295
            = x8 & + x8 x13 4294967295
            = x7 ^^ x7 x8
            = x7 & | << x7 12 >> x7 20 4294967295
            = x2 & + x2 x7 4294967295
            = x13 ^^ x13 x2
            = x13 & | << x13 8 >> x13 24 4294967295
            = x8 & + x8 x13 4294967295
            = x7 ^^ x7 x8
            = x7 & | << x7 7 >> x7 25 4294967295
            = x3 & + x3 x4 4294967295
            = x14 ^^ x14 x3
            = x14 & | << x14 16 >> x14 16 4294967295
            = x9 & + x9 x14 4294967295
            = x4 ^^ x4 x9
            = x4 & | << x4 12 >> x4 20 4294967295
            = x3 & + x3 x4 4294967295
            = x14 ^^ x14 x3
            = x14 & | << x14 8 >> x14 24 4294967295
            = x9 & + x9 x14 4294967295
            = x4 ^^ x4 x9
            = x4 & | << x4 7 >> x4 25 4294967295
            = rr + rr 1
        }
        = x0 & + x0 1634760805 4294967295
        = x1 & + x1 857760878 4294967295
        = x2 & + x2 2036477234 4294967295
        = x3 & + x3 1797285236 4294967295
        = x4 & + x4 k0 4294967295
        = x5 & + x5 k1 4294967295
        = x6 & + x6 k2 4294967295
        = x7 & + x7 k3 4294967295
        = x8 & + x8 k4 4294967295
        = x9 & + x9 k5 4294967295
        = x10 & + x10 k6 4294967295
        = x11 & + x11 k7 4294967295
        = x12 & + x12 & ctr 4294967295 4294967295
        = x13 & + x13 n0 4294967295
        = x14 & + x14 n1 4294967295
        = x15 & + x15 n2 4294967295
        ? >= - n off 64 {
            : i v0 x0
            = . op off # u ^^ # i . dp off & v0 255
            = . op + off 1 # u ^^ # i . dp + off 1 & >> v0 8 255
            = . op + off 2 # u ^^ # i . dp + off 2 & >> v0 16 255
            = . op + off 3 # u ^^ # i . dp + off 3 & >> v0 24 255
            : i v1 x1
            = . op + off 4 # u ^^ # i . dp + off 4 & v1 255
            = . op + off 5 # u ^^ # i . dp + off 5 & >> v1 8 255
            = . op + off 6 # u ^^ # i . dp + off 6 & >> v1 16 255
            = . op + off 7 # u ^^ # i . dp + off 7 & >> v1 24 255
            : i v2 x2
            = . op + off 8 # u ^^ # i . dp + off 8 & v2 255
            = . op + off 9 # u ^^ # i . dp + off 9 & >> v2 8 255
            = . op + off 10 # u ^^ # i . dp + off 10 & >> v2 16 255
            = . op + off 11 # u ^^ # i . dp + off 11 & >> v2 24 255
            : i v3 x3
            = . op + off 12 # u ^^ # i . dp + off 12 & v3 255
            = . op + off 13 # u ^^ # i . dp + off 13 & >> v3 8 255
            = . op + off 14 # u ^^ # i . dp + off 14 & >> v3 16 255
            = . op + off 15 # u ^^ # i . dp + off 15 & >> v3 24 255
            : i v4 x4
            = . op + off 16 # u ^^ # i . dp + off 16 & v4 255
            = . op + off 17 # u ^^ # i . dp + off 17 & >> v4 8 255
            = . op + off 18 # u ^^ # i . dp + off 18 & >> v4 16 255
            = . op + off 19 # u ^^ # i . dp + off 19 & >> v4 24 255
            : i v5 x5
            = . op + off 20 # u ^^ # i . dp + off 20 & v5 255
            = . op + off 21 # u ^^ # i . dp + off 21 & >> v5 8 255
            = . op + off 22 # u ^^ # i . dp + off 22 & >> v5 16 255
            = . op + off 23 # u ^^ # i . dp + off 23 & >> v5 24 255
            : i v6 x6
            = . op + off 24 # u ^^ # i . dp + off 24 & v6 255
            = . op + off 25 # u ^^ # i . dp + off 25 & >> v6 8 255
            = . op + off 26 # u ^^ # i . dp + off 26 & >> v6 16 255
            = . op + off 27 # u ^^ # i . dp + off 27 & >> v6 24 255
            : i v7 x7
            = . op + off 28 # u ^^ # i . dp + off 28 & v7 255
            = . op + off 29 # u ^^ # i . dp + off 29 & >> v7 8 255
            = . op + off 30 # u ^^ # i . dp + off 30 & >> v7 16 255
            = . op + off 31 # u ^^ # i . dp + off 31 & >> v7 24 255
            : i v8 x8
            = . op + off 32 # u ^^ # i . dp + off 32 & v8 255
            = . op + off 33 # u ^^ # i . dp + off 33 & >> v8 8 255
            = . op + off 34 # u ^^ # i . dp + off 34 & >> v8 16 255
            = . op + off 35 # u ^^ # i . dp + off 35 & >> v8 24 255
            : i v9 x9
            = . op + off 36 # u ^^ # i . dp + off 36 & v9 255
            = . op + off 37 # u ^^ # i . dp + off 37 & >> v9 8 255
            = . op + off 38 # u ^^ # i . dp + off 38 & >> v9 16 255
            = . op + off 39 # u ^^ # i . dp + off 39 & >> v9 24 255
            : i v10 x10
            = . op + off 40 # u ^^ # i . dp + off 40 & v10 255
            = . op + off 41 # u ^^ # i . dp + off 41 & >> v10 8 255
            = . op + off 42 # u ^^ # i . dp + off 42 & >> v10 16 255
            = . op + off 43 # u ^^ # i . dp + off 43 & >> v10 24 255
            : i v11 x11
            = . op + off 44 # u ^^ # i . dp + off 44 & v11 255
            = . op + off 45 # u ^^ # i . dp + off 45 & >> v11 8 255
            = . op + off 46 # u ^^ # i . dp + off 46 & >> v11 16 255
            = . op + off 47 # u ^^ # i . dp + off 47 & >> v11 24 255
            : i v12 x12
            = . op + off 48 # u ^^ # i . dp + off 48 & v12 255
            = . op + off 49 # u ^^ # i . dp + off 49 & >> v12 8 255
            = . op + off 50 # u ^^ # i . dp + off 50 & >> v12 16 255
            = . op + off 51 # u ^^ # i . dp + off 51 & >> v12 24 255
            : i v13 x13
            = . op + off 52 # u ^^ # i . dp + off 52 & v13 255
            = . op + off 53 # u ^^ # i . dp + off 53 & >> v13 8 255
            = . op + off 54 # u ^^ # i . dp + off 54 & >> v13 16 255
            = . op + off 55 # u ^^ # i . dp + off 55 & >> v13 24 255
            : i v14 x14
            = . op + off 56 # u ^^ # i . dp + off 56 & v14 255
            = . op + off 57 # u ^^ # i . dp + off 57 & >> v14 8 255
            = . op + off 58 # u ^^ # i . dp + off 58 & >> v14 16 255
            = . op + off 59 # u ^^ # i . dp + off 59 & >> v14 24 255
            : i v15 x15
            = . op + off 60 # u ^^ # i . dp + off 60 & v15 255
            = . op + off 61 # u ^^ # i . dp + off 61 & >> v15 8 255
            = . op + off 62 # u ^^ # i . dp + off 62 & >> v15 16 255
            = . op + off 63 # u ^^ # i . dp + off 63 & >> v15 24 255
        } {
            : i v0 x0
            = . ks 0 # u & v0 255
            = . ks 1 # u & >> v0 8 255
            = . ks 2 # u & >> v0 16 255
            = . ks 3 # u & >> v0 24 255
            : i v1 x1
            = . ks 4 # u & v1 255
            = . ks 5 # u & >> v1 8 255
            = . ks 6 # u & >> v1 16 255
            = . ks 7 # u & >> v1 24 255
            : i v2 x2
            = . ks 8 # u & v2 255
            = . ks 9 # u & >> v2 8 255
            = . ks 10 # u & >> v2 16 255
            = . ks 11 # u & >> v2 24 255
            : i v3 x3
            = . ks 12 # u & v3 255
            = . ks 13 # u & >> v3 8 255
            = . ks 14 # u & >> v3 16 255
            = . ks 15 # u & >> v3 24 255
            : i v4 x4
            = . ks 16 # u & v4 255
            = . ks 17 # u & >> v4 8 255
            = . ks 18 # u & >> v4 16 255
            = . ks 19 # u & >> v4 24 255
            : i v5 x5
            = . ks 20 # u & v5 255
            = . ks 21 # u & >> v5 8 255
            = . ks 22 # u & >> v5 16 255
            = . ks 23 # u & >> v5 24 255
            : i v6 x6
            = . ks 24 # u & v6 255
            = . ks 25 # u & >> v6 8 255
            = . ks 26 # u & >> v6 16 255
            = . ks 27 # u & >> v6 24 255
            : i v7 x7
            = . ks 28 # u & v7 255
            = . ks 29 # u & >> v7 8 255
            = . ks 30 # u & >> v7 16 255
            = . ks 31 # u & >> v7 24 255
            : i v8 x8
            = . ks 32 # u & v8 255
            = . ks 33 # u & >> v8 8 255
            = . ks 34 # u & >> v8 16 255
            = . ks 35 # u & >> v8 24 255
            : i v9 x9
            = . ks 36 # u & v9 255
            = . ks 37 # u & >> v9 8 255
            = . ks 38 # u & >> v9 16 255
            = . ks 39 # u & >> v9 24 255
            : i v10 x10
            = . ks 40 # u & v10 255
            = . ks 41 # u & >> v10 8 255
            = . ks 42 # u & >> v10 16 255
            = . ks 43 # u & >> v10 24 255
            : i v11 x11
            = . ks 44 # u & v11 255
            = . ks 45 # u & >> v11 8 255
            = . ks 46 # u & >> v11 16 255
            = . ks 47 # u & >> v11 24 255
            : i v12 x12
            = . ks 48 # u & v12 255
            = . ks 49 # u & >> v12 8 255
            = . ks 50 # u & >> v12 16 255
            = . ks 51 # u & >> v12 24 255
            : i v13 x13
            = . ks 52 # u & v13 255
            = . ks 53 # u & >> v13 8 255
            = . ks 54 # u & >> v13 16 255
            = . ks 55 # u & >> v13 24 255
            : i v14 x14
            = . ks 56 # u & v14 255
            = . ks 57 # u & >> v14 8 255
            = . ks 58 # u & >> v14 16 255
            = . ks 59 # u & >> v14 24 255
            : i v15 x15
            = . ks 60 # u & v15 255
            = . ks 61 # u & >> v15 8 255
            = . ks 62 # u & >> v15 16 255
            = . ks 63 # u & >> v15 24 255
            : ~ i j 0
            ~ < + off j n {
                = . op + off j # u ^^ # i . dp + off j # i . ks j
                = j + j 1
            }
        }
        = off + off 64
        = ctr + ctr 1
    }
    ( nurl_free # s ks )
    ^ out
}

// ── Poly1305 (poly1305-donna, radix 2^26) ─────────────────────────
// otk = 32-byte one-time key (r || s). Returns the 16-byte tag.
@ poly1305_mac ( Vec u ) otk ( Vec u ) msg → ( Vec u ) {
    // Clamp r into five 26-bit limbs.
    : i r0 & ( __ld32 otk 0 ) 67108863  // 0x3ffffff
    : i r1 & >> ( __ld32 otk 3 ) 2 67108611  // 0x3ffff03
    : i r2 & >> ( __ld32 otk 6 ) 4 67092735  // 0x3ffc0ff
    : i r3 & >> ( __ld32 otk 9 ) 6 66076671  // 0x3f03fff
    : i r4 & >> ( __ld32 otk 12 ) 8 1048575  // 0x00fffff
    : i s1 * r1 5
    : i s2 * r2 5
    : i s3 * r3 5
    : i s4 * r4 5

    : ~ i h0 0
    : ~ i h1 0
    : ~ i h2 0
    : ~ i h3 0
    : ~ i h4 0

    : i mlen ( vec_len [u] msg )
    : *u mp ( vec_data [u] msg )
    : ~ i off 0
    ~ < off mlen {
        : i rem - mlen off
        // Full 16-byte blocks — the whole message but its tail — load
        // their four words straight off the message pointer: the
        // per-block 17-byte scratch Vec and its bounds-checked reads
        // were a fifth of the whole MAC.
        ? >= rem 16 {
            : i w0 | | | # i . mp off << # i . mp + off 1 8 << # i . mp + off 2 16 << # i . mp + off 3 24
            : i w1 | | | # i . mp + off 4 << # i . mp + off 5 8 << # i . mp + off 6 16 << # i . mp + off 7 24
            : i w2 | | | # i . mp + off 8 << # i . mp + off 9 8 << # i . mp + off 10 16 << # i . mp + off 11 24
            : i w3 | | | # i . mp + off 12 << # i . mp + off 13 8 << # i . mp + off 14 16 << # i . mp + off 15 24
            = h0 + h0 & w0 67108863
            = h1 + h1 & | >> w0 26 << w1 6 67108863
            = h2 + h2 & | >> w1 20 << w2 12 67108863
            = h3 + h3 & | >> w2 14 << w3 18 67108863
            = h4 + h4 | >> w3 8 16777216
        } {
            : i blk rem
            // Tail: load into a 17-byte little-endian scratch, append the
            // 0x01 marker at 2^(8*blk), zero-pad the rest.
            : ( Vec u ) b ( vec_with_cap [u] 17 )
            : ~ i j 0
            ~ < j 16 {
                ? < j blk { ( vec_push [u] b # u ( __cc_bget msg + off j ) ) } { ( vec_push [u] b # u 0 ) }
                = j + j 1
            }
            ( vec_push [u] b # u 0 )
            ( vec_set [u] b blk # u 1 )

            = h0 + h0 & ( __ld32 b 0 ) 67108863
            = h1 + h1 & >> ( __ld32 b 3 ) 2 67108863
            = h2 + h2 & >> ( __ld32 b 6 ) 4 67108863
            = h3 + h3 & >> ( __ld32 b 9 ) 6 67108863
            = h4 + h4 | >> ( __ld32 b 12 ) 8 << ( __cc_bget b 16 ) 24
            ( vec_free [u] b )
        }

        // d = h * r mod 2^130-5  (schoolbook with the s_i = 5·r_i fold)
        : i d0 + + + + * h0 r0 * h1 s4 * h2 s3 * h3 s2 * h4 s1
        : ~ i d1 + + + + * h0 r1 * h1 r0 * h2 s4 * h3 s3 * h4 s2
        : ~ i d2 + + + + * h0 r2 * h1 r1 * h2 r0 * h3 s4 * h4 s3
        : ~ i d3 + + + + * h0 r3 * h1 r2 * h2 r1 * h3 r0 * h4 s4
        : ~ i d4 + + + + * h0 r4 * h1 r3 * h2 r2 * h3 r1 * h4 r0

        : ~ i c >> d0 26
        = h0 & d0 67108863
        = d1 + d1 c
        = c >> d1 26
        = h1 & d1 67108863
        = d2 + d2 c
        = c >> d2 26
        = h2 & d2 67108863
        = d3 + d3 c
        = c >> d3 26
        = h3 & d3 67108863
        = d4 + d4 c
        = c >> d4 26
        = h4 & d4 67108863
        = h0 + h0 * c 5
        = c >> h0 26
        = h0 & h0 67108863
        = h1 + h1 c

        = off + off 16
    }

    // Fully carry h.
    : ~ i c >> h1 26
    = h1 & h1 67108863
    = h2 + h2 c
    = c >> h2 26
    = h2 & h2 67108863
    = h3 + h3 c
    = c >> h3 26
    = h3 & h3 67108863
    = h4 + h4 c
    = c >> h4 26
    = h4 & h4 67108863
    = h0 + h0 * c 5
    = c >> h0 26
    = h0 & h0 67108863
    = h1 + h1 c

    // Compute h + -p (i.e. h - p) and select if h >= p.
    : ~ i g0 + h0 5
    : ~ i cc >> g0 26
    = g0 & g0 67108863
    : ~ i g1 + h1 cc
    = cc >> g1 26
    = g1 & g1 67108863
    : ~ i g2 + h2 cc
    = cc >> g2 26
    = g2 & g2 67108863
    : ~ i g3 + h3 cc
    = cc >> g3 26
    = g3 & g3 67108863
    : ~ i g4 - + h4 cc 67108864

    // mask = 0 when g4 borrowed (h < p) → keep h; else 0xff..ff → take g.
    : i mask ? < g4 0 0 -1
    = g0 & g0 mask
    = g1 & g1 mask
    = g2 & g2 mask
    = g3 & g3 mask
    = g4 & g4 mask
    : i imask ^^ mask -1
    = h0 | & h0 imask g0
    = h1 | & h1 imask g1
    = h2 | & h2 imask g2
    = h3 | & h3 imask g3
    = h4 | & h4 imask g4

    // Pack the 130-bit value down to four 32-bit words (mod 2^128).
    : i p0 & | h0 << h1 26 4294967295
    : i p1 & | >> h1 6 << h2 20 4294967295
    : i p2 & | >> h2 12 << h3 14 4294967295
    : i p3 & | >> h3 18 << h4 8 4294967295

    // tag = (h + s) mod 2^128, where s is otk[16..32].
    : ~ i f + p0 ( __ld32 otk 16 )
    : i t0 & f 4294967295
    = f + + p1 ( __ld32 otk 20 ) >> f 32
    : i t1 & f 4294967295
    = f + + p2 ( __ld32 otk 24 ) >> f 32
    : i t2 & f 4294967295
    = f + + p3 ( __ld32 otk 28 ) >> f 32
    : i t3 & f 4294967295

    : ( Vec u ) tag ( vec_with_cap [u] 16 )
    ( __push_le32 tag t0 )
    ( __push_le32 tag t1 )
    ( __push_le32 tag t2 )
    ( __push_le32 tag t3 )
    ^ tag
}

// ── ChaCha20-Poly1305 AEAD (RFC 8439 §2.8) ────────────────────────
// The one-time Poly1305 key: first 32 bytes of the counter-0 block.
@ __poly_key ( Vec u ) key ( Vec u ) nonce → ( Vec u ) {
    : ( Vec u ) blk ( chacha20_block key 0 nonce )
    : ( Vec u ) otk ( vec_with_cap [u] 32 )
    : ~ i k 0
    ~ < k 32 { ( vec_push [u] otk # u ( __cc_bget blk k ) ) = k + k 1 }
    ( vec_free [u] blk )
    ^ otk
}

@ __pad16 ( Vec u ) v i len → v {
    : i r & len 15
    ? != r 0 {
        : ~ i p - 16 r
        ~ > p 0 { ( vec_push [u] v # u 0 ) = p - p 1 }
    } {}
}

@ __push_le64 ( Vec u ) v i n → v {
    : ~ i k 0
    ~ < k 8 { ( vec_push [u] v # u & >> n * 8 k 255 ) = k + k 1 }
}

// Build the Poly1305 input: aad ‖ pad16 ‖ ct ‖ pad16 ‖ le64(|aad|) ‖ le64(|ct|).
@ __mac_data ( Vec u ) aad ( Vec u ) ct → ( Vec u ) {
    : i al ( vec_len [u] aad )
    : i cl ( vec_len [u] ct )
    : ( Vec u ) m ( vec_with_cap [u] + + al cl 32 )
    // Bulk pointer copies, not per-byte checked pushes: the ciphertext
    // side is the whole record and this concat sat at ~4% of a TLS
    // transfer on its own.
    : b _ml ( vec_set_len [u] m al )
    : *u mp ( vec_data [u] m )
    : *u ap ( vec_data [u] aad )
    : ~ i i 0
    ~ < i al { = . mp i . ap i = i + i 1 }
    ( __pad16 m al )
    : i cbase ( vec_len [u] m )
    : b _cl ( vec_set_len [u] m + cbase cl )
    : *u mp2 ( vec_data [u] m )
    : *u cp ( vec_data [u] ct )
    = i 0
    ~ < i cl { = . mp2 + cbase i . cp i = i + i 1 }
    ( __pad16 m cl )
    ( __push_le64 m al )
    ( __push_le64 m cl )
    ^ m
}

// Encrypt: returns ciphertext with the 16-byte tag appended.
@ aead_encrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) plaintext → ( Vec u ) {
    // M5/L6: 32-byte key, 12-byte nonce, and the ChaCha20 keystream limit
    // (2^32 blocks × 64 B); past it the 32-bit block counter wraps and
    // reuses keystream. A wrong nonce length would otherwise risk reuse.
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ ( vec_new [u] ) } {}
    ? > ( vec_len [u] plaintext ) 274877906880 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) otk ( __poly_key key nonce )
    : ( Vec u ) ct ( chacha20_xor key 1 nonce plaintext )
    : ( Vec u ) md ( __mac_data aad ct )
    : ( Vec u ) tag ( poly1305_mac otk md )
    : ~ i k 0
    ~ < k 16 { ( vec_push [u] ct # u ( __cc_bget tag k ) ) = k + k 1 }
    ( vec_free [u] otk )
    ( vec_free [u] md )
    ( vec_free [u] tag )
    ^ ct
}

// Constant-time tag comparison over the trailing 16 bytes of `ct_and_tag`.
@ __tag_ok ( Vec u ) ct_and_tag i ctlen ( Vec u ) want → b {
    : ~ i diff 0
    : ~ i k 0
    ~ < k 16 {
        = diff | diff ^^ ( __cc_bget ct_and_tag + ctlen k ) ( __cc_bget want k )
        = k + k 1
    }
    ^ == diff 0
}

// Decrypt + verify. ct_and_tag is ciphertext followed by its 16-byte
// tag. Returns None on any tampering (wrong tag), the plaintext on success.
@ aead_decrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_and_tag → ?( Vec u ) {
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : i total ( vec_len [u] ct_and_tag )
    ? < total 16 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : i ctlen - total 16
    : ( Vec u ) ct ( vec_with_cap [u] ? > ctlen 0 ctlen 1 )
    : ~ i k 0
    ~ < k ctlen { ( vec_push [u] ct # u ( __cc_bget ct_and_tag k ) ) = k + k 1 }

    : ( Vec u ) otk ( __poly_key key nonce )
    : ( Vec u ) md ( __mac_data aad ct )
    : ( Vec u ) tag ( poly1305_mac otk md )
    : b ok ( __tag_ok ct_and_tag ctlen tag )
    ( vec_free [u] otk )
    ( vec_free [u] md )
    ( vec_free [u] tag )
    ? ! ok {
        ( vec_free [u] ct )
        ^ @ ?( Vec u ) { F # ( Vec u ) 0 }
    } {}
    : ( Vec u ) pt ( chacha20_xor key 1 nonce ct )
    ( vec_free [u] ct )
    ^ @ ?( Vec u ) { T pt }
}
