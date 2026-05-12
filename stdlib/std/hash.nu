// stdlib/std/hash.nu — cryptographic hashing
//
// Thin wrappers over the runtime's SHA-256 + HMAC-SHA-256 (runtime §17).
// Both inputs and outputs are NUL-terminated `s` / owned `String` —
// appropriate for tokens, webhook payloads, JSON bodies and similar text.
// For binary inputs containing NUL bytes wait for the bytes module
// (Tier 3 §22).
//
// The runtime implementation is the canonical FIPS 180-4 SHA-256 with
// the standard HMAC construction (RFC 2104).
//
//   ( sha256_hex s )                → String   64-char lowercase hex digest
//   ( hmac_sha256_hex key msg )     → String   64-char lowercase hex digest
//
// Example — verifying a webhook signature:
//   : String want ( hmac_sha256_hex secret payload )
//   ? ( string_eq want sig ) { ... } { ... }

$ `stdlib/core/string.nu`

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
