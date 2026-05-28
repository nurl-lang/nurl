// stdlib/std/hash.nu — cryptographic hashing
//
// Thin wrappers over the runtime's hash primitives (runtime §17), all
// self-contained — no libsodium / OpenSSL dependency.
//
//   FIPS 180-4 SHA-256 / SHA-512, RFC 3174 SHA-1, RFC 1321 MD5, and the
//   RFC 2104 HMAC construction over SHA-256 and SHA-512.
//
// Two API shapes:
//   * `*_hex` over `s`   — SHA-256 / HMAC-SHA-256 — NUL-terminated text.
//   * `*_bytes` / `*_hex` over `( Vec u )` — SHA-1 / SHA-512 / MD5 and
//     HMAC-SHA-512 — binary-clean (length-aware, NUL bytes preserved).
//
//   ( sha256_hex s )                       → String   64-char hex
//   ( hmac_sha256_hex key msg )            → String   64-char hex
//   ( sha1_bytes   ( Vec u ) data )        → ( Vec u ) 20-byte digest
//   ( sha1_hex     ( Vec u ) data )        → String   40-char hex
//   ( sha512_bytes ( Vec u ) data )        → ( Vec u ) 64-byte digest
//   ( sha512_hex   ( Vec u ) data )        → String   128-char hex
//   ( md5_bytes    ( Vec u ) data )        → ( Vec u ) 16-byte digest
//   ( md5_hex      ( Vec u ) data )        → String   32-char hex
//   ( hmac_sha512_bytes ( Vec u ) key ( Vec u ) msg ) → ( Vec u ) 64 B
//   ( hmac_sha512_hex   ( Vec u ) key ( Vec u ) msg ) → String 128-char
//
// Algorithm strength: SHA-256 / SHA-512 / HMAC-* are fine for new
// security-sensitive use. SHA-1 and MD5 are provided ONLY for
// compatibility with protocols and formats that mandate them (WebSocket
// handshake per RFC 6455 §4.2.2, git object IDs, file checksums, S3
// ETags, legacy APIs) — both are collision-broken and MUST NOT be used
// to authenticate data or hash secrets.
//
// Ownership: every returned `( Vec u )` / `String` is owned — the caller
// frees it (`vec_free [u]` / `string_free`) or lets auto-drop run.
//
// Example — verifying a webhook signature:
//   : String want ( hmac_sha256_hex secret payload )
//   ? ( string_eq want sig ) { ... } { ... }

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_md5.nu`
$ `stdlib/std/hash_sha1.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hash_sha512.nu`

// Helper: copy a NUL-terminated raw `s` into an owned Vec[u].
@ __hash_str_to_bytes s str → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : i n ( nurl_str_len str )
    : ~ i i 0
    ~ < i n {
        ( vec_push [u] v # u & ( nurl_str_get str i ) 255 )
        = i + i 1
    }
    ^ v
}

@ sha256_hex s str → String {
    : ( Vec u ) data ( __hash_str_to_bytes str )
    : ( Vec u ) digest ( sha256_pure data )
    : String out ( bytes_to_hex digest )
    ( vec_free [u] digest )
    ( vec_free [u] data )
    ^ out
}

@ hmac_sha256_hex s key s msg → String {
    : ( Vec u ) k ( __hash_str_to_bytes key )
    : ( Vec u ) m ( __hash_str_to_bytes msg )
    : ( Vec u ) digest ( hmac_sha256_pure k m )
    : String out ( bytes_to_hex digest )
    ( vec_free [u] digest )
    ( vec_free [u] m )
    ( vec_free [u] k )
    ^ out
}

@ sha1_bytes ( Vec u ) data → ( Vec u ) {
    ^ ( sha1_pure data )
}

@ sha1_hex ( Vec u ) data → String {
    : ( Vec u ) digest ( sha1_bytes data )
    : String out ( bytes_to_hex digest )
    ( vec_free [u] digest )
    ^ out
}

// ── SHA-512 / MD5 / HMAC-SHA-512 ────────────────────────────────────
//
// Runtime entries — binary-clean, write the digest into a caller buffer
// (resolved from runtime.o; libc is always linked).

// Crypto algorithms live in pure NURL submodules above. The runtime
// ships no hash transform — `secure_random` is the only crypto FFI.

@ sha512_bytes ( Vec u ) data → ( Vec u ) {
    ^ ( sha512_pure data )
}

@ sha512_hex ( Vec u ) data → String {
    : ( Vec u ) digest ( sha512_bytes data )
    : String out ( bytes_to_hex digest )
    ( vec_free [u] digest )
    ^ out
}

@ md5_bytes ( Vec u ) data → ( Vec u ) {
    ^ ( md5_pure data )
}

@ md5_hex ( Vec u ) data → String {
    : ( Vec u ) digest ( md5_bytes data )
    : String out ( bytes_to_hex digest )
    ( vec_free [u] digest )
    ^ out
}

@ hmac_sha512_bytes ( Vec u ) key ( Vec u ) msg → ( Vec u ) {
    ^ ( hmac_sha512_pure key msg )
}

@ hmac_sha512_hex ( Vec u ) key ( Vec u ) msg → String {
    : ( Vec u ) digest ( hmac_sha512_bytes key msg )
    : String out ( bytes_to_hex digest )
    ( vec_free [u] digest )
    ^ out
}
