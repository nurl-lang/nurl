// stdlib/std/quic_tp.nu — QUIC transport parameters (RFC 9000 §18):
// the body of the `quic_transport_parameters` TLS extension (0x39),
// decoded with the checks §7.4 / §18.2 require of a server reading a
// client's, and encoded for a server's own.
//
//   ( quic_tp_new )                        → *QuicTp   RFC defaults (§18.2)
//   ( quic_tp_free tp )                    → v
//   ( quic_tp_decode bytes from_client )   → *QuicTp   0 when the encoding or a value is invalid
//                                                       (the caller closes with TRANSPORT_PARAMETER_ERROR)
//   ( quic_tp_encode tp is_server )        → ( Vec u )
//
// Presence of the connection-ID parameters is tracked with `has_*`
// flags; the numeric parameters carry their default when absent.
//
// What `quic_tp_decode` refuses, and why (each is an h3spec case):
//   * a parameter id appearing twice                         §7.4
//   * a value whose varint is truncated / length mismatched  §18
//   * from a client: original_destination_connection_id,
//     preferred_address, retry_source_connection_id,
//     stateless_reset_token present                          §18.2
//   * initial_source_connection_id absent                    §7.3
//   * max_udp_payload_size < 1200                            §18.2
//   * ack_delay_exponent > 20                                §18.2
//   * max_ack_delay ≥ 2^14                                   §18.2
//   * active_connection_id_limit < 2                         §18.2
//   * initial_max_streams_bidi / _uni > 2^60                 §4.6
//   * a connection ID longer than 20 bytes                   §17.2
// Unknown ids are skipped (§18.1 — extensions and GREASE).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/quic_varint.nu`

: QuicTp {
    i max_idle_timeout
    i max_udp_payload_size
    i initial_max_data
    i initial_max_stream_data_bidi_local
    i initial_max_stream_data_bidi_remote
    i initial_max_stream_data_uni
    i initial_max_streams_bidi
    i initial_max_streams_uni
    i ack_delay_exponent
    i max_ack_delay
    i disable_active_migration
    i active_connection_id_limit
    i has_original_dcid
    ( Vec u ) original_dcid
    i has_initial_scid
    ( Vec u ) initial_scid
    i has_retry_scid
    ( Vec u ) retry_scid
    i has_stateless_reset_token
    ( Vec u ) stateless_reset_token
    i max_datagram_frame_size
}

@ quic_tp_new → *QuicTp {
    : *QuicTp t # *QuicTp ( nurl_alloc Z QuicTp )
    = . t max_idle_timeout 0
    = . t max_udp_payload_size 65527
    = . t initial_max_data 0
    = . t initial_max_stream_data_bidi_local 0
    = . t initial_max_stream_data_bidi_remote 0
    = . t initial_max_stream_data_uni 0
    = . t initial_max_streams_bidi 0
    = . t initial_max_streams_uni 0
    = . t ack_delay_exponent 3
    = . t max_ack_delay 25
    = . t disable_active_migration 0
    = . t active_connection_id_limit 2
    = . t has_original_dcid 0
    = . t original_dcid ( vec_new [u] )
    = . t has_initial_scid 0
    = . t initial_scid ( vec_new [u] )
    = . t has_retry_scid 0
    = . t retry_scid ( vec_new [u] )
    = . t has_stateless_reset_token 0
    = . t stateless_reset_token ( vec_new [u] )
    = . t max_datagram_frame_size 0
    ^ t
}

@ quic_tp_free * QuicTp t → v {
    ? == # i t 0 { ^ } {}
    ( vec_free [u] . t original_dcid )
    ( vec_free [u] . t initial_scid )
    ( vec_free [u] . t retry_scid )
    ( vec_free [u] . t stateless_reset_token )
    ( nurl_free # s t )
}

@ __qtp_fail * QuicTp t → *QuicTp {
    ( quic_tp_free t )
    ^ # *QuicTp 0
}

// A varint value that must fill exactly `len` bytes at `off`.
@ __qtp_int ( Vec u ) buf i off i len → i {
    : i vl ( quic_varint_len_at buf off )
    ? | == vl 0 != vl len { ^ -1 } {}
    ^ ( quic_varint_read buf off )
}

@ quic_tp_decode ( Vec u ) buf b from_client → *QuicTp {
    : *QuicTp t ( quic_tp_new )
    : i n ( vec_len [u] buf )
    // 64 bits of "seen" for ids 0..63; anything above is unknown anyway.
    : ~ i seen 0
    : ~ i off 0
    ~ < off n {
        : i id ( quic_varint_read buf off )
        ? < id 0 { ^ ( __qtp_fail t ) } {}
        = off + off ( quic_varint_len_at buf off )
        : i len ( quic_varint_read buf off )
        ? < len 0 { ^ ( __qtp_fail t ) } {}
        = off + off ( quic_varint_len_at buf off )
        ? > + off len n { ^ ( __qtp_fail t ) } {}
        ? < id 64 {
            : i bit << 1 id
            ? != & seen bit 0 { ^ ( __qtp_fail t ) } {}
            = seen | seen bit
        } {}
        ? == id 0 {
            ? from_client { ^ ( __qtp_fail t ) } {}
            ? > len 20 { ^ ( __qtp_fail t ) } {}
            = . t has_original_dcid 1
            ( bytes_extend_raw . t original_dcid # s + # i ( vec_data [u] buf ) off len )
        } {}
        ? == id 1 {
            : i v ( __qtp_int buf off len )
            ? < v 0 { ^ ( __qtp_fail t ) } {}
            = . t max_idle_timeout v
        } {}
        ? == id 2 {
            ? from_client { ^ ( __qtp_fail t ) } {}
            ? != len 16 { ^ ( __qtp_fail t ) } {}
            = . t has_stateless_reset_token 1
            ( bytes_extend_raw . t stateless_reset_token # s + # i ( vec_data [u] buf ) off len )
        } {}
        ? == id 3 {
            : i v ( __qtp_int buf off len )
            ? | < v 1200 > v 65527 { ^ ( __qtp_fail t ) } {}
            = . t max_udp_payload_size v
        } {}
        ? == id 4 {
            : i v ( __qtp_int buf off len )
            ? < v 0 { ^ ( __qtp_fail t ) } {}
            = . t initial_max_data v
        } {}
        ? == id 5 {
            : i v ( __qtp_int buf off len )
            ? < v 0 { ^ ( __qtp_fail t ) } {}
            = . t initial_max_stream_data_bidi_local v
        } {}
        ? == id 6 {
            : i v ( __qtp_int buf off len )
            ? < v 0 { ^ ( __qtp_fail t ) } {}
            = . t initial_max_stream_data_bidi_remote v
        } {}
        ? == id 7 {
            : i v ( __qtp_int buf off len )
            ? < v 0 { ^ ( __qtp_fail t ) } {}
            = . t initial_max_stream_data_uni v
        } {}
        ? == id 8 {
            : i v ( __qtp_int buf off len )
            ? | < v 0 > v 1152921504606846976 { ^ ( __qtp_fail t ) } {}
            = . t initial_max_streams_bidi v
        } {}
        ? == id 9 {
            : i v ( __qtp_int buf off len )
            ? | < v 0 > v 1152921504606846976 { ^ ( __qtp_fail t ) } {}
            = . t initial_max_streams_uni v
        } {}
        ? == id 10 {
            : i v ( __qtp_int buf off len )
            ? | < v 0 > v 20 { ^ ( __qtp_fail t ) } {}
            = . t ack_delay_exponent v
        } {}
        ? == id 11 {
            : i v ( __qtp_int buf off len )
            ? | < v 0 >= v 16384 { ^ ( __qtp_fail t ) } {}
            = . t max_ack_delay v
        } {}
        ? == id 12 {
            ? != len 0 { ^ ( __qtp_fail t ) } {}
            = . t disable_active_migration 1
        } {}
        ? == id 13 {
            ? from_client { ^ ( __qtp_fail t ) } {}
            // A server's preferred_address is 4+2+16+2+1+cid+16 bytes; this
            // endpoint never uses one, so it is checked for shape and skipped.
            ? < len 41 { ^ ( __qtp_fail t ) } {}
        } {}
        ? == id 14 {
            : i v ( __qtp_int buf off len )
            ? < v 2 { ^ ( __qtp_fail t ) } {}
            = . t active_connection_id_limit v
        } {}
        ? == id 15 {
            ? > len 20 { ^ ( __qtp_fail t ) } {}
            = . t has_initial_scid 1
            ( bytes_extend_raw . t initial_scid # s + # i ( vec_data [u] buf ) off len )
        } {}
        ? == id 16 {
            ? from_client { ^ ( __qtp_fail t ) } {}
            ? > len 20 { ^ ( __qtp_fail t ) } {}
            = . t has_retry_scid 1
            ( bytes_extend_raw . t retry_scid # s + # i ( vec_data [u] buf ) off len )
        } {}
        ? == id 32 {
            : i v ( __qtp_int buf off len )
            ? < v 0 { ^ ( __qtp_fail t ) } {}
            = . t max_datagram_frame_size v
        } {}
        = off + off len
    }
    ? == . t has_initial_scid 0 { ^ ( __qtp_fail t ) } {}
    ^ t
}

@ __qtp_push_int ( Vec u ) out i id i v → v {
    ( quic_varint_push out id )
    ( quic_varint_push out ( quic_varint_size v ) )
    ( quic_varint_push out v )
}

@ __qtp_push_bytes ( Vec u ) out i id ( Vec u ) v → v {
    ( quic_varint_push out id )
    ( quic_varint_push out ( vec_len [u] v ) )
    ( bytes_extend_bytes out v )
}

// Encode. Defaults are omitted (they mean the same absent); the
// connection IDs are written when their `has_*` flag is set. A server
// writes original_destination_connection_id, stateless_reset_token and
// retry_source_connection_id; a client never does.
@ quic_tp_encode * QuicTp t b is_server → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] 128 )
    ? & is_server != . t has_original_dcid 0 { ( __qtp_push_bytes out 0 . t original_dcid ) } {}
    ? > . t max_idle_timeout 0 { ( __qtp_push_int out 1 . t max_idle_timeout ) } {}
    ? & is_server != . t has_stateless_reset_token 0 { ( __qtp_push_bytes out 2 . t stateless_reset_token ) } {}
    ? != . t max_udp_payload_size 65527 { ( __qtp_push_int out 3 . t max_udp_payload_size ) } {}
    ? > . t initial_max_data 0 { ( __qtp_push_int out 4 . t initial_max_data ) } {}
    ? > . t initial_max_stream_data_bidi_local 0 { ( __qtp_push_int out 5 . t initial_max_stream_data_bidi_local ) } {}
    ? > . t initial_max_stream_data_bidi_remote 0 { ( __qtp_push_int out 6 . t initial_max_stream_data_bidi_remote ) } {}
    ? > . t initial_max_stream_data_uni 0 { ( __qtp_push_int out 7 . t initial_max_stream_data_uni ) } {}
    ? > . t initial_max_streams_bidi 0 { ( __qtp_push_int out 8 . t initial_max_streams_bidi ) } {}
    ? > . t initial_max_streams_uni 0 { ( __qtp_push_int out 9 . t initial_max_streams_uni ) } {}
    ? != . t ack_delay_exponent 3 { ( __qtp_push_int out 10 . t ack_delay_exponent ) } {}
    ? != . t max_ack_delay 25 { ( __qtp_push_int out 11 . t max_ack_delay ) } {}
    ? != . t disable_active_migration 0 { ( quic_varint_push out 12 ) ( quic_varint_push out 0 ) } {}
    ? != . t active_connection_id_limit 2 { ( __qtp_push_int out 14 . t active_connection_id_limit ) } {}
    ? != . t has_initial_scid 0 { ( __qtp_push_bytes out 15 . t initial_scid ) } {}
    ? & is_server != . t has_retry_scid 0 { ( __qtp_push_bytes out 16 . t retry_scid ) } {}
    ? > . t max_datagram_frame_size 0 { ( __qtp_push_int out 32 . t max_datagram_frame_size ) } {}
    ^ out
}
