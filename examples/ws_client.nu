// examples/ws_client.nu — minimal WebSocket client (RFC 6455).
//
// Dials a ws:// or wss:// endpoint, performs the HTTP Upgrade handshake
// (with a random Sec-WebSocket-Key + Sec-WebSocket-Accept validation),
// sends a text message, prints the echo, then closes.
//
// Pairs with examples/ws_echo.nu:
//   ./nurl.sh examples/ws_echo.nu   /tmp/ws_echo   && /tmp/ws_echo &
//   ./nurl.sh examples/ws_client.nu /tmp/ws_client && /tmp/ws_client
//
// The URL defaults to ws://127.0.0.1:9001/ (the ws_echo port). Pass a
// different ws://… / wss://… URL as argv[1].

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/websocket.nu`

@ print_payload s tag ( Vec u ) payload → v {
    : *u p ( vec_data [u] payload )
    : i n ( vec_len [u] payload )
    : String s ( string_from_bytes p n )
    ( nurl_print tag ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
    ( string_free s )
}

@ run s url → i {
    ( nurl_print `connecting to ` ) ( nurl_print url ) ( nurl_print `\n` )
    : !WsClient WsErr cr ( ws_connect url )
    ?? cr {
        T client → {
            ( nurl_print `handshake ok\n` )
            : TcpConn conn ( ws_client_conn client )
            : WsLimits lim ( ws_default_limits )

            : !v WsErr s1 ( ws_client_send_text conn `hello from the nurl websocket client` )
            ?? s1 {
                T _ → {}
                F e → {
                    ( nurl_print `send failed: ` ) ( nurl_print ( ws_err_name e ) ) ( nurl_print `\n` )
                    ( ws_client_close client )
                    ^ 1
                }
            }

            : !WsMessage WsErr mr ( ws_client_read_message conn lim )
            ?? mr {
                T msg → {
                    ( print_payload `echo: ` . msg payload )
                    ( ws_message_free msg )
                }
                F e → {
                    ( nurl_print `read failed: ` ) ( nurl_print ( ws_err_name e ) ) ( nurl_print `\n` )
                }
            }

            : !v WsErr _c ( ws_client_send_close conn 1000 `done` )
            ?? _c { T _ → {} F _ → {} }
            ( ws_client_close client )
            ^ 0
        }
        F e → {
            ( nurl_print `connect failed: ` ) ( nurl_print ( ws_err_name e ) ) ( nurl_print `\n` )
            ^ 1
        }
    }
}

@ main → i {
    ? > ( env_args_count ) 1 {
        : String u ( env_arg 1 )
        : i rc ( run ( string_data u ) )
        ( string_free u )
        ^ rc
    } {
        ^ ( run `ws://127.0.0.1:9001/` )
    }
}
