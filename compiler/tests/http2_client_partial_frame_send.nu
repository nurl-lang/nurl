// A partial inbound frame must not stop the client sending.
//
// The peer grants a large window and, once the client's request body is
// flowing (its first DATA frame has arrived), sends the first 12 bytes of a
// PING frame — the 9-byte header and 3 of its 8 payload bytes — as a
// segment of their own, and withholds the rest until it has received the
// client's whole 2 MiB request body. A client
// that, mid-frame, parks for readability alone while request body is still
// sendable waits for bytes the peer will only send after that body: a duplex
// deadlock, broken only by the idle timeout. The client must keep the body
// moving while it waits for the rest of the frame.
//
// This is the deterministic form of what compiler/tests/http2_client_duplex
// hit intermittently under load once TCP_NODELAY made partial frames common
// (agora #98).
// requires: live
$ `stdlib/ext/http2_client.nu`
$ `stdlib/std/thread.nu`

: ~ i g_body 2097152

@ note s label b value → b {
    ? ! value { ( nurl_print label ) ( nurl_print `=F\n` ) } {}
    ^ value
}

@ word i value → ( Vec u ) {
    : ( Vec u ) bytes ( vec_new [u] )
    ( bytes_push_u32_be bytes # u32 value )
    ^ bytes
}

// The raw bytes of a PING frame (type 6, stream 0, eight opaque bytes),
// header included, so the peer can send it in two pieces.
@ ping_bytes → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 0 ) ( vec_push [u] b # u 0 ) ( vec_push [u] b # u 8 )
    ( vec_push [u] b # u 6 ) ( vec_push [u] b # u 0 )
    ( bytes_push_u32_be b # u32 0 )
    : ~ i k 0
    ~ < k 8 { ( vec_push [u] b # u + 49 k ) = k + k 1 }
    ^ b
}

@ write_all TcpConn tcp ( Vec u ) bytes → b {
    ^ ?? ( tcp_write_all tcp bytes ) { T _ → T F _ → F }
}

@ send_frame TcpConn tcp i ft i flags i sid ( Vec u ) payload → b {
    : H2Frame f @ H2Frame { ft flags sid payload }
    : b ok ?? ( h2_write_frame tcp f 16384 ) { T _ → T F _ → F }
    ( h2_frame_free f )
    ^ ok
}

@ peer TcpConn tcp ( Locked i ) outcome → v {
    ( tcp_set_timeout tcp 20000 )
    : ~ b ok T
    ?? ( h2_read_preface tcp ) { T _ → {} F _ → { = ok F } }
    : ( Vec H2Setting ) settings ( vec_new [H2Setting] )
    ( vec_push [H2Setting] settings @ H2Setting { 4 4194304 } )
    ?? ( h2_send_settings tcp settings ) { T _ → {} F _ → { = ok F } }
    ( vec_free [H2Setting] settings )
    = ok & ok ( send_frame tcp 8 0 0 ( word 4128769 ) )
    : ( Vec u ) ping ( ping_bytes )
    : ~ b ping_started F
    // Take the whole request before sending the rest of the PING.
    : ~ i received 0
    : ~ b request_end F
    : ( Vec u ) rx ( vec_new [u] )
    ~ & ok ! request_end {
        ?? ( h2_read_frame_buf tcp rx 16384 ) {
            T frame → {
                ?? . frame frame_type {
                    4 → {
                        ? == 0 & . frame flags 1 { = ok & ok ( send_frame tcp 4 1 0 ( vec_new [u] ) ) } {}
                    }
                    0 → {
                        = received + received ( vec_len [u] . frame payload )
                        ? != 0 & . frame flags 1 { = request_end T } {}
                        // Mid-body: the first 12 bytes of a PING, a frame
                        // the client starts and cannot finish until the
                        // peer chooses to send the rest.
                        ? ! ping_started {
                            = ping_started T
                            = ok & ok ( write_all tcp ( bytes_slice ping 0 12 ) )
                        } {}
                    }
                    _ → {}
                }
                ( h2_frame_free frame )
            }
            F _ → { = ok F }
        }
    }
    // Now finish the PING and answer: HEADERS :status 200, END_STREAM.
    = ok & ok ( write_all tcp ( bytes_slice ping 12 17 ) )
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `:status` `200` ) )
    = ok & ok ( send_frame tcp 1 5 1 ( hpack_encode_headers hs ) )
    ( vec_free [Header] hs )
    : b complete & ok == received g_body
    ? ! complete {
        ( note `peer_ok` ok )
        ( note `peer_received_all` == received g_body )
    } {}
    ( locked_set [i] outcome ? complete 1 0 )
    // Drain until the client closes, so control frames still in flight are
    // not answered with a reset.
    : ~ b drained F
    ~ ! drained {
        ?? ( h2_read_frame_buf tcp rx 16384 ) {
            T frame → { ( h2_frame_free frame ) }
            F _ → { = drained T }
        }
    }
    ( vec_free [u] rx ) ( tcp_close_conn tcp )
}

@ main → i {
    : TcpListener listener ?? ( tcp_listen `127.0.0.1` 0 ) { T l → l F _ → { ^ 1 } }
    : String address ( tcp_local_addr listener )
    : ~ i port 0
    : ~ i k 0
    ~ < k ( string_len address ) {
        : i ch ( string_get address k )
        ? == ch 58 { = port 0 } { ? & >= ch 48 <= ch 57 { = port + * port 10 - ch 48 } {} }
        = k + k 1
    }
    ( string_free address )
    : ( Locked i ) outcome ( locked_new [i] 0 )
    : !Thread ThreadErr worker ( thread_spawn_owned \ → v {
        ?? ( tcp_accept listener ) { T tcp → { ( peer tcp outcome ) } F _ → {} }
    } )
    : ~ b ok T
    ?? ( h2_client_connect_h2c `127.0.0.1` port ) {
        T client → {
            : ( Vec Header ) headers ( vec_new [Header] )
            : ( Vec u ) request ( vec_with_cap [u] g_body )
            = k 0
            ~ < k g_body { ( vec_push [u] request # u 65 ) = k + k 1 }
            ?? ( h2_client_submit client `POST` `http` `localhost` `/partial` headers request ) {
                T sid → {
                    ?? ( h2_client_run_until_complete client ) {
                        T _ → {
                            ?? ( h2_client_take_response client sid ) {
                                T response → {
                                    = ok & ok == . response status 200
                                    ( http_response_free response )
                                }
                                F e → {
                                    ( nurl_print `client_take_response=` ) ( nurl_print ( h2_client_err_name e ) ) ( nurl_print `\n` )
                                    = ok F
                                }
                            }
                        }
                        F e → {
                            ( nurl_print `client_run=` ) ( nurl_print ( h2_client_err_name e ) ) ( nurl_print `\n` )
                            = ok F
                        }
                    }
                }
                F _ → { = ok F }
            }
            ( vec_free [Header] headers ) ( h2_client_disconnect client )
        }
        F _ → { = ok F }
    }
    ?? worker { T thread → { : i ignored ( thread_join thread ) } F _ → { = ok F } }
    : b final & ok == ( locked_get [i] outcome ) 1
    ? ! final {
        ( note `client_ok` ok )
        ( note `peer_outcome` == ( locked_get [i] outcome ) 1 )
    } {}
    ( tcp_close_listener listener )
    ( nurl_print ? final `partial_frame_send=T\n` `partial_frame_send=F\n` )
    ^ ? final 0 1
}
