// http3_request_validate.nu — stdlib/ext/http3_conn.nu's request field-
// section rules (RFC 9114 §4.1.2 / §4.3.1): what a server accepts and
// what it refuses with H3_MESSAGE_ERROR (0x10e).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http3_conn.nu`

@ check_int s label i got i want → i {
    ? == got want {
        ( nurl_print label ) ( nurl_print `: PASS\n` )
        ^ 0
    } {
        ( nurl_print label ) ( nurl_print `: FAIL got ` )
        ( nurl_print ( nurl_str_int got ) ) ( nurl_print ` want ` )
        ( nurl_print ( nurl_str_int want ) ) ( nurl_print `\n` )
        ^ 1
    }
}

// Build a section from alternating name/value literals ("" ends).
@ section s n0 s v0 s n1 s v1 s n2 s v2 s n3 s v3 s n4 s v4 → ( Vec Header ) {
    : ( Vec Header ) hs ( vec_new [Header] )
    ? > ( nurl_str_len n0 ) 0 { ( vec_push [Header] hs ( header_new n0 v0 ) ) } {}
    ? > ( nurl_str_len n1 ) 0 { ( vec_push [Header] hs ( header_new n1 v1 ) ) } {}
    ? > ( nurl_str_len n2 ) 0 { ( vec_push [Header] hs ( header_new n2 v2 ) ) } {}
    ? > ( nurl_str_len n3 ) 0 { ( vec_push [Header] hs ( header_new n3 v3 ) ) } {}
    ? > ( nurl_str_len n4 ) 0 { ( vec_push [Header] hs ( header_new n4 v4 ) ) } {}
    ^ hs
}

@ run s label i want s n0 s v0 s n1 s v1 s n2 s v2 s n3 s v3 s n4 s v4 → i {
    : ( Vec Header ) hs ( section n0 v0 n1 v1 n2 v2 n3 v3 n4 v4 )
    : i got ( _h3_validate_request hs )
    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
    ^ ( check_int label got want )
}

@ main → i {
    : ~ i fails 0
    : i E 270
    = fails + fails ( run `ok_get` 0 `:method` `GET` `:scheme` `https` `:authority` `h` `:path` `/` `accept` `*/*` )
    = fails + fails ( run `ok_host_instead_of_authority` 0 `:method` `GET` `:scheme` `https` `:path` `/` `host` `h` `` `` )
    = fails + fails ( run `ok_connect` 0 `:method` `CONNECT` `:authority` `h:443` `` `` `` `` `` `` )
    = fails + fails ( run `ok_te_trailers` 0 `:method` `GET` `:scheme` `https` `:authority` `h` `:path` `/` `te` `trailers` )
    = fails + fails ( run `missing_method` E `:scheme` `https` `:authority` `h` `:path` `/` `` `` `` `` )
    = fails + fails ( run `missing_scheme` E `:method` `GET` `:authority` `h` `:path` `/` `` `` `` `` )
    = fails + fails ( run `missing_path` E `:method` `GET` `:scheme` `https` `:authority` `h` `` `` `` `` )
    = fails + fails ( run `missing_authority_and_host` E `:method` `GET` `:scheme` `https` `:path` `/` `` `` `` `` )
    = fails + fails ( run `duplicate_pseudo` E `:method` `GET` `:method` `GET` `:scheme` `https` `:authority` `h` `:path` `/` )
    = fails + fails ( run `pseudo_after_regular` E `:method` `GET` `:scheme` `https` `accept` `*/*` `:authority` `h` `:path` `/` )
    = fails + fails ( run `unknown_pseudo` E `:method` `GET` `:scheme` `https` `:authority` `h` `:path` `/` `:foo` `bar` )
    = fails + fails ( run `status_in_request` E `:method` `GET` `:scheme` `https` `:authority` `h` `:path` `/` `:status` `200` )
    = fails + fails ( run `uppercase_name` E `:method` `GET` `:scheme` `https` `:authority` `h` `:path` `/` `Accept` `*/*` )
    = fails + fails ( run `connection_header` E `:method` `GET` `:scheme` `https` `:authority` `h` `:path` `/` `connection` `close` )
    = fails + fails ( run `transfer_encoding` E `:method` `GET` `:scheme` `https` `:authority` `h` `:path` `/` `transfer-encoding` `chunked` )
    = fails + fails ( run `te_gzip` E `:method` `GET` `:scheme` `https` `:authority` `h` `:path` `/` `te` `gzip` )
    = fails + fails ( run `empty_path` E `:method` `GET` `:scheme` `https` `:authority` `h` `:path` `` `` `` )
    = fails + fails ( run `connect_with_path` E `:method` `CONNECT` `:authority` `h` `:path` `/` `` `` `` `` )
    = fails + fails ( run `connect_without_authority` E `:method` `CONNECT` `` `` `` `` `` `` `` `` )
    ? == fails 0 { ( nurl_print `http3_request_validate: all PASS\n` ) } { ( nurl_print `http3_request_validate: FAILURES\n` ) }
    ^ fails
}
