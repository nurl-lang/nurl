// stdlib/std/aes_gcm.nu — pure-NURL AES-128-GCM AEAD (NIST SP 800-38D),
// no OpenSSL. This is the TLS_AES_128_GCM_SHA256 record protection — the
// mandatory-to-implement TLS 1.3 cipher — so the client can talk to
// servers that only offer AES.
//
//   ( aes128_gcm_encrypt key nonce aad pt )     → ( Vec u )  ct||tag
//   ( aes128_gcm_decrypt key nonce aad ct_tag ) → ?( Vec u )  None if forged
//
//   key = 16 bytes, nonce = 12 bytes.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

@ __aes_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ __aes_sbox → ( Vec u ) {
    ^ ?? ( bytes_from_hex `637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b27509832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cfd0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdbe0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9ee1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16` ) {
        T v → v
        F _ → ( vec_new [u] )
    }
}

@ __xtime i x → i {
    : i s << x 1
    ^ & ? != 0 & x 128 ^^ s 27 s 255
}

// AES-128 key expansion → 176 bytes (11 round keys).
@ __aes128_expand ( Vec u ) key ( Vec u ) sbox → ( Vec u ) {
    : ( Vec u ) w ( vec_with_cap [u] 176 )
    : ~ i i 0
    ~ < i 16 { ( vec_push [u] w # u ( __aes_bget key i ) ) = i + i 1 }
    : ( Vec u ) rcon ?? ( bytes_from_hex `01020408102040801b36` ) { T v → v F _ → ( vec_new [u] ) }
    : ~ i n 16
    : ~ i rc 0
    ~ < n 176 {
        : ~ i t0 ( __aes_bget w - n 4 )
        : ~ i t1 ( __aes_bget w - n 3 )
        : ~ i t2 ( __aes_bget w - n 2 )
        : ~ i t3 ( __aes_bget w - n 1 )
        ? == % n 16 0 {
            // RotWord + SubWord + Rcon
            : i a ( __aes_bget sbox t1 )
            : i b ( __aes_bget sbox t2 )
            : i c ( __aes_bget sbox t3 )
            : i d ( __aes_bget sbox t0 )
            = t0 ^^ a ( __aes_bget rcon rc )
            = t1 b
            = t2 c
            = t3 d
            = rc + rc 1
        } {}
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 16 ) t0 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 15 ) t1 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 14 ) t2 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 13 ) t3 )
        = n + n 4
    }
    ( vec_free [u] rcon )
    ^ w
}

// Encrypt one 16-byte block `in` at offset `off` → 16-byte ( Vec u ).
@ __aes_encrypt_block ( Vec u ) inb i off ( Vec u ) rk ( Vec u ) sbox → ( Vec u ) {
    : ( Vec u ) s ( vec_with_cap [u] 16 )
    : ~ i i 0
    ~ < i 16 { ( vec_push [u] s # u ^^ ( __aes_bget inb + off i ) ( __aes_bget rk i ) ) = i + i 1 }
    : ~ i round 1
    ~ < round 10 {
        ( __aes_sub_shift s sbox )
        ( __aes_mixcolumns s )
        ( __aes_addroundkey s rk * round 16 )
        = round + round 1
    }
    ( __aes_sub_shift s sbox )
    ( __aes_addroundkey s rk 160 )
    ^ s
}

@ __aes_addroundkey ( Vec u ) s ( Vec u ) rk i off → v {
    : ~ i i 0
    ~ < i 16 { ( vec_set [u] s i # u ^^ ( __aes_bget s i ) ( __aes_bget rk + off i ) ) = i + i 1 }
}

// SubBytes + ShiftRows combined (state is column-major: s[r + 4c]).
@ __aes_sub_shift ( Vec u ) s ( Vec u ) sbox → v {
    : ( Vec u ) t ( vec_with_cap [u] 16 )
    : ~ i i 0
    ~ < i 16 { ( vec_push [u] t # u ( __aes_bget s i ) ) = i + i 1 }
    : ~ i c 0
    ~ < c 4 {
        : ~ i r 0
        ~ < r 4 {
            // ShiftRows: row r takes element from column (c+r)
            : i src + r * 4 % + c r 4
            ( vec_set [u] s + r * 4 c # u ( __aes_bget sbox ( __aes_bget t src ) ) )
            = r + r 1
        }
        = c + c 1
    }
    ( vec_free [u] t )
}

@ __aes_mixcolumns ( Vec u ) s → v {
    : ~ i c 0
    ~ < c 4 {
        : i b0 ( __aes_bget s + 0 * 4 c )
        : i b1 ( __aes_bget s + 1 * 4 c )
        : i b2 ( __aes_bget s + 2 * 4 c )
        : i b3 ( __aes_bget s + 3 * 4 c )
        ( vec_set [u] s + 0 * 4 c # u ^^ ^^ ^^ ( __xtime b0 ) ^^ ( __xtime b1 ) b1 b2 b3 )
        ( vec_set [u] s + 1 * 4 c # u ^^ ^^ ^^ b0 ( __xtime b1 ) ^^ ( __xtime b2 ) b2 b3 )
        ( vec_set [u] s + 2 * 4 c # u ^^ ^^ ^^ b0 b1 ( __xtime b2 ) ^^ ( __xtime b3 ) b3 )
        ( vec_set [u] s + 3 * 4 c # u ^^ ^^ ^^ ^^ ( __xtime b0 ) b0 b1 b2 ( __xtime b3 ) )
        = c + c 1
    }
}

// ── GHASH over GF(2^128) ──────────────────────────────────────────
// Z ^= X then Z = Z·H, accumulating one 16-byte block.
@ __ghash_mul ( Vec u ) x ( Vec u ) h → ( Vec u ) {
    : ( Vec u ) z ( vec_with_cap [u] 16 )
    : ~ i zi 0
    ~ < zi 16 { ( vec_push [u] z # u 0 ) = zi + zi 1 }
    : ( Vec u ) v ( vec_with_cap [u] 16 )
    : ~ i vi 0
    ~ < vi 16 { ( vec_push [u] v # u ( __aes_bget h vi ) ) = vi + vi 1 }
    : ~ i bit 0
    ~ < bit 128 {
        : i byte >> bit 3
        : i mask >> 128 & bit 7
        ? != 0 & ( __aes_bget x byte ) mask {
            : ~ i k 0
            ~ < k 16 { ( vec_set [u] z k # u ^^ ( __aes_bget z k ) ( __aes_bget v k ) ) = k + k 1 }
        } {}
        // V >>= 1 (across 16 bytes); if LSB was set, XOR R = 0xe1||0^120.
        : i lsb & ( __aes_bget v 15 ) 1
        : ~ i j 15
        ~ > j 0 {
            ( vec_set [u] v j # u | >> ( __aes_bget v j ) 1 << & ( __aes_bget v - j 1 ) 1 7 )
            = j - j 1
        }
        ( vec_set [u] v 0 # u >> ( __aes_bget v 0 ) 1 )
        ? != 0 lsb { ( vec_set [u] v 0 # u ^^ ( __aes_bget v 0 ) 225 ) } {}
        = bit + bit 1
    }
    ( vec_free [u] v )
    ^ z
}

// GHASH `data` (zero-padded to blocks) starting from accumulator `y`.
// Returns a fresh accumulator; does NOT consume `y` (the caller owns it).
@ __ghash ( Vec u ) y ( Vec u ) h ( Vec u ) data → ( Vec u ) {
    : ~ ( Vec u ) acc ( vec_with_cap [u] 16 )
    : ~ i ci 0
    ~ < ci 16 { ( vec_push [u] acc # u ( __aes_bget y ci ) ) = ci + ci 1 }
    : i n ( vec_len [u] data )
    : ~ i off 0
    ~ < off n {
        : ( Vec u ) blk ( vec_with_cap [u] 16 )
        : ~ i i 0
        ~ < i 16 {
            ? < + off i n { ( vec_push [u] blk # u ( __aes_bget data + off i ) ) } { ( vec_push [u] blk # u 0 ) }
            = i + i 1
        }
        : ~ i k 0
        ~ < k 16 { ( vec_set [u] blk k # u ^^ ( __aes_bget blk k ) ( __aes_bget acc k ) ) = k + k 1 }
        : ( Vec u ) nz ( __ghash_mul blk h )
        ( vec_free [u] acc )
        ( vec_free [u] blk )
        = acc nz
        = off + off 16
    }
    ^ acc
}

@ __ctr_block ( Vec u ) j0 i counter ( Vec u ) rk ( Vec u ) sbox → ( Vec u ) {
    : ( Vec u ) cb ( vec_with_cap [u] 16 )
    : ~ i i 0
    ~ < i 12 { ( vec_push [u] cb # u ( __aes_bget j0 i ) ) = i + i 1 }
    ( vec_push [u] cb # u & >> counter 24 255 )
    ( vec_push [u] cb # u & >> counter 16 255 )
    ( vec_push [u] cb # u & >> counter 8 255 )
    ( vec_push [u] cb # u & counter 255 )
    : ( Vec u ) ks ( __aes_encrypt_block cb 0 rk sbox )
    ( vec_free [u] cb )
    ^ ks
}

@ __u64be ( Vec u ) v i n → v {
    : ~ i k 0
    ~ < k 8 { ( vec_push [u] v # u & >> n * 8 - 7 k 255 ) = k + k 1 }
}

// Core GCM: returns ciphertext (or recovered plaintext) and writes the
// 16-byte tag into `tag_out`. CTR mode is symmetric, so the same routine
// serves encrypt and decrypt; the caller compares/produces the tag.
@ __gcm_core ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) input ( Vec u ) tag_out → ( Vec u ) {
    : ( Vec u ) sbox ( __aes_sbox )
    : ( Vec u ) rk ( __aes128_expand key sbox )
    : ( Vec u ) zero ( vec_with_cap [u] 16 )
    : ~ i zz 0
    ~ < zz 16 { ( vec_push [u] zero # u 0 ) = zz + zz 1 }
    : ( Vec u ) h ( __aes_encrypt_block zero 0 rk sbox )

    // J0 = nonce || 0x00000001
    : ( Vec u ) j0 ( vec_with_cap [u] 12 )
    : ~ i ni 0
    ~ < ni 12 { ( vec_push [u] j0 # u ( __aes_bget nonce ni ) ) = ni + ni 1 }

    // CTR over the input, counter from 2 (J0 uses counter 1).
    : i n ( vec_len [u] input )
    : ( Vec u ) out ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i off 0
    : ~ i ctr 2
    ~ < off n {
        : ( Vec u ) ks ( __ctr_block j0 ctr rk sbox )
        : ~ i j 0
        ~ & < j 16 < + off j n {
            ( vec_push [u] out # u ^^ ( __aes_bget input + off j ) ( __aes_bget ks j ) )
            = j + j 1
        }
        ( vec_free [u] ks )
        = off + off 16
        = ctr + ctr 1
    }

    // For auth, GHASH covers the CIPHERTEXT. On encrypt that's `out`; on
    // decrypt the ciphertext is the `input`. The caller passes plaintext
    // on encrypt / ciphertext on decrypt — so GHASH the ciphertext: it is
    // `out` when encrypting and `input` when decrypting. We always GHASH
    // the data that travels on the wire — handled by __gcm_tag below.
    ( vec_free [u] sbox )
    ( vec_free [u] rk )
    ( vec_free [u] zero )
    ( vec_free [u] h )
    ( vec_free [u] j0 )
    ^ out
}

// Compute the GCM tag over aad + ciphertext.
@ __gcm_tag ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct → ( Vec u ) {
    : ( Vec u ) sbox ( __aes_sbox )
    : ( Vec u ) rk ( __aes128_expand key sbox )
    : ( Vec u ) zero ( vec_with_cap [u] 16 )
    : ~ i zz 0
    ~ < zz 16 { ( vec_push [u] zero # u 0 ) = zz + zz 1 }
    : ( Vec u ) h ( __aes_encrypt_block zero 0 rk sbox )
    : ( Vec u ) y ( vec_with_cap [u] 16 )
    : ~ i yi 0
    ~ < yi 16 { ( vec_push [u] y # u 0 ) = yi + yi 1 }
    : ( Vec u ) y1 ( __ghash y h aad )
    : ( Vec u ) y2 ( __ghash y1 h ct )
    // length block: [len(aad)*8]_64 || [len(ct)*8]_64
    : ( Vec u ) lenblk ( vec_with_cap [u] 16 )
    ( __u64be lenblk * ( vec_len [u] aad ) 8 )
    ( __u64be lenblk * ( vec_len [u] ct ) 8 )
    : ( Vec u ) y3 ( __ghash y2 h lenblk )
    // tag = E_K(J0) XOR GHASH
    : ( Vec u ) j0 ( vec_with_cap [u] 12 )
    : ~ i ni 0
    ~ < ni 12 { ( vec_push [u] j0 # u ( __aes_bget nonce ni ) ) = ni + ni 1 }
    : ( Vec u ) ekj0 ( __ctr_block j0 1 rk sbox )
    : ( Vec u ) tag ( vec_with_cap [u] 16 )
    : ~ i ti 0
    ~ < ti 16 { ( vec_push [u] tag # u ^^ ( __aes_bget y3 ti ) ( __aes_bget ekj0 ti ) ) = ti + ti 1 }
    ( vec_free [u] sbox ) ( vec_free [u] rk ) ( vec_free [u] zero ) ( vec_free [u] h )
    ( vec_free [u] y1 ) ( vec_free [u] y2 ) ( vec_free [u] lenblk ) ( vec_free [u] y3 )
    ( vec_free [u] j0 ) ( vec_free [u] ekj0 ) ( vec_free [u] y )
    ^ tag
}

// AES-128-GCM seal: returns ciphertext with the 16-byte tag appended.
@ aes128_gcm_encrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → ( Vec u ) {
    : ( Vec u ) dummy ( vec_new [u] )
    : ( Vec u ) ct ( __gcm_core key nonce aad pt dummy )
    ( vec_free [u] dummy )
    : ( Vec u ) tag ( __gcm_tag key nonce aad ct )
    : ~ i ti 0
    ~ < ti 16 { ( vec_push [u] ct # u ( __aes_bget tag ti ) ) = ti + ti 1 }
    ( vec_free [u] tag )
    ^ ct
}

@ __ct_eq ( Vec u ) a i aoff ( Vec u ) b → b {
    : ~ i diff 0
    : ~ i k 0
    ~ < k 16 { = diff | diff ^^ ( __aes_bget a + aoff k ) ( __aes_bget b k ) = k + k 1 }
    ^ == diff 0
}

// AES-128-GCM open: ct_tag is ciphertext followed by its 16-byte tag.
// None on tag mismatch.
@ aes128_gcm_decrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_tag → ?( Vec u ) {
    : i total ( vec_len [u] ct_tag )
    ? < total 16 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : i ctlen - total 16
    : ( Vec u ) ct ( bytes_slice ct_tag 0 ctlen )
    : ( Vec u ) tag ( __gcm_tag key nonce aad ct )
    : b ok ( __ct_eq ct_tag ctlen tag )
    ( vec_free [u] tag )
    ? ! ok { ( vec_free [u] ct ) ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : ( Vec u ) dummy ( vec_new [u] )
    : ( Vec u ) pt ( __gcm_core key nonce aad ct dummy )
    ( vec_free [u] dummy )
    ( vec_free [u] ct )
    ^ @ ?( Vec u ) { T pt }
}
