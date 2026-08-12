// stdlib/std/chacha20poly1305.nu — pure-NURL ChaCha20, Poly1305, and the
// ChaCha20-Poly1305 AEAD (RFC 8439). No OpenSSL, no FFI.
//
// This is the record-protection half of a pure TLS 1.3 stack (the
// TLS_CHACHA20_POLY1305_SHA256 cipher suite), and is equally usable for
// Noise / age / any AEAD need on a host with nothing installed.
//
// ChaCha20 words are kept in i64 limbs masked to 32 bits;
// Poly1305 is a port of the well-trodden poly1305-donna radix-2^44
// reference — three 44/44/42-bit limbs whose h·r terms are full
// 64×64→128 products (nurl_umulhi supplies the high half), 9 multiplies
// a block against the 25 a 2^26 form needs.
//
// Public surface:
//   ( chacha20_block key counter nonce )      → ( Vec u )  64-byte block
//   ( chacha20_xor key counter nonce data )   → ( Vec u )  stream cipher
//   ( chacha20_xor_range k c n data off len ) → ( Vec u )  … over a range
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

// ── ChaCha20 ──────────────────────────────────────────────────────
// The round function lives once, inside `chacha20_xor_range` below, with
// the sixteen state words held in locals. The separate quarter-round /
// state-vector helpers this file used to carry for `chacha20_block` were
// the accessor-based second copy of it, and are gone.

// Does a 64-bit store land in memory low byte first? The block loop
// below combines two 32-bit keystream words into one machine word and
// stores it whole, which is only the same bytes on a little-endian
// machine. Every target NURL builds for is one, but this file is where
// getting it wrong would mean silently wrong ciphertext rather than a
// build error, so it asks instead of assuming — once, into a global, not
// once per record. (Two threads racing here both write the same answer.)
: ~ i g_cc_le -1

@ __le_words → i {
    ? >= g_cc_le 0 { ^ g_cc_le } {}
    : *u p # *u ( nurl_zalloc 8 )
    ( nurl_poke # s p 0 1 )
    = g_cc_le ? == # i . p 0 1 1 0
    ( nurl_free # s p )
    ^ g_cc_le
}

// `n` zero bytes — the plaintext that turns the XOR kernel into a plain
// keystream generator.
@ __zeros i n → ( Vec u ) {
    : ( Vec u ) z ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] z # u 0 ) = k + k 1 }
    ^ z
}

// The 64-byte keystream block for (key, counter, nonce). Keystream is
// what the XOR kernel produces against a zero plaintext, so this goes
// through `chacha20_xor_range` rather than keeping a second, slower copy
// of the round function: the accessor-based version this replaced ran
// ~960 bounds-checked Vec calls a block, and the AEAD below needs one
// block PER RECORD for the Poly1305 one-time key.
@ chacha20_block ( Vec u ) key i counter ( Vec u ) nonce → ( Vec u ) {
    : ( Vec u ) z ( __zeros 64 )
    : ( Vec u ) out ( chacha20_xor_range key counter nonce z 0 64 )
    ( vec_free [u] z )
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
    ^ ( chacha20_xor_range key counter nonce data 0 ( vec_len [u] data ) )
}

// The same, over the `n` bytes of `data` starting at `doff`, so a caller
// that holds its plaintext or ciphertext INSIDE a larger buffer does not
// have to slice a copy out first just to name it. An AEAD record arrives
// as ciphertext‖tag in one Vec, and every 16 KB of a TLS transfer used
// to be copied out of that buffer byte by bounds-checked byte before
// this kernel would look at it.
//
// The caller is responsible for `doff + n` being within `data`; this is
// a private-by-convention entry point (the AEAD pair below and the
// record layer are its only users) and it does no bounds check of its
// own, exactly like the raw-pointer loop it feeds.
@ chacha20_xor_range ( Vec u ) key i counter ( Vec u ) nonce ( Vec u ) data i doff i n → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] ? > n 0 n 1 )
    : b _ol ( vec_set_len [u] out n )
    ? == n 0 { ^ out } {}
    : *u dp # *u + # i ( vec_data [u] data ) doff
    : *u op ( vec_data [u] out )
    : u32 k0 # u32 ( __ld32 key 0 )
    : u32 k1 # u32 ( __ld32 key 4 )
    : u32 k2 # u32 ( __ld32 key 8 )
    : u32 k3 # u32 ( __ld32 key 12 )
    : u32 k4 # u32 ( __ld32 key 16 )
    : u32 k5 # u32 ( __ld32 key 20 )
    : u32 k6 # u32 ( __ld32 key 24 )
    : u32 k7 # u32 ( __ld32 key 28 )
    : u32 n0 # u32 ( __ld32 nonce 0 )
    : u32 n1 # u32 ( __ld32 nonce 4 )
    : u32 n2 # u32 ( __ld32 nonce 8 )
    // Whole-block XOR through 8-byte loads and stores when both buffers
    // are 8-byte aligned — a Vec's storage comes from malloc, so they
    // are unless a caller hands in an unaligned `doff`. Eight loads,
    // eight XORs and eight stores a block, against sixty-four of each
    // plus their shifts and masks on the byte path below, which stays as
    // the fallback for the unaligned and big-endian cases.
    : i wordio & ( __le_words ) ? == 0 | & # i dp 7 & # i op 7 1 0
    : *u ks # *u ( nurl_zalloc 64 )
    : ~ i ctr counter
    : ~ i off 0
    ~ < off n {
        : ~ u32 x0 1634760805
        : ~ u32 x1 857760878
        : ~ u32 x2 2036477234
        : ~ u32 x3 1797285236
        : ~ u32 x4 k0
        : ~ u32 x5 k1
        : ~ u32 x6 k2
        : ~ u32 x7 k3
        : ~ u32 x8 k4
        : ~ u32 x9 k5
        : ~ u32 x10 k6
        : ~ u32 x11 k7
        : ~ u32 x12 # u32 ctr
        : ~ u32 x13 n0
        : ~ u32 x14 n1
        : ~ u32 x15 n2
        : ~ i rr 0
        ~ < rr 10 {
            = x0 + x0 x4
            = x12 ^^ x12 x0
            = x12 | << x12 16 >> x12 16
            = x8 + x8 x12
            = x4 ^^ x4 x8
            = x4 | << x4 12 >> x4 20
            = x0 + x0 x4
            = x12 ^^ x12 x0
            = x12 | << x12 8 >> x12 24
            = x8 + x8 x12
            = x4 ^^ x4 x8
            = x4 | << x4 7 >> x4 25
            = x1 + x1 x5
            = x13 ^^ x13 x1
            = x13 | << x13 16 >> x13 16
            = x9 + x9 x13
            = x5 ^^ x5 x9
            = x5 | << x5 12 >> x5 20
            = x1 + x1 x5
            = x13 ^^ x13 x1
            = x13 | << x13 8 >> x13 24
            = x9 + x9 x13
            = x5 ^^ x5 x9
            = x5 | << x5 7 >> x5 25
            = x2 + x2 x6
            = x14 ^^ x14 x2
            = x14 | << x14 16 >> x14 16
            = x10 + x10 x14
            = x6 ^^ x6 x10
            = x6 | << x6 12 >> x6 20
            = x2 + x2 x6
            = x14 ^^ x14 x2
            = x14 | << x14 8 >> x14 24
            = x10 + x10 x14
            = x6 ^^ x6 x10
            = x6 | << x6 7 >> x6 25
            = x3 + x3 x7
            = x15 ^^ x15 x3
            = x15 | << x15 16 >> x15 16
            = x11 + x11 x15
            = x7 ^^ x7 x11
            = x7 | << x7 12 >> x7 20
            = x3 + x3 x7
            = x15 ^^ x15 x3
            = x15 | << x15 8 >> x15 24
            = x11 + x11 x15
            = x7 ^^ x7 x11
            = x7 | << x7 7 >> x7 25
            = x0 + x0 x5
            = x15 ^^ x15 x0
            = x15 | << x15 16 >> x15 16
            = x10 + x10 x15
            = x5 ^^ x5 x10
            = x5 | << x5 12 >> x5 20
            = x0 + x0 x5
            = x15 ^^ x15 x0
            = x15 | << x15 8 >> x15 24
            = x10 + x10 x15
            = x5 ^^ x5 x10
            = x5 | << x5 7 >> x5 25
            = x1 + x1 x6
            = x12 ^^ x12 x1
            = x12 | << x12 16 >> x12 16
            = x11 + x11 x12
            = x6 ^^ x6 x11
            = x6 | << x6 12 >> x6 20
            = x1 + x1 x6
            = x12 ^^ x12 x1
            = x12 | << x12 8 >> x12 24
            = x11 + x11 x12
            = x6 ^^ x6 x11
            = x6 | << x6 7 >> x6 25
            = x2 + x2 x7
            = x13 ^^ x13 x2
            = x13 | << x13 16 >> x13 16
            = x8 + x8 x13
            = x7 ^^ x7 x8
            = x7 | << x7 12 >> x7 20
            = x2 + x2 x7
            = x13 ^^ x13 x2
            = x13 | << x13 8 >> x13 24
            = x8 + x8 x13
            = x7 ^^ x7 x8
            = x7 | << x7 7 >> x7 25
            = x3 + x3 x4
            = x14 ^^ x14 x3
            = x14 | << x14 16 >> x14 16
            = x9 + x9 x14
            = x4 ^^ x4 x9
            = x4 | << x4 12 >> x4 20
            = x3 + x3 x4
            = x14 ^^ x14 x3
            = x14 | << x14 8 >> x14 24
            = x9 + x9 x14
            = x4 ^^ x4 x9
            = x4 | << x4 7 >> x4 25
            = rr + rr 1
        }
        = x0 + x0 1634760805
        = x1 + x1 857760878
        = x2 + x2 2036477234
        = x3 + x3 1797285236
        = x4 + x4 k0
        = x5 + x5 k1
        = x6 + x6 k2
        = x7 + x7 k3
        = x8 + x8 k4
        = x9 + x9 k5
        = x10 + x10 k6
        = x11 + x11 k7
        = x12 + x12 # u32 ctr
        = x13 + x13 n0
        = x14 + x14 n1
        = x15 + x15 n2
        ? & == 1 wordio >= - n off 64 {
            // Eight machine words: the state pairs up low-word-first,
            // which is the same byte order the byte path spells out.
            : i w8 >> off 3
            ( nurl_poke # s op w8 ^^ ( nurl_peek # s dp w8 ) | # i x0 << # i x1 32 )
            ( nurl_poke # s op + w8 1 ^^ ( nurl_peek # s dp + w8 1 ) | # i x2 << # i x3 32 )
            ( nurl_poke # s op + w8 2 ^^ ( nurl_peek # s dp + w8 2 ) | # i x4 << # i x5 32 )
            ( nurl_poke # s op + w8 3 ^^ ( nurl_peek # s dp + w8 3 ) | # i x6 << # i x7 32 )
            ( nurl_poke # s op + w8 4 ^^ ( nurl_peek # s dp + w8 4 ) | # i x8 << # i x9 32 )
            ( nurl_poke # s op + w8 5 ^^ ( nurl_peek # s dp + w8 5 ) | # i x10 << # i x11 32 )
            ( nurl_poke # s op + w8 6 ^^ ( nurl_peek # s dp + w8 6 ) | # i x12 << # i x13 32 )
            ( nurl_poke # s op + w8 7 ^^ ( nurl_peek # s dp + w8 7 ) | # i x14 << # i x15 32 )
        } {}
        // Both write the same bytes; only the width differs.
        ? & == 0 wordio >= - n off 64 {
            : i v0 # i x0
            = . op off # u ^^ # i . dp off & v0 255
            = . op + off 1 # u ^^ # i . dp + off 1 & >> v0 8 255
            = . op + off 2 # u ^^ # i . dp + off 2 & >> v0 16 255
            = . op + off 3 # u ^^ # i . dp + off 3 & >> v0 24 255
            : i v1 # i x1
            = . op + off 4 # u ^^ # i . dp + off 4 & v1 255
            = . op + off 5 # u ^^ # i . dp + off 5 & >> v1 8 255
            = . op + off 6 # u ^^ # i . dp + off 6 & >> v1 16 255
            = . op + off 7 # u ^^ # i . dp + off 7 & >> v1 24 255
            : i v2 # i x2
            = . op + off 8 # u ^^ # i . dp + off 8 & v2 255
            = . op + off 9 # u ^^ # i . dp + off 9 & >> v2 8 255
            = . op + off 10 # u ^^ # i . dp + off 10 & >> v2 16 255
            = . op + off 11 # u ^^ # i . dp + off 11 & >> v2 24 255
            : i v3 # i x3
            = . op + off 12 # u ^^ # i . dp + off 12 & v3 255
            = . op + off 13 # u ^^ # i . dp + off 13 & >> v3 8 255
            = . op + off 14 # u ^^ # i . dp + off 14 & >> v3 16 255
            = . op + off 15 # u ^^ # i . dp + off 15 & >> v3 24 255
            : i v4 # i x4
            = . op + off 16 # u ^^ # i . dp + off 16 & v4 255
            = . op + off 17 # u ^^ # i . dp + off 17 & >> v4 8 255
            = . op + off 18 # u ^^ # i . dp + off 18 & >> v4 16 255
            = . op + off 19 # u ^^ # i . dp + off 19 & >> v4 24 255
            : i v5 # i x5
            = . op + off 20 # u ^^ # i . dp + off 20 & v5 255
            = . op + off 21 # u ^^ # i . dp + off 21 & >> v5 8 255
            = . op + off 22 # u ^^ # i . dp + off 22 & >> v5 16 255
            = . op + off 23 # u ^^ # i . dp + off 23 & >> v5 24 255
            : i v6 # i x6
            = . op + off 24 # u ^^ # i . dp + off 24 & v6 255
            = . op + off 25 # u ^^ # i . dp + off 25 & >> v6 8 255
            = . op + off 26 # u ^^ # i . dp + off 26 & >> v6 16 255
            = . op + off 27 # u ^^ # i . dp + off 27 & >> v6 24 255
            : i v7 # i x7
            = . op + off 28 # u ^^ # i . dp + off 28 & v7 255
            = . op + off 29 # u ^^ # i . dp + off 29 & >> v7 8 255
            = . op + off 30 # u ^^ # i . dp + off 30 & >> v7 16 255
            = . op + off 31 # u ^^ # i . dp + off 31 & >> v7 24 255
            : i v8 # i x8
            = . op + off 32 # u ^^ # i . dp + off 32 & v8 255
            = . op + off 33 # u ^^ # i . dp + off 33 & >> v8 8 255
            = . op + off 34 # u ^^ # i . dp + off 34 & >> v8 16 255
            = . op + off 35 # u ^^ # i . dp + off 35 & >> v8 24 255
            : i v9 # i x9
            = . op + off 36 # u ^^ # i . dp + off 36 & v9 255
            = . op + off 37 # u ^^ # i . dp + off 37 & >> v9 8 255
            = . op + off 38 # u ^^ # i . dp + off 38 & >> v9 16 255
            = . op + off 39 # u ^^ # i . dp + off 39 & >> v9 24 255
            : i v10 # i x10
            = . op + off 40 # u ^^ # i . dp + off 40 & v10 255
            = . op + off 41 # u ^^ # i . dp + off 41 & >> v10 8 255
            = . op + off 42 # u ^^ # i . dp + off 42 & >> v10 16 255
            = . op + off 43 # u ^^ # i . dp + off 43 & >> v10 24 255
            : i v11 # i x11
            = . op + off 44 # u ^^ # i . dp + off 44 & v11 255
            = . op + off 45 # u ^^ # i . dp + off 45 & >> v11 8 255
            = . op + off 46 # u ^^ # i . dp + off 46 & >> v11 16 255
            = . op + off 47 # u ^^ # i . dp + off 47 & >> v11 24 255
            : i v12 # i x12
            = . op + off 48 # u ^^ # i . dp + off 48 & v12 255
            = . op + off 49 # u ^^ # i . dp + off 49 & >> v12 8 255
            = . op + off 50 # u ^^ # i . dp + off 50 & >> v12 16 255
            = . op + off 51 # u ^^ # i . dp + off 51 & >> v12 24 255
            : i v13 # i x13
            = . op + off 52 # u ^^ # i . dp + off 52 & v13 255
            = . op + off 53 # u ^^ # i . dp + off 53 & >> v13 8 255
            = . op + off 54 # u ^^ # i . dp + off 54 & >> v13 16 255
            = . op + off 55 # u ^^ # i . dp + off 55 & >> v13 24 255
            : i v14 # i x14
            = . op + off 56 # u ^^ # i . dp + off 56 & v14 255
            = . op + off 57 # u ^^ # i . dp + off 57 & >> v14 8 255
            = . op + off 58 # u ^^ # i . dp + off 58 & >> v14 16 255
            = . op + off 59 # u ^^ # i . dp + off 59 & >> v14 24 255
            : i v15 # i x15
            = . op + off 60 # u ^^ # i . dp + off 60 & v15 255
            = . op + off 61 # u ^^ # i . dp + off 61 & >> v15 8 255
            = . op + off 62 # u ^^ # i . dp + off 62 & >> v15 16 255
            = . op + off 63 # u ^^ # i . dp + off 63 & >> v15 24 255
        } {}
        ? < - n off 64 {
            : i v0 # i x0
            = . ks 0 # u & v0 255
            = . ks 1 # u & >> v0 8 255
            = . ks 2 # u & >> v0 16 255
            = . ks 3 # u & >> v0 24 255
            : i v1 # i x1
            = . ks 4 # u & v1 255
            = . ks 5 # u & >> v1 8 255
            = . ks 6 # u & >> v1 16 255
            = . ks 7 # u & >> v1 24 255
            : i v2 # i x2
            = . ks 8 # u & v2 255
            = . ks 9 # u & >> v2 8 255
            = . ks 10 # u & >> v2 16 255
            = . ks 11 # u & >> v2 24 255
            : i v3 # i x3
            = . ks 12 # u & v3 255
            = . ks 13 # u & >> v3 8 255
            = . ks 14 # u & >> v3 16 255
            = . ks 15 # u & >> v3 24 255
            : i v4 # i x4
            = . ks 16 # u & v4 255
            = . ks 17 # u & >> v4 8 255
            = . ks 18 # u & >> v4 16 255
            = . ks 19 # u & >> v4 24 255
            : i v5 # i x5
            = . ks 20 # u & v5 255
            = . ks 21 # u & >> v5 8 255
            = . ks 22 # u & >> v5 16 255
            = . ks 23 # u & >> v5 24 255
            : i v6 # i x6
            = . ks 24 # u & v6 255
            = . ks 25 # u & >> v6 8 255
            = . ks 26 # u & >> v6 16 255
            = . ks 27 # u & >> v6 24 255
            : i v7 # i x7
            = . ks 28 # u & v7 255
            = . ks 29 # u & >> v7 8 255
            = . ks 30 # u & >> v7 16 255
            = . ks 31 # u & >> v7 24 255
            : i v8 # i x8
            = . ks 32 # u & v8 255
            = . ks 33 # u & >> v8 8 255
            = . ks 34 # u & >> v8 16 255
            = . ks 35 # u & >> v8 24 255
            : i v9 # i x9
            = . ks 36 # u & v9 255
            = . ks 37 # u & >> v9 8 255
            = . ks 38 # u & >> v9 16 255
            = . ks 39 # u & >> v9 24 255
            : i v10 # i x10
            = . ks 40 # u & v10 255
            = . ks 41 # u & >> v10 8 255
            = . ks 42 # u & >> v10 16 255
            = . ks 43 # u & >> v10 24 255
            : i v11 # i x11
            = . ks 44 # u & v11 255
            = . ks 45 # u & >> v11 8 255
            = . ks 46 # u & >> v11 16 255
            = . ks 47 # u & >> v11 24 255
            : i v12 # i x12
            = . ks 48 # u & v12 255
            = . ks 49 # u & >> v12 8 255
            = . ks 50 # u & >> v12 16 255
            = . ks 51 # u & >> v12 24 255
            : i v13 # i x13
            = . ks 52 # u & v13 255
            = . ks 53 # u & >> v13 8 255
            = . ks 54 # u & >> v13 16 255
            = . ks 55 # u & >> v13 24 255
            : i v14 # i x14
            = . ks 56 # u & v14 255
            = . ks 57 # u & >> v14 8 255
            = . ks 58 # u & >> v14 16 255
            = . ks 59 # u & >> v14 24 255
            : i v15 # i x15
            = . ks 60 # u & v15 255
            = . ks 61 # u & >> v15 8 255
            = . ks 62 # u & >> v15 16 255
            = . ks 63 # u & >> v15 24 255
            : ~ i j 0
            ~ < + off j n {
                = . op + off j # u ^^ # i . dp + off j # i . ks j
                = j + j 1
            }
        } {}
        = off + off 64
        = ctr + ctr 1
    }
    ( nurl_free # s ks )
    ^ out
}

// ── Poly1305 (poly1305-donna, radix 2^44) ─────────────────────────
// The accumulator is THREE 44/44/42-bit limbs, not five 26-bit ones.
// The wider radix is what `nurl_umulhi` (64×64→128) buys: each h·r term
// is a full 128-bit product instead of one kept artificially under 2^63,
// so the schoolbook is 9 multiplies a block against the 25 the 26-bit
// form needed — and this MAC runs over every byte of every TLS record,
// both directions. (Floodyberry's poly1305-donna-64, the reference every
// fast Poly1305 descends from.)

// Little-endian 64-bit load of the 8 bytes at `mp[off .. off+7]`, built
// from bytes so it is correct on any target and needs no alignment. The
// full-block path calls it at 8-aligned offsets, but the two `<< 32`
// halves keep it valid off-alignment too.
@ __ld64 * u mp i off → i {
    : i lo | | | # i . mp off << # i . mp + off 1 8 << # i . mp + off 2 16 << # i . mp + off 3 24
    : i hi | | | # i . mp + off 4 << # i . mp + off 5 8 << # i . mp + off 6 16 << # i . mp + off 7 24
    ^ | lo << hi 32
}

// otk = 32-byte one-time key (r || s). Returns the 16-byte tag.
//
// h and r are held as three unsigned limbs at radix 2^44 (h2/r2 are the
// 42-bit top). Each h·r term is a full 64×64→128 product, accumulated as
// an explicit (lo, hi) pair — NURL's `*` gives the low half, nurl_umulhi
// the high — because the sum of three such products overflows 64 bits and
// the reduction needs the bits above 2^44 that a truncating multiply drops.
@ poly1305_mac ( Vec u ) otk ( Vec u ) msg → ( Vec u ) {
    : *u kp ( vec_data [u] otk )
    // Clamp r (otk[0..15]) into three 44-bit limbs. These are RFC 8439's
    // clamp mask re-expressed for the 44/44/42 split (poly1305-donna-64).
    : u64 kt0 # u64 ( __ld64 kp 0 )
    : u64 kt1 # u64 ( __ld64 kp 8 )
    : u64 r0 & kt0 0xffc0fffffff
    : u64 r1 & | >> kt0 44 << kt1 20 0xfffffc0ffff
    : u64 r2 & >> kt1 24 0x00ffffffc0f
    : u64 s1 * r1 20  // 5·r1·4 → the 2^130-5 wrap fold (5<<2)
    : u64 s2 * r2 20

    : ~ u64 h0 0
    : ~ u64 h1 0
    : ~ u64 h2 0

    : i mlen ( vec_len [u] msg )
    : *u mp ( vec_data [u] msg )
    : ~ i off 0
    ~ < off mlen {
        : i rem - mlen off
        : ~ u64 t0 0
        : ~ u64 t1 0
        : ~ u64 hibit 0x10000000000  // 1<<40: the 2^128 block marker in h2
        ? >= rem 16 {
            = t0 # u64 ( __ld64 mp off )
            = t1 # u64 ( __ld64 mp + off 8 )
        } {
            // Tail: gather the remaining bytes into a 16-byte zero buffer,
            // set the 0x01 marker byte after them, and clear `hibit` — the
            // marker now rides inside t0/t1 at its natural position.
            : i blk rem
            : *u bb # *u ( nurl_zalloc 16 )
            : ~ i j 0
            ~ < j blk { = . bb j . mp + off j = j + j 1 }
            = . bb blk # u 1
            = t0 # u64 ( __ld64 bb 0 )
            = t1 # u64 ( __ld64 bb 8 )
            = hibit 0
            ( nurl_free # s bb )
        }
        // h += m (three 44/44/42-bit limbs plus the block-marker bit).
        = h0 + h0 & t0 0xfffffffffff
        = h1 + h1 & | >> t0 44 << t1 20 0xfffffffffff
        = h2 + + h2 & >> t1 24 0x3ffffffffff hibit

        // d0 = h0·r0 + h1·s2 + h2·s1, as a 128-bit (lo,hi) accumulator.
        : ~ u64 d0lo * h0 r0
        : ~ u64 d0hi ( nurl_umulhi h0 r0 )
        : u64 pa * h1 s2
        = d0lo + d0lo pa
        = d0hi + + d0hi ( nurl_umulhi h1 s2 ) ? < d0lo pa 1 0
        : u64 pb * h2 s1
        = d0lo + d0lo pb
        = d0hi + + d0hi ( nurl_umulhi h2 s1 ) ? < d0lo pb 1 0
        // d1 = h0·r1 + h1·r0 + h2·s2
        : ~ u64 d1lo * h0 r1
        : ~ u64 d1hi ( nurl_umulhi h0 r1 )
        : u64 pc * h1 r0
        = d1lo + d1lo pc
        = d1hi + + d1hi ( nurl_umulhi h1 r0 ) ? < d1lo pc 1 0
        : u64 pd * h2 s2
        = d1lo + d1lo pd
        = d1hi + + d1hi ( nurl_umulhi h2 s2 ) ? < d1lo pd 1 0
        // d2 = h0·r2 + h1·r1 + h2·r0
        : ~ u64 d2lo * h0 r2
        : ~ u64 d2hi ( nurl_umulhi h0 r2 )
        : u64 pe * h1 r1
        = d2lo + d2lo pe
        = d2hi + + d2hi ( nurl_umulhi h1 r1 ) ? < d2lo pe 1 0
        : u64 pf * h2 r0
        = d2lo + d2lo pf
        = d2hi + + d2hi ( nurl_umulhi h2 r0 ) ? < d2lo pf 1 0

        // Partial reduction: carry each di>>44 (di>>42 for d2) up a limb.
        : ~ u64 c | << d0hi 20 >> d0lo 44
        = h0 & d0lo 0xfffffffffff
        = d1lo + d1lo c
        = d1hi + d1hi ? < d1lo c 1 0
        = c | << d1hi 20 >> d1lo 44
        = h1 & d1lo 0xfffffffffff
        = d2lo + d2lo c
        = d2hi + d2hi ? < d2lo c 1 0
        = c | << d2hi 22 >> d2lo 42
        = h2 & d2lo 0x3ffffffffff
        = h0 + h0 * c 5
        = c >> h0 44
        = h0 & h0 0xfffffffffff
        = h1 + h1 c

        = off + off 16
    }

    // Fully carry h.
    : ~ u64 c >> h1 44
    = h1 & h1 0xfffffffffff
    = h2 + h2 c
    = c >> h2 42
    = h2 & h2 0x3ffffffffff
    = h0 + h0 * c 5
    = c >> h0 44
    = h0 & h0 0xfffffffffff
    = h1 + h1 c

    // Compute h + -p and select h if h < p (constant-time).
    : ~ u64 g0 + h0 5
    : ~ u64 cc >> g0 44
    = g0 & g0 0xfffffffffff
    : ~ u64 g1 + h1 cc
    = cc >> g1 44
    = g1 & g1 0xfffffffffff
    : ~ u64 g2 - + h2 cc 0x40000000000  // − (1<<42)

    // g2's top bit is set exactly when it borrowed (h < p): mask 0 keeps h,
    // otherwise all-ones takes g. `>> g2 63` is a logical shift (u64).
    : u64 mask - >> g2 63 1
    = g0 & g0 mask
    = g1 & g1 mask
    = g2 & g2 mask
    : u64 imask ^^ mask -1
    = h0 | & h0 imask g0
    = h1 | & h1 imask g1
    = h2 | & h2 imask g2

    // tag = (h + s) mod 2^128: repack the three limbs into two 64-bit
    // words at the 44-bit boundary, add the pad s = otk[16..32] with carry.
    : u64 st0 # u64 ( __ld64 kp 16 )
    : u64 st1 # u64 ( __ld64 kp 24 )
    : ~ u64 f0 | h0 << h1 44
    : ~ u64 f1 | >> h1 20 << h2 24
    = f0 + f0 st0
    = f1 + + f1 st1 ? < f0 st0 1 0
    : ( Vec u ) tag ( vec_with_cap [u] 16 )
    ( __push_le32 tag # i & f0 4294967295 )
    ( __push_le32 tag # i & >> f0 32 4294967295 )
    ( __push_le32 tag # i & f1 4294967295 )
    ( __push_le32 tag # i & >> f1 32 4294967295 )
    ^ tag
}

// ── ChaCha20-Poly1305 AEAD (RFC 8439 §2.8) ────────────────────────
// The one-time Poly1305 key: first 32 bytes of the counter-0 block.
@ __poly_key ( Vec u ) key ( Vec u ) nonce → ( Vec u ) {
    // Only the first half of the counter-0 block is the key, so ask the
    // kernel for 32 bytes and skip both the second half and the copy out
    // of it. One of these per AEAD record.
    : ( Vec u ) z ( __zeros 32 )
    : ( Vec u ) otk ( chacha20_xor_range key 0 nonce z 0 32 )
    ( vec_free [u] z )
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

// Build the Poly1305 input: aad ‖ pad16 ‖ ct ‖ pad16 ‖ le64(|aad|) ‖ le64(|ct|),
// where the ciphertext is the `cl` bytes of `ct` at `coff` — decrypt hands
// in the record buffer with the tag still on the end rather than a copy.
@ __mac_data ( Vec u ) aad ( Vec u ) ct i coff i cl → ( Vec u ) {
    : i al ( vec_len [u] aad )
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
    : *u cp # *u + # i ( vec_data [u] ct ) coff
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
    : ( Vec u ) md ( __mac_data aad ct 0 ( vec_len [u] ct ) )
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
    // The ciphertext is `ct_and_tag` minus its trailing tag — both the MAC
    // and the keystream take it as a range, so nothing is copied out of
    // the record to name it. Extracting it used to cost a bounds-checked
    // `vec_get` + `vec_push` PER BYTE of every 16 KB record, a quarter of
    // the whole receive path.
    : ( Vec u ) otk ( __poly_key key nonce )
    : ( Vec u ) md ( __mac_data aad ct_and_tag 0 ctlen )
    : ( Vec u ) tag ( poly1305_mac otk md )
    : b ok ( __tag_ok ct_and_tag ctlen tag )
    ( vec_free [u] otk )
    ( vec_free [u] md )
    ( vec_free [u] tag )
    ? ! ok { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : ( Vec u ) pt ( chacha20_xor_range key 1 nonce ct_and_tag 0 ctlen )
    ^ @ ?( Vec u ) { T pt }
}
