// stdlib/net/ipv4.nu — IPv4 header parse/build for the sans-IO stack.
//
// PURE — zero-copy parse in the same shape as net/eth (scalar header
// struct + payload offset/length into the caller's buffer).
//
// TWO CORRECTNESS POINTS THAT BITE EVERY HAND-ROLLED STACK
//
// 1. The payload length comes from the IP header's `total_len`, NEVER
//    from the received frame length. Ethernet pads frames to a 60-byte
//    minimum, so a 4-byte UDP payload arrives in a frame with 18 bytes
//    of trailing garbage. A stack that trusts the frame length hands
//    that padding to the application, and — worse — computes the UDP
//    checksum over it and rejects a perfectly good datagram.
//
// 2. Fragments are detected explicitly, not ignored. v1 does not
//    reassemble (see the unikernel plan), so a fragment must be
//    dropped with a distinct reason code. Silently parsing the first
//    fragment as a whole datagram would hand truncated data upward as
//    if it were complete — a correctness hole that looks like a flaky
//    peer for months.
//
// Header options (IHL > 5) are parsed and skipped, not rejected: the
// payload offset follows IHL. We never *emit* options.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`

// ── constants ────────────────────────────────────────────────────

@ ip_proto_icmp → i { ^ 1 }

@ ip_proto_tcp → i { ^ 6 }

@ ip_proto_udp → i { ^ 17 }

@ ip4_min_hdr → i { ^ 20 }

@ ip4_ok → i { ^ 0 }

@ ip4_err_short → i { ^ 1 }

@ ip4_err_version → i { ^ 2 }

@ ip4_err_ihl → i { ^ 3 }

@ ip4_err_checksum → i { ^ 4 }

@ ip4_err_truncated → i { ^ 5 }

@ ip4_err_fragment → i { ^ 6 }

// ── parse ────────────────────────────────────────────────────────

: Ip4Hdr {
    i ihl  // header length in BYTES, options included
    i tos
    i total_len
    i id
    i flags  // bit 0 = MF, bit 1 = DF (as carried, not shifted)
    i frag_off  // in 8-byte units, as carried
    i ttl
    i proto
    i src
    i dst
    i payload_off  // absolute offset into the buffer handed to ip4_parse
    i payload_len
    b valid
    i reason
}

@ __ip4_bad i reason → Ip4Hdr {
    ^ @ Ip4Hdr { 0 0 0 0 0 0 0 0 0 0 0 0 F reason }
}

// Parse the IPv4 datagram starting at `off` in `buf`, where `avail`
// bytes are actually present from `off` on (the Ethernet payload
// length — which may exceed total_len because of frame padding).
@ ip4_parse ( Vec u ) buf i off i avail → Ip4Hdr {
    ? < avail 20 { ^ ( __ip4_bad ( ip4_err_short ) ) } {}
    : i b0 ?? ( vec_get [u] buf off ) { T x → # i x F → 0 }
    ? != >> b0 4 4 { ^ ( __ip4_bad ( ip4_err_version ) ) } {}
    : i ihl * & b0 15 4
    ? || < ihl 20 > ihl avail { ^ ( __ip4_bad ( ip4_err_ihl ) ) } {}
    : i total ?? ( bytes_read_u16_be buf + off 2 ) { T x → # i x F → 0 }
    // total_len must cover the header and must not claim more bytes
    // than the link layer delivered.
    ? || < total ihl > total avail { ^ ( __ip4_bad ( ip4_err_truncated ) ) } {}
    ? != ( inet_fold ( inet_sum buf off ihl ) ) 65535 {
        ^ ( __ip4_bad ( ip4_err_checksum ) )
    } {}
    : i ff ?? ( bytes_read_u16_be buf + off 6 ) { T x → # i x F → 0 }
    : i flags >> ff 13
    : i frag & ff 8191
    // MF set or a non-zero offset ⇒ this is a fragment. v1 has no
    // reassembly; report it distinctly so the caller can count it.
    ? || == & flags 1 1 != frag 0 { ^ ( __ip4_bad ( ip4_err_fragment ) ) } {}
    ^ @ Ip4Hdr {
        ihl
        ?? ( vec_get [u] buf + off 1 ) { T x → # i x F → 0 }
        total
        ?? ( bytes_read_u16_be buf + off 4 ) { T x → # i x F → 0 }
        flags
        frag
        ?? ( vec_get [u] buf + off 8 ) { T x → # i x F → 0 }
        ?? ( vec_get [u] buf + off 9 ) { T x → # i x F → 0 }
        ?? ( bytes_read_u32_be buf + off 12 ) { T x → # i x F → 0 }
        ?? ( bytes_read_u32_be buf + off 16 ) { T x → # i x F → 0 }
        + off ihl
        - total ihl
        T
        ( ip4_ok )
    }
}

// ── build ────────────────────────────────────────────────────────

// Append a 20-byte IPv4 header with a correct checksum. `payload_len`
// is the length of what the caller appends next.
//
// `df` sets Don't-Fragment. We set it on everything we originate: this
// stack cannot reassemble replies to its own fragmented output either,
// so DF turns a silent black hole into an ICMP "fragmentation needed"
// the path-MTU logic above can actually see.
@ ip4_push_header ( Vec u ) out i src i dst i proto i payload_len i id i ttl b df → v {
    : i start ( vec_len [u] out )
    ( vec_push [u] out # u 69 )  // version 4, IHL 5
    ( vec_push [u] out # u 0 )  // TOS
    ( bytes_push_u16_be out # u16 & + 20 payload_len 65535 )
    ( bytes_push_u16_be out # u16 & id 65535 )
    ( bytes_push_u16_be out # u16 ? df 16384 0 )
    ( vec_push [u] out # u & ttl 255 )
    ( vec_push [u] out # u & proto 255 )
    ( bytes_push_u16_be out # u16 0 )  // checksum placeholder
    ( bytes_push_u32_be out # u32 & src 4294967295 )
    ( bytes_push_u32_be out # u32 & dst 4294967295 )
    : i ck ( inet_checksum out start 20 )
    : b _a ( vec_set [u] out + start 10 # u & >> ck 8 255 )
    : b _b ( vec_set [u] out + start 11 # u & ck 255 )
}

// ── pseudo-header ────────────────────────────────────────────────

// The 12-byte IPv4 pseudo-header sum used by UDP and TCP checksums:
// src, dst, zero, protocol, transport length. Returned as a partial
// accumulator so the caller folds it together with the real payload —
// no temporary buffer is ever built.
@ ip4_pseudo_sum i src i dst i proto i transport_len → i {
    : ~ i s 0
    = s ( inet_sum_u32 s src )
    = s ( inet_sum_u32 s dst )
    = s ( inet_sum_u16 s & proto 255 )
    = s ( inet_sum_u16 s & transport_len 65535 )
    ^ s
}
