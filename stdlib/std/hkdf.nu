// stdlib/std/hkdf.nu — HKDF (RFC 5869) over pure-NURL HMAC-SHA-256,
// plus the TLS 1.3 key-schedule helpers HKDF-Expand-Label and
// Derive-Secret (RFC 8446 §7.1). No OpenSSL/FFI.
//
//   ( hkdf_extract salt ikm )                     → ( Vec u )  PRK (32 B)
//   ( hkdf_expand prk info length )               → ( Vec u )
//   ( hkdf_expand_label secret label ctx length ) → ( Vec u )
//   ( derive_secret secret label transcript_hash )→ ( Vec u )  (32 B)
//
// A secret that derives more than once — every secret of a TLS 1.3 key
// schedule derives two or three — is prepared once with
// ( hmac_sha256_key secret ) and the derivations take the HmacSha256:
//
//   ( hkdf_expand_in prk info out at length )              → b
//   ( hkdf_expand_label_in prk label ctx out at length )   → b
//   ( hkdf_expand_label_prk prk label ctx length )         → ( Vec u )
//   ( derive_secret_prk prk label transcript_hash )        → ( Vec u )
//
// `out` must not overlap `info` / `context`: a multi-block expansion
// streams the info into every block's MAC, so output written into it
// would change the later blocks. And one derivation at a time per prepared
// key (see HmacSha256 in std/hash_sha256.nu).
//
// The `_in` forms write out[at, at + length) of the caller's buffer and
// allocate nothing; they return false, writing nothing, when the range
// is not inside `out` or the request is not one HKDF defines (length
// above 255 blocks, a label or context above 255 bytes). The Vec forms
// return an empty Vec for those.
//
// `label` is a plain `s`; the "tls13 " prefix is added internally.
// `transcript_hash` is the SHA-256 of the handshake transcript so far.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`

// HKDF-Extract → a 32-byte pseudo-random key.
@ hkdf_extract ( Vec u ) salt ( Vec u ) ikm → ( Vec u ) {
    ^ ( hmac_sha256_pure salt ikm )
}

// RFC 5869 §2.3: L <= 255 * HashLen. `length <= len - at` (both sides
// in range once `at` ≥ 0), not `at + length <= len`, which wraps for a
// huge `at`.
@ __hkdf_range_ok ( Vec u ) out i at i length → b {
    ^ & & & >= at 0 >= length 0 <= length 8160 <= length - ( vec_len [u] out ) at
}

// T(1) ‖ T(2) ‖ … into the `length` bytes at `op`, the info being the
// `n1` bytes at `p1` followed by the `n2` bytes at `p2`:
// T(i) = HMAC(prk, T(i-1) ‖ info ‖ i). The info streams into each MAC
// from where it lives, and T(i) is made in the key's own scratch (word
// 168 of its block, see HmacSha256), so nothing is allocated or
// assembled. The scratch is wiped at the end.
@ __hkdf_expand_to HmacSha256 prk * u p1 i n1 * u p2 i n2 * u op i length → v {
    : *u t # *u + # i ( _hmac_words prk ) 672
    : ~ i counter 1
    : ~ i generated 0
    ~ < generated length {
        ( _hmac_begin prk )
        ? > counter 1 { ( _hmac_absorb prk t 32 ) } {}
        ( _hmac_absorb prk p1 n1 )
        ( _hmac_absorb prk p2 n2 )
        ( _hmac_absorb_byte prk counter )
        ( _hmac_end_to prk t )
        : i rem - length generated
        : i take ? < rem 32 rem 32
        ( nurl_memcpy # s + # i op generated # s t take )
        = generated + generated take
        = counter + counter 1
    }
    ( nurl_memset # s t 0 32 )
}

// HKDF-Expand under a prepared PRK, into out[at, at + length).
@ hkdf_expand_in HmacSha256 prk ( Vec u ) info ( Vec u ) out i at i length → b {
    ? ( __hkdf_range_ok out at length ) {} { ^ F }
    : *u ip ( vec_data [u] info )
    ( __hkdf_expand_to prk ip ( vec_len [u] info ) ip 0 # *u + # i ( vec_data [u] out ) at length )
    ^ T
}

// HKDF-Expand → `length` bytes of output key material.
@ hkdf_expand ( Vec u ) prk ( Vec u ) info i length → ( Vec u ) {
    ? | <= length 0 > length 8160 { ^ ( vec_new [u] ) } {}
    : HmacSha256 k ( hmac_sha256_key prk )
    : ( Vec u ) out ( vec_with_cap [u] length )
    : b _l ( vec_set_len [u] out length )
    : b _ok ( hkdf_expand_in k info out 0 length )
    ^ out
}

// HKDF-Expand-Label (RFC 8446 §7.1) under a prepared secret, into
// out[at, at + length): HKDF-Expand with the info
//
//   struct { uint16 length; opaque label<7..255>; opaque context<0..255>; }
//
// whose label is "tls13 " + `label`. The head — length, the label and
// the context's length byte, at most 259 bytes — is written into the
// key's scratch (word 176 of its block, see HmacSha256); the context
// streams from the caller's buffer.
@ hkdf_expand_label_in HmacSha256 prk s label ( Vec u ) context ( Vec u ) out i at i length → b {
    : i slen ( nurl_str_len label )
    : i lablen + 6 slen
    : i ctxlen ( vec_len [u] context )
    ? | > lablen 255 > ctxlen 255 { ^ F } {}
    ? ( __hkdf_range_ok out at length ) {} { ^ F }
    : *u hp # *u + # i ( _hmac_words prk ) 704
    = . hp 0 # u & >> length 8 255
    = . hp 1 # u & length 255
    = . hp 2 # u lablen
    = . hp 3 # u 116
    = . hp 4 # u 108
    = . hp 5 # u 115
    = . hp 6 # u 49
    = . hp 7 # u 51
    = . hp 8 # u 32
    ? > slen 0 { ( nurl_memcpy # s + # i hp 9 # s label slen ) } {}
    : i hlen + 4 lablen
    = . hp - hlen 1 # u ctxlen
    ( __hkdf_expand_to prk hp hlen ( vec_data [u] context ) ctxlen # *u + # i ( vec_data [u] out ) at length )
    ^ T
}

// HKDF-Expand-Label under a prepared secret, as a fresh Vec.
@ hkdf_expand_label_prk HmacSha256 prk s label ( Vec u ) context i length → ( Vec u ) {
    ? | <= length 0 > length 8160 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) out ( vec_with_cap [u] length )
    : b _l ( vec_set_len [u] out length )
    ? ( hkdf_expand_label_in prk label context out 0 length ) {} { : b _z ( vec_set_len [u] out 0 ) }
    ^ out
}

// HKDF-Expand-Label (RFC 8446 §7.1): expand `secret` under the
// length-prefixed structured label "tls13 "+label and `context`.
@ hkdf_expand_label ( Vec u ) secret s label ( Vec u ) context i length → ( Vec u ) {
    : HmacSha256 k ( hmac_sha256_key secret )
    ^ ( hkdf_expand_label_prk k label context length )
}

// Derive-Secret = HKDF-Expand-Label(secret, label, Transcript-Hash, 32).
@ derive_secret_prk HmacSha256 prk s label ( Vec u ) transcript_hash → ( Vec u ) {
    ^ ( hkdf_expand_label_prk prk label transcript_hash 32 )
}

@ derive_secret ( Vec u ) secret s label ( Vec u ) transcript_hash → ( Vec u ) {
    ^ ( hkdf_expand_label secret label transcript_hash 32 )
}
