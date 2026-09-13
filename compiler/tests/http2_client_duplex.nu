// Simultaneous 1 MiB request/response with 4 KiB socket send buffers and large
// peer flow windows. Neither endpoint can finish writing before reading. This
// exercises persistent frame offsets, not a timeout escape from a deadlock.
//
// What it does NOT assert is that a short write was observed. Whether a
// given flush comes back partial is the kernel's socket-buffer accounting
// talking, not this stack's: with the same 4 KiB SO_SNDBUF the exchange
// goes partial on Linux and completes whole on macOS, and a golden is one
// file for all three unixes. Handling a partial write is pinned where it
// can be made to happen on purpose — tools/net_write_deadline.nu, whose
// peer stops reading — and what stays here is the part that is the same
// everywhere: a megabyte crosses in each direction and both ends finish.
// requires: live
$ `stdlib/ext/http2_client.nu`
$ `stdlib/std/thread.nu`

// Name the failing half on the way out — only when something failed, so the
// recorded output stays identical on every platform. A bare T/F golden says
// a duplex exchange went wrong somewhere in a megabyte, which is the same
// report for a rejected socket option and for a stalled write loop.
@ note s label b value → b {
    ? ! value { ( nurl_print label ) ( nurl_print `=F\n` ) } {}
    ^ value
}

// A stall has a shape: how far each side got, and what it was waiting for.
@ count s label i value → v {
    ( nurl_print label ) ( nurl_print `=` )
    ( nurl_print ( nurl_str_int value ) ) ( nurl_print `\n` )
}

@ small_send_buffer TcpConn tcp → b {
    : b zero ?? ( tcp_set_send_buffer tcp 0 ) { T _ → F F _ → T }
    : b negative ?? ( tcp_set_send_buffer tcp -1 ) { T _ → F F _ → T }
    : b overflow ?? ( tcp_set_send_buffer tcp 2147483648 ) { T _ → F F _ → T }
    : b valid ?? ( tcp_set_send_buffer tcp 4096 ) { T _ → T F _ → F }
    ( note `sndbuf_rejects_zero` zero )
    ( note `sndbuf_rejects_negative` negative )
    ( note `sndbuf_rejects_overflow` overflow )
    ( note `sndbuf_accepts_4096` valid )
    ^ & & zero negative & overflow valid
}

@ queue H2FrameWriter writer i ft i flags i sid ( Vec u ) bytes → b {
    : H2Frame frame @ H2Frame { ft flags sid bytes }
    : b ok ?? ( h2_frame_writer_queue writer frame 16384 ) { T _ → T F _ → F }
    ( h2_frame_free frame )
    ^ ok
}

@ word i value → ( Vec u ) {
    : ( Vec u ) bytes ( vec_new [u] )
    ( bytes_push_u32_be bytes # u32 value )
    ^ bytes
}

@ read_word ( Vec u ) bytes → i {
    : *u p ( vec_data [u] bytes )
    ^ + + + << # i . p 0 24 << # i . p 1 16 << # i . p 2 8 # i . p 3
}

@ buffered_frame ( Vec u ) bytes → b {
    ? < ( vec_len [u] bytes ) 9 { ^ F } {}
    : *u p ( vec_data [u] bytes )
    : i length + + << # i . p 0 16 << # i . p 1 8 # i . p 2
    ^ >= ( vec_len [u] bytes ) + 9 length
}

@ peer TcpConn tcp ( Vec i ) outcome → v {
    : ~ b ok ( small_send_buffer tcp )
    ( tcp_set_timeout tcp 5000 )
    ?? ( h2_read_preface tcp ) { T _ → {} F _ → { = ok F } }
    : ( Vec H2Setting ) settings ( vec_new [H2Setting] )
    ( vec_push [H2Setting] settings @ H2Setting { 4 4194304 } )
    ?? ( h2_send_settings tcp settings ) { T _ → {} F _ → { = ok F } }
    ( vec_free [H2Setting] settings )
    : H2FrameWriter writer ( h2_frame_writer tcp 1048576 )
    = ok & ok ( queue writer 8 0 0 ( word 4128769 ) )
    : ( Vec u ) rx ( vec_new [u] )
    : ~ i received 0
    : ~ i sent 0
    : ~ i conn_credit 65535
    : ~ i stream_credit 65535
    : ~ b headers F
    : ~ b request_end F
    : ~ b response_end F
    : ~ b pressure F
    : i deadline + ( monotonic_ns ) 10000000000
    ~ & & ok ! response_end < ( monotonic_ns ) deadline {
        // Fill a bounded burst before flushing. A single frame can fit into
        // the kernel even with SO_SNDBUF=4096 and a fast loopback reader,
        // which would make the backpressure assertion depend on scheduling.
        ~ & & headers < sent 1048576 & < ( h2_frame_writer_pending writer ) 65536
        & > conn_credit 0 > stream_credit 0 {
            : i credit ? < conn_credit stream_credit conn_credit stream_credit
            : i remaining - 1048576 sent
            : i cap ? < remaining 16384 remaining 16384
            : i size ? < cap credit cap credit
            ? > size 0 {
                : ( Vec u ) data ( vec_with_cap [u] size )
                : ~ i k 0
                ~ < k size { ( vec_push [u] data # u 66 ) = k + k 1 }
                = ok & ok ( queue writer 0 0 1 data )
                = sent + sent size = conn_credit - conn_credit size = stream_credit - stream_credit size
            } {}
        }
        ? & request_end == sent 1048576 {
            = ok & ok ( queue writer 0 1 1 ( vec_new [u] ) )
            = response_end T
        } {}
        ?? ( h2_frame_writer_flush writer ) { T _ → {} F _ → { = ok F } }
        ? > ( h2_frame_writer_pending writer ) 0 { = pressure T } {}
        // Readiness refers to socket bytes, not the retained frame buffer.
        // Never park in a blocking frame read while our writer needs progress.
        ? < ( vec_len [u] rx ) 65536 {
            ?? ( tcp_try_read_into tcp rx - 65536 ( vec_len [u] rx ) ) {
                T _ → {} F _ → { = ok F }
            }
        } {}
        ? ( buffered_frame rx ) {
            ?? ( h2_read_frame_buf tcp rx 16384 ) {
                T frame → {
                    ?? . frame frame_type {
                        4 → {
                            ? == 0 & . frame flags 1 { = ok & ok ( queue writer 4 1 0 ( vec_new [u] ) ) } {}
                        }
                        1 → {
                            : ( Vec Header ) hs ( vec_new [Header] )
                            ( vec_push [Header] hs ( header_new `:status` `200` ) )
                            = ok & ok ( queue writer 1 4 1 ( hpack_encode_headers hs ) )
                            ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
                            = headers T
                        }
                        0 → {
                            = received + received ( vec_len [u] . frame payload )
                            ? != 0 & . frame flags 1 { = request_end T } {}
                        }
                        8 → {
                            : i increment & 2147483647 ( read_word . frame payload )
                            ? == . frame stream_id 0 { = conn_credit + conn_credit increment }
                            { = stream_credit + stream_credit increment }
                        }
                        _ → {}
                    }
                    ( h2_frame_free frame )
                }
                F _ → { = ok F }
            }
        } {
            ? | > ( h2_frame_writer_pending writer ) 0
            | ! headers <= ? < conn_credit stream_credit conn_credit stream_credit 0 {
                : i ready ( tcp_wait_io tcp T > ( h2_frame_writer_pending writer ) 0 100 )
                ? < ready 0 { = ok F } {}
            } {}
        }
    }
    ~ & & ok > ( h2_frame_writer_pending writer ) 0 < ( monotonic_ns ) deadline {
        ?? ( h2_frame_writer_flush writer ) { T _ → {} F _ → { = ok F } }
        ? > ( h2_frame_writer_pending writer ) 0 { : i ready ( tcp_wait_io tcp T T 100 ) } {}
    }
    : b complete & & ok == received 1048576 response_end
    ? ! complete {
        ( note `peer_ok` ok )
        ( note `peer_received_all` == received 1048576 )
        ( note `peer_sent_end_stream` response_end )
        ( note `peer_saw_backpressure` pressure )
        ( note `peer_saw_headers` headers )
        ( note `peer_saw_request_end` request_end )
        ( count `peer_received` received )
        ( count `peer_sent` sent )
        ( count `peer_conn_credit` conn_credit )
        ( count `peer_stream_credit` stream_credit )
        ( count `peer_write_pending` ( h2_frame_writer_pending writer ) )
        ( count `peer_rx_buffered` ( vec_len [u] rx ) )
    } {}
    ( vec_set [i] outcome 0 ? complete 1 0 )
    // A completed response can leave WINDOW_UPDATE frames in flight. Drain
    // until the client closes, so closing this raw test peer does not reset
    // the socket while those legitimate control frames are being delivered.
    : ~ b drained F
    ~ ! drained {
        ?? ( h2_read_frame_buf tcp rx 16384 ) {
            T frame → { ( h2_frame_free frame ) }
            F _ → { = drained T }
        }
    }
    ( vec_free [u] rx ) ( h2_frame_writer_free writer ) ( tcp_close_conn tcp )
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
    : ( Vec i ) outcome ( vec_new [i] ) ( vec_push [i] outcome 0 )
    : !Thread ThreadErr worker ( thread_spawn_owned \ → v {
        ?? ( tcp_accept listener ) { T tcp → { ( peer tcp outcome ) } F _ → {} }
    } )
    : ~ b ok T
    ?? ( h2_client_connect_h2c `127.0.0.1` port ) {
        T client → {
            = ok & ok ( small_send_buffer . client tcp )
            : ( Vec Header ) headers ( vec_new [Header] )
            : ( Vec u ) request ( vec_with_cap [u] 1048576 )
            = k 0
            ~ < k 1048576 { ( vec_push [u] request # u 65 ) = k + k 1 }
            ?? ( h2_client_submit client `POST` `http` `localhost` `/duplex` headers request ) {
                T sid → {
                    ?? ( h2_client_set_stream_deadline client sid + ( monotonic_ns ) 10000000000 ) { T _ → {} F _ → {} }
                    ?? ( h2_client_run_until_complete client ) {
                        T _ → {
                            ?? ( h2_client_take_response client sid ) {
                                T response → {
                                    = ok & & ok == . response status 200 == ( vec_len [u] . response body ) 1048576
                                    ( http_response_free response )
                                }
                                F _ → { = ok F }
                            }
                        }
                        F e → { ( nurl_print ( h2_client_err_name e ) ) ( nurl_print `\n` ) = ok F }
                    }
                }
                F _ → { = ok F }
            }
            ( vec_free [Header] headers ) ( h2_client_disconnect client )
        }
        F _ → { = ok F }
    }
    ?? worker { T thread → { : i ignored ( thread_join thread ) } F _ → { = ok F } }
    : b final & ok == . ( vec_data [i] outcome ) 0 1
    ? ! final {
        ( note `client_ok` ok )
        ( note `peer_outcome` == . ( vec_data [i] outcome ) 0 1 )
    } {}
    = ok final
    ( vec_free [i] outcome ) ( tcp_close_listener listener )
    ( nurl_print ? ok `duplex_small_buffers=T\n` `duplex_small_buffers=F\n` )
    ^ ? ok 0 1
}
