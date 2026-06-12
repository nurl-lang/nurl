// cbor.nu — ext/cbor.nu acceptance (RFC 8949).
//
// (1) Round-trips a representative Json document Json→CBOR→Json and
//     checks the bytes are the canonical shortest-head encoding.
// (2) Decodes raw RFC 8949 Appendix A vectors, including the integer
//     size boundaries, negatives, nested array/map, and float16/32/64.
// (3) Checks the documented rejections (byte string, tag, indefinite,
//     non-text map key, trailing bytes).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/cbor.nu`

// hex string → Vec[u]
@ hx s h → ( Vec u ) {
    : i n ( nurl_str_len h )
    : ( Vec u ) out ( vec_with_cap [u] ? > n 1 / n 2 1 )
    : ~ i k 0
    ~ < + k 1 n {
        : i hi ( nurl_str_get h k )
        : i lo ( nurl_str_get h + k 1 )
        : i hv ? <= hi 57 - hi 48 - hi 87
        : i lv ? <= lo 57 - lo 48 - lo 87
        ( vec_push [u] out # u + * hv 16 lv )
        = k + k 2
    }
    ^ out
}

// Vec[u] → lowercase hex (binary-safe: indexed *u read)
@ tohex ( Vec u ) v → String {
    : i n ( vec_len [u] v )
    : *u p ( vec_data [u] v )
    : String out ( string_with_cap + * n 2 1 )
    : ~ i k 0
    ~ < k n {
        : i b # i . p k
        : i hi / b 16
        : i lo % b 16
        ( string_push_char out ? < hi 10 + 48 hi + 87 hi )
        ( string_push_char out ? < lo 10 + 48 lo + 87 lo )
        = k + k 1
    }
    ^ out
}

// decode a hex CBOR vector and print its JSON form (or the error name)
@ dec s label s hexv → v {
    ( nurl_print label ) ( nurl_print `: ` )
    : ( Vec u ) bytes ( hx hexv )
    : !Json CborErr r ( cbor_decode bytes )
    ?? r {
        T j → { : String s ( json_stringify j ) ( nurl_print ( string_data s ) ) ( string_free s ) ( json_free j ) }
        F e → ( nurl_print ( cbor_err_name # CborErr e ) )
    }
    ( vec_free [u] bytes )
    ( nurl_print `\n` )
}

@ main → i {
    // ── (1) round-trip + canonical encoding ──
    : !Json JsonError pj ( json_parse `{"id":42,"name":"NURL","ok":true,"tags":[1,2,3],"pi":3.5,"neg":-7,"nil":null}` )
    ?? pj {
        T doc → {
            : !( Vec u ) CborErr er ( cbor_encode doc )
            ?? er {
                T bytes → {
                    : String hexs ( tohex bytes )
                    ( nurl_print `encode_hex=` ) ( nurl_print ( string_data hexs ) ) ( nurl_print `\n` )
                    ( string_free hexs )
                    : !Json CborErr dr ( cbor_decode bytes )
                    ?? dr {
                        T back → {
                            : String s ( json_stringify back )
                            ( nurl_print `roundtrip=` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
                            ( string_free s ) ( json_free back )
                        }
                        F _ → ( nurl_print `roundtrip DECODE ERR\n` )
                    }
                    ( vec_free [u] bytes )
                }
                F _ → ( nurl_print `encode ERR\n` )
            }
            ( json_free doc )
        }
        F _ → ( nurl_print `parse ERR\n` )
    }

    // ── (2) RFC 8949 Appendix A decode vectors ──
    ( dec `u0` `00` )                 // 0
    ( dec `u23` `17` )                // 23
    ( dec `u24` `1818` )              // 24 (1-byte arg)
    ( dec `u255` `18ff` )             // 255
    ( dec `u256` `190100` )           // 256 (2-byte)
    ( dec `u65535` `19ffff` )         // 65535
    ( dec `u1m` `1a000f4240` )        // 1000000 (4-byte)
    ( dec `neg1` `20` )               // -1
    ( dec `neg100` `3863` )           // -100
    ( dec `neg1000` `3903e7` )        // -1000
    ( dec `str` `6449455446` )        // "IETF"
    ( dec `emptystr` `60` )           // ""
    ( dec `arr` `83010203` )          // [1,2,3]
    ( dec `nested` `8301820203820405` ) // [1,[2,3],[4,5]]
    ( dec `map` `a26161016162820203` ) // {"a":1,"b":[2,3]}
    ( dec `false` `f4` )
    ( dec `true` `f5` )
    ( dec `null` `f6` )
    ( dec `undef` `f7` )              // → null
    // floats: half / single / double
    ( dec `half_1.0` `f93c00` )       // 1.0
    ( dec `half_1.5` `f93e00` )       // 1.5
    ( dec `half_neg4` `f9c400` )      // -4.0
    ( dec `half_0` `f90000` )         // 0.0
    ( dec `single_100000` `fa47c35000` ) // 100000.0
    ( dec `double_1.1` `fb3ff199999999999a` ) // 1.1
    ( dec `double_pi` `fb400921fb54442d18` )   // 3.141592653589793

    // ── (3) documented rejections ──
    ( dec `bytestring` `4401020304` )  // major 2 → unsupported
    ( dec `tag` `c074323031332d30332d3231` ) // tag 0 (datetime) → unsupported
    ( dec `indefinite_arr` `9f00ff` )  // → unsupported
    ( dec `intkey_map` `a1010a` )      // {1:10} non-text key → bad-map-key
    ( dec `trailing` `0000` )          // 0 then a stray byte → trailing-bytes
    ( dec `truncated` `19ff` )         // 2-byte head, 1 byte present → truncated
    ^ 0
}
