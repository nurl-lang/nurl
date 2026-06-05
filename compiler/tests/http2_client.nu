// http2_client.nu — regression for the native HTTP/2 CLIENT
// (stdlib/ext/http2_client.nu).
//
// Offline sections ASSERT (main returns the failure count, so a
// regression trips the run_tests baseline diff):
//   §A  Request header HPACK encode → decode round-trip + pseudo-header
//       ordering (RFC 7541 / RFC 9113 §8.3).
//   §B  https:// / http:// URL parsing (__h2_parse_url).
//
// Live section (gated on NURL_NET_TESTS=1) drives a real loopback
// round-trip against the in-repo h2c SERVER (http2_serve), proving the
// two interoperate AND exercising multiplexing — two concurrent streams
// on one connection:
//   §C  connect h2c → submit 2 requests → run → collect both responses.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http2_hpack.nu`
$ `stdlib/ext/http2_server.nu`
$ `stdlib/ext/http2_client.nu`

@ print_bool s tag b v → v {
    ( nurl_print tag ) ( nurl_print `=` )
    ( nurl_print ? v `T` `F` ) ( nurl_print `\n` )
}

// Borrowed value lookup by header name; `` when absent.
@ hdr_val ( Vec Header ) hs s name → s {
    : i n ( vec_len [Header] hs )
    : *Header hp ( vec_data [Header] hs )
    : ~ i k 0
    : ~ s found ``
    ~ < k n {
        : Header h . hp k
        ? != 0 ( nurl_str_eq ( string_data . h name ) name ) {
            = found ( string_data . h value )
        } {}
        = k + k 1
    }
    ^ found
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

// ── §A request header HPACK round-trip ────────────────────────────────

@ section_a → i {
    ( nurl_print `--- A request header round-trip ---\n` )
    : ~ i fails 0
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `:method` `GET` ) )
    ( vec_push [Header] hs ( header_new `:scheme` `https` ) )
    ( vec_push [Header] hs ( header_new `:authority` `example.com` ) )
    ( vec_push [Header] hs ( header_new `:path` `/foo` ) )
    ( vec_push [Header] hs ( header_new `x-test` `bar` ) )
    : ( Vec u ) block ( hpack_encode_headers hs )
    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
    : HpackDynTable dyn ( hpack_dyn_new 4096 )
    : !HpackDecoded HpackErr dr ( hpack_decode_block block dyn )
    ( vec_free [u] block )
    ?? dr {
        T dec → {
            : b ok & & & & & == ( vec_len [Header] . dec headers ) 5
            != 0 ( nurl_str_eq ( hdr_val . dec headers `:method` ) `GET` )
            != 0 ( nurl_str_eq ( hdr_val . dec headers `:scheme` ) `https` )
            != 0 ( nurl_str_eq ( hdr_val . dec headers `:authority` ) `example.com` )
            != 0 ( nurl_str_eq ( hdr_val . dec headers `:path` ) `/foo` )
            != 0 ( nurl_str_eq ( hdr_val . dec headers `x-test` ) `bar` )
            ( print_bool `req_hdr_roundtrip` ok )
            ? ! ok { = fails + fails 1 } {}
            // First field must be the :method pseudo-header (§8.3).
            : *Header hp0 ( vec_data [Header] . dec headers )
            : Header h0 . hp0 0
            : b pseudo_first != 0 ( nurl_str_eq ( string_data . h0 name ) `:method` )
            ( print_bool `pseudo_first` pseudo_first )
            ? ! pseudo_first { = fails + fails 1 } {}
            ( hpack_decoded_free dec )
        }
        F e → {
            ( nurl_print `  decode_err=` ) ( nurl_print ( hpack_err_name e ) ) ( nurl_print `\n` )
            = fails + fails 1
        }
    }
    ^ fails
}

// ── §B URL parsing ────────────────────────────────────────────────────

@ check_url s url b want_tls s want_host i want_port s want_path → b {
    : ?H2Url pu ( __h2_parse_url url )
    ?? pu {
        T u → {
            : b ok & & & == . u tls want_tls
            != 0 ( nurl_str_eq ( string_data . u host ) want_host )
            == . u port want_port
            != 0 ( nurl_str_eq ( string_data . u path ) want_path )
            ( __h2_url_free u )
            ^ ok
        }
        F _ → { ^ F }
    }
}

@ section_b → i {
    ( nurl_print `--- B url parsing ---\n` )
    : ~ i fails 0
    : b b1 ( check_url `https://example.com/foo` T `example.com` 443 `/foo` )
    ( print_bool `https_default_port` b1 )
    ? ! b1 { = fails + fails 1 } {}
    : b b2 ( check_url `http://localhost:8080/a/b` F `localhost` 8080 `/a/b` )
    ( print_bool `http_explicit_port` b2 )
    ? ! b2 { = fails + fails 1 } {}
    : b b3 ( check_url `https://h2.example` T `h2.example` 443 `/` )
    ( print_bool `https_default_path` b3 )
    ? ! b3 { = fails + fails 1 } {}
    : ?H2Url bad ( __h2_parse_url `ftp://nope` )
    : b b4 ?? bad { T u → { ( __h2_url_free u ) F } F _ → T }
    ( print_bool `bad_scheme_rejected` b4 )
    ? ! b4 { = fails + fails 1 } {}
    ^ fails
}

// ── §C live loopback (NURL_NET_TESTS=1) ───────────────────────────────

// Echo the request path back in the body so the client can tell the
// two multiplexed streams apart.
@ h2c_handler HttpRequest req → HttpResponse {
    : String b ( string_new )
    ( string_push_str b `ok:` )
    ( string_push_str b ( string_data . req path ) )
    : HttpResponse r ( response_text 200 ( string_data b ) )
    ( string_free b )
    ^ r
}

@ serve_one TcpConn conn → v {
    ( tcp_set_timeout conn 5000 )
    : ( @ HttpResponse HttpRequest ) h
    \ HttpRequest req → HttpResponse { ^ ( h2c_handler req ) }
    : !v H2ConnErr sr ( http2_serve conn h )
    ?? sr { T _ → {} F _ → {} }
    ( tcp_close_conn conn )
}

// One submitted request: check the response is 200 with body "ok:<path>".
@ check_resp H2Client client i sid s want_path → i {
    : !HttpResponse H2ClientErr tr ( h2_client_take_response client sid )
    ?? tr {
        T resp → {
            : String want ( string_new )
            ( string_push_str want `ok:` )
            ( string_push_str want want_path )
            : b ok & == . resp status 200 ( vec_eq_str . resp body ( string_data want ) )
            ( string_free want )
            ( print_bool `resp_ok` ok )
            ( http_response_free resp )
            ^ ? ok 0 1
        }
        F e → {
            ( nurl_print `  take_err=` ) ( nurl_print ( h2_client_err_name e ) ) ( nurl_print `\n` )
            ^ 1
        }
    }
}

@ run_live_test → i {
    : ~ i fails 0
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18811 )
    ?? lr {
        T listener → {
            : ( @ v ) server_fn \ → v {
                : !TcpConn NetErr ar ( tcp_accept listener )
                ?? ar {
                    T conn → { ( serve_one conn ) }
                    F _ → {}
                }
            }
            : !Thread ThreadErr st ( thread_spawn server_fn )
            ( sleep_ms 100 )

            : !H2Client H2ClientErr cr ( h2_client_connect_h2c `127.0.0.1` 18811 )
            ?? cr {
                T client → {
                    : ( Vec Header ) h1 ( vec_new [Header] )
                    : ( Vec u ) b1 ( vec_new [u] )
                    : !i H2ClientErr s1 ( h2_client_submit client `GET` `http`
                    `127.0.0.1` `/alpha` h1 b1 )
                    ( vec_free_with [Header] h1 \ Header hh → v { ( header_free hh ) } )

                    : ( Vec Header ) h2 ( vec_new [Header] )
                    : ( Vec u ) b2 ( vec_new [u] )
                    : !i H2ClientErr s2 ( h2_client_submit client `GET` `http`
                    `127.0.0.1` `/beta` h2 b2 )
                    ( vec_free_with [Header] h2 \ Header hh → v { ( header_free hh ) } )

                    ?? s1 {
                        T sid1 → {
                            ?? s2 {
                                T sid2 → {
                                    : b distinct != sid1 sid2
                                    ( print_bool `distinct_stream_ids` distinct )
                                    ? ! distinct { = fails + fails 1 } {}
                                    : !v H2ClientErr rr ( h2_client_run_until_complete client )
                                    ?? rr {
                                        T _ → {
                                            = fails + fails ( check_resp client sid1 `/alpha` )
                                            = fails + fails ( check_resp client sid2 `/beta` )
                                        }
                                        F e → {
                                            ( nurl_print `  run_err=` )
                                            ( nurl_print ( h2_client_err_name e ) )
                                            ( nurl_print `\n` )
                                            = fails + fails 1
                                        }
                                    }
                                }
                                F _ → { = fails + fails 1 }
                            }
                        }
                        F e → {
                            ( nurl_print `  submit_err=` )
                            ( nurl_print ( h2_client_err_name e ) )
                            ( nurl_print `\n` )
                            = fails + fails 1
                        }
                    }
                    ( h2_client_disconnect client )
                }
                F e → {
                    ( nurl_print `  connect_err=` )
                    ( nurl_print ( h2_client_err_name e ) )
                    ( nurl_print `\n` )
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

@ main → i {
    : ~ i fails 0
    = fails + fails ( section_a )
    = fails + fails ( section_b )
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
