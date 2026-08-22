// stdlib/std/hkdf.nu — HKDF (RFC 5869) over pure-NURL HMAC-SHA-256,
// plus the TLS 1.3 key-schedule helpers HKDF-Expand-Label and
// Derive-Secret (RFC 8446 §7.1). No OpenSSL/FFI.
//
//   ( hkdf_extract salt ikm )                     → ( Vec u )  PRK (32 B)
//   ( hkdf_expand prk info length )               → ( Vec u )
//   ( hkdf_expand_label secret label ctx length ) → ( Vec u )
//   ( derive_secret secret label transcript_hash )→ ( Vec u )  (32 B)
//
// `label` is a plain `s`; the "tls13 " prefix is added internally.
// `transcript_hash` is the SHA-256 of the handshake transcript so far.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`

@ __hk_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

// `bytes_extend_str` is one strlen + one memcpy; the per-byte
// `nurl_str_get` loop this replaced re-ran strlen per call (O(n²)).
@ __push_str ( Vec u ) v s str → v {
    ( bytes_extend_str v str )
}

// HKDF-Extract → a 32-byte pseudo-random key.
@ hkdf_extract ( Vec u ) salt ( Vec u ) ikm → ( Vec u ) {
    ^ ( hmac_sha256_pure salt ikm )
}

// HKDF-Expand → `length` bytes of output key material.
@ hkdf_expand ( Vec u ) prk ( Vec u ) info i length → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] ? > length 0 length 1 )
    : ~ ( Vec u ) prev ( vec_new [u] )
    : ~ i counter 1
    : ~ i generated 0
    ~ < generated length {
        : ( Vec u ) input ( vec_with_cap [u] + + ( vec_len [u] prev ) ( vec_len [u] info ) 1 )
        : ~ i pi 0
        ~ < pi ( vec_len [u] prev ) { ( vec_push [u] input # u ( __hk_bget prev pi ) ) = pi + pi 1 }
        : ~ i ii 0
        ~ < ii ( vec_len [u] info ) { ( vec_push [u] input # u ( __hk_bget info ii ) ) = ii + ii 1 }
        ( vec_push [u] input # u & counter 255 )
        : ( Vec u ) t ( hmac_sha256_pure prk input )
        ( vec_free [u] input )
        ( vec_free [u] prev )
        = prev t
        : ~ i j 0
        ~ & < j 32 < generated length {
            ( vec_push [u] out # u ( __hk_bget t j ) )
            = generated + generated 1
            = j + j 1
        }
        = counter + counter 1
    }
    ( vec_free [u] prev )
    ^ out
}

// HKDF-Expand-Label (RFC 8446 §7.1): expand `secret` under the
// length-prefixed structured label "tls13 "+label and `context`.
@ hkdf_expand_label ( Vec u ) secret s label ( Vec u ) context i length → ( Vec u ) {
    : i lablen + 6 ( nurl_str_len label )
    : i ctxlen ( vec_len [u] context )
    : ( Vec u ) hl ( vec_with_cap [u] + + lablen ctxlen 4 )
    // uint16 length
    ( vec_push [u] hl # u & >> length 8 255 )
    ( vec_push [u] hl # u & length 255 )
    // opaque label<7..255> = "tls13 " + label
    ( vec_push [u] hl # u & lablen 255 )
    ( __push_str hl `tls13 ` )
    ( __push_str hl label )
    // opaque context<0..255>
    ( vec_push [u] hl # u & ctxlen 255 )
    : ~ i ci 0
    ~ < ci ctxlen { ( vec_push [u] hl # u ( __hk_bget context ci ) ) = ci + ci 1 }
    : ( Vec u ) okm ( hkdf_expand secret hl length )
    ( vec_free [u] hl )
    ^ okm
}

// Derive-Secret = HKDF-Expand-Label(secret, label, Transcript-Hash, 32).
@ derive_secret ( Vec u ) secret s label ( Vec u ) transcript_hash → ( Vec u ) {
    ^ ( hkdf_expand_label secret label transcript_hash 32 )
}
