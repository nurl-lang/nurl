// stdlib/net/icmp.nu — ICMPv4 echo + error messages, sans-IO.
//
// PURE — parse and build only.
//
// v1 handles echo request/reply (so the guest answers ping, the first
// end-to-end proof that rx and tx both work) and *parses* the error
// messages that matter to a stack with no fragmentation: destination
// unreachable, in particular code 4 "fragmentation needed", which is
// how a path-MTU black hole announces itself when we set DF.
//
// ICMPv4 checksums cover the ICMP message only — no pseudo-header
// (that is ICMPv6, and the difference is a classic silent-corruption
// bug when porting between the two).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/ipv4.nu`

// ── constants ────────────────────────────────────────────────────

@ icmp_echo_reply → i { ^ 0 }

@ icmp_dest_unreach → i { ^ 3 }

@ icmp_echo_request → i { ^ 8 }

@ icmp_time_exceeded → i { ^ 11 }

// Code 4 of destination-unreachable: "fragmentation needed and DF set".
@ icmp_code_frag_needed → i { ^ 4 }

@ icmp_hdr_len → i { ^ 8 }

// ── parse ────────────────────────────────────────────────────────

: IcmpMsg {
    i mtype
    i code
    i id  // echo: identifier. errors: unused/next-hop MTU high half.
    i seq  // echo: sequence. dest-unreach code 4: next-hop MTU.
    i payload_off
    i payload_len
    b valid
}

@ icmp_parse ( Vec u ) buf i off i len → IcmpMsg {
    ? < len 8 { ^ @ IcmpMsg { 0 0 0 0 0 0 F } } {}
    ? != ( inet_fold ( inet_sum buf off len ) ) 65535 {
        ^ @ IcmpMsg { 0 0 0 0 0 0 F }
    } {}
    ^ @ IcmpMsg {
        ?? ( vec_get [u] buf off ) { T x → # i x F → 0 }
        ?? ( vec_get [u] buf + off 1 ) { T x → # i x F → 0 }
        ?? ( bytes_read_u16_be buf + off 4 ) { T x → # i x F → 0 }
        ?? ( bytes_read_u16_be buf + off 6 ) { T x → # i x F → 0 }
        + off 8
        - len 8
        T
    }
}

// ── build ────────────────────────────────────────────────────────

// Append a complete ICMP message (header + payload) and fix up its
// checksum. Unlike the other layers, the payload is passed in rather
// than appended by the caller afterwards: the ICMP checksum covers
// header *and* payload, so the bytes must be present before the
// prefix field can be filled in.
@ icmp_push ( Vec u ) out i mtype i code i id i seq ( Vec u ) payload i pay_off i pay_len → v {
    : i start ( vec_len [u] out )
    ( vec_push [u] out # u & mtype 255 )
    ( vec_push [u] out # u & code 255 )
    ( bytes_push_u16_be out # u16 0 )  // checksum placeholder
    ( bytes_push_u16_be out # u16 & id 65535 )
    ( bytes_push_u16_be out # u16 & seq 65535 )
    : ~ i k 0
    ~ < k pay_len {
        ( vec_push [u] out ?? ( vec_get [u] payload + pay_off k ) { T x → x F → # u 0 } )
        = k + k 1
    }
    : i ck ( inet_checksum out start + 8 pay_len )
    : b _a ( vec_set [u] out + start 2 # u & >> ck 8 255 )
    : b _b ( vec_set [u] out + start 3 # u & ck 255 )
}

// An echo reply mirrors the request's identifier, sequence AND payload
// (RFC 792) — ping measures RTT by embedding a timestamp in the
// payload, so dropping it makes every ping report nonsense.
@ icmp_push_echo_reply ( Vec u ) out IcmpMsg req ( Vec u ) src → v {
    ( icmp_push out ( icmp_echo_reply ) 0 . req id . req seq src . req payload_off . req payload_len )
}
