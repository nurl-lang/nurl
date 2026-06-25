// stdlib/ext/crypto.nu — AEAD ciphers, signatures, key exchange, KDFs.
//
// PURE NURL — no OpenSSL, no FFI beyond libc's CSPRNG (nurl_rand_fill). This
// is a thin, uniform façade over the pure primitives in std/: AES-256-GCM and
// ChaCha20-Poly1305 AEAD, Ed25519 signing, X25519 key exchange, and the
// PBKDF2 / HKDF / scrypt KDFs. The public surface (and the CryptoErr /
// CryptoKeypair types) is unchanged, so net/* , jwt and other callers are
// untouched; only the implementation moved off libcrypto.
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
// Errors: CryptoArg (bad length/parameter), CryptoInit / CryptoOp
// (reserved), CryptoVerify (AEAD tag rejected). Compare derived MACs/keys
// with constant_time_eq_vec (std/subtle.nu), never vec-wise ==.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/aes_gcm.nu`
$ `stdlib/std/chacha20poly1305.nu`
$ `stdlib/std/ed25519.nu`
$ `stdlib/std/x25519.nu`
$ `stdlib/std/hkdf.nu`
$ `stdlib/std/pbkdf2.nu`
$ `stdlib/std/scrypt.nu`

// OS CSPRNG (getrandom / arc4random / BCryptGenRandom / urandom) — the one
// libc dependency, shared with std/random.nu (FFI declarations dedupe).
& `c` @ nurl_rand_fill *u buf i n → i

: | CryptoErr { CryptoArg CryptoInit CryptoOp CryptoVerify }

// Raw keypair: secret + public, 32 bytes each for both Ed25519 (seed)
// and X25519.
: CryptoKeypair { ( Vec u ) sk ( Vec u ) pk }

// ── helpers ─────────────────────────────────────────────────────────

// `n` cryptographically-random bytes (nonces, keys, salts).
@ rand_fill_vec i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    ? > n 0 { ( nurl_rand_fill # *u ( vec_data [u] v ) n ) } {}
    : b _o ( vec_set_len [u] v ? > n 0 n 0 )
    ^ v
}

@ __cr_str_vec s str → ( Vec u ) {
    : i n ( nurl_str_len str )
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u ( nurl_str_get str k ) ) = k + k 1 }
    ^ v
}

// ── AEAD ────────────────────────────────────────────────────────────

@ aes256gcm_encrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → !( Vec u ) CryptoErr {
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ^ @ !( Vec u ) CryptoErr { T ( aes256_gcm_encrypt key nonce aad pt ) }
}

@ aes256gcm_decrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_and_tag → !( Vec u ) CryptoErr {
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ?? ( aes256_gcm_decrypt key nonce aad ct_and_tag ) {
        T pt → ^ @ !( Vec u ) CryptoErr { T pt }
        F _ → ^ @ !( Vec u ) CryptoErr { F CryptoVerify }
    }
}

@ chacha20poly1305_encrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → !( Vec u ) CryptoErr {
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ^ @ !( Vec u ) CryptoErr { T ( aead_encrypt key nonce aad pt ) }
}

@ chacha20poly1305_decrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_and_tag → !( Vec u ) CryptoErr {
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ?? ( aead_decrypt key nonce aad ct_and_tag ) {
        T pt → ^ @ !( Vec u ) CryptoErr { T pt }
        F _ → ^ @ !( Vec u ) CryptoErr { F CryptoVerify }
    }
}

// ── Ed25519 / X25519 ────────────────────────────────────────────────

@ ed25519_keygen → !CryptoKeypair CryptoErr {
    : ( Vec u ) sk ( rand_fill_vec 32 )
    : ( Vec u ) pk ( ed25519_pubkey_pure sk )
    ^ @ !CryptoKeypair CryptoErr { T @ CryptoKeypair { sk pk } }
}

@ x25519_keygen → !CryptoKeypair CryptoErr {
    : ( Vec u ) sk ( rand_fill_vec 32 )
    : ( Vec u ) pk ( x25519_base sk )
    ^ @ !CryptoKeypair CryptoErr { T @ CryptoKeypair { sk pk } }
}

@ ed25519_pubkey ( Vec u ) sk → !( Vec u ) CryptoErr {
    ? != ( vec_len [u] sk ) 32 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ^ @ !( Vec u ) CryptoErr { T ( ed25519_pubkey_pure sk ) }
}

@ x25519_pubkey ( Vec u ) sk → !( Vec u ) CryptoErr {
    ? != ( vec_len [u] sk ) 32 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ^ @ !( Vec u ) CryptoErr { T ( x25519_base sk ) }
}

// Detached Ed25519 signature (64 bytes) over msg with a 32-byte seed.
@ ed25519_sign ( Vec u ) sk ( Vec u ) msg → !( Vec u ) CryptoErr {
    ? != ( vec_len [u] sk ) 32 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ^ @ !( Vec u ) CryptoErr { T ( ed25519_sign_pure sk msg ) }
}

// True iff sig (64 B) is valid over msg under pk (32 B). Malformed inputs
// simply verify false.
@ ed25519_verify ( Vec u ) pk ( Vec u ) msg ( Vec u ) sig → b {
    ? != ( vec_len [u] pk ) 32 { ^ F } {}
    ? != ( vec_len [u] sig ) 64 { ^ F } {}
    ^ ( ed25519_verify_pure pk msg sig )
}

// X25519 ECDH: 32-byte shared secret from our secret key + peer's public
// key. Pass the result through hkdf_sha256 before keying a cipher.
@ x25519_derive ( Vec u ) sk ( Vec u ) peer_pk → !( Vec u ) CryptoErr {
    ? | != ( vec_len [u] sk ) 32 != ( vec_len [u] peer_pk ) 32 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ^ @ !( Vec u ) CryptoErr { T ( x25519 sk peer_pk ) }
}

// ── Key derivation ──────────────────────────────────────────────────

@ pbkdf2_sha256 s pass ( Vec u ) salt i iters i keylen → !( Vec u ) CryptoErr {
    ? | <= iters 0 <= keylen 0 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : ( Vec u ) pw ( __cr_str_vec pass )
    : ( Vec u ) dk ( pbkdf2_hmac_sha256 pw salt iters keylen )
    ( vec_free [u] pw )
    ^ @ !( Vec u ) CryptoErr { T dk }
}

@ pbkdf2_sha512 s pass ( Vec u ) salt i iters i keylen → !( Vec u ) CryptoErr {
    ? | <= iters 0 <= keylen 0 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : ( Vec u ) pw ( __cr_str_vec pass )
    : ( Vec u ) dk ( pbkdf2_hmac_sha512 pw salt iters keylen )
    ( vec_free [u] pw )
    ^ @ !( Vec u ) CryptoErr { T dk }
}

// HKDF-SHA256 (RFC 5869, extract-and-expand). Empty salt = RFC's
// zero-length-salt path; empty IKM and empty info are valid.
@ hkdf_sha256 ( Vec u ) ikm ( Vec u ) salt ( Vec u ) info i keylen → !( Vec u ) CryptoErr {
    ? <= keylen 0 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : ( Vec u ) prk ( hkdf_extract salt ikm )
    : ( Vec u ) okm ( hkdf_expand prk info keylen )
    ( vec_free [u] prk )
    ^ @ !( Vec u ) CryptoErr { T okm }
}

// scrypt (RFC 7914). n must be a power of two > 1.
@ scrypt_kdf s pass ( Vec u ) salt i n i r i p i keylen → !( Vec u ) CryptoErr {
    ? | | | <= n 1 <= r 0 <= p 0 <= keylen 0 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    ? != & n - n 1 0 { ^ @ !( Vec u ) CryptoErr { F CryptoArg } } {}
    : ( Vec u ) pw ( __cr_str_vec pass )
    : ( Vec u ) dk ( scrypt_pure pw salt n r p keylen )
    ( vec_free [u] pw )
    ^ @ !( Vec u ) CryptoErr { T dk }
}
