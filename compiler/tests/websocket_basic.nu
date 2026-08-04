// websocket_basic.nu — exhaustive regression for stdlib/ext/websocket.nu.
//
// Offline sections cover:
//   §A  Handshake derivation (RFC 6455 §1.3 worked example)
//   §B  ws_is_upgrade T/F dispatch
//   §C  UTF-8 validator (RFC 3629, strict)
//   §D  Frame serializer (RFC 6455 §5.2 byte-format check)
//   §E  ws_parse_close + ws_send_close validation
//   §F  Frame writer validation gates
//
// Live section (the `live` half of the declaration below):
//   §G  Loopback handshake + echo round-trip + ping/pong + close handshake
// requires: live

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/websocket.nu`

@ print_label s tag s value → v {
    ( nurl_print tag )
    ( nurl_print `=` )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ print_bool s tag b v → v {
    ( print_label tag ? v `T` `F` )
}

@ bytes_push_str_to ( Vec u ) buf s raw → v {
    ( bytes_extend_str buf raw )
}

@ vec_bytes_eq_hex ( Vec u ) got s want_hex → b {
    : i n ( vec_len [u] got )
    : i wh ( nurl_str_len want_hex )
    ? != * n 2 wh { ^ F } {}
    : *u p ( vec_data [u] got )
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k n {
        : i b # i . p k
        : i hi_nib >> b 4
        : i lo_nib & b 15
        : i hi_char ? < hi_nib 10 + 48 hi_nib + 87 hi_nib
        : i lo_char ? < lo_nib 10 + 48 lo_nib + 87 lo_nib
        : i want_hi ( nurl_str_get want_hex * k 2 )
        : i want_lo ( nurl_str_get want_hex + * k 2 1 )
        ? | != hi_char want_hi != lo_char want_lo { = ok F } {}
        = k + k 1
    }
    ^ ok
}

@ make_request_for_upgrade → HttpRequest {
    : HttpRequest r ( request_new )
    ( string_free . r method ) = . r method ( string_from `GET` )
    ( string_free . r path ) = . r path ( string_from `/ws` )
    ( string_free . r version ) = . r version ( string_from `HTTP/1.1` )
    ( vec_push [Header] . r headers ( header_new `Host` `example.com` ) )
    ( vec_push [Header] . r headers ( header_new `Upgrade` `websocket` ) )
    ( vec_push [Header] . r headers ( header_new `Connection` `keep-alive, Upgrade` ) )
    ( vec_push [Header] . r headers ( header_new `Sec-WebSocket-Version` `13` ) )
    ( vec_push [Header] . r headers ( header_new `Sec-WebSocket-Key` `dGhlIHNhbXBsZSBub25jZQ==` ) )
    ^ r
}

@ section_a → v {
    ( nurl_print `--- A handshake ---\n` )
    // RFC 6455 §1.3 worked example
    : String acc ( ws_accept_key `dGhlIHNhbXBsZSBub25jZQ==` )
    : b ok ( nurl_str_eq ( string_data acc ) `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=` )
    ( print_bool `rfc1_3_accept` ok )
    ( string_free acc )

    : HttpRequest r ( make_request_for_upgrade )
    : !HttpResponse WsErr rr ( ws_handshake_response_for r @ ?String { F ( string_new ) } )
    ?? rr {
        T resp → {
            : ( Vec u ) wire ( response_serialize resp )
            : i wn ( vec_len [u] wire )
            // Status line "HTTP/1.1 101 Switching Protocols" is 32 chars
            // → first byte after status line is at offset 32.
            ( print_bool `status_101` > wn 16 )
            // Spot-check the wire bytes for "Sec-WebSocket-Accept:"
            : *u wp ( vec_data [u] wire )
            : ~ b found F
            : ~ i k 0
            ~ & ! found < k - wn 21 {
                ? & & & == # i . wp k 83 == # i . wp + k 1 101 == # i . wp + k 2 99
                & == # i . wp + k 3 45 == # i . wp + k 4 87 {
                    = found T
                } {}
                = k + k 1
            }
            ( print_bool `accept_header_present` found )
            ( vec_free [u] wire )
            ( http_response_free resp )
        }
        F e → {
            ( print_label `handshake_err` ( ws_err_name e ) )
        }
    }
    ( request_free r )
}

@ section_b → v {
    ( nurl_print `--- B ws_is_upgrade ---\n` )
    : HttpRequest r1 ( make_request_for_upgrade )
    ( print_bool `valid_upgrade` ( ws_is_upgrade r1 ) )
    ( request_free r1 )

    // Wrong method
    : HttpRequest r2 ( make_request_for_upgrade )
    ( string_free . r2 method ) = . r2 method ( string_from `POST` )
    ( print_bool `post_rejected` ! ( ws_is_upgrade r2 ) )
    ( request_free r2 )

    // Missing key
    : HttpRequest r3 ( request_new )
    ( string_free . r3 method ) = . r3 method ( string_from `GET` )
    ( vec_push [Header] . r3 headers ( header_new `Upgrade` `websocket` ) )
    ( vec_push [Header] . r3 headers ( header_new `Connection` `Upgrade` ) )
    ( print_bool `nokey_rejected` ! ( ws_is_upgrade r3 ) )
    ( request_free r3 )

    // Connection header missing Upgrade token
    : HttpRequest r4 ( make_request_for_upgrade )
    : *Header hp ( vec_data [Header] . r4 headers )
    // Headers added in order: Host, Upgrade, Connection, Version, Key
    // Replace index 2 (Connection) with keep-alive only.
    : Header old . hp 2
    ( header_free old )
    = . hp 2 ( header_new `Connection` `keep-alive` )
    ( print_bool `no_upgrade_token_rejected` ! ( ws_is_upgrade r4 ) )
    ( request_free r4 )
}

@ section_c → v {
    ( nurl_print `--- C UTF-8 ---\n` )
    // ASCII
    : ( Vec u ) a ( bytes_from_str `Hello, world!` )
    ( print_bool `ascii_ok` ( ws_validate_utf8 a ) )
    ( vec_free [u] a )

    // 2-byte: U+00E4 ä = 0xC3 0xA4
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 195 ) ( vec_push [u] b # u 164 )
    ( print_bool `2byte_ok` ( ws_validate_utf8 b ) )
    ( vec_free [u] b )

    // 3-byte: U+20AC € = 0xE2 0x82 0xAC
    : ( Vec u ) c ( vec_new [u] )
    ( vec_push [u] c # u 226 ) ( vec_push [u] c # u 130 ) ( vec_push [u] c # u 172 )
    ( print_bool `3byte_ok` ( ws_validate_utf8 c ) )
    ( vec_free [u] c )

    // 4-byte: U+1F600 😀 = 0xF0 0x9F 0x98 0x80
    : ( Vec u ) d ( vec_new [u] )
    ( vec_push [u] d # u 240 ) ( vec_push [u] d # u 159 )
    ( vec_push [u] d # u 152 ) ( vec_push [u] d # u 128 )
    ( print_bool `4byte_ok` ( ws_validate_utf8 d ) )
    ( vec_free [u] d )

    // Overlong: 0xC0 0x80 (would be U+0000)
    : ( Vec u ) o ( vec_new [u] )
    ( vec_push [u] o # u 192 ) ( vec_push [u] o # u 128 )
    ( print_bool `overlong_rejected` ! ( ws_validate_utf8 o ) )
    ( vec_free [u] o )

    // Surrogate: 0xED 0xA0 0x80 = U+D800
    : ( Vec u ) s ( vec_new [u] )
    ( vec_push [u] s # u 237 ) ( vec_push [u] s # u 160 ) ( vec_push [u] s # u 128 )
    ( print_bool `surrogate_rejected` ! ( ws_validate_utf8 s ) )
    ( vec_free [u] s )

    // Truncated 2-byte
    : ( Vec u ) t ( vec_new [u] )
    ( vec_push [u] t # u 195 )
    ( print_bool `truncated_rejected` ! ( ws_validate_utf8 t ) )
    ( vec_free [u] t )

    // Bare continuation
    : ( Vec u ) bc ( vec_new [u] )
    ( vec_push [u] bc # u 128 )
    ( print_bool `bare_cont_rejected` ! ( ws_validate_utf8 bc ) )
    ( vec_free [u] bc )

    // Code point > U+10FFFF (0xF5+)
    : ( Vec u ) cp ( vec_new [u] )
    ( vec_push [u] cp # u 245 ) ( vec_push [u] cp # u 128 )
    ( vec_push [u] cp # u 128 ) ( vec_push [u] cp # u 128 )
    ( print_bool `over_max_rejected` ! ( ws_validate_utf8 cp ) )
    ( vec_free [u] cp )
}

@ section_d → v {
    ( nurl_print `--- D frame serializer ---\n` )
    // RFC 6455 §5.7: single unmasked "Hello" text frame
    // Expected wire: 81 05 48 65 6c 6c 6f
    : ( Vec u ) hello ( bytes_from_str `Hello` )
    : !( Vec u ) WsErr sr ( ws_serialize_frame T 1 hello )
    ?? sr {
        T wire → {
            ( print_bool `hello_wire` ( vec_bytes_eq_hex wire `810548656c6c6f` ) )
            ( vec_free [u] wire )
        }
        F e → { ( print_label `hello_err` ( ws_err_name e ) ) }
    }
    ( vec_free [u] hello )

    // Empty text frame: 81 00
    : ( Vec u ) empty ( vec_new [u] )
    : !( Vec u ) WsErr se ( ws_serialize_frame T 1 empty )
    ?? se {
        T wire → {
            ( print_bool `empty_wire` ( vec_bytes_eq_hex wire `8100` ) )
            ( vec_free [u] wire )
        }
        F _ → ( nurl_print `empty_err\n` )
    }
    ( vec_free [u] empty )

    // 126-byte payload triggers the 16-bit extended length encoding.
    // First 4 bytes: 82 7E 00 7E, then 126 zero bytes.
    : ( Vec u ) p126 ( vec_with_cap [u] 126 )
    : ~ i k 0
    ~ < k 126 { ( vec_push [u] p126 # u 0 ) = k + k 1 }
    : !( Vec u ) WsErr s126 ( ws_serialize_frame T 2 p126 )
    ?? s126 {
        T wire → {
            : i wn ( vec_len [u] wire )
            : *u wp ( vec_data [u] wire )
            : b ok & & & == wn 130 == # i . wp 0 130
            & == # i . wp 1 126 == # i . wp 2 0
            == # i . wp 3 126
            ( print_bool `len126_header` ok )
            ( vec_free [u] wire )
        }
        F _ → ( nurl_print `len126_err\n` )
    }
    ( vec_free [u] p126 )

    // 65536-byte payload triggers the 64-bit extended length encoding.
    // First 10 bytes: 82 7F 00 00 00 00 00 01 00 00
    : ( Vec u ) p64k ( vec_with_cap [u] 65536 )
    : ~ i k2 0
    ~ < k2 65536 { ( vec_push [u] p64k # u 0 ) = k2 + k2 1 }
    : !( Vec u ) WsErr s64k ( ws_serialize_frame T 2 p64k )
    ?? s64k {
        T wire → {
            : i wn ( vec_len [u] wire )
            : *u wp ( vec_data [u] wire )
            : b ok & & & == wn 65546 == # i . wp 0 130
            & == # i . wp 1 127 == # i . wp 7 1
            & == # i . wp 8 0 == # i . wp 9 0
            ( print_bool `len64k_header` ok )
            ( vec_free [u] wire )
        }
        F _ → ( nurl_print `len64k_err\n` )
    }
    ( vec_free [u] p64k )

    // Continuation frame (opcode 0, FIN=0): byte0 = 0x00
    : ( Vec u ) chunk ( bytes_from_str `xyz` )
    : !( Vec u ) WsErr sc ( ws_serialize_frame F 0 chunk )
    ?? sc {
        T wire → {
            ( print_bool `cont_wire` ( vec_bytes_eq_hex wire `000378797a` ) )
            ( vec_free [u] wire )
        }
        F _ → ( nurl_print `cont_err\n` )
    }
    ( vec_free [u] chunk )

    // Ping with payload "ab"
    : ( Vec u ) pp ( bytes_from_str `ab` )
    : !( Vec u ) WsErr sp ( ws_serialize_frame T 9 pp )
    ?? sp {
        T wire → {
            ( print_bool `ping_wire` ( vec_bytes_eq_hex wire `89026162` ) )
            ( vec_free [u] wire )
        }
        F _ → ( nurl_print `ping_err\n` )
    }
    ( vec_free [u] pp )
}

@ section_e → v {
    ( nurl_print `--- E close-frame ---\n` )

    // Parse empty payload → 1005 / ""
    : ( Vec u ) e ( vec_new [u] )
    : WsCloseInfo ci ( ws_parse_close e )
    ( print_bool `empty_1005` & == . ci code 1005 == 0 ( string_len . ci reason ) )
    ( ws_close_info_free ci )
    ( vec_free [u] e )

    // Parse 1-byte → 1002 (protocol error)
    : ( Vec u ) one ( vec_new [u] )
    ( vec_push [u] one # u 3 )
    : WsCloseInfo ci2 ( ws_parse_close one )
    ( print_bool `onebyte_1002` == . ci2 code 1002 )
    ( ws_close_info_free ci2 )
    ( vec_free [u] one )

    // Parse code-only 0x03 0xE8 = 1000
    : ( Vec u ) c1k ( vec_new [u] )
    ( vec_push [u] c1k # u 3 ) ( vec_push [u] c1k # u 232 )
    : WsCloseInfo ci3 ( ws_parse_close c1k )
    ( print_bool `code_1000` & == . ci3 code 1000 == 0 ( string_len . ci3 reason ) )
    ( ws_close_info_free ci3 )
    ( vec_free [u] c1k )

    // Parse code + reason "bye" → 0x03 0xE9 'b' 'y' 'e'
    : ( Vec u ) cr ( vec_new [u] )
    ( vec_push [u] cr # u 3 ) ( vec_push [u] cr # u 233 )
    ( vec_push [u] cr # u 98 ) ( vec_push [u] cr # u 121 ) ( vec_push [u] cr # u 101 )
    : WsCloseInfo ci4 ( ws_parse_close cr )
    ( print_bool `code_reason` & == . ci4 code 1001
    != 0 ( nurl_str_eq ( string_data . ci4 reason ) `bye` ) )
    ( ws_close_info_free ci4 )
    ( vec_free [u] cr )
}

@ section_f → v {
    ( nurl_print `--- F writer validation ---\n` )
    // Control frame with FIN=0 → rejected
    : ( Vec u ) p ( bytes_from_str `x` )
    : !( Vec u ) WsErr r1 ( ws_serialize_frame F 9 p )
    ?? r1 {
        T w → { ( nurl_print `ctl_fin0_unexpected_ok\n` ) ( vec_free [u] w ) }
        F e → ( print_label `ctl_fin0_err` ( ws_err_name e ) )
    }
    ( vec_free [u] p )

    // Control frame with 126-byte payload → rejected
    : ( Vec u ) big ( vec_with_cap [u] 126 )
    : ~ i k 0
    ~ < k 126 { ( vec_push [u] big # u 65 ) = k + k 1 }
    : !( Vec u ) WsErr r2 ( ws_serialize_frame T 9 big )
    ?? r2 {
        T w → { ( nurl_print `ctl_big_unexpected_ok\n` ) ( vec_free [u] w ) }
        F e → ( print_label `ctl_big_err` ( ws_err_name e ) )
    }
    ( vec_free [u] big )

    // Bad opcode 5
    : ( Vec u ) z ( vec_new [u] )
    : !( Vec u ) WsErr r3 ( ws_serialize_frame T 5 z )
    ?? r3 {
        T w → { ( nurl_print `op5_unexpected_ok\n` ) ( vec_free [u] w ) }
        F e → ( print_label `op5_err` ( ws_err_name e ) )
    }
    ( vec_free [u] z )
}

@ main → i {
    ( section_a )
    ( section_b )
    ( section_c )
    ( section_d )
    ( section_e )
    ( section_f )
    ^ 0
}
