// tests/ws_client.nu — a WebSocket client for the serve tests, in NURL.
//
//   ws_client ws://127.0.0.1:PORT/ <audio.wav>
//
// Connects with stdlib's OWN RFC 6455 client (the server is stdlib's server —
// both ends of the protocol are the same implementation under test), sends a
// config message, streams the WAV as PCM16 in half-second chunks with two
// seconds of silence after it (the VAD needs a pause to close the utterance),
// prints every JSON message the server sends, then closes.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/args.nu`
$ `deps/audio/src/wav.nu`
$ `deps/audio/src/resample.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/websocket.nu`

@ __wsc_send_chunk TcpConn conn ( Vec f ) x i from i n → b {
    : ( Vec u ) d ( vec_new [u] )
    : ~ i k 0
    ~ < k n {
        : ~ f v 0.0
        ?? ( vec_get [f] x + from k ) { T s → { = v s } F → {} }
        : ~ i q # i * v 32767.0
        ? > q 32767 { = q 32767 } {}
        ? < q -32768 { = q -32768 } {}
        ? < q 0 { = q + q 65536 } {}
        ( vec_push [u] d # u & q 255 )
        ( vec_push [u] d # u & >> q 8 255 )
        = k + k 1
    }
    : ~ b ok T
    ?? ( ws_client_send_binary conn d ) { T _ → {} F _ → { = ok F } }
    ( vec_free [u] d )
    ^ ok
}

@ main → i {
    : ArgParser p ( args_new `ws_client` `` )
    ? ( args_parse_argv p ) {} { ^ 2 }
    : ( Vec String ) pos ( args_positionals p )
    : ~ s url ``
    : ~ s wavpath ``
    ?? ( vec_get [String] pos 0 ) { T c → { = url ( string_data c ) } F → {} }
    ?? ( vec_get [String] pos 1 ) { T c → { = wavpath ( string_data c ) } F → {} }

    ?? ( ws_connect url ) {
        T cl → {
            : TcpConn conn ( ws_client_conn cl )
            : WsLimits lim ( ws_default_limits )

            // config first: pcm16 (the default — the ack proves the round trip)
            : !v WsErr _s ( ws_client_send_text conn `{"format":"pcm16"}` )
            ?? ( ws_client_read_message conn lim ) {
                T ack → {
                    : String am ( string_new )
                    : ~ i k 0
                    ~ < k ( vec_len [u] . ack payload ) {
                        ?? ( vec_get [u] . ack payload k ) {
                            T ch → { ( string_push_char am ch ) }
                            F → {}
                        }
                        = k + k 1
                    }
                    ( nurl_print ( string_data am ) ) ( nurl_print `\n` )
                    ( string_free am )
                    ( vec_free [u] . ack payload )
                }
                F _ → {}
            }

            ?? ( wav_read wavpath ) {
                T aw → {
                    : ( Vec f ) mono ( wav_mono aw )
                    : ( Vec f ) at16 ( resample mono . aw rate 16000 )
                    ( wav_free aw )
                    ( vec_free [f] mono )
                    : i n ( vec_len [f] at16 )
                    : ~ i off 0
                    ~ < off n {
                        : ~ i take 8000
                        ? > + off take n { = take - n off } {}
                        : b _ok ( __wsc_send_chunk conn at16 off take )
                        = off + off take
                    }
                    // two seconds of the room being quiet, so the VAD closes
                    // the utterance while the socket is still open
                    : ( Vec f ) quiet ( vec_new [f] )
                    : ~ i q 0
                    ~ < q 8000 { ( vec_push [f] quiet 0.0001 ) = q + q 1 }
                    : ~ i r 0
                    ~ < r 4 {
                        : b _q ( __wsc_send_chunk conn quiet 0 8000 )
                        = r + r 1
                    }
                    ( vec_free [f] quiet )
                    ( vec_free [f] at16 )

                    // done sending: initiate the close handshake. The server
                    // flushes an open utterance, sends its text, THEN answers
                    // the close — so read until the close comes back.
                    : !v WsErr _cl ( ws_client_send_close conn 1000 `done` )
                    : ~ b reading T
                    ~ reading {
                        ?? ( ws_client_read_message conn lim ) {
                            T msg → {
                                : String tm ( string_new )
                                : ~ i k 0
                                ~ < k ( vec_len [u] . msg payload ) {
                                    ?? ( vec_get [u] . msg payload k ) {
                                        T ch → { ( string_push_char tm ch ) }
                                        F → {}
                                    }
                                    = k + k 1
                                }
                                ( nurl_print ( string_data tm ) ) ( nurl_print `\n` )
                                ( string_free tm )
                                ( vec_free [u] . msg payload )
                            }
                            F _ → { = reading F }
                        }
                    }
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) )
                    ( string_free e )
                }
            }
            ( ws_client_close cl )
        }
        F _ → {
            ( nurl_eprintln `cannot connect` )
            ( args_free p )
            ^ 1
        }
    }
    ( args_free p )
    ^ 0
}
