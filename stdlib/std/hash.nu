// stdlib/std/hash.nu — cryptographic hashing
//
// Thin wrappers over the runtime's SHA-256, HMAC-SHA-256 and SHA-1
// (runtime §17). SHA-256 and HMAC-SHA-256 are NUL-terminated text-only;
// SHA-1 is binary-clean (length-aware).
//
// The runtime implementations are the canonical FIPS 180-4 SHA-256 with
// the standard HMAC construction (RFC 2104) and RFC 3174 SHA-1.
//
//   ( sha256_hex s )                → String      64-char lowercase hex digest
//   ( hmac_sha256_hex key msg )     → String      64-char lowercase hex digest
//   ( sha1_bytes ( Vec u ) data )   → ( Vec u )   20-byte raw digest
//   ( sha1_hex   ( Vec u ) data )   → String      40-char lowercase hex digest
//
// SHA-1 is included primarily for protocol compatibility (WebSocket
// handshake per RFC 6455 §4.2.2, git object IDs, legacy systems) — it
// is NOT recommended for new security-sensitive applications. Use
// `sha256_hex` for hashing secrets, payloads, or any value that needs
// collision resistance.
//
// Example — verifying a webhook signature:
//   : String want ( hmac_sha256_hex secret payload )
//   ? ( string_eq want sig ) { ... } { ... }

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/std/bytes.nu`

@ sha256_hex s str → String {
    : s digest ( nurl_sha256_hex str )
    : String out ( string_from digest )
    ( nurl_free digest )
    ^ out
}

@ hmac_sha256_hex s key s msg → String {
    : s digest ( nurl_hmac_sha256_hex key msg )
    : String out ( string_from digest )
    ( nurl_free digest )
    ^ out
}

@ sha1_bytes ( Vec u ) data → ( Vec u ) {
    : i n ( vec_len [u] data )
    : *u srcp ( vec_data [u] data )
    : ( Vec u ) out ( vec_with_cap [u] 20 )
    ( vec_reserve [u] out 20 )
    : *u dst ( vec_data [u] out )
    ( nurl_sha1_bytes srcp n dst )
    : b _ ( vec_set_len [u] out 20 )
    ^ out
}

@ sha1_hex ( Vec u ) data → String {
    : ( Vec u ) digest ( sha1_bytes data )
    : String out ( bytes_to_hex digest )
    ( vec_free [u] digest )
    ^ out
}
