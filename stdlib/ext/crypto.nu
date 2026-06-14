// stdlib/ext/crypto.nu — AEAD ciphers, signatures, key exchange, KDFs.
//
// Binds libcrypto's EVP layer the same way sqlite.nu binds libsqlite3:
// pure NURL `& `openssl` @ …` declarations, no C bridge. The `openssl`
// library token routes the build-time sentinel check to
// stdlib/runtime.openssl (created by build.sh when libssl-dev is
// installed), so a missing dev package fails at compile time with an
// install hint instead of at link time. Hashing (SHA-2, BLAKE3, HMAC)
// stays pure NURL in std/hash*.nu — this module covers what genuinely
// needs vetted cipher implementations: AEAD encryption, Ed25519/X25519,
// and password/key derivation.
//
// AEAD (key 32 B; nonce 12 B; returns ciphertext with the 16-byte tag
// APPENDED — split or feed back whole, decrypt expects ct||tag):
//   ( aes256gcm_encrypt  ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt )
//       → !( Vec u ) CryptoErr
//   ( aes256gcm_decrypt  key nonce aad ct_and_tag ) → !( Vec u ) CryptoErr
//   ( chacha20poly1305_encrypt … ) / ( chacha20poly1305_decrypt … )  same shape
//   Decrypt returns CryptoVerify when the tag does not authenticate —
//   key/nonce/aad/ciphertext mismatch are indistinguishable by design.
//   NONCE DISCIPLINE: never reuse a (key, nonce) pair. Use a counter or
//   ( rand_fill_vec 12 ) per message; GCM with a repeated nonce forfeits
//   both confidentiality and integrity.
//
// Signatures & key exchange (raw byte keys, no PEM/DER here):
//   ( ed25519_keygen )                        → !CryptoKeypair CryptoErr
//   ( ed25519_pubkey ( Vec u ) sk )           → !( Vec u ) CryptoErr   32 B
//   ( ed25519_sign   ( Vec u ) sk ( Vec u ) msg ) → !( Vec u ) CryptoErr  64 B
//   ( ed25519_verify ( Vec u ) pk ( Vec u ) msg ( Vec u ) sig ) → b
//   ( x25519_keygen )                         → !CryptoKeypair CryptoErr
//   ( x25519_derive  ( Vec u ) sk ( Vec u ) peer_pk ) → !( Vec u ) CryptoErr  32 B
//   X25519's shared secret is NOT uniformly random — always pass it
//   through hkdf_sha256 before using it as a key.
//
// Key derivation:
//   ( pbkdf2_sha256 s pass ( Vec u ) salt i iters i keylen ) → !( Vec u ) CryptoErr
//   ( pbkdf2_sha512 s pass ( Vec u ) salt i iters i keylen ) → !( Vec u ) CryptoErr
//   ( hkdf_sha256   ( Vec u ) ikm ( Vec u ) salt ( Vec u ) info i keylen )
//       → !( Vec u ) CryptoErr
//   ( scrypt_kdf    s pass ( Vec u ) salt i n i r i p i keylen )
//       → !( Vec u ) CryptoErr        (n must be a power of two; the
//       interactive-login baseline is n=16384 r=8 p=1)
//   PBKDF2/scrypt are for passwords (slow on purpose); HKDF is for
//   stretching already-strong keys (X25519 output, session secrets).
//
// Errors: CryptoArg (bad length/parameter, caught before any FFI),
// CryptoInit (context/key setup failed), CryptoOp (cipher/derive step
// failed), CryptoVerify (AEAD tag rejected). Compare derived MACs/keys
// with constant_time_eq_vec (std/subtle.nu), never vec-wise ==.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | CryptoErr { CryptoArg CryptoInit CryptoOp CryptoVerify }

// Raw keypair: secret + public, 32 bytes each for both Ed25519 (seed)
// and X25519.
: CryptoKeypair { ( Vec u ) sk ( Vec u ) pk }

// ── libcrypto FFI ───────────────────────────────────────────────────
//
// Opaque pointers (EVP_CIPHER_CTX*, EVP_PKEY*, EVP_MD*, …) travel as
// `s`. Out-parameters (int*/size_t*) are 8-byte nurl_zalloc'd slots
// read back via nurl_peek — libcrypto writes 4 bytes into int* slots,
// the zeroed high half keeps the i64 read exact on little-endian.

& `openssl` @ EVP_CIPHER_CTX_new → s
& `openssl` @ EVP_CIPHER_CTX_free s ctx → v
& `openssl` @ EVP_CIPHER_CTX_ctrl s ctx i cmd i arg *u ptr → i
& `openssl` @ EVP_aes_256_gcm → s
& `openssl` @ EVP_chacha20_poly1305 → s
& `openssl` @ EVP_EncryptInit_ex s ctx s cipher *u engine s key s iv → i
& `openssl` @ EVP_EncryptUpdate s ctx s out *u outl s in i inl → i
& `openssl` @ EVP_EncryptFinal_ex s ctx s out *u outl → i
& `openssl` @ EVP_DecryptInit_ex s ctx s cipher *u engine s key s iv → i
& `openssl` @ EVP_DecryptUpdate s ctx s out *u outl s in i inl → i
& `openssl` @ EVP_DecryptFinal_ex s ctx s out *u outl → i

& `openssl` @ EVP_PKEY_new_raw_private_key i type *u engine s key i keylen → s
& `openssl` @ EVP_PKEY_new_raw_public_key i type *u engine s key i keylen → s
& `openssl` @ EVP_PKEY_get_raw_private_key s pkey s out *u outlen → i
& `openssl` @ EVP_PKEY_get_raw_public_key s pkey s out *u outlen → i
& `openssl` @ EVP_PKEY_free s pkey → v
& `openssl` @ EVP_PKEY_CTX_new s pkey *u engine → s
& `openssl` @ EVP_PKEY_CTX_new_id i id *u engine → s
& `openssl` @ EVP_PKEY_CTX_free s ctx → v
& `openssl` @ EVP_PKEY_CTX_ctrl_str s ctx s type s value → i
& `openssl` @ EVP_PKEY_keygen_init s ctx → i
& `openssl` @ EVP_PKEY_keygen s ctx *u out_pkey → i
& `openssl` @ EVP_PKEY_derive_init s ctx → i
& `openssl` @ EVP_PKEY_derive_set_peer s ctx s peer → i
& `openssl` @ EVP_PKEY_derive s ctx s out *u outlen → i

& `openssl` @ EVP_MD_CTX_new → s
& `openssl` @ EVP_MD_CTX_free s ctx → v
& `openssl` @ EVP_DigestSignInit s ctx *u pctx *u md *u engine s pkey → i
& `openssl` @ EVP_DigestSign s ctx s sig *u siglen s msg i msglen → i
& `openssl` @ EVP_DigestVerifyInit s ctx *u pctx *u md *u engine s pkey → i
& `openssl` @ EVP_DigestVerify s ctx s sig i siglen s msg i msglen → i

& `openssl` @ EVP_sha256 → s
& `openssl` @ EVP_sha512 → s
& `openssl` @ PKCS5_PBKDF2_HMAC s pass i passlen s salt i saltlen i iter s md i keylen s out → i
& `openssl` @ EVP_PBE_scrypt s pass i passlen s salt i saltlen i n i r i p i maxmem s out i keylen → i

// EVP_CIPHER_CTX_ctrl commands (stable ABI constants since 1.0; the
// AEAD aliases EVP_CTRL_AEAD_* equal the GCM originals).
: i __EVP_CTRL_AEAD_SET_IVLEN 0x9
: i __EVP_CTRL_AEAD_GET_TAG 0x10
: i __EVP_CTRL_AEAD_SET_TAG 0x11
// EVP_PKEY id NIDs (stable libcrypto object ids).
: i __NID_X25519 1034
: i __NID_ED25519 1087
: i __NID_HKDF 1036

: i __AEAD_KEYLEN 32
: i __AEAD_NONCELEN 12
: i __AEAD_TAGLEN 16

// ── Internal helpers ───────────────────────────────────────────────

// Hex of a Vec[u] for EVP_PKEY_CTX_ctrl_str's hex* controls. encode.nu's
// hex_encode walks a NUL-terminated `s` and would truncate binary
// material at the first zero byte; this walks the explicit length.
@ __hex_of_vec ( Vec u ) v → String {
    : i n ( vec_len [u] v )
    : String out ( string_with_cap + * n 2 1 )
    : *u p ( vec_data [u] v )
    : ~ i k 0
    ~ < k n {
        // `. p k` is the indexed byte load. nurl_str_get must NOT be
        // used here: it is a NUL-bounded C-string read, so binary
        // material with an embedded (or leading) 0x00 byte would read
        // as zero past that point — exactly the bug that made HKDF
        // ignore an all-low-byte salt.
        : i b # i . p k
        : i hi / b 16
        : i lo % b 16
        ( string_push_char out ? < hi 10 + 48 hi + 87 hi )
        ( string_push_char out ? < lo 10 + 48 lo + 87 lo )
        = k + k 1
    }
    ^ out
}

// Owned Vec[u] of the first n bytes at p.
@ __vec_of_bytes s p i n → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] ? > n 0 n 1 )
    ( nurl_memcpy ( vec_data [u] out ) # *u p n )
    : b _ok ( vec_set_len [u] out n )
    ^ out
}

// ── AEAD ───────────────────────────────────────────────────────────

// Shared one-shot AEAD encrypt: ct||tag on success. `cipher` is the
// EVP_CIPHER* from EVP_aes_256_gcm / EVP_chacha20_poly1305 — both use
// 32-byte keys, 12-byte nonces, 16-byte tags.
@ __aead_encrypt s cipher ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → !( Vec u ) CryptoErr {
    ? != ( vec_len [u] key ) __AEAD_KEYLEN { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ? != ( vec_len [u] nonce ) __AEAD_NONCELEN { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : s ctx ( EVP_CIPHER_CTX_new )
    ? == # i ctx 0 { ^ @ !( Vec u ) CryptoErr { F CryptoInit } } {}
    : s lenbuf ( nurl_zalloc 8 )
    : ~ i ok 1
    // Init cipher first (key/iv NULL), set the 12-byte IV length, then
    // load key + nonce — the canonical EVP AEAD call order.
    ? == ( EVP_EncryptInit_ex ctx cipher # *u 0 # s 0 # s 0 ) 1 {} { = ok 0 }
    ? & == ok 1 != ( EVP_CIPHER_CTX_ctrl ctx __EVP_CTRL_AEAD_SET_IVLEN __AEAD_NONCELEN # *u 0 ) 1 { = ok 0 } {}
    ? & == ok 1 != ( EVP_EncryptInit_ex ctx # s 0 # *u 0 # s ( vec_data [u] key ) # s ( vec_data [u] nonce ) ) 1 { = ok 0 } {}
    // AAD pass: out = NULL.
    : i aadn ( vec_len [u] aad )
    ? & == ok 1 > aadn 0 {
        ? == ( EVP_EncryptUpdate ctx # s 0 # *u lenbuf # s ( vec_data [u] aad ) aadn ) 1 {} { = ok 0 }
    } {}
    : i ptn ( vec_len [u] pt )
    : ( Vec u ) out ( vec_with_cap [u] + ptn __AEAD_TAGLEN )
    : ~ i written 0
    ? & == ok 1 > ptn 0 {
        ? == ( EVP_EncryptUpdate ctx # s ( vec_data [u] out ) # *u lenbuf # s ( vec_data [u] pt ) ptn ) 1
        { = written ( nurl_peek # s lenbuf 0 ) }
        { = ok 0 }
    } {}
    ? == ok 1 {
        ? == ( EVP_EncryptFinal_ex ctx # s + # i ( vec_data [u] out ) written # *u lenbuf ) 1
        { = written + written ( nurl_peek # s lenbuf 0 ) }
        { = ok 0 }
    } {}
    ? == ok 1 {
        ? == ( EVP_CIPHER_CTX_ctrl ctx __EVP_CTRL_AEAD_GET_TAG __AEAD_TAGLEN # *u + # i ( vec_data [u] out ) written ) 1
        { = written + written __AEAD_TAGLEN }
        { = ok 0 }
    } {}
    ( nurl_free # s lenbuf )
    ( EVP_CIPHER_CTX_free ctx )
    ? == ok 1 {
        : b _ok ( vec_set_len [u] out written )
        ^ @ !( Vec u ) CryptoErr { T out }
    } {
        ( vec_free [u] out )
        ^ @ !( Vec u ) CryptoErr { F CryptoOp }
    }
}

// Shared one-shot AEAD decrypt of ct||tag. Tag rejection (the ONLY
// authentication signal) surfaces as CryptoVerify.
@ __aead_decrypt s cipher ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_and_tag → !( Vec u ) CryptoErr {
    ? != ( vec_len [u] key ) __AEAD_KEYLEN { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ? != ( vec_len [u] nonce ) __AEAD_NONCELEN { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : i total ( vec_len [u] ct_and_tag )
    ? < total __AEAD_TAGLEN { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : i ctn - total __AEAD_TAGLEN
    : s ctx ( EVP_CIPHER_CTX_new )
    ? == # i ctx 0 { ^ @ !( Vec u ) CryptoErr { F CryptoInit } } {}
    : s lenbuf ( nurl_zalloc 8 )
    : ~ i ok 1
    ? == ( EVP_DecryptInit_ex ctx cipher # *u 0 # s 0 # s 0 ) 1 {} { = ok 0 }
    ? & == ok 1 != ( EVP_CIPHER_CTX_ctrl ctx __EVP_CTRL_AEAD_SET_IVLEN __AEAD_NONCELEN # *u 0 ) 1 { = ok 0 } {}
    ? & == ok 1 != ( EVP_DecryptInit_ex ctx # s 0 # *u 0 # s ( vec_data [u] key ) # s ( vec_data [u] nonce ) ) 1 { = ok 0 } {}
    : i aadn ( vec_len [u] aad )
    ? & == ok 1 > aadn 0 {
        ? == ( EVP_DecryptUpdate ctx # s 0 # *u lenbuf # s ( vec_data [u] aad ) aadn ) 1 {} { = ok 0 }
    } {}
    : ( Vec u ) out ( vec_with_cap [u] ? > ctn 0 ctn 1 )
    : ~ i written 0
    ? & == ok 1 > ctn 0 {
        ? == ( EVP_DecryptUpdate ctx # s ( vec_data [u] out ) # *u lenbuf # s ( vec_data [u] ct_and_tag ) ctn ) 1
        { = written ( nurl_peek # s lenbuf 0 ) }
        { = ok 0 }
    } {}
    // Hand the trailing 16 bytes to the cipher as the expected tag,
    // then Final performs the authenticated check.
    : ~ i verified 0
    ? == ok 1 {
        ? == ( EVP_CIPHER_CTX_ctrl ctx __EVP_CTRL_AEAD_SET_TAG __AEAD_TAGLEN # *u + # i ( vec_data [u] ct_and_tag ) ctn ) 1 {} { = ok 0 }
    } {}
    ? == ok 1 {
        ? == ( EVP_DecryptFinal_ex ctx # s + # i ( vec_data [u] out ) written # *u lenbuf ) 1
        { = verified 1 = written + written ( nurl_peek # s lenbuf 0 ) }
        {}
    } {}
    ( nurl_free # s lenbuf )
    ( EVP_CIPHER_CTX_free ctx )
    ? == verified 1 {
        : b _ok ( vec_set_len [u] out written )
        ^ @ !( Vec u ) CryptoErr { T out }
    } {
        ( vec_free [u] out )
        ^ @ !( Vec u ) CryptoErr { F ? == ok 1 CryptoVerify CryptoOp }
    }
}

@ aes256gcm_encrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → !( Vec u ) CryptoErr {
    ^ ( __aead_encrypt ( EVP_aes_256_gcm ) key nonce aad pt )
}

@ aes256gcm_decrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_and_tag → !( Vec u ) CryptoErr {
    ^ ( __aead_decrypt ( EVP_aes_256_gcm ) key nonce aad ct_and_tag )
}

@ chacha20poly1305_encrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → !( Vec u ) CryptoErr {
    ^ ( __aead_encrypt ( EVP_chacha20_poly1305 ) key nonce aad pt )
}

@ chacha20poly1305_decrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_and_tag → !( Vec u ) CryptoErr {
    ^ ( __aead_decrypt ( EVP_chacha20_poly1305 ) key nonce aad ct_and_tag )
}

// ── Ed25519 / X25519 ───────────────────────────────────────────────

// Extract 32-byte raw secret + public keys out of a freshly generated
// EVP_PKEY. Frees the pkey.
@ __keypair_of_pkey s pkey → !CryptoKeypair CryptoErr {
    : s skbuf ( nurl_zalloc 32 )
    : s pkbuf ( nurl_zalloc 32 )
    : s lenbuf ( nurl_zalloc 8 )
    ( nurl_poke lenbuf 0 32 )
    : ~ i ok ( EVP_PKEY_get_raw_private_key pkey skbuf # *u lenbuf )
    ( nurl_poke lenbuf 0 32 )
    ? == ok 1 { = ok ( EVP_PKEY_get_raw_public_key pkey pkbuf # *u lenbuf ) } {}
    ( EVP_PKEY_free pkey )
    ( nurl_free # s lenbuf )
    ? == ok 1 {
        : ( Vec u ) sk ( __vec_of_bytes skbuf 32 )
        : ( Vec u ) pk ( __vec_of_bytes pkbuf 32 )
        ( nurl_free skbuf )
        ( nurl_free pkbuf )
        ^ @ !CryptoKeypair CryptoErr { T @ CryptoKeypair { sk pk } }
    } {
        ( nurl_free skbuf )
        ( nurl_free pkbuf )
        ^ @ !CryptoKeypair CryptoErr { F CryptoOp }
    }
}

// Generate a keypair for a raw-key NID (Ed25519 / X25519).
@ __raw_keygen i nid → !CryptoKeypair CryptoErr {
    : s pctx ( EVP_PKEY_CTX_new_id nid # *u 0 )
    ? == # i pctx 0 { ^ @ !CryptoKeypair CryptoErr { F CryptoInit } } {}
    : ~ i ok ( EVP_PKEY_keygen_init pctx )
    : s outbuf ( nurl_zalloc 8 )
    ? == ok 1 { = ok ( EVP_PKEY_keygen pctx # *u outbuf ) } {}
    : s pkey # s ( nurl_peek outbuf 0 )
    ( nurl_free # s outbuf )
    ( EVP_PKEY_CTX_free pctx )
    ? & == ok 1 != # i pkey 0 { ^ ( __keypair_of_pkey pkey ) }
    { ^ @ !CryptoKeypair CryptoErr { F CryptoOp } }
}

@ ed25519_keygen → !CryptoKeypair CryptoErr {
    ^ ( __raw_keygen __NID_ED25519 )
}

@ x25519_keygen → !CryptoKeypair CryptoErr {
    ^ ( __raw_keygen __NID_X25519 )
}

// Public key for a 32-byte secret key (works for both NIDs — kept
// per-algorithm in the API so call sites stay self-documenting).
@ __raw_pubkey i nid ( Vec u ) sk → !( Vec u ) CryptoErr {
    ? != ( vec_len [u] sk ) 32 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : s pkey ( EVP_PKEY_new_raw_private_key nid # *u 0 # s ( vec_data [u] sk ) 32 )
    ? == # i pkey 0 { ^ @ !( Vec u ) CryptoErr { F CryptoInit } } {}
    : s pkbuf ( nurl_zalloc 32 )
    : s lenbuf ( nurl_zalloc 8 )
    ( nurl_poke lenbuf 0 32 )
    : i ok ( EVP_PKEY_get_raw_public_key pkey pkbuf # *u lenbuf )
    ( EVP_PKEY_free pkey )
    ( nurl_free # s lenbuf )
    ? == ok 1 {
        : ( Vec u ) pk ( __vec_of_bytes pkbuf 32 )
        ( nurl_free pkbuf )
        ^ @ !( Vec u ) CryptoErr { T pk }
    } {
        ( nurl_free pkbuf )
        ^ @ !( Vec u ) CryptoErr { F CryptoOp }
    }
}

@ ed25519_pubkey ( Vec u ) sk → !( Vec u ) CryptoErr {
    ^ ( __raw_pubkey __NID_ED25519 sk )
}

@ x25519_pubkey ( Vec u ) sk → !( Vec u ) CryptoErr {
    ^ ( __raw_pubkey __NID_X25519 sk )
}

// Detached Ed25519 signature (64 bytes) over msg with a 32-byte secret
// key. Ed25519 is "pure": the message itself is signed, no pre-hash —
// EVP_DigestSign with a NULL md is the correct call shape.
@ ed25519_sign ( Vec u ) sk ( Vec u ) msg → !( Vec u ) CryptoErr {
    ? != ( vec_len [u] sk ) 32 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : s pkey ( EVP_PKEY_new_raw_private_key __NID_ED25519 # *u 0 # s ( vec_data [u] sk ) 32 )
    ? == # i pkey 0 { ^ @ !( Vec u ) CryptoErr { F CryptoInit } } {}
    : s mdctx ( EVP_MD_CTX_new )
    : s sigbuf ( nurl_zalloc 64 )
    : s lenbuf ( nurl_zalloc 8 )
    ( nurl_poke lenbuf 0 64 )
    : ~ i ok ( EVP_DigestSignInit mdctx # *u 0 # *u 0 # *u 0 pkey )
    ? == ok 1 {
        = ok ( EVP_DigestSign mdctx sigbuf # *u lenbuf # s ( vec_data [u] msg ) ( vec_len [u] msg ) )
    } {}
    ( EVP_MD_CTX_free mdctx )
    ( EVP_PKEY_free pkey )
    ( nurl_free # s lenbuf )
    ? == ok 1 {
        : ( Vec u ) sig ( __vec_of_bytes sigbuf 64 )
        ( nurl_free sigbuf )
        ^ @ !( Vec u ) CryptoErr { T sig }
    } {
        ( nurl_free sigbuf )
        ^ @ !( Vec u ) CryptoErr { F CryptoOp }
    }
}

// True iff sig (64 B) is a valid Ed25519 signature over msg under pk
// (32 B). Malformed inputs simply verify false — a boolean is the
// whole contract here, no error channel to confuse with "invalid".
@ ed25519_verify ( Vec u ) pk ( Vec u ) msg ( Vec u ) sig → b {
    ? != ( vec_len [u] pk ) 32 { ^ F } {}
    ? != ( vec_len [u] sig ) 64 { ^ F } {}
    : s pkey ( EVP_PKEY_new_raw_public_key __NID_ED25519 # *u 0 # s ( vec_data [u] pk ) 32 )
    ? == # i pkey 0 { ^ F } {}
    : s mdctx ( EVP_MD_CTX_new )
    : ~ i ok ( EVP_DigestVerifyInit mdctx # *u 0 # *u 0 # *u 0 pkey )
    ? == ok 1 {
        = ok ( EVP_DigestVerify mdctx # s ( vec_data [u] sig ) 64 # s ( vec_data [u] msg ) ( vec_len [u] msg ) )
    } {}
    ( EVP_MD_CTX_free mdctx )
    ( EVP_PKEY_free pkey )
    ^ == ok 1
}

// X25519 ECDH: 32-byte shared secret from our secret key + peer's
// public key. Pass the result through hkdf_sha256 before keying a
// cipher — the raw output is a curve point coordinate, not a
// uniformly random key.
@ x25519_derive ( Vec u ) sk ( Vec u ) peer_pk → !( Vec u ) CryptoErr {
    ? != ( vec_len [u] sk ) 32 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ? != ( vec_len [u] peer_pk ) 32 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : s pkey ( EVP_PKEY_new_raw_private_key __NID_X25519 # *u 0 # s ( vec_data [u] sk ) 32 )
    ? == # i pkey 0 { ^ @ !( Vec u ) CryptoErr { F CryptoInit } } {}
    : s peer ( EVP_PKEY_new_raw_public_key __NID_X25519 # *u 0 # s ( vec_data [u] peer_pk ) 32 )
    ? == # i peer 0 {
        ( EVP_PKEY_free pkey )
        ^ @ !( Vec u ) CryptoErr { F CryptoInit }
    } {}
    : s pctx ( EVP_PKEY_CTX_new pkey # *u 0 )
    : ~ i ok ? == # i pctx 0 0 1
    ? == ok 1 { = ok ( EVP_PKEY_derive_init pctx ) } {}
    ? == ok 1 { = ok ( EVP_PKEY_derive_set_peer pctx peer ) } {}
    : s outbuf ( nurl_zalloc 32 )
    : s lenbuf ( nurl_zalloc 8 )
    ( nurl_poke lenbuf 0 32 )
    ? == ok 1 { = ok ( EVP_PKEY_derive pctx outbuf # *u lenbuf ) } {}
    ? != # i pctx 0 { ( EVP_PKEY_CTX_free pctx ) } {}
    ( EVP_PKEY_free peer )
    ( EVP_PKEY_free pkey )
    ( nurl_free # s lenbuf )
    ? == ok 1 {
        : ( Vec u ) secret ( __vec_of_bytes outbuf 32 )
        ( nurl_free outbuf )
        ^ @ !( Vec u ) CryptoErr { T secret }
    } {
        ( nurl_free outbuf )
        ^ @ !( Vec u ) CryptoErr { F CryptoOp }
    }
}

// ── Key derivation ─────────────────────────────────────────────────

@ __pbkdf2 s pass ( Vec u ) salt i iters i keylen s md → !( Vec u ) CryptoErr {
    ? | <= iters 0 <= keylen 0 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : ( Vec u ) out ( vec_with_cap [u] keylen )
    : i ok ( PKCS5_PBKDF2_HMAC pass ( nurl_str_len pass )
    # s ( vec_data [u] salt ) ( vec_len [u] salt )
    iters md keylen # s ( vec_data [u] out ) )
    ? == ok 1 {
        : b _ok ( vec_set_len [u] out keylen )
        ^ @ !( Vec u ) CryptoErr { T out }
    } {
        ( vec_free [u] out )
        ^ @ !( Vec u ) CryptoErr { F CryptoOp }
    }
}

@ pbkdf2_sha256 s pass ( Vec u ) salt i iters i keylen → !( Vec u ) CryptoErr {
    ^ ( __pbkdf2 pass salt iters keylen ( EVP_sha256 ) )
}

@ pbkdf2_sha512 s pass ( Vec u ) salt i iters i keylen → !( Vec u ) CryptoErr {
    ^ ( __pbkdf2 pass salt iters keylen ( EVP_sha512 ) )
}

// HKDF-SHA256 (RFC 5869, extract-and-expand). Parameters go in via
// EVP_PKEY_CTX_ctrl_str's hex* controls — real exported functions with
// a stable contract across OpenSSL 1.1/3.x, unlike the raw ctrl-macro
// constants, and hex transport keeps binary salt/ikm/info NUL-safe.
// Empty salt = RFC's "zero-length salt" path; empty info is valid.
@ hkdf_sha256 ( Vec u ) ikm ( Vec u ) salt ( Vec u ) info i keylen → !( Vec u ) CryptoErr {
    // Empty IKM is valid (RFC 5869 — e.g. Noise's Split derives transport
    // keys with HKDF(ck, "")). Only a non-positive output length is invalid.
    ? <= keylen 0 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : s pctx ( EVP_PKEY_CTX_new_id __NID_HKDF # *u 0 )
    ? == # i pctx 0 { ^ @ !( Vec u ) CryptoErr { F CryptoInit } } {}
    : ~ i ok ( EVP_PKEY_derive_init pctx )
    ? == ok 1 { = ok ( EVP_PKEY_CTX_ctrl_str pctx `md` `SHA256` ) } {}
    ? == ok 1 {
        : String hexkey ( __hex_of_vec ikm )
        = ok ( EVP_PKEY_CTX_ctrl_str pctx `hexkey` ( string_data hexkey ) )
        ( string_free hexkey )
    } {}
    ? & == ok 1 > ( vec_len [u] salt ) 0 {
        : String hexsalt ( __hex_of_vec salt )
        = ok ( EVP_PKEY_CTX_ctrl_str pctx `hexsalt` ( string_data hexsalt ) )
        ( string_free hexsalt )
    } {}
    ? & == ok 1 > ( vec_len [u] info ) 0 {
        : String hexinfo ( __hex_of_vec info )
        = ok ( EVP_PKEY_CTX_ctrl_str pctx `hexinfo` ( string_data hexinfo ) )
        ( string_free hexinfo )
    } {}
    : ( Vec u ) out ( vec_with_cap [u] keylen )
    : s lenbuf ( nurl_zalloc 8 )
    ( nurl_poke lenbuf 0 keylen )
    ? == ok 1 { = ok ( EVP_PKEY_derive pctx # s ( vec_data [u] out ) # *u lenbuf ) } {}
    ( nurl_free # s lenbuf )
    ( EVP_PKEY_CTX_free pctx )
    ? == ok 1 {
        : b _ok ( vec_set_len [u] out keylen )
        ^ @ !( Vec u ) CryptoErr { T out }
    } {
        ( vec_free [u] out )
        ^ @ !( Vec u ) CryptoErr { F CryptoOp }
    }
}

// scrypt (RFC 7914). n must be a power of two > 1; maxmem 0 keeps
// libcrypto's default cap (~32 MiB), which fits the interactive
// baseline n=16384 r=8 p=1.
@ scrypt_kdf s pass ( Vec u ) salt i n i r i p i keylen → !( Vec u ) CryptoErr {
    ? | | <= n 1 <= r 0 | <= p 0 <= keylen 0 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : ( Vec u ) out ( vec_with_cap [u] keylen )
    : i ok ( EVP_PBE_scrypt pass ( nurl_str_len pass )
    # s ( vec_data [u] salt ) ( vec_len [u] salt )
    n r p 0 # s ( vec_data [u] out ) keylen )
    ? == ok 1 {
        : b _ok ( vec_set_len [u] out keylen )
        ^ @ !( Vec u ) CryptoErr { T out }
    } {
        ( vec_free [u] out )
        ^ @ !( Vec u ) CryptoErr { F CryptoOp }
    }
}
