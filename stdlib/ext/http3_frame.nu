// stdlib/ext/http3_frame.nu — HTTP/3 framing (RFC 9114 §7): frames are
// `type(varint) length(varint) payload`, stream types are one varint,
// SETTINGS are `id(varint) value(varint)` pairs. Pure codec.
//
//   ( h3_frame_peek buf off )            → *H3FrameHead   0 when the header is not complete yet
//   ( h3_frame_head_free h )             → v
//   ( h3_push_frame out ftype payload )  → v
//   ( h3_push_settings out max_field_section_size ) → v   the SETTINGS this endpoint sends
//   ( h3_settings_parse payload )        → i        0 ok · else H3_SETTINGS_ERROR (reserved H2 ids, dup)
//   ( h3_settings_get payload id )       → i        value or -1
//   ( h3_type_is_reserved t )            → b        0x1f * N + 0x21 grease (§7.2.8)
//
// Frame types: 0x0 DATA · 0x1 HEADERS · 0x3 CANCEL_PUSH · 0x4 SETTINGS ·
// 0x5 PUSH_PROMISE · 0x7 GOAWAY · 0xd MAX_PUSH_ID. Unidirectional stream
// types: 0x0 control · 0x1 push · 0x2 QPACK encoder · 0x3 QPACK decoder.
// Settings: 0x1 QPACK_MAX_TABLE_CAPACITY · 0x6 MAX_FIELD_SECTION_SIZE ·
// 0x7 QPACK_BLOCKED_STREAMS; 0x2–0x5 are HTTP/2's and forbidden.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/quic_varint.nu`

@ h3_ft_data → i { ^ 0 }

@ h3_ft_headers → i { ^ 1 }

@ h3_ft_cancel_push → i { ^ 3 }

@ h3_ft_settings → i { ^ 4 }

@ h3_ft_push_promise → i { ^ 5 }

@ h3_ft_goaway → i { ^ 7 }

@ h3_ft_max_push_id → i { ^ 13 }

@ h3_st_control → i { ^ 0 }

@ h3_st_push → i { ^ 1 }

@ h3_st_qpack_encoder → i { ^ 2 }

@ h3_st_qpack_decoder → i { ^ 3 }

@ h3_setting_qpack_max_table_capacity → i { ^ 1 }

@ h3_setting_max_field_section_size → i { ^ 6 }

@ h3_setting_qpack_blocked_streams → i { ^ 7 }

// Error codes (RFC 9114 §8.1)
@ h3_err_no_error → i { ^ 256 }

@ h3_err_general_protocol → i { ^ 257 }

@ h3_err_internal → i { ^ 258 }

@ h3_err_stream_creation → i { ^ 259 }

@ h3_err_closed_critical_stream → i { ^ 260 }

@ h3_err_frame_unexpected → i { ^ 261 }

@ h3_err_frame_error → i { ^ 262 }

@ h3_err_excessive_load → i { ^ 263 }

@ h3_err_id_error → i { ^ 264 }

@ h3_err_settings_error → i { ^ 265 }

@ h3_err_missing_settings → i { ^ 266 }

@ h3_err_request_rejected → i { ^ 267 }

@ h3_err_request_cancelled → i { ^ 268 }

@ h3_err_request_incomplete → i { ^ 269 }

@ h3_err_message_error → i { ^ 270 }

@ h3_err_connect_error → i { ^ 271 }

@ h3_err_version_fallback → i { ^ 272 }

@ h3_type_is_reserved i t → b {
    ? < t 33 { ^ F } {}
    ^ == % - t 33 31 0
}

: H3FrameHead {
    i ftype
    i length
    i head_len
}

@ h3_frame_head_free * H3FrameHead h → v {
    ? == # i h 0 { ^ } {}
    ( nurl_free # s h )
}

// The frame header at `off`, if all of it has arrived.
@ h3_frame_peek ( Vec u ) buf i off → *H3FrameHead {
    : i t ( quic_varint_read buf off )
    ? < t 0 { ^ # *H3FrameHead 0 } {}
    : i tl ( quic_varint_len_at buf off )
    : i l ( quic_varint_read buf + off tl )
    ? < l 0 { ^ # *H3FrameHead 0 } {}
    : i ll ( quic_varint_len_at buf + off tl )
    : *H3FrameHead h # *H3FrameHead ( nurl_alloc Z H3FrameHead )
    = . h ftype t
    = . h length l
    = . h head_len + tl ll
    ^ h
}

@ h3_push_frame ( Vec u ) out i ftype ( Vec u ) payload → v {
    ( quic_varint_push out ftype )
    ( quic_varint_push out ( vec_len [u] payload ) )
    ( bytes_extend_bytes out payload )
}

// SETTINGS: QPACK capacity 0, blocked streams 0, and the field-section cap.
@ h3_push_settings ( Vec u ) out i max_field_section_size → v {
    : ( Vec u ) p ( vec_new [u] )
    ( quic_varint_push p ( h3_setting_qpack_max_table_capacity ) )
    ( quic_varint_push p 0 )
    ( quic_varint_push p ( h3_setting_qpack_blocked_streams ) )
    ( quic_varint_push p 0 )
    ( quic_varint_push p ( h3_setting_max_field_section_size ) )
    ( quic_varint_push p max_field_section_size )
    ( h3_push_frame out ( h3_ft_settings ) p )
    ( vec_free [u] p )
}

// Validate a SETTINGS payload (§7.2.4): well-formed pairs, no HTTP/2
// identifiers (§7.2.4.1), no duplicates.
@ h3_settings_parse ( Vec u ) payload → i {
    : i n ( vec_len [u] payload )
    : ~ i off 0
    : ~ i seen 0
    ~ < off n {
        : i id ( quic_varint_read payload off )
        ? < id 0 { ^ ( h3_err_settings_error ) } {}
        = off + off ( quic_varint_len_at payload off )
        : i v ( quic_varint_read payload off )
        ? < v 0 { ^ ( h3_err_settings_error ) } {}
        = off + off ( quic_varint_len_at payload off )
        ? & >= id 2 <= id 5 { ^ ( h3_err_settings_error ) } {}
        ? < id 64 {
            : i bit << 1 id
            ? != & seen bit 0 { ^ ( h3_err_settings_error ) } {}
            = seen | seen bit
        } {}
    }
    ^ 0
}

@ h3_settings_get ( Vec u ) payload i want → i {
    : i n ( vec_len [u] payload )
    : ~ i off 0
    ~ < off n {
        : i id ( quic_varint_read payload off )
        ? < id 0 { ^ -1 } {}
        = off + off ( quic_varint_len_at payload off )
        : i v ( quic_varint_read payload off )
        ? < v 0 { ^ -1 } {}
        = off + off ( quic_varint_len_at payload off )
        ? == id want { ^ v } {}
    }
    ^ -1
}
