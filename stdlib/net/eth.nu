// stdlib/net/eth.nu — Ethernet II framing for the sans-IO stack.
//
// PURE — parse and build only; nothing here touches a device.
//
// ZERO-COPY PARSE. `eth_parse` does not copy the payload: it returns
// the header fields plus the payload's offset and length *into the
// caller's buffer*. The caller owns the frame for the whole parse
// chain (eth → ipv4 → udp/tcp), so every layer is a scalar struct and
// a pair of indices — no per-packet allocation, and no ownership
// transfer between layers. A stack that allocated a fresh buffer per
// layer would do four allocations per received frame.
//
// A parse failure is a value, not a panic: `valid = F` with a reason
// code. Malformed frames arrive from the network by definition, so
// rejecting them is normal control flow, and the reason code lets the
// device layer keep honest counters instead of dropping silently.
//
// NOT SUPPORTED IN v1 (deliberate, documented): 802.1Q VLAN tags and
// 802.3/LLC framing. Both parse as an unknown ethertype and are
// dropped by the layer above. The unikernel target sees a virtio-net
// device on a hypervisor-side switch, where neither appears.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`

// ── constants ────────────────────────────────────────────────────

@ eth_hdr_len → i { ^ 14 }

@ ethertype_ipv4 → i { ^ 2048 }

@ ethertype_arp → i { ^ 2054 }

@ ethertype_ipv6 → i { ^ 34525 }

// The largest payload an Ethernet II frame carries without jumbo
// frames. The stack's IPv4 MTU derives from this.
@ eth_mtu → i { ^ 1500 }

// Reason codes for a rejected frame — kept as small ints so the
// device layer can index a counter array directly.
@ eth_ok → i { ^ 0 }

@ eth_err_short → i { ^ 1 }

// ── parse ────────────────────────────────────────────────────────

: EthHdr {
    i dst
    i src
    i ethertype
    i payload_off
    i payload_len
    b valid
    i reason
}

@ __mac_at ( Vec u ) v i off → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 6 {
        : i b ?? ( vec_get [u] v + off k ) { T x → # i x F → 0 }
        = acc | << acc 8 b
        = k + k 1
    }
    ^ acc
}

@ eth_parse ( Vec u ) frame → EthHdr {
    : i n ( vec_len [u] frame )
    ? < n 14 {
        ^ @ EthHdr { 0 0 0 0 0 F ( eth_err_short ) }
    } {}
    : i et ?? ( bytes_read_u16_be frame 12 ) { T x → # i x F → 0 }
    ^ @ EthHdr {
        ( __mac_at frame 0 )
        ( __mac_at frame 6 )
        et
        14
        - n 14
        T
        ( eth_ok )
    }
}

// ── build ────────────────────────────────────────────────────────

@ eth_push_mac ( Vec u ) out i mac → v {
    : ~ i k 0
    ~ < k 6 {
        ( vec_push [u] out # u & >> mac * 8 - 5 k 255 )
        = k + k 1
    }
}

// Append a 14-byte Ethernet II header to `out`. The payload is the
// caller's to append next — keeping them separate is what lets the
// IPv4 layer write its header directly after this one with no splice.
@ eth_push_header ( Vec u ) out i dst i src i ethertype → v {
    ( eth_push_mac out dst )
    ( eth_push_mac out src )
    ( bytes_push_u16_be out # u16 & ethertype 65535 )
}

// Does this frame's destination address concern us? Accepts our
// unicast address, broadcast, and multicast (the stack above filters
// multicast groups it did not join).
@ eth_addressed_to_us i dst i our_mac → b {
    ^ || == dst our_mac || ( mac_is_broadcast dst ) ( mac_is_multicast dst )
}
