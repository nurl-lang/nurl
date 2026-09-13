// HTTP/2 client validates connection and stream state before accepting DATA
// or expanding send windows. A raw peer deliberately violates each invariant.
// requires: live
$ `stdlib/ext/http2_client.nu`
$ `stdlib/std/thread.nu`

@ check b ok s label → i {
    ( nurl_print label ) ( nurl_print ? ok `=T\n` `=F\n` )
    ^ ? ok 0 1
}

@ wire TcpConn tcp i ft i flags i sid ( Vec u ) body → v {
    : H2Frame f @ H2Frame { ft flags sid body }
    ?? ( h2_write_frame tcp f 16384 ) { T _ → {} F _ → {} }
    ( h2_frame_free f )
}

@ attack_peer TcpConn tcp i scenario → v {
    ( tcp_set_timeout tcp 2000 )
    ?? ( h2_read_preface tcp ) { T _ → {} F _ → {} }
    : ( Vec H2Setting ) settings ( vec_new [H2Setting] )
    ?? ( h2_send_settings tcp settings ) { T _ → {} F _ → {} }
    ( vec_free [H2Setting] settings )
    : ~ b ready F
    ~ ! ready {
        ?? ( h2_read_frame tcp 16384 ) {
            T f → { = ready == . f frame_type 1 ( h2_frame_free f ) }
            F _ → { = ready T }
        }
    }
    ?? scenario {
        0 → {
            : ( Vec u ) payload ( vec_new [u] )
            ( bytes_push_u32_be payload # u32 0 )
            ( wire tcp 8 0 0 payload )
        }
        1 → {
            : ( Vec u ) payload ( vec_new [u] )
            ( bytes_push_u32_be payload # u32 2147483647 )
            ( wire tcp 8 0 0 payload )
        }
        2 → { ( wire tcp 0 1 1 ( bytes_from_str `unexpected` ) ) }
        3 → {
            : ( Vec Header ) hs ( vec_new [Header] )
            ( vec_push [Header] hs ( header_new `:status` `200x` ) )
            ( wire tcp 1 5 1 ( hpack_encode_headers hs ) )
            ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
        }
        4 → {
            : ( Vec Header ) hs ( vec_new [Header] )
            ( vec_push [Header] hs ( header_new `:status` `200` ) )
            ( wire tcp 1 4 1 ( hpack_encode_headers hs ) )
            ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
            ( wire tcp 0 0 1 ( bytes_from_str `123456789` ) )
            ?? ( h2_read_frame tcp 16384 ) { T f → { ( h2_frame_free f ) } F _ → {} }
        }
        _ → {
            : ( Vec Header ) hs ( vec_new [Header] )
            ( vec_push [Header] hs ( header_new `:status` ? == scenario 6 `204` `200` ) )
            ? != scenario 6 {
                ( vec_push [Header] hs ( header_new `content-length` ? == scenario 5 `2` `1` ) )
            } {}
            ( wire tcp 1 ? == scenario 7 5 4 1 ( hpack_encode_headers hs ) )
            ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
            ? != scenario 7 { ( wire tcp 0 1 1 ( bytes_from_str `123` ) ) } {}
        }
    }
    ( tcp_close_conn tcp )
}

@ trial i scenario → b {
    : TcpListener listener ?? ( tcp_listen `127.0.0.1` 0 ) { T l → l F _ → { ^ F } }
    : String address ( tcp_local_addr listener )
    : ~ i port 0
    : ~ i k 0
    ~ < k ( string_len address ) {
        : i ch ( string_get address k )
        ? == ch 58 { = port 0 } { ? & >= ch 48 <= ch 57 { = port + * port 10 - ch 48 } {} }
        = k + k 1
    }
    ( string_free address )
    : !Thread ThreadErr worker ( thread_spawn_owned \ → v {
        ?? ( tcp_accept listener ) { T tcp → { ( attack_peer tcp scenario ) } F _ → {} }
    } )
    : ~ b ok F
    ?? ( h2_client_connect_h2c `127.0.0.1` port ) {
        T c → {
            ?? ( h2_client_set_limits c 16 8 2 ) { T _ → {} F _ → {} }
            : ( Vec Header ) hs ( vec_new [Header] )
            ?? ( h2_client_open c `POST` `http` `localhost` `/test` hs ) {
                T sid → {
                    : !v H2ClientErr run ( h2_client_run_until_complete c )
                    ?? run {
                        F e → {
                            = ok ?? scenario {
                                0 → ?? e { H2CProtocol → T _ → F }
                                1 → ?? e { H2CFlowControl → T _ → F }
                                2 → ?? e { H2CProtocol → T _ → F }
                                3 → ?? e { H2CProtocol → T _ → F }
                                _ → & >= scenario 5 ?? e { H2CProtocol → T _ → F }
                            }
                        }
                        T _ → {
                            ?? ( h2_client_stream_state c sid ) {
                                T s → { = ok & == scenario 4 == . s rst_code ( h2_err_enhance_your_calm ) }
                                F _ → {}
                            }
                        }
                    }
                }
                F _ → {}
            }
            ( vec_free [Header] hs )
            ( h2_client_disconnect c )
        }
        F _ → {}
    }
    ?? worker { T t → { : i ignored ( thread_join t ) } F _ → {} }
    ( tcp_close_listener listener )
    ^ ok
}

@ main → i {
    : ~ i failures 0
    = failures + failures ( check ( trial 0 ) `zero_window_rejected` )
    = failures + failures ( check ( trial 1 ) `window_overflow_rejected` )
    = failures + failures ( check ( trial 2 ) `data_before_headers_rejected` )
    = failures + failures ( check ( trial 3 ) `malformed_status_rejected` )
    = failures + failures ( check ( trial 4 ) `receive_buffer_limit_resets_stream` )
    = failures + failures ( check ( trial 5 ) `content_length_mismatch_rejected` )
    = failures + failures ( check ( trial 6 ) `data_forbidden_status_rejected` )
    = failures + failures ( check ( trial 7 ) `headers_only_length_mismatch_rejected` )
    ^ failures
}
