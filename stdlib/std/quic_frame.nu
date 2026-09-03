// stdlib/std/quic_frame.nu — QUIC v1 frames (RFC 9000 §19): parse one
// frame at a time out of a decrypted packet payload, build frames into
// a payload. Pure codec; the connection decides what a frame means.
//
//   ( quic_frame_parse buf off )       → *QuicFrame   0 on a malformed frame (FRAME_ENCODING_ERROR
//                                                     for the caller); `. f next` is the offset after it
//   ( quic_frame_free f )              → v
//   ( quic_frame_allowed ftype ptype ) → b            RFC 9000 §12.4 Table 3 (ptype as in quic_packet.nu)
//   ( quic_frame_is_ack_eliciting ftype ) → b         everything but PADDING, ACK, CONNECTION_CLOSE
//   ( quic_frame_type_name ftype )     → s            for logs
//
// Builders append to a payload Vec:
//
//   ( quic_push_padding out n ) · ( quic_push_ping out )
//   ( quic_push_ack out largest delay first_range ranges ect0 ect1 ce )   ranges = [gap, len, …] as in `ints`;
//                                                                        ect0 < 0 ⇒ plain ACK (type 0x02)
//   ( quic_push_reset_stream out id err final ) · ( quic_push_stop_sending out id err )
//   ( quic_push_crypto out off data ) · ( quic_push_new_token out token )
//   ( quic_push_stream out id off data fin )                     offset omitted when 0, length always present
//   ( quic_push_max_data out v ) · ( quic_push_max_stream_data out id v ) · ( quic_push_max_streams out bidi v )
//   ( quic_push_data_blocked out v ) · ( quic_push_stream_data_blocked out id v ) · ( quic_push_streams_blocked out bidi v )
//   ( quic_push_new_connection_id out seq retire cid token ) · ( quic_push_retire_connection_id out seq )
//   ( quic_push_path_challenge out data8 ) · ( quic_push_path_response out data8 )
//   ( quic_push_connection_close out code frame_type reason )    transport close (0x1c)
//   ( quic_push_application_close out code reason )              application close (0x1d)
//   ( quic_push_handshake_done out )
//
// One flat struct carries every frame: NURL enums take scalar payloads
// only, and a frame is at most four integers, one byte string and one
// integer list. Field use per type:
//
//   ftype   the frame type byte (STREAM: the full 0x08..0x0f value)
//   a b c d ACK: largest, ack_delay, first_range, ecn_count(0=none, 1=present)
//           RESET_STREAM: id, err, final_size · STOP_SENDING: id, err
//           CRYPTO: offset, length · STREAM: id, offset, length, fin(0/1)
//           MAX_*/…_BLOCKED: value (a) [, stream id in a and value in b]
//           MAX_STREAMS / STREAMS_BLOCKED: a = value, b = 1 bidi / 0 uni
//           NEW_CONNECTION_ID: seq, retire_prior_to · RETIRE_CONNECTION_ID: seq
//           CONNECTION_CLOSE: a = error code, b = offending frame type (0x1c), c = 1 for 0x1d
//   bytes   CRYPTO/STREAM data, NEW_TOKEN token, NEW_CONNECTION_ID cid (bytes) —
//           the 16-byte reset token follows the cid in the same Vec —
//           PATH_CHALLENGE/RESPONSE 8 bytes, CONNECTION_CLOSE reason
//   ints    ACK: [gap, range, gap, range, …] for the ranges after the first,
//           then ECN counts ect0, ect1, ce when d = 1
//   next    offset of the byte after this frame

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/quic_varint.nu`

: QuicFrame {
    i ftype
    i a
    i b
    i c
    i d
    ( Vec u ) bytes
    ( Vec i ) ints
    i next
}

@ quic_ft_padding → i { ^ 0 }

@ quic_ft_ping → i { ^ 1 }

@ quic_ft_ack → i { ^ 2 }

@ quic_ft_ack_ecn → i { ^ 3 }

@ quic_ft_reset_stream → i { ^ 4 }

@ quic_ft_stop_sending → i { ^ 5 }

@ quic_ft_crypto → i { ^ 6 }

@ quic_ft_new_token → i { ^ 7 }

@ quic_ft_stream → i { ^ 8 }

@ quic_ft_max_data → i { ^ 16 }

@ quic_ft_max_stream_data → i { ^ 17 }

@ quic_ft_max_streams_bidi → i { ^ 18 }

@ quic_ft_max_streams_uni → i { ^ 19 }

@ quic_ft_data_blocked → i { ^ 20 }

@ quic_ft_stream_data_blocked → i { ^ 21 }

@ quic_ft_streams_blocked_bidi → i { ^ 22 }

@ quic_ft_streams_blocked_uni → i { ^ 23 }

@ quic_ft_new_connection_id → i { ^ 24 }

@ quic_ft_retire_connection_id → i { ^ 25 }

@ quic_ft_path_challenge → i { ^ 26 }

@ quic_ft_path_response → i { ^ 27 }

@ quic_ft_connection_close → i { ^ 28 }

@ quic_ft_application_close → i { ^ 29 }

@ quic_ft_handshake_done → i { ^ 30 }

@ quic_frame_is_stream i ftype → b { ^ & >= ftype 8 <= ftype 15 }

@ __qf_new i ftype → *QuicFrame {
    : *QuicFrame f # *QuicFrame ( nurl_alloc Z QuicFrame )
    = . f ftype ftype
    = . f a 0
    = . f b 0
    = . f c 0
    = . f d 0
    = . f bytes ( vec_new [u] )
    = . f ints ( vec_new [i] )
    = . f next 0
    ^ f
}

@ quic_frame_free * QuicFrame f → v {
    ? == # i f 0 { ^ } {}
    ( vec_free [u] . f bytes )
    ( vec_free [i] . f ints )
    ( nurl_free # s f )
}

@ __qf_fail * QuicFrame f → *QuicFrame {
    ( quic_frame_free f )
    ^ # *QuicFrame 0
}

// Read a varint at `. f next`, advancing; -1 when truncated.
@ __qf_vi * QuicFrame f ( Vec u ) buf → i {
    : i v ( quic_varint_read buf . f next )
    ? < v 0 { ^ -1 } {}
    = . f next + . f next ( quic_varint_len_at buf . f next )
    ^ v
}

// Copy `n` bytes at `. f next` into `. f bytes`, advancing; F if short.
@ __qf_take * QuicFrame f ( Vec u ) buf i n → b {
    ? | < n 0 > + . f next n ( vec_len [u] buf ) { ^ F } {}
    ? > n 0 {
        : *u p ( vec_data [u] buf )
        ( bytes_extend_raw . f bytes # s + # i p . f next n )
    } {}
    = . f next + . f next n
    ^ T
}

@ quic_frame_parse ( Vec u ) buf i off → *QuicFrame {
    : i n ( vec_len [u] buf )
    ? | < off 0 >= off n { ^ # *QuicFrame 0 } {}
    : i ft ( quic_varint_read buf off )
    ? < ft 0 { ^ # *QuicFrame 0 } {}
    : *QuicFrame f ( __qf_new ft )
    = . f next + off ( quic_varint_len_at buf off )
    ? == ft 0 {
        // PADDING: swallow the whole run so a 1200-byte Initial is one frame.
        ~ & < . f next n == ( __qf_bget buf . f next ) 0 { = . f next + . f next 1 }
        ^ f
    } {}
    ? == ft 1 { ^ f } {}
    ? | == ft 2 == ft 3 {
        = . f a ( __qf_vi f buf )
        = . f b ( __qf_vi f buf )
        : i count ( __qf_vi f buf )
        = . f c ( __qf_vi f buf )
        ? | | | < . f a 0 < . f b 0 < count 0 < . f c 0 { ^ ( __qf_fail f ) } {}
        ? > . f c . f a { ^ ( __qf_fail f ) } {}
        : ~ i smallest - . f a . f c
        : ~ i i 0
        ~ < i count {
            : i gap ( __qf_vi f buf )
            : i len ( __qf_vi f buf )
            ? | < gap 0 < len 0 { ^ ( __qf_fail f ) } {}
            // Each range must fit below the previous one (§19.3.1).
            : i largest_next - - smallest gap 2
            ? < largest_next len { ^ ( __qf_fail f ) } {}
            = smallest - largest_next len
            ( vec_push [i] . f ints gap )
            ( vec_push [i] . f ints len )
            = i + i 1
        }
        ? == ft 3 {
            = . f d 1
            : ~ i e 0
            ~ < e 3 {
                : i v ( __qf_vi f buf )
                ? < v 0 { ^ ( __qf_fail f ) } {}
                ( vec_push [i] . f ints v )
                = e + e 1
            }
        } {}
        ^ f
    } {}
    ? == ft 4 {
        = . f a ( __qf_vi f buf )
        = . f b ( __qf_vi f buf )
        = . f c ( __qf_vi f buf )
        ? | | < . f a 0 < . f b 0 < . f c 0 { ^ ( __qf_fail f ) } {}
        ^ f
    } {}
    ? == ft 5 {
        = . f a ( __qf_vi f buf )
        = . f b ( __qf_vi f buf )
        ? | < . f a 0 < . f b 0 { ^ ( __qf_fail f ) } {}
        ^ f
    } {}
    ? == ft 6 {
        = . f a ( __qf_vi f buf )
        = . f b ( __qf_vi f buf )
        ? | < . f a 0 < . f b 0 { ^ ( __qf_fail f ) } {}
        ? > + . f a . f b ( quic_varint_max ) { ^ ( __qf_fail f ) } {}
        ? ! ( __qf_take f buf . f b ) { ^ ( __qf_fail f ) } {}
        ^ f
    } {}
    ? == ft 7 {
        : i tl ( __qf_vi f buf )
        ? <= tl 0 { ^ ( __qf_fail f ) } {}
        ? ! ( __qf_take f buf tl ) { ^ ( __qf_fail f ) } {}
        ^ f
    } {}
    ? ( quic_frame_is_stream ft ) {
        = . f a ( __qf_vi f buf )
        ? < . f a 0 { ^ ( __qf_fail f ) } {}
        ? != & ft 4 0 { = . f b ( __qf_vi f buf ) ? < . f b 0 { ^ ( __qf_fail f ) } {} } {}
        : ~ i len - n . f next
        ? != & ft 2 0 { = len ( __qf_vi f buf ) ? < len 0 { ^ ( __qf_fail f ) } {} } {}
        = . f c len
        = . f d ? != & ft 1 0 1 0
        ? > + . f b len ( quic_varint_max ) { ^ ( __qf_fail f ) } {}
        ? ! ( __qf_take f buf len ) { ^ ( __qf_fail f ) } {}
        ^ f
    } {}
    ? | | == ft 16 == ft 20 == ft 18 {
        = . f a ( __qf_vi f buf )
        ? < . f a 0 { ^ ( __qf_fail f ) } {}
        ? == ft 18 { = . f b 1 } {}
        ^ f
    } {}
    ? | | == ft 19 == ft 22 == ft 23 {
        = . f a ( __qf_vi f buf )
        ? < . f a 0 { ^ ( __qf_fail f ) } {}
        = . f b ? == ft 22 1 0
        ^ f
    } {}
    ? | == ft 17 == ft 21 {
        = . f a ( __qf_vi f buf )
        = . f b ( __qf_vi f buf )
        ? | < . f a 0 < . f b 0 { ^ ( __qf_fail f ) } {}
        ^ f
    } {}
    ? == ft 24 {
        = . f a ( __qf_vi f buf )
        = . f b ( __qf_vi f buf )
        ? | < . f a 0 < . f b 0 { ^ ( __qf_fail f ) } {}
        ? > . f b . f a { ^ ( __qf_fail f ) } {}
        ? >= . f next n { ^ ( __qf_fail f ) } {}
        : i cl ( __qf_bget buf . f next )
        = . f next + . f next 1
        ? | < cl 1 > cl 20 { ^ ( __qf_fail f ) } {}
        = . f c cl
        ? ! ( __qf_take f buf + cl 16 ) { ^ ( __qf_fail f ) } {}
        ^ f
    } {}
    ? == ft 25 {
        = . f a ( __qf_vi f buf )
        ? < . f a 0 { ^ ( __qf_fail f ) } {}
        ^ f
    } {}
    ? | == ft 26 == ft 27 {
        ? ! ( __qf_take f buf 8 ) { ^ ( __qf_fail f ) } {}
        ^ f
    } {}
    ? | == ft 28 == ft 29 {
        = . f a ( __qf_vi f buf )
        ? < . f a 0 { ^ ( __qf_fail f ) } {}
        ? == ft 28 { = . f b ( __qf_vi f buf ) ? < . f b 0 { ^ ( __qf_fail f ) } {} } { = . f c 1 }
        : i rl ( __qf_vi f buf )
        ? < rl 0 { ^ ( __qf_fail f ) } {}
        ? ! ( __qf_take f buf rl ) { ^ ( __qf_fail f ) } {}
        ^ f
    } {}
    ? == ft 30 { ^ f } {}
    // Anything else — including DATAGRAM (0x30/0x31), which this
    // endpoint has not negotiated — is unknown here.
    ^ ( __qf_fail f )
}

@ __qf_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

// RFC 9000 §12.4 Table 3. ptype: 0 Initial, 1 0-RTT, 2 Handshake, 4 1-RTT.
@ quic_frame_allowed i ftype i ptype → b {
    ? == ptype 4 { ^ T } {}
    ? | == ptype 0 == ptype 2 {
        ^ | | | | == ftype 0 == ftype 1 == ftype 2 == ftype 3 | == ftype 6 == ftype 28
    } {}
    // 0-RTT: no ACK, CRYPTO, NEW_TOKEN, PATH_RESPONSE, HANDSHAKE_DONE,
    // and RETIRE_CONNECTION_ID is allowed only for the client's own IDs
    // (we never send any in 0-RTT; refuse it here too).
    ? | | | | == ftype 2 == ftype 3 == ftype 6 == ftype 7 == ftype 27 { ^ F } {}
    ? | == ftype 30 == ftype 25 { ^ F } {}
    ^ T
}

@ quic_frame_is_ack_eliciting i ftype → b {
    ^ ! | | | == ftype 0 == ftype 2 == ftype 3 | == ftype 28 == ftype 29
}

@ quic_frame_type_name i ftype → s {
    ? == ftype 0 { ^ `PADDING` } {}
    ? == ftype 1 { ^ `PING` } {}
    ? | == ftype 2 == ftype 3 { ^ `ACK` } {}
    ? == ftype 4 { ^ `RESET_STREAM` } {}
    ? == ftype 5 { ^ `STOP_SENDING` } {}
    ? == ftype 6 { ^ `CRYPTO` } {}
    ? == ftype 7 { ^ `NEW_TOKEN` } {}
    ? ( quic_frame_is_stream ftype ) { ^ `STREAM` } {}
    ? == ftype 16 { ^ `MAX_DATA` } {}
    ? == ftype 17 { ^ `MAX_STREAM_DATA` } {}
    ? | == ftype 18 == ftype 19 { ^ `MAX_STREAMS` } {}
    ? == ftype 20 { ^ `DATA_BLOCKED` } {}
    ? == ftype 21 { ^ `STREAM_DATA_BLOCKED` } {}
    ? | == ftype 22 == ftype 23 { ^ `STREAMS_BLOCKED` } {}
    ? == ftype 24 { ^ `NEW_CONNECTION_ID` } {}
    ? == ftype 25 { ^ `RETIRE_CONNECTION_ID` } {}
    ? == ftype 26 { ^ `PATH_CHALLENGE` } {}
    ? == ftype 27 { ^ `PATH_RESPONSE` } {}
    ? == ftype 28 { ^ `CONNECTION_CLOSE` } {}
    ? == ftype 29 { ^ `CONNECTION_CLOSE_APP` } {}
    ? == ftype 30 { ^ `HANDSHAKE_DONE` } {}
    ^ `UNKNOWN`
}

// ── Builders ─────────────────────────────────────────────────────

@ quic_push_padding ( Vec u ) out i n → v {
    : ~ i i 0
    ~ < i n { ( vec_push [u] out # u 0 ) = i + i 1 }
}

@ quic_push_ping ( Vec u ) out → v { ( vec_push [u] out # u 1 ) }

// `ranges` = [gap, len, gap, len, …] after the first range (the
// encoding of §19.3.1, i.e. exactly what a parsed frame's `ints`
// holds); `ecn` < 0 for a plain ACK, otherwise ect0/ect1/ce follow.
@ quic_push_ack ( Vec u ) out i largest i delay i first_range ( Vec i ) ranges i ect0 i ect1 i ce → v {
    : b ecn >= ect0 0
    ( vec_push [u] out # u ? ecn 3 2 )
    ( quic_varint_push out largest )
    ( quic_varint_push out delay )
    ( quic_varint_push out / ( vec_len [i] ranges ) 2 )
    ( quic_varint_push out first_range )
    : ~ i i 0
    ~ < i ( vec_len [i] ranges ) {
        ( quic_varint_push out ?? ( vec_get [i] ranges i ) { T x → x F → 0 } )
        = i + i 1
    }
    ? ecn {
        ( quic_varint_push out ect0 )
        ( quic_varint_push out ect1 )
        ( quic_varint_push out ce )
    } {}
}

@ quic_push_reset_stream ( Vec u ) out i id i err i final → v {
    ( vec_push [u] out # u 4 )
    ( quic_varint_push out id )
    ( quic_varint_push out err )
    ( quic_varint_push out final )
}

@ quic_push_stop_sending ( Vec u ) out i id i err → v {
    ( vec_push [u] out # u 5 )
    ( quic_varint_push out id )
    ( quic_varint_push out err )
}

@ quic_push_crypto ( Vec u ) out i off ( Vec u ) data → v {
    ( vec_push [u] out # u 6 )
    ( quic_varint_push out off )
    ( quic_varint_push out ( vec_len [u] data ) )
    ( bytes_extend_bytes out data )
}

@ quic_push_new_token ( Vec u ) out ( Vec u ) token → v {
    ( vec_push [u] out # u 7 )
    ( quic_varint_push out ( vec_len [u] token ) )
    ( bytes_extend_bytes out token )
}

// Bytes a STREAM frame with these fields costs before its data.
@ quic_stream_frame_overhead i id i off i len → i {
    ^ + + 1 ( quic_varint_size id ) + ? > off 0 ( quic_varint_size off ) 0 ( quic_varint_size len )
}

@ quic_push_stream ( Vec u ) out i id i off ( Vec u ) data b fin → v {
    : i ft | | 8 ? fin 1 0 | 2 ? > off 0 4 0
    ( vec_push [u] out # u ft )
    ( quic_varint_push out id )
    ? > off 0 { ( quic_varint_push out off ) } {}
    ( quic_varint_push out ( vec_len [u] data ) )
    ( bytes_extend_bytes out data )
}

@ quic_push_max_data ( Vec u ) out i v → v {
    ( vec_push [u] out # u 16 )
    ( quic_varint_push out v )
}

@ quic_push_max_stream_data ( Vec u ) out i id i v → v {
    ( vec_push [u] out # u 17 )
    ( quic_varint_push out id )
    ( quic_varint_push out v )
}

@ quic_push_max_streams ( Vec u ) out b bidi i v → v {
    ( vec_push [u] out # u ? bidi 18 19 )
    ( quic_varint_push out v )
}

@ quic_push_data_blocked ( Vec u ) out i v → v {
    ( vec_push [u] out # u 20 )
    ( quic_varint_push out v )
}

@ quic_push_stream_data_blocked ( Vec u ) out i id i v → v {
    ( vec_push [u] out # u 21 )
    ( quic_varint_push out id )
    ( quic_varint_push out v )
}

@ quic_push_streams_blocked ( Vec u ) out b bidi i v → v {
    ( vec_push [u] out # u ? bidi 22 23 )
    ( quic_varint_push out v )
}

@ quic_push_new_connection_id ( Vec u ) out i seq i retire ( Vec u ) cid ( Vec u ) token → v {
    ( vec_push [u] out # u 24 )
    ( quic_varint_push out seq )
    ( quic_varint_push out retire )
    ( vec_push [u] out # u ( vec_len [u] cid ) )
    ( bytes_extend_bytes out cid )
    ( bytes_extend_bytes out token )
}

@ quic_push_retire_connection_id ( Vec u ) out i seq → v {
    ( vec_push [u] out # u 25 )
    ( quic_varint_push out seq )
}

@ quic_push_path_challenge ( Vec u ) out ( Vec u ) data8 → v {
    ( vec_push [u] out # u 26 )
    ( bytes_extend_bytes out data8 )
}

@ quic_push_path_response ( Vec u ) out ( Vec u ) data8 → v {
    ( vec_push [u] out # u 27 )
    ( bytes_extend_bytes out data8 )
}

@ quic_push_connection_close ( Vec u ) out i code i frame_type ( Vec u ) reason → v {
    ( vec_push [u] out # u 28 )
    ( quic_varint_push out code )
    ( quic_varint_push out frame_type )
    ( quic_varint_push out ( vec_len [u] reason ) )
    ( bytes_extend_bytes out reason )
}

@ quic_push_application_close ( Vec u ) out i code ( Vec u ) reason → v {
    ( vec_push [u] out # u 29 )
    ( quic_varint_push out code )
    ( quic_varint_push out ( vec_len [u] reason ) )
    ( bytes_extend_bytes out reason )
}

@ quic_push_handshake_done ( Vec u ) out → v { ( vec_push [u] out # u 30 ) }
