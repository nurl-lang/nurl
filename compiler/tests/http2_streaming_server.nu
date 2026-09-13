// The server's incremental transport preserves DATA, trailer HPACK state,
// END_STREAM, cancellation, and partial frames across a deadline. Offline:
// complete wire frames reside in rx, so there is no socket dependency.
$ `stdlib/ext/http2_conn.nu`
$ `stdlib/std/bytes.nu`

@ connection → H2Connection {
    ^ @ H2Connection {
        @ TcpConn { # s 0 }
        4096 0 256 65535 16384 65536
        4096 1 0 65535 16384 0
        ( hpack_dyn_new 4096 ) ( hpack_dyn_new 4096 ) -1
        ( vec_new [H2Stream] ) 65535 65535 0 T 0 0 0 0
        ( vec_new [u] ) ( h2_default_max_body_bytes )
        ( response_text 500 `error` ) T F ( h2_frame_writer @ TcpConn { # s 0 } 1048576 )
    }
}

@ feed H2Connection c i kind i flags i sid ( Vec u ) payload → v {
    : H2Frame frame @ H2Frame { kind flags sid payload }
    ?? ( h2_serialize_frame frame 16384 ) {
        T wire → { ( vec_extend [u] . c rx wire ) ( vec_free [u] wire ) }
        F _ → { ( nurl_print `FAIL serialize\n` ) }
    }
    ( h2_frame_free frame )
}

@ check s name b ok ( Vec i ) failures → v {
    ( nurl_print name ) ( nurl_print `=` ) ( nurl_print ? ok `T\n` `F\n` )
    ? ! ok { ( vec_push [i] failures 1 ) } {}
}

@ request_headers → ( Vec Header ) {
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `:method` `POST` ) )
    ( vec_push [Header] hs ( header_new `:scheme` `http` ) )
    ( vec_push [Header] hs ( header_new `:path` `/echo` ) )
    ( vec_push [Header] hs ( header_new `te` `trailers` ) )
    ^ hs
}

@ encode inout HpackDynTable table ( Vec Header ) hs → ( Vec u ) {
    : HpackEncoded encoded ( hpack_encode_headers_dyn hs table -1 )
    = table . encoded dyn
    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
    ^ . encoded block
}

@ next_kind inout H2Connection c i expected b end ( Vec i ) failures → v {
    ?? ( h2_conn_next c ) {
        T event → {
            ( check `event` & == . event kind expected == . event end_stream end failures )
            ( h2_event_free event )
        }
        F e → { ( nurl_print ( h2_conn_err_name e ) ) ( nurl_print `\n` ) ( vec_push [i] failures 1 ) }
    }
}

@ main → i {
    : ( Vec i ) failures ( vec_new [i] )
    : ~ H2Connection c ( connection )
    : ~ HpackDynTable encoder ( hpack_dyn_new 4096 )
    ( feed c 1 4 1 ( encode encoder ( request_headers ) ) )
    ( next_kind c ( h2_event_headers ) F failures )
    ( feed c 0 0 1 ( bytes_from_str `early` ) )
    ?? ( h2_conn_next c ) {
        T event → {
            ( check `data_before_end` & & == . event kind ( h2_event_data )
            == ( vec_len [u] . event data ) 5 ! . event end_stream failures )
            ( h2_event_free event )
        }
        F _ → { ( check `data_before_end` F failures ) }
    }
    : *H2Stream streams ( vec_data [H2Stream] . c streams )
    : H2Stream first . streams 0
    ( check `no_hidden_body_buffer` == ( vec_len [u] . first body ) 0 failures )
    ( check `cumulative_body_length` == . first body_received 5 failures )
    : ( Vec Header ) trailers ( vec_new [Header] )
    ( vec_push [Header] trailers ( header_new `x-reused` `dynamic-value` ) )
    : ( Vec u ) trailer_block ( encode encoder trailers )
    // Empty HEADERS carrying END_STREAM, then the complete trailer block
    // in CONTINUATION. The event must wait until the HPACK block completes.
    ( feed c 1 1 1 ( vec_new [u] ) )
    ( next_kind c ( h2_event_control ) F failures )
    ( feed c 9 4 1 trailer_block )
    ?? ( h2_conn_next c ) {
        T event → {
            : *Header p ( vec_data [Header] . event headers )
            : Header h . p 0
            ( check `continued_trailers` & & == . event kind ( h2_event_trailers ) . event end_stream
            != 0 ( nurl_str_eq ( string_data . h value ) `dynamic-value` ) failures )
            ( h2_event_free event )
        }
        F _ → { ( check `continued_trailers` F failures ) }
    }
    : ( Vec Header ) next_headers ( request_headers )
    ( vec_push [Header] next_headers ( header_new `x-reused` `dynamic-value` ) )
    ( feed c 1 5 3 ( encode encoder next_headers ) )
    ?? ( h2_conn_next c ) {
        T event → {
            : *Header p ( vec_data [Header] . event headers )
            : Header last . p - ( vec_len [Header] . event headers ) 1
            ( check `trailer_dynamic_table_preserved` & == . event kind ( h2_event_headers )
            != 0 ( nurl_str_eq ( string_data . last value ) `dynamic-value` ) failures )
            ( h2_event_free event )
        }
        F _ → { ( check `trailer_dynamic_table_preserved` F failures ) }
    }
    : ( Vec u ) reset ( vec_new [u] )
    ( vec_push [u] reset # u 0 ) ( vec_push [u] reset # u 0 )
    ( vec_push [u] reset # u 0 ) ( vec_push [u] reset # u 8 )
    ( feed c 3 0 3 reset )
    ( next_kind c ( h2_event_reset ) T failures )
    // An expired RPC deadline must not consume partial bytes, close the
    // connection, or require resetting its compression state.
    ( vec_push [u] . c rx # u 0 )
    ?? ( h2_conn_next_until c 1 ) {
        F e → {
            ( check `deadline_retains_partial_frame` & == ( vec_len [u] . c rx ) 1
            != 0 ( nurl_str_eq ( h2_conn_err_name e ) `H2ConnReadTimeout` ) failures )
        }
        T event → { ( check `deadline_retains_partial_frame` F failures ) ( h2_event_free event ) }
    }
    ( vec_clear [u] . c rx )
    // Decimal overflow used to wrap to a small valid content length.
    : ( Vec Header ) bad_headers ( request_headers )
    ( vec_push [Header] bad_headers ( header_new `content-length` `18446744073709551616` ) )
    ( feed c 1 5 5 ( encode encoder bad_headers ) )
    ?? ( h2_conn_next c ) {
        F e → { ( check `content_length_overflow_rejected`
            != 0 ( nurl_str_eq ( h2_conn_err_name e ) `H2ConnProtocol` ) failures ) }
        T event → { ( check `content_length_overflow_rejected` F failures ) ( h2_event_free event ) }
    }
    ( hpack_dyn_free encoder )
    ( h2_conn_free c )
    : i count ( vec_len [i] failures )
    ( vec_free [i] failures )
    ^ count
}
