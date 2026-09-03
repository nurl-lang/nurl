// stdlib/ext/http3_client.nu — HTTP/3 (RFC 9114) CLIENT over one QUIC
// connection (`std/quic_client.nu`): the mirror of `ext/http3_conn.nu`,
// which drives the server half. Our control and QPACK streams open at
// connect, a request is one bidirectional stream (HEADERS, DATA, FIN),
// the response comes back the same way and is handed over as the
// `HttpResponse` the HTTP/1.1 and HTTP/2 clients produce.
//
//   ( h3_client_connect host port server_name verify timeout_ms ) → *H3Client
//                                            0 when the name does not resolve or no socket could be
//                                            bound; otherwise `h3_client_connected` says whether the
//                                            QUIC handshake completed (with ALPN "h3") and
//                                            `h3_client_close_code` why not
//   ( h3_client_connected cl )            → b
//   ( h3_client_alive cl )                → b     still usable for requests (not closing, no GOAWAY, no failure)
//   ( h3_client_is_pq cl )                → b     the key exchange was X25519MLKEM768
//   ( h3_client_close_code cl )           → i     the QUIC close code (-1 none)
//   ( h3_client_request cl method scheme authority path headers body timeout_ms )
//                                         → !HttpResponse i   OWNED response; the error is an
//                                            H3ClientErr code: 1 not connected / connection gone ·
//                                            2 timed out · 3 protocol error (the connection is closed
//                                            with the HTTP/3 code) · 4 response too large · 5 refused
//                                            (the server's GOAWAY or a stream reset)
//   ( h3_client_close cl )                → v     H3_NO_ERROR application close, driven to the peer
//   ( h3_client_free cl )                 → v
//   ( h3_client_set_body_max cl n )       → v     response body cap (default 64 MiB)
//   ( h3_client_last_refusal cl )         → i     the HTTP/3 code of the server's last stream reset (-1 none)
//
// `headers` is BORROWED (the caller keeps it); pseudo-headers are
// added here; hop-by-hop fields are dropped (§4.2); names go on the
// wire lower-case. `body` is BORROWED. One request at a time — the
// facade serialises its requests, like it does on HTTP/2.
//
// Server push is never enabled (no MAX_PUSH_ID); a push stream is a
// connection error, as the RFC says. QPACK runs with a zero-size
// dynamic table both ways (this endpoint advertises 0 and never inserts).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/quic_varint.nu`
$ `stdlib/std/quic_tp.nu`
$ `stdlib/std/quic_conn.nu`
$ `stdlib/std/quic_client.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http3_frame.nu`
$ `stdlib/ext/http3_qpack.nu`

: H3CStream {
    i id
    i kind  // 0 request · 1 control · 3 QPACK encoder · 4 QPACK decoder · 5 ignored · -1 unknown yet
    ( Vec u ) buf
    i state  // request: 0 awaiting HEADERS · 1 headers seen · 2 trailers seen
    i status
    ( Vec Header ) headers
    ( Vec u ) body
    i done
    i err  // H3ClientErr code once the stream failed (0 none)
}

: H3Client {
    * QuicClient qc
    * QuicConn c
    ( Vec i ) streams
    i ctl_out
    i enc_out
    i dec_out
    i peer_control
    i peer_qenc
    i peer_qdec
    i peer_settings
    i max_field_section
    i body_max
    i failed
    i goaway_id  // the server's GOAWAY: request streams ≥ this were not processed (-1 none)
    i last_refusal  // the HTTP/3 code of the last RESET_STREAM / STOP_SENDING the server sent on a request (-1 none)
}

@ h3c_default_max_field_section → i { ^ 65536 }

@ h3_client_err_name i e → s {
    ? == e 1 { ^ `H3NotConnected` } {}
    ? == e 2 { ^ `H3Timeout` } {}
    ? == e 3 { ^ `H3Protocol` } {}
    ? == e 4 { ^ `H3TooLarge` } {}
    ? == e 5 { ^ `H3Refused` } {}
    ^ `H3Ok`
}

@ __h3c_stream_new i id i kind → *H3CStream {
    : *H3CStream s # *H3CStream ( nurl_alloc Z H3CStream )
    = . s id id
    = . s kind kind
    = . s buf ( vec_new [u] )
    = . s state 0
    = . s status 0
    = . s headers ( vec_new [Header] )
    = . s body ( vec_new [u] )
    = . s done 0
    = . s err 0
    ^ s
}

@ __h3c_stream_free * H3CStream s → v {
    ( vec_free [u] . s buf )
    ( vec_free_with [Header] . s headers \ Header hh → v { ( header_free hh ) } )
    ( vec_free [u] . s body )
    ( nurl_free # s s )
}

@ __h3c_ri ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → x F → 0 }
}

@ __h3c_stream_get * H3Client h i id → *H3CStream {
    : ~ i k 0
    ~ < k ( vec_len [i] . h streams ) {
        : *H3CStream s # *H3CStream ( __h3c_ri . h streams k )
        ? == . s id id { ^ s } {}
        = k + k 1
    }
    ^ # *H3CStream 0
}

@ __h3c_stream_drop * H3Client h i id → v {
    : ( Vec i ) keep ( vec_new [i] )
    : ~ i k 0
    ~ < k ( vec_len [i] . h streams ) {
        : *H3CStream s # *H3CStream ( __h3c_ri . h streams k )
        ? == . s id id { ( __h3c_stream_free s ) } { ( vec_push [i] keep # i s ) }
        = k + k 1
    }
    ( vec_free [i] . h streams )
    = . h streams keep
}

// A connection error: close with the HTTP/3 code (application close).
@ __h3c_fail * H3Client h i code → v {
    ? != . h failed 0 { ^ } {}
    = . h failed 1
    : ( Vec u ) reason ( vec_new [u] )
    ( quic_conn_close . h c 1 code reason )
    ( vec_free [u] reason )
    ( quic_client_pump . h qc )
}

// The transport parameters an HTTP/3 client advertises: the server may
// open no bidirectional stream (§6.1) and three unidirectional ones
// (control + 2 QPACK).
@ __h3c_tp → *QuicTp {
    : *QuicTp tp ( quic_client_default_tp )
    = . tp initial_max_streams_bidi 0
    = . tp initial_max_streams_uni 3
    ^ tp
}

@ h3_client_connect s host i port s server_name i verify i timeout_ms → *H3Client {
    : *QuicTp tp ( __h3c_tp )
    : *QuicClient qc ( quic_client_connect host port server_name `h3` tp verify timeout_ms )
    ( quic_tp_free tp )
    ? == # i qc 0 { ^ # *H3Client 0 } {}
    : *H3Client h # *H3Client ( nurl_alloc Z H3Client )
    = . h qc qc
    = . h c ( quic_client_conn qc )
    = . h streams ( vec_new [i] )
    = . h ctl_out -1
    = . h enc_out -1
    = . h dec_out -1
    = . h peer_control -1
    = . h peer_qenc -1
    = . h peer_qdec -1
    = . h peer_settings 0
    = . h max_field_section ( h3c_default_max_field_section )
    = . h body_max 67108864
    = . h failed 0
    = . h goaway_id -1
    = . h last_refusal -1
    ? ( quic_client_connected qc ) {
        // our unidirectional streams: control (type 0x00 + SETTINGS),
        // QPACK encoder (0x02) and decoder (0x03), each just its type byte
        : *QuicConn c . h c
        = . h ctl_out ( quic_conn_open_uni c )
        = . h enc_out ( quic_conn_open_uni c )
        = . h dec_out ( quic_conn_open_uni c )
        ? >= . h ctl_out 0 {
            : ( Vec u ) cb ( vec_new [u] )
            ( quic_varint_push cb ( h3_st_control ) )
            ( h3_push_settings cb ( h3c_default_max_field_section ) )
            : i _n ( quic_conn_stream_send c . h ctl_out cb F )
            ( vec_free [u] cb )
        } {}
        ? >= . h enc_out 0 {
            : ( Vec u ) e ( vec_new [u] )
            ( quic_varint_push e ( h3_st_qpack_encoder ) )
            : i _n ( quic_conn_stream_send c . h enc_out e F )
            ( vec_free [u] e )
        } {}
        ? >= . h dec_out 0 {
            : ( Vec u ) d ( vec_new [u] )
            ( quic_varint_push d ( h3_st_qpack_decoder ) )
            : i _n ( quic_conn_stream_send c . h dec_out d F )
            ( vec_free [u] d )
        } {}
        ( quic_client_pump qc )
    } {}
    ^ h
}

@ h3_client_connected * H3Client h → b { ^ ( quic_client_connected . h qc ) }

@ h3_client_alive * H3Client h → b {
    ? != . h failed 0 { ^ F } {}
    ? >= . h goaway_id 0 { ^ F } {}
    ^ == ( quic_conn_state . h c ) 1
}

@ h3_client_is_pq * H3Client h → b { ^ ( quic_conn_is_pq . h c ) }

@ h3_client_close_code * H3Client h → i { ^ ( quic_conn_close_code . h c ) }

@ h3_client_set_body_max * H3Client h i n → v { = . h body_max n }

// The HTTP/3 error code of the server's last RESET_STREAM / STOP_SENDING
// on a request stream (-1 none) — why a request was refused.
@ h3_client_last_refusal * H3Client h → i { ^ . h last_refusal }

@ h3_client_close * H3Client h → v {
    ? >= ( quic_conn_state . h c ) 2 { ^ } {}
    : ( Vec u ) reason ( vec_new [u] )
    ( quic_client_close . h qc 1 ( h3_err_no_error ) reason 500 )
    ( vec_free [u] reason )
}

@ h3_client_free * H3Client h → v {
    ? == # i h 0 { ^ } {}
    : ~ i k 0
    ~ < k ( vec_len [i] . h streams ) {
        ( __h3c_stream_free # *H3CStream ( __h3c_ri . h streams k ) )
        = k + k 1
    }
    ( vec_free [i] . h streams )
    ( quic_client_free . h qc )
    ( nurl_free # s h )
}

// ── the request ──────────────────────────────────────────────────

@ __h3c_eq_ci s a s b → b {
    : i n ( nurl_str_len a )
    ? != n ( nurl_str_len b ) { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : ~ i x ( nurl_str_get a k )
        : ~ i y ( nurl_str_get b k )
        ? & >= x 65 <= x 90 { = x + x 32 } {}
        ? & >= y 65 <= y 90 { = y + y 32 } {}
        ? != x y { ^ F } {}
        = k + k 1
    }
    ^ T
}

// The request's field section: pseudo-headers first (§4.3.1), then the
// caller's fields lower-cased, hop-by-hop ones left out (§4.2).
@ __h3c_request_block s method s scheme s authority s path ( Vec Header ) headers → ( Vec u ) {
    : ( Vec Header ) all ( vec_new [Header] )
    ( vec_push [Header] all ( header_new `:method` method ) )
    ( vec_push [Header] all ( header_new `:scheme` scheme ) )
    ( vec_push [Header] all ( header_new `:authority` authority ) )
    ( vec_push [Header] all ( header_new `:path` path ) )
    : i nh ( vec_len [Header] headers )
    : *Header hp ( vec_data [Header] headers )
    : ~ i k 0
    ~ < k nh {
        : Header hh . hp k
        : s nm ( string_data . hh name )
        : b hop | | | | | ( __h3c_eq_ci nm `connection` ) ( __h3c_eq_ci nm `transfer-encoding` ) ( __h3c_eq_ci nm `keep-alive` ) ( __h3c_eq_ci nm `proxy-connection` ) ( __h3c_eq_ci nm `upgrade` ) ( __h3c_eq_ci nm `host` )
        ? hop {} {
            : i ln ( nurl_str_len nm )
            : String lower ( string_with_cap ln )
            : ~ i j 0
            ~ < j ln {
                : i ch ( nurl_str_get nm j )
                ( string_push_char lower ? & >= ch 65 <= ch 90 + ch 32 ch )
                = j + j 1
            }
            ( vec_push [Header] all ( header_new ( string_data lower ) ( string_data . hh value ) ) )
            ( string_free lower )
        }
        = k + k 1
    }
    : ( Vec u ) block ( qpack_encode_section all )
    ( vec_free_with [Header] all \ Header hh → v { ( header_free hh ) } )
    ^ block
}

// Leading decimal digits of `s`, -1 when there are none.
@ __h3c_int s v → i {
    : i n ( nurl_str_len v )
    : ~ i out 0
    : ~ i k 0
    : ~ i any 0
    ~ < k n {
        : i ch ( nurl_str_get v k )
        ? & >= ch 48 <= ch 57 { = out + * out 10 - ch 48 = any 1 } { = k n }
        = k + k 1
    }
    ^ ? == any 1 out -1
}

// One frame of the response stream; F when the loop must stop.
@ __h3c_response_frame * H3Client h * H3CStream s b fin * H3FrameHead fh → b {
    : i ft . fh ftype
    : i flen . fh length
    : i hl . fh head_len
    ( h3_frame_head_free fh )
    ? | | | == ft ( h3_ft_settings ) == ft ( h3_ft_goaway ) == ft ( h3_ft_max_push_id ) == ft ( h3_ft_cancel_push ) { ( __h3c_fail h ( h3_err_frame_unexpected ) ) = . s err 3 ^ F } {}
    // PUSH_PROMISE with push never enabled (§7.2.5)
    ? == ft ( h3_ft_push_promise ) { ( __h3c_fail h ( h3_err_id_error ) ) = . s err 3 ^ F } {}
    ? & == ft ( h3_ft_data ) == . s state 0 { ( __h3c_fail h ( h3_err_frame_unexpected ) ) = . s err 3 ^ F } {}
    ? > flen + ( h3c_default_max_field_section ) . h body_max { ( __h3c_fail h ( h3_err_excessive_load ) ) = . s err 4 ^ F } {}
    : i have - ( vec_len [u] . s buf ) hl
    ? < have flen {
        ? fin { ( __h3c_fail h ( h3_err_frame_error ) ) = . s err 3 } {}
        ^ F
    } {}
    : ( Vec u ) payload ( bytes_slice . s buf hl + hl flen )
    : ( Vec u ) rest ( bytes_slice . s buf + hl flen ( vec_len [u] . s buf ) )
    ( vec_free [u] . s buf )
    = . s buf rest
    ? == ft ( h3_ft_headers ) {
        ? == . s state 2 { ( vec_free [u] payload ) ( __h3c_fail h ( h3_err_frame_unexpected ) ) = . s err 3 ^ F } {}
        ? > flen . h max_field_section { ( vec_free [u] payload ) ( __h3c_fail h ( h3_err_excessive_load ) ) = . s err 4 ^ F } {}
        ?? ( qpack_decode_section payload ) {
            T hs → {
                ? == . s state 0 {
                    // :status first (§4.3.2); the rest are the response's fields
                    : ~ i st -1
                    : ~ i bad 0
                    : i nh ( vec_len [Header] hs )
                    : *Header hp ( vec_data [Header] hs )
                    : ~ i k 0
                    ~ < k nh {
                        : Header hh . hp k
                        : s nm ( string_data . hh name )
                        ? & > ( nurl_str_len nm ) 0 == ( nurl_str_get nm 0 ) 58 {
                            ? != 0 ( nurl_str_eq nm `:status` ) {
                                ? | >= st 0 != k 0 { = bad 1 } { = st ( __h3c_int ( string_data . hh value ) ) }
                            } { = bad 1 }
                        } {
                            ( vec_push [Header] . s headers ( header_new nm ( string_data . hh value ) ) )
                        }
                        = k + k 1
                    }
                    ( vec_free_with [Header] hs \ Header hh → v { ( header_free hh ) } )
                    ? | != bad 0 | < st 100 > st 999 { ( vec_free [u] payload ) ( __h3c_fail h ( h3_err_message_error ) ) = . s err 3 ^ F } {}
                    // 1xx interim responses: another HEADERS follows (§4.1)
                    ? < st 200 {
                        ( vec_free_with [Header] . s headers \ Header hh → v { ( header_free hh ) } )
                        = . s headers ( vec_new [Header] )
                    } {
                        = . s status st
                        = . s state 1
                    }
                } {
                    // trailers: accepted, not surfaced
                    ( vec_free_with [Header] hs \ Header hh → v { ( header_free hh ) } )
                    = . s state 2
                }
            }
            F code → { ( vec_free [u] payload ) ( __h3c_fail h code ) = . s err 3 ^ F }
        }
    } {
        ? == ft ( h3_ft_data ) {
            ? == . s state 2 { ( vec_free [u] payload ) ( __h3c_fail h ( h3_err_frame_unexpected ) ) = . s err 3 ^ F } {}
            ? > + ( vec_len [u] . s body ) flen . h body_max {
                ( vec_free [u] payload )
                = . s err 4
                ( quic_conn_stream_stop_sending . h c . s id ( h3_err_excessive_load ) )
                = . s done 1
                ^ F
            } {}
            ( bytes_extend_bytes . s body payload )
        } {}
        // reserved / unknown types: skipped (§7.2.8, §9)
    }
    ( vec_free [u] payload )
    ^ T
}

@ __h3c_response_stream * H3Client h * H3CStream s b fin → v {
    : ~ b more T
    ~ & & more == . s done 0 == . h failed 0 {
        : *H3FrameHead fh ( h3_frame_peek . s buf 0 )
        ? == # i fh 0 {
            ? & fin > ( vec_len [u] . s buf ) 0 { ( __h3c_fail h ( h3_err_frame_error ) ) = . s err 3 } {}
            = more F
        } {
            ? ! ( __h3c_response_frame h s fin fh ) { = more F } {}
        }
    }
    ? & & fin == . s done 0 == . h failed 0 {
        ? == ( vec_len [u] . s buf ) 0 {
            ? >= . s state 1 { = . s done 1 } { = . s err 3 = . s done 1 }
        } {}
    } {}
}

// ── the server's unidirectional streams ─────────────────────────

@ __h3c_control_stream * H3Client h * H3CStream s b fin → v {
    ~ & == . h failed 0 T {
        : *H3FrameHead fh ( h3_frame_peek . s buf 0 )
        ? == # i fh 0 { ? fin { ( __h3c_fail h ( h3_err_closed_critical_stream ) ) } {} ^ } {}
        : i ft . fh ftype
        : i flen . fh length
        : i hl . fh head_len
        ( h3_frame_head_free fh )
        ? & == . h peer_settings 0 != ft ( h3_ft_settings ) { ? ( h3_type_is_reserved ft ) {} { ( __h3c_fail h ( h3_err_missing_settings ) ) ^ } } {}
        ? & != . h peer_settings 0 == ft ( h3_ft_settings ) { ( __h3c_fail h ( h3_err_frame_unexpected ) ) ^ } {}
        ? | | | == ft ( h3_ft_data ) == ft ( h3_ft_headers ) == ft ( h3_ft_push_promise ) == ft ( h3_ft_max_push_id ) { ( __h3c_fail h ( h3_err_frame_unexpected ) ) ^ } {}
        ? > flen 65536 { ( __h3c_fail h ( h3_err_excessive_load ) ) ^ } {}
        : i have - ( vec_len [u] . s buf ) hl
        ? < have flen { ? fin { ( __h3c_fail h ( h3_err_closed_critical_stream ) ) } {} ^ } {}
        : ( Vec u ) payload ( bytes_slice . s buf hl + hl flen )
        : ( Vec u ) rest ( bytes_slice . s buf + hl flen ( vec_len [u] . s buf ) )
        ( vec_free [u] . s buf )
        = . s buf rest
        ? == ft ( h3_ft_settings ) {
            : i bad ( h3_settings_parse payload )
            ? != bad 0 { ( vec_free [u] payload ) ( __h3c_fail h bad ) ^ } {}
            = . h peer_settings 1
            : i mfs ( h3_settings_get payload ( h3_setting_max_field_section_size ) )
            ? > mfs 0 { ? < mfs . h max_field_section { = . h max_field_section mfs } {} } {}
        } {}
        ? == ft ( h3_ft_goaway ) {
            // the server is going away: the id names the first request
            // stream it did not process (§5.2); it may only go down
            : i gid ( quic_varint_read payload 0 )
            ? | < gid 0 != & gid 3 0 { ( vec_free [u] payload ) ( __h3c_fail h ( h3_err_id_error ) ) ^ } {}
            ? & >= . h goaway_id 0 > gid . h goaway_id { ( vec_free [u] payload ) ( __h3c_fail h ( h3_err_id_error ) ) ^ } {}
            = . h goaway_id gid
        } {}
        // CANCEL_PUSH, reserved, unknown: nothing to do
        ( vec_free [u] payload )
    }
}

@ __h3c_qpack_stream * H3Client h * H3CStream s b fin b encoder → v {
    ~ & == . h failed 0 > ( vec_len [u] . s buf ) 0 {
        : i r ? encoder ( qpack_encoder_instruction . s buf 0 ) ( qpack_decoder_instruction . s buf 0 )
        ? == r -1 { ? fin { ( __h3c_fail h ( h3_err_closed_critical_stream ) ) } {} ^ } {}
        ? == r -2 { ( __h3c_fail h ? encoder ( qpack_err_encoder_stream ) ( qpack_err_decoder_stream ) ) ^ } {}
        : ( Vec u ) rest ( bytes_slice . s buf r ( vec_len [u] . s buf ) )
        ( vec_free [u] . s buf )
        = . s buf rest
    }
    ? & fin == . h failed 0 { ( __h3c_fail h ( h3_err_closed_critical_stream ) ) } {}
}

// Classify a server unidirectional stream by its first varint (§6.2).
@ __h3c_classify * H3Client h * H3CStream s → v {
    : i t ( quic_varint_read . s buf 0 )
    ? < t 0 { ^ } {}
    : i tl ( quic_varint_len_at . s buf 0 )
    : ( Vec u ) rest ( bytes_slice . s buf tl ( vec_len [u] . s buf ) )
    ( vec_free [u] . s buf )
    = . s buf rest
    ? == t ( h3_st_control ) {
        ? >= . h peer_control 0 { ( __h3c_fail h ( h3_err_stream_creation ) ) ^ } {}
        = . h peer_control . s id
        = . s kind 1
        ^
    } {}
    ? == t ( h3_st_qpack_encoder ) {
        ? >= . h peer_qenc 0 { ( __h3c_fail h ( h3_err_stream_creation ) ) ^ } {}
        = . h peer_qenc . s id
        = . s kind 3
        ^
    } {}
    ? == t ( h3_st_qpack_decoder ) {
        ? >= . h peer_qdec 0 { ( __h3c_fail h ( h3_err_stream_creation ) ) ^ } {}
        = . h peer_qdec . s id
        = . s kind 4
        ^
    } {}
    // a push stream with push never enabled (§6.2.2)
    ? == t ( h3_st_push ) { ( __h3c_fail h ( h3_err_id_error ) ) ^ } {}
    = . s kind 5
    ( vec_clear [u] . s buf )
    ( quic_conn_stream_stop_sending . h c . s id ( h3_err_stream_creation ) )
}

// Everything that arrived on stream `id`.
@ __h3c_on_stream * H3Client h i id → v {
    : *QuicConn c . h c
    : ~ * H3CStream s ( __h3c_stream_get h id )
    : b uni != & id 2 0
    ? == # i s 0 {
        // a server-initiated bidirectional stream cannot exist (§6.1) —
        // the transport limit is 0, so the connection has failed already
        ? ! uni { ^ } {}
        = s ( __h3c_stream_new id -1 )
        ( vec_push [i] . h streams # i s )
    } {}
    ? != . s done 0 { ^ } {}
    ? >= ( quic_conn_stream_reset_err c id ) 0 {
        ? | == . s kind 1 | == . s kind 3 == . s kind 4 { ( __h3c_fail h ( h3_err_closed_critical_stream ) ) ^ } {}
        ? == . s kind 0 { = . h last_refusal ( quic_conn_stream_reset_err c id ) = . s err 5 = . s done 1 ^ } {}
        ( __h3c_stream_drop h id )
        ^
    } {}
    ? & == . s kind 0 >= ( quic_conn_stream_stop_err c id ) 0 { = . h last_refusal ( quic_conn_stream_stop_err c id ) = . s err 5 = . s done 1 ^ } {}
    : ~ b more T
    ~ more {
        : ( Vec u ) d ( quic_conn_stream_recv c id 65536 )
        ? == ( vec_len [u] d ) 0 { = more F } {
            ? == . s kind 5 {} { ( bytes_extend_bytes . s buf d ) }
        }
        ( vec_free [u] d )
    }
    : b fin ( quic_conn_stream_fin c id )
    ? == . s kind -1 { ( __h3c_classify h s ) } {}
    ? == . h failed 0 {
        ? == . s kind 0 { ( __h3c_response_stream h s fin ) } {}
        ? == . s kind 1 { ( __h3c_control_stream h s fin ) } {}
        ? == . s kind 3 { ( __h3c_qpack_stream h s fin T ) } {}
        ? == . s kind 4 { ( __h3c_qpack_stream h s fin F ) } {}
    } {}
    ? & == . s kind 5 fin { ( __h3c_stream_drop h id ) } {}
}

@ __h3c_now → i { ^ / ( monotonic_ns ) 1000000 }

@ h3_client_request * H3Client h s method s scheme s authority s path ( Vec Header ) headers ( Vec u ) body i timeout_ms → !HttpResponse i {
    ? ! ( h3_client_alive h ) { ^ @ !HttpResponse i { F 1 } } {}
    : *QuicConn c . h c
    : i sid ( quic_conn_open_bidi c )
    ? < sid 0 { ^ @ !HttpResponse i { F 1 } } {}
    : *H3CStream s ( __h3c_stream_new sid 0 )
    ( vec_push [i] . h streams # i s )
    : ( Vec u ) block ( __h3c_request_block method scheme authority path headers )
    : ( Vec u ) wire ( vec_new [u] )
    ( h3_push_frame wire ( h3_ft_headers ) block )
    ( vec_free [u] block )
    ? > ( vec_len [u] body ) 0 { ( h3_push_frame wire ( h3_ft_data ) body ) } {}
    : i _n ( quic_conn_stream_send c sid wire T )
    ( vec_free [u] wire )
    ( quic_client_pump . h qc )
    // drive the connection until the response is complete
    : i deadline + ( __h3c_now ) timeout_ms
    : ~ i err 0
    ~ & & == . s done 0 == err 0 == . h failed 0 {
        : i now ( __h3c_now )
        ? >= now deadline { = err 2 } {
            ? ( quic_client_wait_readable . h qc - deadline now ) {
                : ( Vec i ) ids ( quic_conn_take_readable c )
                : ~ i k 0
                ~ & < k ( vec_len [i] ids ) == . h failed 0 {
                    ( __h3c_on_stream h ( __h3c_ri ids k ) )
                    = k + k 1
                }
                ( vec_free [i] ids )
                ( quic_client_pump . h qc )
            } {
                ? >= ( quic_conn_state c ) 2 { = err 1 } {}
            }
        }
    }
    ? & == err 0 != . h failed 0 { = err 3 } {}
    ? & == err 0 != . s err 0 { = err . s err } {}
    // a GOAWAY that names this stream or an earlier one: not processed
    ? & == err 0 & >= . h goaway_id 0 >= sid . h goaway_id { ? == . s state 0 { = err 5 } {} } {}
    ? != err 0 {
        ? == ( quic_conn_state c ) 1 { ( quic_conn_stream_reset c sid ( h3_err_request_cancelled ) ) ( quic_conn_stream_stop_sending c sid ( h3_err_request_cancelled ) ) ( quic_client_pump . h qc ) } {}
        ( quic_conn_stream_done c sid )
        ( __h3c_stream_drop h sid )
        ^ @ !HttpResponse i { F err }
    } {}
    : HttpResponse r ( response_new . s status )
    ( vec_free [Header] . r headers )
    = . r headers . s headers
    = . s headers ( vec_new [Header] )
    ( vec_free [u] . r body )
    = . r body . s body
    = . s body ( vec_new [u] )
    ( quic_conn_stream_done c sid )
    ( __h3c_stream_drop h sid )
    ^ @ !HttpResponse i { T r }
}
