// stdlib/net/stun.nu — minimal STUN client (RFC 8489 / 5389).
//
// **Phase 1 of TODO §7.4.** Discovers a node's server-reflexive (public)
// candidate: send a Binding request to a STUN server over the SAME UDP
// socket the transport uses, and read the XOR-MAPPED-ADDRESS the server
// observed. Binding only — no TURN, no auth, no IPv6 reflexive (IPv4 is
// the NAT case; native IPv6 is usually a direct path and skips STUN).
//
// The message codec is pure and deterministic (offline-testable); the
// `stun_query` wrapper adds the UDP round trip. XOR-MAPPED-ADDRESS
// de-obfuscation uses NURL's `^^` (bitwise XOR) operator.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/std/random.nu`

: StunAddr {
    String host
    i port
    i family  // 1 = IPv4, 2 = IPv6
}

@ stun_addr_free StunAddr a → v { ( string_free . a host ) }

// 0x2112A442
@ __stun_cookie → i { ^ 554869826 }

@ __u16 ( Vec u ) v i off → i { ^ ?? ( bytes_read_u16_be v off ) { T x → # i x F → -1 } }

@ __u32 ( Vec u ) v i off → i { ^ ?? ( bytes_read_u32_be v off ) { T x → # i x F → -1 } }

@ __b ( Vec u ) v i off → i { ^ ?? ( vec_get [u] v off ) { T x → # i x F → -1 } }

// 12 random transaction-ID bytes.
@ __txid → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( bytes_push_u32_be v # u32 ( rand_u64 ) )
    ( bytes_push_u32_be v # u32 ( rand_u64 ) )
    ( bytes_push_u32_be v # u32 ( rand_u64 ) )
    ^ v
}

: StunRequest {
    ( Vec u ) txid
    ( Vec u ) msg
}

@ stun_request_free StunRequest r → v {
    ( vec_free [u] . r txid )
    ( vec_free [u] . r msg )
}

// Build a Binding request carrying the given 12-byte transaction id.
@ stun_build_request_with ( Vec u ) txid → ( Vec u ) {
    : ( Vec u ) m ( vec_new [u] )
    ( bytes_push_u16_be m # u16 1 )  // type: Binding request
    ( bytes_push_u16_be m # u16 0 )  // length: no attributes
    ( bytes_push_u32_be m # u32 ( __stun_cookie ) )
    ( vec_extend [u] m txid )
    ^ m
}

@ stun_build_request → StunRequest {
    : ( Vec u ) txid ( __txid )
    ^ @ StunRequest { txid ( stun_build_request_with txid ) }
}

// Parse a Binding response. Verifies it is a success response (0x0101) with
// the magic cookie and matching transaction id, then extracts the
// (XOR-)MAPPED-ADDRESS. None on any mismatch / absence.
@ stun_parse ( Vec u ) msg ( Vec u ) txid → ?StunAddr {
    : i len ( vec_len [u] msg )
    ? < len 20 { ^ @ ?StunAddr { F # StunAddr 0 } } {}
    ? != ( __u16 msg 0 ) 257 { ^ @ ?StunAddr { F # StunAddr 0 } } {}  // 0x0101
    ? != ( __u32 msg 4 ) ( __stun_cookie ) { ^ @ ?StunAddr { F # StunAddr 0 } } {}
    : ~ b txok T
    : ~ i ti 0
    ~ & txok < ti 12 {
        ? != ( __b msg + 8 ti ) ( __b txid ti ) { = txok F } {}
        = ti + ti 1
    }
    ? ! txok { ^ @ ?StunAddr { F # StunAddr 0 } } {}

    // walk attributes
    : ~ i off 20
    : ~ ? StunAddr out @ ?StunAddr { F # StunAddr 0 }
    : ~ b found F
    ~ & ! found < + off 4 len {
        : i atype ( __u16 msg off )
        : i alen ( __u16 msg + off 2 )
        : i voff + off 4
        // XOR-MAPPED-ADDRESS (0x0020) or legacy MAPPED-ADDRESS (0x0001)
        ? | == atype 32 == atype 1 {
            : i fam ( __b msg + voff 1 )
            ? == fam 1 {
                : b is_xor == atype 32
                : i xport ( __u16 msg + voff 2 )
                : i port ? is_xor ^^ xport 8466 xport  // 8466 = 0x2112
                : i a0 ( __b msg + voff 4 )
                : i a1 ( __b msg + voff 5 )
                : i a2 ( __b msg + voff 6 )
                : i a3 ( __b msg + voff 7 )
                : i c ( __stun_cookie )
                : i o0 ? is_xor ^^ a0 & >> c 24 255 a0
                : i o1 ? is_xor ^^ a1 & >> c 16 255 a1
                : i o2 ? is_xor ^^ a2 & >> c 8 255 a2
                : i o3 ? is_xor ^^ a3 & c 255 a3
                : String h ( string_with_cap 16 )
                ( string_push_int h o0 ) ( string_push_char h 46 )
                ( string_push_int h o1 ) ( string_push_char h 46 )
                ( string_push_int h o2 ) ( string_push_char h 46 )
                ( string_push_int h o3 )
                = out @ ?StunAddr { T @ StunAddr { h port 1 } }
                = found T
            } {}
        } {}
        // attributes are padded to a 4-byte boundary
        : i pad ? == 0 % alen 4 0 - 4 % alen 4
        = off + + + off 4 alen pad
    }
    ^ out
}

// One STUN round trip on `sock` to `host:port`. None on timeout / bad reply.
@ stun_query UdpSocket sock s host i port i timeout_ms → ?StunAddr {
    ( udp_set_timeout sock timeout_ms )
    : StunRequest req ( stun_build_request )
    : !i NetErr sr ( udp_send_to sock . req msg host port )
    : ?StunAddr out ?? sr {
        T _ → {
            : !UdpPacket NetErr rr ( udp_recv_from sock 512 )
            ?? rr {
                T pkt → {
                    : ?StunAddr a ( stun_parse . pkt data . req txid )
                    ( udp_packet_free pkt )
                    a
                }
                F _ → @ ?StunAddr { F # StunAddr 0 }
            }
        }
        F _ → @ ?StunAddr { F # StunAddr 0 }
    }
    ( stun_request_free req )
    ^ out
}
