// examples/ws_deflate_echo.nu — WebSocket echo server with
// permessage-deflate (RFC 7692) negotiation.
//
// Identical in shape to examples/ws_echo.nu, but the handshake offers
// permessage-deflate and, when the client accepts, every echoed message
// is compressed. Browsers (Chrome / Firefox / Safari) offer
// permessage-deflate by default, so a page doing
//
//   const ws = new WebSocket("ws://127.0.0.1:9002/");
//   ws.onopen = () => ws.send("hello".repeat(100));
//   ws.onmessage = (e) => console.log(e.data);
//
// exchanges compressed frames over the wire transparently.
//
// Run:
//   ./nurl.sh examples/ws_deflate_echo.nu /tmp/ws_deflate_echo && /tmp/ws_deflate_echo
//
// Shutdown: Ctrl+C (SIGINT) — the listener closes and the accept loop exits.

$ `stdlib/std/net.nu`
$ `stdlib/std/signal.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/websocket.nu`

@ serve_one_connection TcpConn conn → v {
    : ( Vec u ) carry ( vec_new [u] )
    : HttpLimits lim ( http_default_limits )
    : !ParsedHeadOk HttpReqErr ph ( __read_request_head conn carry lim )
    ?? ph {
        T pho → {
            : HttpRequest req . pho head
            ? ( ws_is_upgrade req ) {
                // Negotiate permessage-deflate (default policy: enabled,
                // full window, context takeover both directions).
                : !WsDeflate WsErr hr ( ws_perform_handshake_deflate conn req @ ?String { F } ( ws_deflate_default_config ) )
                ?? hr {
                    T dctx → {
                        : WsLimits wlim ( ws_default_limits )
                        ? ( ws_deflate_active dctx ) {
                            // Compressed session: echo each message back
                            // compressed, preserving its text/binary opcode.
                            : !v WsErr sr ( ws_serve_messages_deflate dctx conn wlim
                            \ WsMessage msg → !v WsErr {
                                ^ ( __ws_send_message_deflate dctx conn . msg opcode . msg payload F )
                            } )
                            ?? sr { T _ → {} F _ → {} }
                        } {
                            // Client declined the extension: plain echo.
                            : !v WsErr sr ( ws_serve_messages conn wlim
                            \ WsMessage msg → !v WsErr {
                                ^ ( ws_write_frame conn T . msg opcode . msg payload )
                            } )
                            ?? sr { T _ → {} F _ → {} }
                        }
                        ( ws_deflate_free dctx )
                    }
                    F _ → {}
                }
            } {
                : HttpResponse r400 ( response_text 400 `Not a WebSocket upgrade\n` )
                : ( Vec u ) wire ( response_serialize r400 )
                : !v NetErr _ww ( tcp_write_all conn wire )
                ?? _ww { T _ → {} F _ → {} }
                ( vec_free [u] wire )
                ( http_response_free r400 )
            }
            ( request_free req )
        }
        F _ → {}
    }
    ( vec_free [u] carry )
}

@ main → i {
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 9002 )
    ?? lr {
        T listener → {
            ( signal_install_shutdown listener )
            ( nurl_print `ws permessage-deflate echo server on 127.0.0.1:9002\n` )
            : ~ b done F
            ~ ! done {
                : !TcpConn NetErr ar ( tcp_accept listener )
                ?? ar {
                    T conn → {
                        ( tcp_set_timeout conn 30000 )
                        ( serve_one_connection conn )
                        ( tcp_close_conn conn )
                    }
                    F e → {
                        : s nm ( net_err_name e )
                        ? | != 0 ( nurl_str_eq nm `NetClosed` ) != 0 ( nurl_str_eq nm `NetAccept` ) {
                            = done T
                        } {
                            ( nurl_print `accept err: ` ) ( nurl_print nm ) ( nurl_print `\n` )
                            = done T
                        }
                    }
                }
            }
            ( tcp_close_listener listener )
        }
        F e → {
            ( nurl_print `bind failed: ` ) ( nurl_print ( net_err_name e ) ) ( nurl_print `\n` )
            ^ 1
        }
    }
    ^ 0
}
