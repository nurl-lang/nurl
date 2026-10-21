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
    ? <= length 0 { ^ ( vec_new [u] ) } {}
    : i ilen ( vec_len [u] info )
    ? <= length 32 {
        : ( Vec u ) input ( vec_with_cap [u] + ilen 1 )
        : b _li ( vec_set_len [u] input + ilen 1 )
        : *u ip ( vec_data [u] input )
        ? > ilen 0 { ( nurl_memcpy # s ip # s ( vec_data [u] info ) ilen ) } {}
        = . ip ilen # u 1
        : ( Vec u ) t ( hmac_sha256_pure prk input )
        ? < length 32 { : b _lt ( vec_set_len [u] t length ) } {}
        ^ t
    } {}
    : HmacSha256 hk ( hmac_sha256_key prk )
    : ( Vec u ) out ( vec_with_cap [u] length )
    : b _lo ( vec_set_len [u] out length )
    : *u op ( vec_data [u] out )
    : ( Vec u ) input ( vec_with_cap [u] + + 32 ilen 1 )
    : *u ip ( vec_data [u] input )
    : *u infop ( vec_data [u] info )
    : ~ i counter 1
    : ~ i generated 0
    ~ < generated length {
        ? == counter 1 {
            : b _l1 ( vec_set_len [u] input + ilen 1 )
            ? > ilen 0 { ( nurl_memcpy # s ip # s infop ilen ) } {}
            = . ip ilen # u 1
        } {
            : b _ln ( vec_set_len [u] input + + 32 ilen 1 )
            ( nurl_memcpy # s ip # s + # i op - generated 32 32 )
            ? > ilen 0 { ( nurl_memcpy # s + # i ip 32 # s infop ilen ) } {}
            = . ip + 32 ilen # u & counter 255
        }
        : ( Vec u ) t ( hmac_sha256_mac hk input )
        : i rem - length generated
        : i take ? < rem 32 rem 32
        ( nurl_memcpy # s + # i op generated # s ( vec_data [u] t ) take )
        = generated + generated take
        = counter + counter 1
    }
    ^ out
}

// HKDF-Expand-Label (RFC 8446 §7.1): expand `secret` under the
// length-prefixed structured label "tls13 "+label and `context`.
@ hkdf_expand_label ( Vec u ) secret s label ( Vec u ) context i length → ( Vec u ) {
    : i slen ( nurl_str_len label )
    : i lablen + 6 slen
    : i ctxlen ( vec_len [u] context )
    ? & <= length 32 > length 0 {
        : i msg_len + + lablen ctxlen 5
        : ( Vec u ) hl ( vec_with_cap [u] msg_len )
        : b _lh ( vec_set_len [u] hl msg_len )
        : *u hp ( vec_data [u] hl )
        = . hp 0 # u & >> length 8 255
        = . hp 1 # u & length 255
        = . hp 2 # u & lablen 255
        = . hp 3 # u 116
        = . hp 4 # u 108
        = . hp 5 # u 115
        = . hp 6 # u 49
        = . hp 7 # u 51
        = . hp 8 # u 32
        ? > slen 0 { ( nurl_memcpy # s + # i hp 9 # s label slen ) } {}
        : i coff + 3 lablen
        = . hp coff # u & ctxlen 255
        ? > ctxlen 0 { ( nurl_memcpy # s + + # i hp coff 1 # s ( vec_data [u] context ) ctxlen ) } {}
        = . hp - msg_len 1 # u 1
        : ( Vec u ) t ( hmac_sha256_pure secret hl )
        ? < length 32 { : b _lt ( vec_set_len [u] t length ) } {}
        ^ t
    } {}
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
    ( bytes_extend_bytes hl context )
    ^ ( hkdf_expand secret hl length )
}

// Derive-Secret = HKDF-Expand-Label(secret, label, Transcript-Hash, 32).
@ derive_secret ( Vec u ) secret s label ( Vec u ) transcript_hash → ( Vec u ) {
    ^ ( hkdf_expand_label secret label transcript_hash 32 )
}
