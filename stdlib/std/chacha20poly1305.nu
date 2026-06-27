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
@ chacha20_xor ( Vec u ) key i counter ( Vec u ) nonce ( Vec u ) data → ( Vec u ) {
    : i n ( vec_len [u] data )
    : ( Vec u ) out ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i ctr counter
    : ~ i off 0
    ~ < off n {
        : ( Vec u ) ks ( chacha20_block key ctr nonce )
        : ~ i j 0
        ~ & < j 64 < + off j n {
            ( vec_push [u] out # u ^^ ( __cc_bget data + off j ) ( __cc_bget ks j ) )
            = j + j 1
        }
        ( vec_free [u] ks )
        = off + off 64
        = ctr + ctr 1
    }
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
    : ~ i off 0
    ~ < off mlen {
        : i rem - mlen off
        : i blk ? >= rem 16 16 rem
        // Load up to 16 bytes of this block into a 17-byte little-endian
        // scratch, append the 0x01 high marker, zero-pad the rest.
        : ( Vec u ) b ( vec_with_cap [u] 17 )
        : ~ i j 0
        ~ < j 16 {
            ? < j blk { ( vec_push [u] b # u ( __cc_bget msg + off j ) ) } { ( vec_push [u] b # u 0 ) }
            = j + j 1
        }
        // high bit: 2^128 for a full block, 2^(8*blk) for the final one.
        ( vec_push [u] b # u 0 )
        ? >= rem 16 { ( vec_set [u] b 16 # u 1 ) } { ( vec_set [u] b blk # u 1 ) }

        = h0 + h0 & ( __ld32 b 0 ) 67108863
        = h1 + h1 & >> ( __ld32 b 3 ) 2 67108863
        = h2 + h2 & >> ( __ld32 b 6 ) 4 67108863
        = h3 + h3 & >> ( __ld32 b 9 ) 6 67108863
        = h4 + h4 | >> ( __ld32 b 12 ) 8 << ( __cc_bget b 16 ) 24

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

        ( vec_free [u] b )
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
    : ~ i i 0
    ~ < i al { ( vec_push [u] m # u ( __cc_bget aad i ) ) = i + i 1 }
    ( __pad16 m al )
    = i 0
    ~ < i cl { ( vec_push [u] m # u ( __cc_bget ct i ) ) = i + i 1 }
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
