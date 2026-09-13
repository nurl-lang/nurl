// Independent raw HTTP/2 peer: interleaved request/response DATA, informational
// headers, split final trailers, partial-frame deadline retention and reuse.
// requires: live
$ `stdlib/ext/http2_client.nu`
$ `stdlib/std/thread.nu`

@ expect b ok s label → i {
    ( nurl_print label ) ( nurl_print ? ok `=T\n` `=F\n` )
    ^ ? ok 0 1
}

@ send_frame TcpConn tcp i ft i flags i sid ( Vec u ) payload → v {
    : H2Frame frame @ H2Frame { ft flags sid payload }
    ?? ( h2_write_frame tcp frame 16384 ) { T _ → {} F _ → {} }
    ( h2_frame_free frame )
}

@ send_headers TcpConn tcp i sid i status s name s value b end → v {
    : ( Vec Header ) hs ( vec_new [Header] )
    ? > status 0 {
        : String number ( string_new )
        ( string_push_int number status )
        ( vec_push [Header] hs ( header_new `:status` ( string_data number ) ) )
        ( string_free number )
    } {}
    ( vec_push [Header] hs ( header_new name value ) )
    : ( Vec u ) block ( hpack_encode_headers hs )
    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
    ? end {
        // HEADERS(END_STREAM) + CONTINUATION(END_HEADERS), including an
        // empty first fragment. END_STREAM belongs to the HEADERS frame.
        ( send_frame tcp 1 1 sid ( vec_new [u] ) )
        ( send_frame tcp 9 4 sid block )
    } { ( send_frame tcp 1 4 sid block ) }
}

@ raw_peer TcpConn tcp → v {
    ( tcp_set_timeout tcp 3000 )
    ?? ( h2_read_preface tcp ) { T _ → {} F _ → { ^ } }
    : ( Vec H2Setting ) settings ( vec_new [H2Setting] )
    ?? ( h2_send_settings tcp settings ) { T _ → {} F _ → {} }
    ( vec_free [H2Setting] settings )
    : ~ b done F
    : ~ b first T
    ~ ! done {
        ?? ( h2_read_frame tcp 16384 ) {
            T frame → {
                : i sid . frame stream_id
                ? & == . frame frame_type 4 == 0 & . frame flags 1 {
                    ?? ( h2_send_settings_ack tcp ) { T _ → {} F _ → {} }
                } {}
                ? == . frame frame_type 0 {
                    ? first {
                        ( send_headers tcp sid 103 `link` `preload` F )
                        ( send_headers tcp sid 200 `content-type` `application/grpc` F )
                        ( send_frame tcp 0 0 sid ( bytes_from_str `early` ) )
                        = first F
                    } {
                        ? != 0 & . frame flags 1 {
                            ( send_headers tcp sid 0 `grpc-status` `0` T )
                        } {}
                    }
                } {}
                ? & == . frame frame_type 1 == sid 3 {
                    // Partial HEADERS frame, deliberately crossing the RPC
                    // deadline. Client must retain its prefix for stream 5.
                    : ( Vec Header ) hs ( vec_new [Header] )
                    ( vec_push [Header] hs ( header_new `:status` `200` ) )
                    : H2Frame reply @ H2Frame { 1 5 sid ( hpack_encode_headers hs ) }
                    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
                    ?? ( h2_serialize_frame reply 16384 ) {
                        T wire → {
                            : ( Vec u ) prefix ( vec_new [u] )
                            : ( Vec u ) tail ( vec_new [u] )
                            : *u p ( vec_data [u] wire )
                            : ~ i k 0
                            ~ < k ( vec_len [u] wire ) {
                                ? < k 4 { ( vec_push [u] prefix . p k ) }
                                { ( vec_push [u] tail . p k ) }
                                = k + k 1
                            }
                            ?? ( tcp_write_all tcp prefix ) { T _ → {} F _ → {} }
                            ( sleep_ms 100 )
                            ?? ( tcp_write_all tcp tail ) { T _ → {} F _ → {} }
                            ( vec_free [u] prefix ) ( vec_free [u] tail ) ( vec_free [u] wire )
                        }
                        F _ → {}
                    }
                    ( h2_frame_free reply )
                } {}
                ? & == . frame frame_type 1 == sid 5 {
                    ( send_headers tcp sid 200 `content-type` `application/grpc` F )
                    ( send_headers tcp sid 0 `grpc-status` `0` T )
                    = done T
                } {}
                ( h2_frame_free frame )
            }
            F _ → { = done T }
        }
    }
    ( tcp_close_conn tcp )
}

@ run_client H2Client c → i {
    : ~ i failures 0
    : ( Vec Header ) hs ( vec_new [Header] )
    : i sid ?? ( h2_client_open c `POST` `http` `localhost` `/svc/Call` hs ) {
        T id → id F _ → { ( vec_free [Header] hs ) ^ 1 }
    }
    : b early_take ?? ( h2_client_take_response c sid ) {
        T r → { ( http_response_free r ) F }
        F e → ?? e { H2CIncomplete → T _ → F }
    }
    = failures + failures ( expect early_take `incomplete_preserves_stream` )
    ?? ( h2_client_send c sid ( bytes_from_str `first` ) F ) { T _ → {} F _ → { = failures + failures 1 } }
    : ~ b received F
    : ~ i loops 0
    ~ & ! received < loops 20 {
        ?? ( h2_client_pump_once c ) { T _ → {} F _ → { ^ + failures 1 } }
        ?? ( h2_client_stream_state c sid ) {
            T s → { = received > ( vec_len [u] . s body ) 0 }
            F _ → {}
        }
        = loops + loops 1
    }
    ?? ( h2_client_take_data c sid ) {
        T bytes → {
            : String value ( string_from_bytes ( vec_data [u] bytes ) ( vec_len [u] bytes ) )
            = failures + failures ( expect != 0 ( nurl_str_eq ( string_data value ) `early` ) `response_before_request_end` )
            ( string_free value ) ( vec_free [u] bytes )
        }
        F _ → { = failures + failures 1 }
    }
    ?? ( h2_client_send c sid ( bytes_from_str `last` ) T ) { T _ → {} F _ → { = failures + failures 1 } }
    ?? ( h2_client_run_until_complete c ) { T _ → {} F _ → { ^ + failures 1 } }
    ?? ( h2_client_stream_state c sid ) {
        T s → {
            = failures + failures ( expect & & == . s status 200 . s trailers_done == ( vec_len [Header] . s headers ) 1 `final_headers_separate` )
            = failures + failures ( expect == ( vec_len [Header] . s trailers ) 1 `continuation_trailers` )
        }
        F _ → { = failures + failures 1 }
    }
    ?? ( h2_client_release_stream c sid ) { T _ → {} F _ → { = failures + failures 1 } }
    : i delayed ?? ( h2_client_open c `POST` `http` `localhost` `/svc/Slow` hs ) { T id → id F _ → { ^ + failures 1 } }
    ?? ( h2_client_set_stream_deadline c delayed + ( monotonic_ns ) 30000000 ) { T _ → {} F _ → {} }
    : i start ( monotonic_ns )
    ?? ( h2_client_run_until_complete c ) { T _ → {} F _ → { ^ + failures 1 } }
    : i elapsed - ( monotonic_ns ) start
    ?? ( h2_client_stream_state c delayed ) {
        T s → { = failures + failures ( expect & . s deadline_expired < elapsed 90000000 `absolute_deadline` ) }
        F _ → { = failures + failures 1 }
    }
    ?? ( h2_client_release_stream c delayed ) { T _ → {} F _ → {} }
    : i next ?? ( h2_client_open c `POST` `http` `localhost` `/svc/Next` hs ) { T id → id F _ → { ^ + failures 1 } }
    ( vec_free [Header] hs )
    ?? ( h2_client_run_until_complete c ) { T _ → {} F _ → { ^ + failures 1 } }
    ?? ( h2_client_stream_state c next ) {
        T s → { = failures + failures ( expect & == . s status 200 . s trailers_done `connection_reused_after_partial_deadline` ) }
        F _ → { = failures + failures 1 }
    }
    ^ failures
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
    : !Thread ThreadErr worker ( thread_spawn_owned \ → v {
        ?? ( tcp_accept listener ) { T tcp → { ( raw_peer tcp ) } F _ → {} }
    } )
    : ~ i failures 0
    ?? ( h2_client_connect_h2c `127.0.0.1` port ) {
        T c → { = failures ( run_client c ) ( h2_client_disconnect c ) }
        F _ → { = failures 1 }
    }
    ?? worker { T t → { : i ignored ( thread_join t ) } F _ → {} }
    ( tcp_close_listener listener )
    ^ failures
}
