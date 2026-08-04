// stdlib/net/udp4.nu — UDP over IPv4 (RFC 768), sans-IO.
//
// PURE — parse and build. Named `udp4` to keep it distinct from
// `stdlib/std/udp.nu`, which is the host socket API; this module is
// the wire format the sans-IO stack speaks.
//
// TWO RULES THAT ARE EASY TO GET SUBTLY WRONG
//
// 1. Transmitted checksum 0 means "not computed". So when the computed
//    checksum happens to be 0x0000, the sender must transmit 0xFFFF
//    instead — the two are equal in one's-complement arithmetic, and
//    the substitution is what keeps a real checksum from being read as
//    "none". Roughly one datagram in 65536 hits this; a stack missing
//    it looks perfect in testing and corrupts rarely in production.
//
// 2. The checksum covers a pseudo-header (src, dst, proto, UDP length)
//    that is not on the wire. We accumulate it via `ip4_pseudo_sum`
//    and fold it together with the real bytes, so no scratch buffer is
//    built per datagram.
//
// On receive, checksum 0 means the sender skipped it and we accept the
// datagram unverified — mandatory per RFC 768 over IPv4.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/ipv4.nu`

@ udp4_hdr_len → i { ^ 8 }

@ udp4_ok → i { ^ 0 }

@ udp4_err_short → i { ^ 1 }

@ udp4_err_length → i { ^ 2 }

@ udp4_err_checksum → i { ^ 3 }

: Udp4Hdr {
    i src_port
    i dst_port
    i length  // header + payload, as carried
    i checksum
    i payload_off
    i payload_len
    b valid
    i reason
}

// Parse the UDP datagram at `off`, `avail` bytes present, verifying
// the checksum against the enclosing IPv4 addresses.
@ udp4_parse ( Vec u ) buf i off i avail i src_ip i dst_ip → Udp4Hdr {
    ? < avail 8 { ^ @ Udp4Hdr { 0 0 0 0 0 0 F ( udp4_err_short ) } } {}
    : i len ?? ( bytes_read_u16_be buf + off 4 ) { T x → # i x F → 0 }
    ? || < len 8 > len avail { ^ @ Udp4Hdr { 0 0 0 0 0 0 F ( udp4_err_length ) } } {}
    : i ck ?? ( bytes_read_u16_be buf + off 6 ) { T x → # i x F → 0 }
    ? != ck 0 {
        : i s ( inet_sum_add ( ip4_pseudo_sum src_ip dst_ip ( ip_proto_udp ) len ) buf off len )
        ? != ( inet_fold s ) 65535 {
            ^ @ Udp4Hdr { 0 0 0 0 0 0 F ( udp4_err_checksum ) }
        } {}
    } {}
    ^ @ Udp4Hdr {
        ?? ( bytes_read_u16_be buf off ) { T x → # i x F → 0 }
        ?? ( bytes_read_u16_be buf + off 2 ) { T x → # i x F → 0 }
        len
        ck
        + off 8
        - len 8
        T
        ( udp4_ok )
    }
}

// Append a complete UDP datagram (header + payload) with a correct
// checksum. Like ICMP, the payload is passed in because the checksum
// is a prefix field over suffix bytes.
@ udp4_push ( Vec u ) out i src_ip i dst_ip i src_port i dst_port ( Vec u ) payload i pay_off i pay_len → v {
    : i start ( vec_len [u] out )
    : i total + 8 pay_len
    ( bytes_push_u16_be out # u16 & src_port 65535 )
    ( bytes_push_u16_be out # u16 & dst_port 65535 )
    ( bytes_push_u16_be out # u16 & total 65535 )
    ( bytes_push_u16_be out # u16 0 )  // checksum placeholder
    : ~ i k 0
    ~ < k pay_len {
        ( vec_push [u] out ?? ( vec_get [u] payload + pay_off k ) { T x → x F → # u 0 } )
        = k + k 1
    }
    : i s ( inet_sum_add ( ip4_pseudo_sum src_ip dst_ip ( ip_proto_udp ) total ) out start total )
    : ~ i ck ( inet_finish s )
    // RFC 768: a computed zero is transmitted as all-ones, because a
    // transmitted zero means "no checksum".
    ? == ck 0 { = ck 65535 } {}
    : b _a ( vec_set [u] out + start 6 # u & >> ck 8 255 )
    : b _b ( vec_set [u] out + start 7 # u & ck 255 )
}
