// websocket_client.nu — regression for the client-side of
// stdlib/ext/websocket.nu (RFC 6455 §4.1 handshake + §5.3 masking).
//
// Offline sections ASSERT (main returns the failure count, so a
// regression trips the baseline diff):
//   §A  Masked frame serialiser — RFC 6455 §5.7 worked example.
//   §B  Masked empty / control frame format.
//   §C  ws://… / wss://… URL parsing.
//
// Live section (gated on NURL_NET_TESTS=1) drives a real round-trip
// against the existing SERVER stack, proving the two interoperate:
//   §D  ws_connect → send text → echo → send binary → echo → close.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/websocket.nu`

@ print_bool s tag b v → v {
    ( nurl_print tag ) ( nurl_print `=` )
    ( nurl_print ? v `T` `F` ) ( nurl_print `\n` )
}

// Compare an owned Vec[u] against a lowercase hex string.
@ vec_eq_hex ( Vec u ) got s want_hex → b {
    : i n ( vec_len [u] got )
    : i wh ( nurl_str_len want_hex )
    ? != * n 2 wh { ^ F } {}
    : *u p ( vec_data [u] got )
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k n {
        : i b & 255 # i . p k
        : i hi >> b 4
        : i lo & b 15
        : i hc ? < hi 10 + 48 hi + 87 hi
        : i lc ? < lo 10 + 48 lo + 87 lo
        ? | != hc ( nurl_str_get want_hex * k 2 ) != lc ( nurl_str_get want_hex + * k 2 1 ) {
            = ok F
        } {}
        = k + k 1
    }
    ^ ok
}

// ── §A masked frame serialiser (RFC 6455 §5.7) ────────────────────────

// The spec's worked example: a single masked "Hello" text frame with
// key 0x37 0xfa 0x21 0x3d serialises to
//   0x81 0x85 0x37 0xfa 0x21 0x3d 0x7f 0x9f 0x4d 0x51 0x58
@ section_a → i {
    ( nurl_print `--- A masked serialiser ---\n` )
    : ~ i fails 0
    : ( Vec u ) hello ( bytes_from_str `Hello` )
    : !( Vec u ) WsErr sr ( ws_serialize_frame_masked T 1 hello 55 250 33 61 )
    ?? sr {
        T wire → {
            : b ok ( vec_eq_hex wire `818537fa213d7f9f4d5158` )
            ( print_bool `rfc5_7_masked_hello` ok )
            ? ! ok { = fails + fails 1 } {}
            ( vec_free [u] wire )
        }
        F e → {
            ( nurl_print `  serialise_err=` ) ( nurl_print ( ws_err_name e ) ) ( nurl_print `\n` )
            = fails + fails 1
        }
    }
    ( vec_free [u] hello )
    ^ fails
}

// ── §B masked empty + control frame format ────────────────────────────

@ section_b → i {
    ( nurl_print `--- B masked empty/control ---\n` )
    : ~ i fails 0
    // Empty text frame with key 0x01020304 → 81 80 01 02 03 04
    : ( Vec u ) empty ( vec_new [u] )
    : !( Vec u ) WsErr se ( ws_serialize_frame_masked T 1 empty 1 2 3 4 )
    ?? se {
        T wire → {
            : b ok ( vec_eq_hex wire `818001020304` )
            ( print_bool `empty_masked` ok )
            ? ! ok { = fails + fails 1 } {}
            ( vec_free [u] wire )
        }
        F _ → { = fails + fails 1 }
    }
    ( vec_free [u] empty )

    // Control frame (close, opcode 8) with FIN=0 must be rejected.
    : ( Vec u ) p ( bytes_from_str `x` )
    : !( Vec u ) WsErr sc ( ws_serialize_frame_masked F 8 p 0 0 0 0 )
    ?? sc {
        T w → { ( print_bool `ctl_fin0_rejected` F ) = fails + fails 1 ( vec_free [u] w ) }
        F _ → { ( print_bool `ctl_fin0_rejected` T ) }
    }
    ( vec_free [u] p )
    ^ fails
}

// ── §C URL parsing ────────────────────────────────────────────────────

@ check_url s url b want_ok b want_tls s want_host i want_port s want_path → i {
    : ?WsUrl pu ( __ws_parse_url url )
    : ~ i fails 0
    ?? pu {
        T u → {
            ? ! want_ok {
                ( print_bool `unexpected_parse_ok` F ) = fails + fails 1
            } {
                : b ok & & &
                ? . u tls want_tls ! want_tls
                != 0 ( nurl_str_eq ( string_data . u host ) want_host )
                == . u port want_port
                != 0 ( nurl_str_eq ( string_data . u path ) want_path )
                ( print_bool url ok )
                ? ! ok { = fails + fails 1 } {}
            }
            ( ws_url_free u )
        }
        F _ → {
            ? want_ok { ( print_bool url F ) = fails + fails 1 }
            { ( print_bool url T ) }
        }
    }
    ^ fails
}

@ section_c → i {
    ( nurl_print `--- C URL parsing ---\n` )
    : ~ i fails 0
    = fails + fails ( check_url `ws://example.com/ws` T F `example.com` 80 `/ws` )
    = fails + fails ( check_url `wss://example.com/chat` T T `example.com` 443 `/chat` )
    = fails + fails ( check_url `ws://127.0.0.1:9001/` T F `127.0.0.1` 9001 `/` )
    = fails + fails ( check_url `wss://host:8443/a/b` T T `host` 8443 `/a/b` )
    // No path → default "/"
    = fails + fails ( check_url `ws://h` T F `h` 80 `/` )
    // Bad scheme
    = fails + fails ( check_url `http://example.com/` F F `` 0 `` )
    ^ fails
}

// ── §D live loopback round-trip (NURL_NET_TESTS=1) ────────────────────

@ ws_echo_handler TcpConn conn WsMessage msg → !v WsErr {
    : i op . msg opcode
    ? == op ( ws_opcode_text ) {
        ^ ( ws_write_frame conn T ( ws_opcode_text ) . msg payload )
    } {
        ^ ( ws_send_binary conn . msg payload )
    }
}

@ serve_one_connection TcpConn conn → v {
    : ( Vec u ) carry ( vec_new [u] )
    : HttpLimits lim ( http_default_limits )
    : !ParsedHeadOk HttpReqErr ph ( __read_request_head conn carry lim )
    ?? ph {
        T pho → {
            : HttpRequest req . pho req
            ? ( ws_is_upgrade req ) {
                : !v WsErr hr ( ws_perform_handshake conn req )
                ?? hr {
                    T _ → {
                        : WsLimits wlim ( ws_default_limits )
                        : !v WsErr sr ( ws_serve_messages conn wlim
                        \ WsMessage msg → !v WsErr {
                            ^ ( ws_echo_handler conn msg )
                        } )
                        ?? sr { T _ → {} F _ → {} }
                    }
                    F _ → {}
                }
            } {}
            ( request_free req )
        }
        F _ → {}
    }
    ( vec_free [u] carry )
}

@ run_live_test → i {
    : ~ i fails 0
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18799 )
    ?? lr {
        T listener → {
            : ( @ v ) server_fn \ → v {
                : !TcpConn NetErr ar ( tcp_accept listener )
                ?? ar {
                    T conn → {
                        ( tcp_set_timeout conn 10000 )
                        ( serve_one_connection conn )
                        ( tcp_close_conn conn )
                    }
                    F _ → {}
                }
            }
            : !Thread ThreadErr st ( thread_spawn server_fn )
            ( sleep_ms 100 )

            : !WsClient WsErr cr ( ws_connect `ws://127.0.0.1:18799/ws` )
            ?? cr {
                T client → {
                    : TcpConn conn ( ws_client_conn client )
                    : WsLimits lim ( ws_default_limits )

                    // Text round-trip.
                    : !v WsErr s1 ( ws_client_send_text conn `hello-from-client` )
                    ?? s1 { T _ → {} F _ → { = fails + fails 1 } }
                    : !WsMessage WsErr m1 ( ws_client_read_message conn lim )
                    ?? m1 {
                        T msg → {
                            : b ok & == . msg opcode ( ws_opcode_text )
                            ( vec_eq_str . msg payload `hello-from-client` )
                            ( print_bool `text_echo` ok )
                            ? ! ok { = fails + fails 1 } {}
                            ( ws_message_free msg )
                        }
                        F e → {
                            ( nurl_print `  text_read_err=` ) ( nurl_print ( ws_err_name e ) ) ( nurl_print `\n` )
                            = fails + fails 1
                        }
                    }

                    // Binary round-trip.
                    : ( Vec u ) bin ( vec_new [u] )
                    ( vec_push [u] bin # u 1 ) ( vec_push [u] bin # u 2 )
                    ( vec_push [u] bin # u 253 ) ( vec_push [u] bin # u 0 )
                    : !v WsErr s2 ( ws_client_send_binary conn bin )
                    ?? s2 { T _ → {} F _ → { = fails + fails 1 } }
                    : !WsMessage WsErr m2 ( ws_client_read_message conn lim )
                    ?? m2 {
                        T msg → {
                            : b ok & == . msg opcode ( ws_opcode_binary )
                            & == ( vec_len [u] . msg payload ) 4
                            == & 255 # i . ( vec_data [u] . msg payload ) 2 253
                            ( print_bool `binary_echo` ok )
                            ? ! ok { = fails + fails 1 } {}
                            ( ws_message_free msg )
                        }
                        F _ → { = fails + fails 1 }
                    }
                    ( vec_free [u] bin )

                    // Close handshake.
                    : !v WsErr sc ( ws_client_send_close conn 1000 `bye` )
                    ?? sc { T _ → {} F _ → {} }
                    ( ws_client_close client )
                }
                F e → {
                    ( nurl_print `  connect_err=` ) ( nurl_print ( ws_err_name e ) ) ( nurl_print `\n` )
                    = fails + fails 1
                }
            }
            : i _sj ( thread_join_safe st )
            ( tcp_close_listener listener )
        }
        F e → {
            ( nurl_print `  listen_err=` ) ( nurl_print ( net_err_name e ) ) ( nurl_print `\n` )
            = fails + fails 1
        }
    }
    ^ fails
}

@ thread_join_safe ! Thread ThreadErr tr → i {
    ?? tr {
        T th → ( thread_join th )
        F _ → 0
    }
}

// Compare an owned Vec[u] against a raw string's bytes.
@ vec_eq_str ( Vec u ) got s want → b {
    : i n ( vec_len [u] got )
    : i wn ( nurl_str_len want )
    ? != n wn { ^ F } {}
    : *u p ( vec_data [u] got )
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k n {
        ? != & 255 # i . p k ( nurl_str_get want k ) { = ok F } {}
        = k + k 1
    }
    ^ ok
}

@ main → i {
    : ~ i fails 0
    = fails + fails ( section_a )
    = fails + fails ( section_b )
    = fails + fails ( section_c )
    : ?String gate ( env_get `NURL_NET_TESTS` )
    ?? gate {
        T s → {
            ( string_free s )
            = fails + fails ( run_live_test )
        }
        F → { ( nurl_print `live client test skipped (NURL_NET_TESTS != 1)\n` ) }
    }
    ? > fails 0 {
        : String m ( string_new )
        ( string_push_str m `FAILURES: ` )
        ( string_push_int m fails )
        ( string_push_char m 10 )
        ( nurl_print ( string_data m ) )
        ( string_free m )
    } { ( nurl_print `all offline assertions passed\n` ) }
    ^ fails
}
