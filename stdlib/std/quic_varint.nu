// stdlib/std/quic_varint.nu — QUIC variable-length integers (RFC 9000 §16)
// and packet-number encoding (RFC 9000 §17.1, Appendix A).
//
//   ( quic_varint_len_at buf off )        → i   1/2/4/8 from the first byte, 0 if `off` is past the end
//   ( quic_varint_read buf off )          → i   the value, or -1 if the encoding is truncated
//   ( quic_varint_size v )                → i   bytes the shortest encoding of v needs (1/2/4/8), 0 if v ≥ 2^62
//   ( quic_varint_push buf v )            → v   append the shortest encoding
//   ( quic_varint_push_len buf v len )    → v   append a fixed-length encoding (a Length field a packet
//                                                builder reserves before it knows the payload size)
//   ( quic_varint_max )                   → i   2^62 - 1
//
//   ( quic_pn_encode_len pn largest_acked )  → i   1..4 bytes so the peer can decode pn (App. A.2)
//   ( quic_pn_decode truncated pn_len largest) → i  full packet number (App. A.3)
//
// A varint is two length bits then 6/14/30/62 bits big-endian. Values are
// carried in `i` (i64); 2^62-1 fits, and anything the wire cannot carry is
// refused by `quic_varint_size` returning 0 rather than silently encoded.

$ `stdlib/core/vec.nu`

@ __qv_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ quic_varint_max → i { ^ 4611686018427387903 }

@ quic_varint_len_at ( Vec u ) buf i off → i {
    ? | < off 0 >= off ( vec_len [u] buf ) { ^ 0 } {}
    : i b ( __qv_bget buf off )
    : i tag >> b 6
    ? == tag 0 { ^ 1 } {}
    ? == tag 1 { ^ 2 } {}
    ? == tag 2 { ^ 4 } {}
    ^ 8
}

@ quic_varint_read ( Vec u ) buf i off → i {
    : i len ( quic_varint_len_at buf off )
    ? == len 0 { ^ -1 } {}
    ? > + off len ( vec_len [u] buf ) { ^ -1 } {}
    : ~ i v & ( __qv_bget buf off ) 63
    : ~ i k 1
    ~ < k len {
        = v | << v 8 ( __qv_bget buf + off k )
        = k + k 1
    }
    ^ v
}

@ quic_varint_size i v → i {
    ? < v 0 { ^ 0 } {}
    ? < v 64 { ^ 1 } {}
    ? < v 16384 { ^ 2 } {}
    ? < v 1073741824 { ^ 4 } {}
    ? <= v ( quic_varint_max ) { ^ 8 } {}
    ^ 0
}

@ quic_varint_push_len ( Vec u ) buf i v i len → v {
    : i tag ? == len 1 0 ? == len 2 1 ? == len 4 2 3
    : ~ i k - len 1
    ~ >= k 0 {
        : ~ i byte & >> v * 8 k 255
        ? == k - len 1 { = byte | & byte 63 << tag 6 } {}
        ( vec_push [u] buf # u byte )
        = k - k 1
    }
}

@ quic_varint_push ( Vec u ) buf i v → v {
    : i len ( quic_varint_size v )
    ? == len 0 { ^ } {}
    ( quic_varint_push_len buf v len )
}

// Packet number length: enough bits to cover twice the number of
// packets in flight (RFC 9000 Appendix A.2). `largest_acked` < 0 means
// nothing acknowledged yet, so the whole number must be sent.
@ quic_pn_encode_len i pn i largest_acked → i {
    : i range ? < largest_acked 0 + pn 1 - pn largest_acked
    : i need * 2 range
    ? < need 256 { ^ 1 } {}
    ? < need 65536 { ^ 2 } {}
    ? < need 16777216 { ^ 3 } {}
    ^ 4
}

// Recover the full packet number from its truncated form (Appendix A.3):
// the candidate closest to largest+1 within the encoded window.
@ quic_pn_decode i truncated i pn_len i largest → i {
    : i bits * 8 pn_len
    : i win << 1 bits
    : i hwin >> win 1
    : i mask - win 1
    : i expected + largest 1
    : i candidate | & expected ^^ mask -1 truncated
    : i lim - 4611686018427387904 win
    ? & <= candidate - expected hwin < candidate lim { ^ + candidate win } {}
    ? & > candidate + expected hwin >= candidate win { ^ - candidate win } {}
    ^ candidate
}
