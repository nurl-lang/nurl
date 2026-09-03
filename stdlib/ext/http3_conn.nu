// stdlib/ext/http3_conn.nu — HTTP/3 (RFC 9114) over one QUIC
// connection, server side: the control and QPACK streams both ways,
// request streams turned into `HttpRequest`s for the same handler the
// HTTP/1.1 and HTTP/2 paths call, and the response written back as
// HEADERS + DATA + FIN.
//
//   ( h3_conn_new qc body_max )                 → *H3Conn   opens our control / QPACK streams, sends SETTINGS
//   ( h3_conn_free h )                          → v
//   ( h3_conn_on_readable h handler )           → v         drain `quic_conn_take_readable`, run requests
//   ( h3_conn_goaway h )                        → v         GOAWAY: no new requests (shutdown)
//
// Errors are the RFC's: a connection error closes the QUIC connection
// with the HTTP/3 code (application close); a malformed request is a
// stream error (RESET_STREAM + STOP_SENDING with H3_MESSAGE_ERROR).
// Server push is never used (no MAX_PUSH_ID is sent); a push stream or
// PUSH_PROMISE from the peer is a violation, as the RFC says.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/quic_varint.nu`
$ `stdlib/std/quic_conn.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http3_frame.nu`
$ `stdlib/ext/http3_qpack.nu`

: H3Stream {
    i id
    i kind
    ( Vec u ) buf
    i state
    ( Vec Header ) headers
    ( Vec u ) body
    i done
}

@ h3_kind_request → i { ^ 0 }

@ h3_kind_control → i { ^ 1 }

@ h3_kind_push → i { ^ 2 }

@ h3_kind_qpack_encoder → i { ^ 3 }

@ h3_kind_qpack_decoder → i { ^ 4 }

@ h3_kind_ignored → i { ^ 5 }

@ h3_kind_unknown → i { ^ -1 }

@ __h3_stream_new i id i kind → *H3Stream {
    : *H3Stream s # *H3Stream ( nurl_alloc Z H3Stream )
    = . s id id
    = . s kind kind
    = . s buf ( vec_new [u] )
    = . s state 0
    = . s headers ( vec_new [Header] )
    = . s body ( vec_new [u] )
    = . s done 0
    ^ s
}

@ __h3_stream_free * H3Stream s → v {
    ( vec_free [u] . s buf )
    ( vec_free_with [Header] . s headers \ Header h → v { ( header_free h ) } )
    ( vec_free [u] . s body )
    ( nurl_free # s s )
}

: H3Conn {
    * QuicConn qc
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
    i goaway_sent
    i failed
}

@ h3_default_max_field_section → i { ^ 65536 }

@ h3_conn_new * QuicConn qc i body_max → *H3Conn {
    : *H3Conn h # *H3Conn ( nurl_alloc Z H3Conn )
    = . h qc qc
    = . h streams ( vec_new [i] )
    = . h peer_control -1
    = . h peer_qenc -1
    = . h peer_qdec -1
    = . h peer_settings 0
    = . h max_field_section ( h3_default_max_field_section )
    = . h body_max body_max
    = . h goaway_sent 0
    = . h failed 0
    // our unidirectional streams: control (type 0x00 + SETTINGS), QPACK
    // encoder (0x02) and decoder (0x03), each just its type byte
    = . h ctl_out ( quic_conn_open_uni qc )
    = . h enc_out ( quic_conn_open_uni qc )
    = . h dec_out ( quic_conn_open_uni qc )
    ? >= . h ctl_out 0 {
        : ( Vec u ) c ( vec_new [u] )
        ( quic_varint_push c ( h3_st_control ) )
        ( h3_push_settings c ( h3_default_max_field_section ) )
        : i _n ( quic_conn_stream_send qc . h ctl_out c F )
        ( vec_free [u] c )
    } {}
    ? >= . h enc_out 0 {
        : ( Vec u ) e ( vec_new [u] )
        ( quic_varint_push e ( h3_st_qpack_encoder ) )
        : i _n ( quic_conn_stream_send qc . h enc_out e F )
        ( vec_free [u] e )
    } {}
    ? >= . h dec_out 0 {
        : ( Vec u ) d ( vec_new [u] )
        ( quic_varint_push d ( h3_st_qpack_decoder ) )
        : i _n ( quic_conn_stream_send qc . h dec_out d F )
        ( vec_free [u] d )
    } {}
    ^ h
}

@ h3_conn_free * H3Conn h → v {
    ? == # i h 0 { ^ } {}
    : ~ i k 0
    ~ < k ( vec_len [i] . h streams ) {
        ( __h3_stream_free # *H3Stream ?? ( vec_get [i] . h streams k ) { T x → x F → 0 } )
        = k + k 1
    }
    ( vec_free [i] . h streams )
    ( nurl_free # s h )
}

@ __h3_ri ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → ^ x F → ^ 0 }
}

@ __h3_stream_get * H3Conn h i id → *H3Stream {
    : ~ i k 0
    ~ < k ( vec_len [i] . h streams ) {
        : *H3Stream s # *H3Stream ( __h3_ri . h streams k )
        ? == . s id id { ^ s } {}
        = k + k 1
    }
    ^ # *H3Stream 0
}

@ __h3_stream_drop * H3Conn h i id → v {
    : ~ i k 0
    ~ < k ( vec_len [i] . h streams ) {
        : *H3Stream s # *H3Stream ( __h3_ri . h streams k )
        ? == . s id id {
            ( __h3_stream_free s )
            : ?i _r ( vec_remove [i] . h streams k )
            ( quic_conn_stream_done . h qc id )
            ^
        } {}
        = k + k 1
    }
}

// Connection error: application close with an HTTP/3 code.
@ __h3_fail * H3Conn h i code → v {
    ? != . h failed 0 { ^ } {}
    = . h failed 1
    : ( Vec u ) e ( vec_new [u] )
    ( quic_conn_close . h qc 1 code e )
    ( vec_free [u] e )
}

// Stream error (§8.1): reset our side, stop the peer's.
@ __h3_stream_error * H3Conn h * H3Stream s i code → v {
    ( quic_conn_stream_reset . h qc . s id code )
    ( quic_conn_stream_stop_sending . h qc . s id code )
    = . s done 1
}

@ h3_conn_goaway * H3Conn h → v {
    ? | != . h goaway_sent 0 < . h ctl_out 0 { ^ } {}
    = . h goaway_sent 1
    : ( Vec u ) p ( vec_new [u] )
    // the smallest request stream id we will not process: "all seen so far"
    : ~ i max_id 0
    : ~ i k 0
    ~ < k ( vec_len [i] . h streams ) {
        : *H3Stream s # *H3Stream ( __h3_ri . h streams k )
        ? & == . s kind 0 > + . s id 4 max_id { = max_id + . s id 4 } {}
        = k + k 1
    }
    ( quic_varint_push p max_id )
    : ( Vec u ) f ( vec_new [u] )
    ( h3_push_frame f ( h3_ft_goaway ) p )
    : i _n ( quic_conn_stream_send . h qc . h ctl_out f F )
    ( vec_free [u] f ) ( vec_free [u] p )
}

// ── request validation (§4.1.2, §4.3.1) ─────────────────────────

@ __h3_lower_ok s nm → b {
    : i n ( nurl_str_len nm )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get nm k )
        ? & >= c 65 <= c 90 { ^ F } {}
        ? | | == c 32 == c 0 > c 126 { ^ F } {}
        = k + k 1
    }
    ^ > n 0
}

@ __h3_eq s a s b → b { ^ != 0 ( nurl_str_eq a b ) }

// 0 when the field section is a valid request; else H3_MESSAGE_ERROR.
@ _h3_validate_request ( Vec Header ) hs → i {
    : ~ i seen_method 0
    : ~ i seen_scheme 0
    : ~ i seen_path 0
    : ~ i seen_authority 0
    : ~ i seen_host 0
    : ~ i regular_seen 0
    : ~ b is_connect F
    : ~ b scheme_needs_authority F
    : i nh ( vec_len [Header] hs )
    : *Header hp ( vec_data [Header] hs )
    : ~ i k 0
    ~ < k nh {
        : Header hh . hp k
        : s nm ( string_data . hh name )
        : s vl ( string_data . hh value )
        ? ! ( __h3_lower_ok nm ) { ^ ( h3_err_message_error ) } {}
        ? == ( nurl_str_get nm 0 ) 58 {
            ? != regular_seen 0 { ^ ( h3_err_message_error ) } {}
            ? ( __h3_eq nm `:method` ) {
                ? != seen_method 0 { ^ ( h3_err_message_error ) } {}
                = seen_method 1
                ? ( __h3_eq vl `CONNECT` ) { = is_connect T } {}
                ? == ( nurl_str_len vl ) 0 { ^ ( h3_err_message_error ) } {}
            } {
                ? ( __h3_eq nm `:scheme` ) {
                    ? != seen_scheme 0 { ^ ( h3_err_message_error ) } {}
                    = seen_scheme 1
                    ? | ( __h3_eq vl `https` ) ( __h3_eq vl `http` ) { = scheme_needs_authority T } {}
                } {
                    ? ( __h3_eq nm `:path` ) {
                        ? != seen_path 0 { ^ ( h3_err_message_error ) } {}
                        = seen_path 1
                        ? == ( nurl_str_len vl ) 0 { ^ ( h3_err_message_error ) } {}
                    } {
                        ? ( __h3_eq nm `:authority` ) {
                            ? != seen_authority 0 { ^ ( h3_err_message_error ) } {}
                            = seen_authority 1
                        } {
                            // :status, :protocol (no extended CONNECT offered), anything else
                            ^ ( h3_err_message_error )
                        }
                    }
                }
            }
        } {
            = regular_seen 1
            // connection-specific fields are forbidden (§4.2)
            ? | | | | ( __h3_eq nm `connection` ) ( __h3_eq nm `keep-alive` ) ( __h3_eq nm `proxy-connection` ) ( __h3_eq nm `transfer-encoding` ) ( __h3_eq nm `upgrade` ) { ^ ( h3_err_message_error ) } {}
            ? & ( __h3_eq nm `te` ) ! ( __h3_eq vl `trailers` ) { ^ ( h3_err_message_error ) } {}
            ? ( __h3_eq nm `host` ) { = seen_host 1 } {}
        }
        = k + k 1
    }
    ? is_connect {
        ? | | == seen_authority 0 != seen_scheme 0 != seen_path 0 { ^ ( h3_err_message_error ) } {}
    } {
        ? | | == seen_method 0 == seen_scheme 0 == seen_path 0 { ^ ( h3_err_message_error ) } {}
        // http / https targets need an authority: :authority or Host (§4.3.1)
        ? & & scheme_needs_authority == seen_authority 0 == seen_host 0 { ^ ( h3_err_message_error ) } {}
    }
    ^ 0
}

// ── request → HttpRequest → handler → response ──────────────────

@ __h3_to_request * H3Stream s → HttpRequest {
    : HttpRequest req ( request_new )
    : i nh ( vec_len [Header] . s headers )
    : *Header hp ( vec_data [Header] . s headers )
    : ~ i k 0
    ~ < k nh {
        : Header hh . hp k
        : s nm ( string_data . hh name )
        : s vl ( string_data . hh value )
        ? ( __h3_eq nm `:method` ) {
            ( string_free . req method )
            = . req method ( string_from vl )
        } {
            ? ( __h3_eq nm `:path` ) {
                : i pl ( nurl_str_len vl )
                : ~ i qi -1
                : ~ i j 0
                ~ & == qi -1 < j pl {
                    ? == 63 ( nurl_str_get vl j ) { = qi j } {}
                    = j + j 1
                }
                ( string_free . req path )
                ? >= qi 0 {
                    ( string_free . req query )
                    : String p ( string_with_cap qi )
                    ( string_push_bytes p # *u vl qi )
                    = . req path p
                    : String q ( string_with_cap - pl + qi 1 )
                    ( string_push_bytes q # *u + # i vl + qi 1 - pl + qi 1 )
                    = . req query q
                } { = . req path ( string_from vl ) }
            } {
                ? ( __h3_eq nm `:authority` ) {
                    ( vec_push [Header] . req headers ( header_new `Host` vl ) )
                } {
                    ? != 58 ( nurl_str_get nm 0 ) {
                        ( vec_push [Header] . req headers ( header_new nm vl ) )
                    } {}
                }
            }
        }
        = k + k 1
    }
    ( string_free . req version )
    = . req version ( string_from `HTTP/3` )
    ( vec_extend [u] . req body . s body )
    ^ req
}

@ __h3_status_str i status → String {
    : String s ( string_new )
    ( string_push_int s status )
    ^ s
}

@ __h3_eq_ci s a s b → b {
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

@ __h3_send_response * H3Conn h * H3Stream s HttpResponse r → v {
    : ( Vec Header ) all ( vec_new [Header] )
    : String st ( __h3_status_str . r status )
    ( vec_push [Header] all ( header_new `:status` ( string_data st ) ) )
    ( string_free st )
    : i nh ( vec_len [Header] . r headers )
    : *Header hp ( vec_data [Header] . r headers )
    : ~ i k 0
    ~ < k nh {
        : Header hh . hp k
        : s nm ( string_data . hh name )
        // hop-by-hop fields do not exist in HTTP/3 (§4.2); names are lower-case
        : b hop | | | | ( __h3_eq_ci nm `connection` ) ( __h3_eq_ci nm `transfer-encoding` ) ( __h3_eq_ci nm `keep-alive` ) ( __h3_eq_ci nm `proxy-connection` ) ( __h3_eq_ci nm `upgrade` )
        ? hop {} {
            : i ln ( nurl_str_len nm )
            : String lower ( string_with_cap ln )
            : ~ i j 0
            ~ < j ln {
                : i c ( nurl_str_get nm j )
                ( string_push_char lower ? & >= c 65 <= c 90 + c 32 c )
                = j + j 1
            }
            ( vec_push [Header] all ( header_new ( string_data lower ) ( string_data . hh value ) ) )
            ( string_free lower )
        }
        = k + k 1
    }
    : ( Vec u ) block ( qpack_encode_section all )
    ( vec_free_with [Header] all \ Header hh → v { ( header_free hh ) } )
    : ( Vec u ) wire ( vec_new [u] )
    ( h3_push_frame wire ( h3_ft_headers ) block )
    ( vec_free [u] block )
    : i blen ( vec_len [u] . r body )
    ? > blen 0 { ( h3_push_frame wire ( h3_ft_data ) . r body ) } {}
    : i _n ( quic_conn_stream_send . h qc . s id wire T )
    ( vec_free [u] wire )
}

@ __h3_dispatch * H3Conn h * H3Stream s ( @ HttpResponse HttpRequest ) handler → v {
    : HttpRequest req ( __h3_to_request s )
    : HttpResponse resp ( handler req )
    ( __h3_send_response h s resp )
    ( http_response_free resp )
    ( request_free req )
    = . s done 1
}

// ── request streams ──────────────────────────────────────────────

// One frame of a request stream; F when the loop must stop (waiting
// for more bytes, or the stream / connection is finished).
@ __h3_request_frame * H3Conn h * H3Stream s b fin * H3FrameHead fh → b {

    : i ft . fh ftype
    : i flen . fh length
    : i hl . fh head_len
    ( h3_frame_head_free fh )
    // frames that may never appear on a request stream (§7.2)
    ? | | | | == ft ( h3_ft_settings ) == ft ( h3_ft_goaway ) == ft ( h3_ft_max_push_id ) == ft ( h3_ft_cancel_push ) == ft ( h3_ft_push_promise ) { ( __h3_fail h ( h3_err_frame_unexpected ) ) ^ F } {}
    ? & == ft ( h3_ft_data ) == . s state 0 { ( __h3_fail h ( h3_err_frame_unexpected ) ) ^ F } {}
    ? > flen + ( h3_default_max_field_section ) . h body_max { ( __h3_fail h ( h3_err_excessive_load ) ) ^ F } {}
    : i have - ( vec_len [u] . s buf ) hl
    ? < have flen {
        ? fin { ( __h3_fail h ( h3_err_frame_error ) ) } {}
        ^ F
    } {}
    : ( Vec u ) payload ( bytes_slice . s buf hl + hl flen )
    : ( Vec u ) rest ( bytes_slice . s buf + hl flen ( vec_len [u] . s buf ) )
    ( vec_free [u] . s buf )
    = . s buf rest
    ? == ft ( h3_ft_headers ) {
        ? == . s state 2 { ( vec_free [u] payload ) ( __h3_fail h ( h3_err_frame_unexpected ) ) ^ F } {}
        ? > flen . h max_field_section { ( vec_free [u] payload ) ( __h3_fail h ( h3_err_excessive_load ) ) ^ F } {}
        ?? ( qpack_decode_section payload ) {
            T hs → {
                ? == . s state 0 {
                    : i bad ( _h3_validate_request hs )
                    ? != bad 0 {
                        ( vec_free_with [Header] hs \ Header hh → v { ( header_free hh ) } )
                        ( vec_free [u] payload )
                        ( __h3_stream_error h s bad )
                        ^ F
                    } {}
                    ( vec_free_with [Header] . s headers \ Header hh → v { ( header_free hh ) } )
                    = . s headers hs
                    = . s state 1
                } {
                    // trailers: accepted, not surfaced
                    ( vec_free_with [Header] hs \ Header hh → v { ( header_free hh ) } )
                    = . s state 2
                }
            }
            F code → { ( vec_free [u] payload ) ( __h3_fail h code ) ^ F }
        }
    } {
        ? == ft ( h3_ft_data ) {
            ? == . s state 2 { ( vec_free [u] payload ) ( __h3_fail h ( h3_err_frame_unexpected ) ) ^ F } {}
            ? > + ( vec_len [u] . s body ) flen . h body_max { ( vec_free [u] payload ) ( __h3_stream_error h s ( h3_err_excessive_load ) ) ^ F } {}
            ( bytes_extend_bytes . s body payload )
        } {}
        // reserved / unknown types: skipped (§7.2.8, §9)
    }
    ( vec_free [u] payload )
    ^ T
}

// Process what has arrived on a request stream. `fin` says the peer
// has finished sending.
@ __h3_request_stream * H3Conn h * H3Stream s b fin ( @ HttpResponse HttpRequest ) handler → v {
    : ~ b more T
    ~ & & more == . s done 0 == . h failed 0 {
        : *H3FrameHead fh ( h3_frame_peek . s buf 0 )
        ? == # i fh 0 {
            ? & fin > ( vec_len [u] . s buf ) 0 { ( __h3_fail h ( h3_err_frame_error ) ) } {}
            = more F
        } {
            ? ! ( __h3_request_frame h s fin fh ) { = more F } {}
        }
    }
    ? & & fin == . s done 0 == . h failed 0 {
        ? == ( vec_len [u] . s buf ) 0 {
            ? >= . s state 1 { ( __h3_dispatch h s handler ) } { ( __h3_stream_error h s ( h3_err_request_incomplete ) ) }
        } {}
    } {}
}

// ── the peer's unidirectional streams ───────────────────────────

@ __h3_control_stream * H3Conn h * H3Stream s b fin → v {
    ~ & == . h failed 0 T {
        : *H3FrameHead fh ( h3_frame_peek . s buf 0 )
        ? == # i fh 0 { ? fin { ( __h3_fail h ( h3_err_closed_critical_stream ) ) } {} ^ } {}
        : i ft . fh ftype
        : i flen . fh length
        : i hl . fh head_len
        ( h3_frame_head_free fh )
        ? & == . h peer_settings 0 != ft ( h3_ft_settings ) { ? ( h3_type_is_reserved ft ) {} { ( __h3_fail h ( h3_err_missing_settings ) ) ^ } } {}
        ? & != . h peer_settings 0 == ft ( h3_ft_settings ) { ( __h3_fail h ( h3_err_frame_unexpected ) ) ^ } {}
        ? | | == ft ( h3_ft_data ) == ft ( h3_ft_headers ) == ft ( h3_ft_push_promise ) { ( __h3_fail h ( h3_err_frame_unexpected ) ) ^ } {}
        ? > flen 65536 { ( __h3_fail h ( h3_err_excessive_load ) ) ^ } {}
        : i have - ( vec_len [u] . s buf ) hl
        ? < have flen { ? fin { ( __h3_fail h ( h3_err_closed_critical_stream ) ) } {} ^ } {}
        : ( Vec u ) payload ( bytes_slice . s buf hl + hl flen )
        : ( Vec u ) rest ( bytes_slice . s buf + hl flen ( vec_len [u] . s buf ) )
        ( vec_free [u] . s buf )
        = . s buf rest
        ? == ft ( h3_ft_settings ) {
            : i bad ( h3_settings_parse payload )
            ? != bad 0 { ( vec_free [u] payload ) ( __h3_fail h bad ) ^ } {}
            = . h peer_settings 1
            // the peer's dynamic-table capacity must stay 0 for us
            // (we never insert); any value is fine to receive
            : i mfs ( h3_settings_get payload ( h3_setting_max_field_section_size ) )
            ? > mfs 0 { ? < mfs . h max_field_section { = . h max_field_section mfs } {} } {}
        } {}
        // CANCEL_PUSH, GOAWAY, MAX_PUSH_ID, reserved, unknown: nothing to do
        ( vec_free [u] payload )
    }
}

@ __h3_qpack_stream * H3Conn h * H3Stream s b fin b encoder → v {
    ~ & == . h failed 0 > ( vec_len [u] . s buf ) 0 {
        : i r ? encoder ( qpack_encoder_instruction . s buf 0 ) ( qpack_decoder_instruction . s buf 0 )
        ? == r -1 { ? fin { ( __h3_fail h ( h3_err_closed_critical_stream ) ) } {} ^ } {}
        ? == r -2 { ( __h3_fail h ? encoder ( qpack_err_encoder_stream ) ( qpack_err_decoder_stream ) ) ^ } {}
        : ( Vec u ) rest ( bytes_slice . s buf r ( vec_len [u] . s buf ) )
        ( vec_free [u] . s buf )
        = . s buf rest
    }
    ? & fin == . h failed 0 { ( __h3_fail h ( h3_err_closed_critical_stream ) ) } {}
}

// Classify a unidirectional stream by its first varint (§6.2).
@ __h3_classify * H3Conn h * H3Stream s → v {
    : i t ( quic_varint_read . s buf 0 )
    ? < t 0 { ^ } {}
    : i tl ( quic_varint_len_at . s buf 0 )
    : ( Vec u ) rest ( bytes_slice . s buf tl ( vec_len [u] . s buf ) )
    ( vec_free [u] . s buf )
    = . s buf rest
    ? == t ( h3_st_control ) {
        ? >= . h peer_control 0 { ( __h3_fail h ( h3_err_stream_creation ) ) ^ } {}
        = . h peer_control . s id
        = . s kind ( h3_kind_control )
        ^
    } {}
    ? == t ( h3_st_qpack_encoder ) {
        ? >= . h peer_qenc 0 { ( __h3_fail h ( h3_err_stream_creation ) ) ^ } {}
        = . h peer_qenc . s id
        = . s kind ( h3_kind_qpack_encoder )
        ^
    } {}
    ? == t ( h3_st_qpack_decoder ) {
        ? >= . h peer_qdec 0 { ( __h3_fail h ( h3_err_stream_creation ) ) ^ } {}
        = . h peer_qdec . s id
        = . s kind ( h3_kind_qpack_decoder )
        ^
    } {}
    ? == t ( h3_st_push ) { ( __h3_fail h ( h3_err_stream_creation ) ) ^ } {}
    // unknown type: stop reading it (§6.2.3). Release whatever was
    // buffered while its type was still unknown — from here on its bytes
    // are drained and discarded, never accumulated.
    = . s kind ( h3_kind_ignored )
    ( vec_clear [u] . s buf )
    ( quic_conn_stream_stop_sending . h qc . s id ( h3_err_stream_creation ) )
}

// ── the entry point ──────────────────────────────────────────────

@ __h3_on_stream * H3Conn h i id ( @ HttpResponse HttpRequest ) handler → v {
    : *QuicConn qc . h qc
    : ~ * H3Stream s ( __h3_stream_get h id )
    : b uni != & id 2 0
    ? == # i s 0 {
        ? & ( _qc_stream_is_server id ) T { ^ } {}
        = s ( __h3_stream_new id ? uni ( h3_kind_unknown ) ( h3_kind_request ) )
        ( vec_push [i] . h streams # i s )
    } {}
    ? != . s done 0 { ^ } {}
    // a reset request stream is simply gone
    ? >= ( quic_conn_stream_reset_err qc id ) 0 {
        ? | == . s kind ( h3_kind_control ) | == . s kind ( h3_kind_qpack_encoder ) == . s kind ( h3_kind_qpack_decoder ) { ( __h3_fail h ( h3_err_closed_critical_stream ) ) ^ } {}
        ( __h3_stream_drop h id )
        ^
    } {}
    // the peer asked us to stop: nothing more to do on this request
    ? >= ( quic_conn_stream_stop_err qc id ) 0 { = . s done 1 ( __h3_stream_drop h id ) ^ } {}
    // pull everything available
    : ~ b more T
    ~ more {
        : ( Vec u ) d ( quic_conn_stream_recv qc id 65536 )
        ? == ( vec_len [u] d ) 0 { = more F } {
            // An ignored unidirectional stream (unknown type, STOP_SENDING
            // already sent) must not buffer: a peer that ignores our
            // STOP_SENDING could otherwise grow . s buf without bound. Drain
            // and discard its bytes instead of accumulating them.
            ? == . s kind ( h3_kind_ignored ) {} {
                ( bytes_extend_bytes . s buf d )
            }
        }
        ( vec_free [u] d )
    }
    : b fin ( quic_conn_stream_fin qc id )
    ? == . s kind ( h3_kind_unknown ) { ( __h3_classify h s ) } {}
    ? == . h failed 0 {
        ? == . s kind ( h3_kind_request ) { ( __h3_request_stream h s fin handler ) } {}
        ? == . s kind ( h3_kind_control ) { ( __h3_control_stream h s fin ) } {}
        ? == . s kind ( h3_kind_qpack_encoder ) { ( __h3_qpack_stream h s fin T ) } {}
        ? == . s kind ( h3_kind_qpack_decoder ) { ( __h3_qpack_stream h s fin F ) } {}
    } {}
    ? & == . s kind ( h3_kind_request ) != . s done 0 { ( __h3_stream_drop h id ) } {}
    ? & == . s kind ( h3_kind_ignored ) fin { ( __h3_stream_drop h id ) } {}
}

@ h3_conn_on_readable * H3Conn h ( @ HttpResponse HttpRequest ) handler → v {
    : ( Vec i ) ids ( quic_conn_take_readable . h qc )
    : ~ i k 0
    ~ & < k ( vec_len [i] ids ) == . h failed 0 {
        ( __h3_on_stream h ( __h3_ri ids k ) handler )
        = k + k 1
    }
    ( vec_free [i] ids )
}
