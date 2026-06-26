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

// C2: the AES S-box is computed CONSTANT-TIME, not read from a table indexed
// by secret bytes (which leaks the key via cache-timing — the reason hardware
// ships AES-NI / bitsliced AES). SubBytes(x) = Affine(x^{-1} in GF(2^8)).
// Both the GF multiply and the fixed-exponent inversion are branchless in the
// data, so duration is independent of key/plaintext. Verified to match the
// reference S-box on all 256 inputs. (Slower than a table — ChaCha20-Poly1305
// is the faster constant-time default; AES is the fallback for AES-only peers.)

// Constant-time GF(2^8) multiply (AES field, reduction polynomial 0x11b).
@ __gf_mul i a i b → i {
    : ~ i p 0
    : ~ i aa & a 255
    : ~ i bb & b 255
    : ~ i k 0
    ~ < k 8 {
        : i m & 1 bb
        = p ^^ p & aa - 0 m            // add aa iff low bit of bb set (mask)
        : i hi & 1 >> aa 7
        = aa & 255 ^^ << aa 1 & 27 - 0 hi  // xtime(aa), branchless reduction
        = bb >> bb 1
        = k + k 1
    }
    ^ & p 255
}

// Multiplicative inverse in GF(2^8): x^254 (= x^{-1}; 0 maps to 0). The
// exponent 254 is a constant, so the square/multiply pattern is fixed and
// independent of the secret x.
@ __gf_inv i x → i {
    : i xx & x 255
    : ~ i r 1
    : ~ i bit 7
    ~ >= bit 0 {
        = r ( __gf_mul r r )
        ? != 0 & 1 >> 254 bit { = r ( __gf_mul r xx ) } {}
        = bit - bit 1
    }
    ^ r
}

@ __rotl8 i x i n → i { ^ & 255 | << x n >> & 255 x - 8 n }

// SubBytes(x) — constant-time. s = inv ⊕ rotl(inv,1..4) ⊕ 0x63.
@ __aes_sbox_ct i x → i {
    : i b0 ( __gf_inv & x 255 )
    ^ & 255 ^^ ^^ ^^ ^^ ^^ b0 ( __rotl8 b0 1 ) ( __rotl8 b0 2 ) ( __rotl8 b0 3 ) ( __rotl8 b0 4 ) 99
}

// xtime (·2 in GF(2^8)), branchless: reduce by 0x1b iff the high bit was set.
@ __xtime i x → i {
    : i s << x 1
    : i hi & 1 >> & x 255 7
    ^ & 255 ^^ s & 27 - 0 hi
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
            : i a ( __aes_sbox_ct t1 )
            : i b ( __aes_sbox_ct t2 )
            : i c ( __aes_sbox_ct t3 )
            : i d ( __aes_sbox_ct t0 )
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
// Encrypt one 16-byte block. `nr` is the round count (10 for AES-128,
// 14 for AES-256); the final round key sits at offset nr*16.
@ __aes_encrypt_block ( Vec u ) inb i off ( Vec u ) rk ( Vec u ) sbox i nr → ( Vec u ) {
    : ( Vec u ) s ( vec_with_cap [u] 16 )
    : ~ i i 0
    ~ < i 16 { ( vec_push [u] s # u ^^ ( __aes_bget inb + off i ) ( __aes_bget rk i ) ) = i + i 1 }
    : ~ i round 1
    ~ < round nr {
        ( __aes_sub_shift s sbox )
        ( __aes_mixcolumns s )
        ( __aes_addroundkey s rk * round 16 )
        = round + round 1
    }
    ( __aes_sub_shift s sbox )
    ( __aes_addroundkey s rk * nr 16 )
    ^ s
}

// AES-256 key expansion → 240 bytes (15 round keys). Nk = 8: an extra
// SubWord every 8th word (the i%8 == 4 case) on top of the 128 schedule.
@ __aes256_expand ( Vec u ) key ( Vec u ) sbox → ( Vec u ) {
    : ( Vec u ) w ( vec_with_cap [u] 240 )
    : ~ i i 0
    ~ < i 32 { ( vec_push [u] w # u ( __aes_bget key i ) ) = i + i 1 }
    : ( Vec u ) rcon ?? ( bytes_from_hex `0102040810204080` ) { T v → v F _ → ( vec_new [u] ) }
    : ~ i n 32
    : ~ i rc 0
    ~ < n 240 {
        : ~ i t0 ( __aes_bget w - n 4 )
        : ~ i t1 ( __aes_bget w - n 3 )
        : ~ i t2 ( __aes_bget w - n 2 )
        : ~ i t3 ( __aes_bget w - n 1 )
        ? == % n 32 0 {
            // RotWord + SubWord + Rcon
            : i a ( __aes_sbox_ct t1 )
            : i b ( __aes_sbox_ct t2 )
            : i c ( __aes_sbox_ct t3 )
            : i d ( __aes_sbox_ct t0 )
            = t0 ^^ a ( __aes_bget rcon rc )
            = t1 b
            = t2 c
            = t3 d
            = rc + rc 1
        } {
            ? == % n 32 16 {
                // SubWord only (no RotWord, no Rcon)
                = t0 ( __aes_sbox_ct t0 )
                = t1 ( __aes_sbox_ct t1 )
                = t2 ( __aes_sbox_ct t2 )
                = t3 ( __aes_sbox_ct t3 )
            } {}
        }
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 32 ) t0 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 31 ) t1 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 30 ) t2 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 29 ) t3 )
        = n + n 4
    }
    ( vec_free [u] rcon )
    ^ w
}

// Pick the expanded round keys for a 16- or 32-byte key.
@ __aes_expand ( Vec u ) key ( Vec u ) sbox → ( Vec u ) {
    ? == ( vec_len [u] key ) 32 { ^ ( __aes256_expand key sbox ) } { ^ ( __aes128_expand key sbox ) }
}

// Round count for a 16- or 32-byte key.
@ __aes_nr ( Vec u ) key → i { ? == ( vec_len [u] key ) 32 { ^ 14 } { ^ 10 } }

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
            ( vec_set [u] s + r * 4 c # u ( __aes_sbox_ct ( __aes_bget t src ) ) )
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
        // M4: branchless. xbit ∈ {0,1}; mx = 0 or 0xFF. z ^= mx & v with no
        // data-dependent branch (the old `if x_bit` / `if lsb` leaked the
        // input bits and — via V — the auth key H through timing).
        : i xbit & 1 >> ( __aes_bget x byte ) - 7 & bit 7
        : i mx - 0 xbit
        : ~ i k 0
        ~ < k 16 { ( vec_set [u] z k # u & 255 ^^ ( __aes_bget z k ) & mx ( __aes_bget v k ) ) = k + k 1 }
        // V >>= 1 (across 16 bytes); if LSB was set, XOR R = 0xe1||0^120.
        : i lsb & ( __aes_bget v 15 ) 1
        : ~ i j 15
        ~ > j 0 {
            ( vec_set [u] v j # u | >> ( __aes_bget v j ) 1 << & ( __aes_bget v - j 1 ) 1 7 )
            = j - j 1
        }
        ( vec_set [u] v 0 # u >> ( __aes_bget v 0 ) 1 )
        : i ml - 0 lsb
        ( vec_set [u] v 0 # u & 255 ^^ ( __aes_bget v 0 ) & ml 225 )
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

@ __ctr_block ( Vec u ) j0 i counter ( Vec u ) rk ( Vec u ) sbox i nr → ( Vec u ) {
    : ( Vec u ) cb ( vec_with_cap [u] 16 )
    : ~ i i 0
    ~ < i 12 { ( vec_push [u] cb # u ( __aes_bget j0 i ) ) = i + i 1 }
    ( vec_push [u] cb # u & >> counter 24 255 )
    ( vec_push [u] cb # u & >> counter 16 255 )
    ( vec_push [u] cb # u & >> counter 8 255 )
    ( vec_push [u] cb # u & counter 255 )
    : ( Vec u ) ks ( __aes_encrypt_block cb 0 rk sbox nr )
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
    : ( Vec u ) sbox ( vec_new [u] )
    : i nr ( __aes_nr key )
    : ( Vec u ) rk ( __aes_expand key sbox )
    : ( Vec u ) zero ( vec_with_cap [u] 16 )
    : ~ i zz 0
    ~ < zz 16 { ( vec_push [u] zero # u 0 ) = zz + zz 1 }
    : ( Vec u ) h ( __aes_encrypt_block zero 0 rk sbox nr )

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
        : ( Vec u ) ks ( __ctr_block j0 ctr rk sbox nr )
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
    : ( Vec u ) sbox ( vec_new [u] )
    : i nr ( __aes_nr key )
    : ( Vec u ) rk ( __aes_expand key sbox )
    : ( Vec u ) zero ( vec_with_cap [u] 16 )
    : ~ i zz 0
    ~ < zz 16 { ( vec_push [u] zero # u 0 ) = zz + zz 1 }
    : ( Vec u ) h ( __aes_encrypt_block zero 0 rk sbox nr )
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
    : ( Vec u ) ekj0 ( __ctr_block j0 1 rk sbox nr )
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
    // M5/L6: validate key (16 B) / nonce (12 B) and the GCM plaintext cap
    // (2^39−256 bits = 2^36−32 bytes). A wrong nonce length would otherwise
    // silently produce a malformed-but-accepted nonce → catastrophic reuse.
    ? | != ( vec_len [u] key ) 16 != ( vec_len [u] nonce ) 12 { ^ ( vec_new [u] ) } {}
    ? > ( vec_len [u] pt ) 68719476704 { ^ ( vec_new [u] ) } {}
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
    ? | != ( vec_len [u] key ) 16 != ( vec_len [u] nonce ) 12 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
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

// AES-256-GCM (NIST SP 800-38D) — same GCM construction with a 32-byte key;
// the block cipher core dispatches on key length (14 rounds). This is the
// TLS_AES_256_GCM_SHA384 record protection and the AEAD used by ext/crypto.
// seal: returns ciphertext with the 16-byte tag appended.
@ aes256_gcm_encrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → ( Vec u ) {
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ ( vec_new [u] ) } {}
    ? > ( vec_len [u] pt ) 68719476704 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) dummy ( vec_new [u] )
    : ( Vec u ) ct ( __gcm_core key nonce aad pt dummy )
    ( vec_free [u] dummy )
    : ( Vec u ) tag ( __gcm_tag key nonce aad ct )
    : ~ i ti 0
    ~ < ti 16 { ( vec_push [u] ct # u ( __aes_bget tag ti ) ) = ti + ti 1 }
    ( vec_free [u] tag )
    ^ ct
}

// open: ct_tag is ciphertext followed by its 16-byte tag. None on mismatch.
@ aes256_gcm_decrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_tag → ?( Vec u ) {
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
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
