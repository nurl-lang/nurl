// examples/ws_echo.nu — minimal WebSocket echo server (RFC 6455).
//
// Listens on 127.0.0.1:9001 (the canonical autobahn-testsuite port),
// performs the HTTP upgrade handshake, then echoes every text and
// binary message back to the peer until either end initiates close.
//
// Run:
//   ./nurl.sh examples/ws_echo.nu /tmp/ws_echo && /tmp/ws_echo
//
// Test (Autobahn):
//   docker run --rm --network host -v "$PWD/autobahn/config:/config" \
//     -v "$PWD/autobahn/reports:/reports" \
//     crossbario/autobahn-testsuite \
//     wstest -m fuzzingclient -s /config/fuzzingclient.json
//
// Shutdown: Ctrl+C (SIGINT) — the listener closes and the accept
// loop exits.

$ `stdlib/std/net.nu`
$ `stdlib/std/signal.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/websocket.nu`

@ ws_echo_handler TcpConn conn WsMessage msg → ! v WsErr {
    : i op . msg opcode
    ? == op ( ws_opcode_text ) {
        // Echo the raw bytes verbatim — RFC 6455 §8.1 already validates
        // the payload is UTF-8 inside ws_read_message, so re-emitting
        // as text is safe.
        ^ ( ws_write_frame conn T ( ws_opcode_text ) . msg payload )
    } {
        ? == op ( ws_opcode_binary ) {
            ^ ( ws_send_binary conn . msg payload )
        } {
            // Should not happen — ws_read_message only surfaces text /
            // binary messages; control frames are handled inside the loop.
            ^ @ ! v WsErr { T 0 }
        }
    }
}

@ serve_one_connection TcpConn conn → v {
    // Read the HTTP upgrade request through the existing server-side
    // carry-buffer pipeline.
    : ( Vec u ) carry ( vec_new [u] )
    : HttpLimits lim ( http_default_limits )
    : ! ParsedHeadOk HttpReqErr ph ( __read_request_head conn carry lim )
    ?? ph {
        T pho → {
            : HttpRequest req . pho req
            ? ( ws_is_upgrade req ) {
                // Inline equivalent of ws_perform_handshake so we
                // control the construction order of the ?String
                // subprotocol argument.
                : ! HttpResponse WsErr rr
                    ( ws_handshake_response_for req @ ?String { F # String 0 } )
                ?? rr {
                    T resp → {
                        : ( Vec u ) wire ( response_serialize resp )
                        : !v NetErr wr ( tcp_write_all conn wire )
                        ?? wr { T _ → {} F _ → {} }
                        ( vec_free [u] wire )
                        // NOTE: deliberately not freeing `resp` — auto-
                        // drop interaction with the manually-constructed
                        // ?String F-arm placeholder triggers a misaligned
                        // ctl read at scope exit. The struct fields are
                        // small (i + Vec[Header] + Vec[u], total 24 bytes
                        // beyond the headers/body allocations) and the
                        // server is a one-handshake-per-connection design
                        // so the per-connection leak is bounded.
                        : WsLimits wlim ( ws_default_limits )
                        : ! v WsErr sr ( ws_serve_messages conn wlim
                            \ WsMessage msg → ! v WsErr {
                                ^ ( ws_echo_handler conn msg )
                            } )
                        ?? sr { T _ → {} F _ → {} }
                    }
                    F _ → {}
                }
            } {
                // Not an upgrade: reply 400 and close.
                : HttpResponse r400 ( response_text 400 `Not a WebSocket upgrade\n` )
                : ( Vec u ) wire ( response_serialize r400 )
                : !v NetErr _ww ( tcp_write_all conn wire )
                ?? _ww { T _ → {} F _ → {} }
                ( vec_free [u] wire )
                ( http_response_free r400 )
            }
            ( request_free req )
        }
        F _ → {}  // Bad / truncated request — silently drop.
    }
    ( vec_free [u] carry )
}

@ main → i {
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 9001 )
    ?? lr {
        T listener → {
            ( signal_install_shutdown listener )
            ( nurl_print `ws echo server listening on 127.0.0.1:9001\n` )
            : ~ b done F
            ~ ! done {
                : !TcpConn NetErr ar ( tcp_accept listener )
                ?? ar {
                    T conn → {
                        // Autobahn's fuzzing client runs ~520 cases
                        // sequentially; a generous per-conn timeout
                        // is fine because individual cases either
                        // complete fast OR exit on the autobahn end.
                        ( tcp_set_timeout conn 30000 )
                        ( serve_one_connection conn )
                        ( tcp_close_conn conn )
                    }
                    F e → {
                        : s nm ( net_err_name e )
                        ? | != 0 ( nurl_str_eq nm `NetClosed` )
                          != 0 ( nurl_str_eq nm `NetAccept` ) {
                            = done T
                        } {
                            ( nurl_print `accept err: ` )
                            ( nurl_print nm )
                            ( nurl_print `\n` )
                            = done T
                        }
                    }
                }
            }
            ( tcp_close_listener listener )
        }
        F e → {
            ( nurl_print `bind failed: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
            ^ 1
        }
    }
    ^ 0
}
