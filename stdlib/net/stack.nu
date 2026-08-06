// stdlib/net/stack.nu — the sans-IO IPv4 stack: frames in, frames out.
//
// THE SANS-IO SEAM. This is the object a device driver talks to, and
// it is deliberately ignorant of devices, sockets, threads and clocks:
//
//     ( stack_rx st frame now out )   → RxResult   (may append a reply to `out`)
//     ( stack_tx_udp st … now out )   → TxResult   (may append an ARP request)
//     ( stack_tick st now out )       → i          (timers → frames)
//
// `now` is milliseconds from a monotonic source the *caller* owns, and
// every emitted frame is appended to a caller-owned `PktBuf` — frames,
// with their boundaries, not a byte soup the driver has to re-parse
// headers to cut up. A device transmits one frame at a time; a buffer
// that cannot say where a frame ends cannot be handed to one. Nothing in
// this file allocates a socket, blocks, or reads a clock — which is
// what lets the whole stack run under a scripted clock in a unit test
// on the host, and unmodified inside a unikernel against virtio-net.
//
// WHAT IT HANDLES (v1)
//   * ARP: answers requests for our address, learns from replies to
//     our own requests, resolves destinations before sending.
//   * ICMP: answers echo requests (this is what makes `ping` work).
//   * UDP: verifies and hands datagrams up; builds and addresses
//     outbound ones.
//   * Routing: on-link destinations go direct, everything else goes
//     via the gateway — the smallest routing table that is still a
//     routing table.
//
// WHAT IT REFUSES, ON PURPOSE
//   * IP fragments (no reassembly in v1) — counted, not silently
//     mis-parsed.
//   * Frames not addressed to us, foreign ARP, bad checksums — all
//     counted so a driver can expose honest statistics instead of a
//     vague "packet loss" feeling.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/eth.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/arp.nu`
$ `stdlib/net/icmp.nu`
$ `stdlib/net/udp4.nu`
$ `stdlib/net/pktbuf.nu`

// ── rx outcomes ──────────────────────────────────────────────────

@ rx_none → i { ^ 0 }  // consumed internally, nothing for the caller

@ rx_udp → i { ^ 1 }  // a UDP datagram is ready

@ rx_icmp_echo → i { ^ 2 }  // we answered a ping

@ rx_arp_handled → i { ^ 3 }

@ rx_dropped → i { ^ 4 }

// A TCP segment for us. This layer stops here on purpose: demultiplexing
// to a connection is the business of net/tcpstack.nu, which owns the
// table. What comes back is the IP payload's extent plus the addresses
// the pseudo-header checksum needs — everything the TCP parse requires
// and nothing it would have to be told twice.
@ rx_tcp → i { ^ 5 }

// drop reasons — every discarded frame lands in exactly one bucket
@ drop_not_for_us → i { ^ 0 }

@ drop_bad_eth → i { ^ 1 }

@ drop_unknown_ethertype → i { ^ 2 }

@ drop_bad_ip → i { ^ 3 }

@ drop_fragment → i { ^ 4 }

@ drop_not_our_ip → i { ^ 5 }

@ drop_bad_udp → i { ^ 6 }

@ drop_bad_icmp → i { ^ 7 }

@ drop_unknown_proto → i { ^ 8 }

@ drop_foreign_arp → i { ^ 9 }

@ n_drop_reasons → i { ^ 10 }

: RxResult {
    i kind
    i reason  // valid when kind == rx_dropped
    i src_ip
    i dst_ip
    i src_port
    i dst_port
    i payload_off  // into the frame passed to stack_rx
    i payload_len
    i emitted  // bytes appended to `out`
}

@ __rx_drop i reason → RxResult { ^ @ RxResult { ( rx_dropped ) reason 0 0 0 0 0 0 0 } }

// ── tx outcomes ──────────────────────────────────────────────────

@ tx_sent → i { ^ 0 }

@ tx_arp_pending → i { ^ 1 }  // an ARP request went out; retry later

@ tx_unreachable → i { ^ 2 }  // ARP gave up — report it, don't queue forever

@ tx_no_address → i { ^ 3 }  // we have no IP yet (DHCP still running)

: TxResult {
    i status
    i emitted
}

// ── the stack ────────────────────────────────────────────────────

: NetStack {
    i our_mac
    i our_ip
    i netmask
    i gateway
    * ArpCache arp
    i ip_id  // IPv4 identification counter for outbound datagrams
    i rx_frames
    i tx_frames
    ( Vec i ) drops  // indexed by drop reason
}

@ stack_new i mac i ip i netmask i gateway → *NetStack {
    : *NetStack st # *NetStack ( nurl_alloc Z NetStack )
    = . st our_mac mac
    = . st our_ip ip
    = . st netmask netmask
    = . st gateway gateway
    = . st arp ( arp_cache_new 64 )
    = . st ip_id 1
    = . st rx_frames 0
    = . st tx_frames 0
    = . st drops ( vec_with_cap [i] ( n_drop_reasons ) )
    : ~ i k 0
    ~ < k ( n_drop_reasons ) { ( vec_push [i] . st drops 0 ) = k + k 1 }
    ^ st
}

@ stack_free * NetStack st → v {
    ( arp_cache_free . st arp )
    ( vec_free [i] . st drops )
    ( free st )
}

// DHCP hands the address over once the lease is bound.
@ stack_set_address * NetStack st i ip i netmask i gateway → v {
    = . st our_ip ip
    = . st netmask netmask
    = . st gateway gateway
}

@ stack_drop_count * NetStack st i reason → i {
    ^ ?? ( vec_get [i] . st drops reason ) { T x → x F → 0 }
}

@ __count_drop * NetStack st i reason → v {
    : b _ok ( vec_set [i] . st drops reason + ( stack_drop_count st reason ) 1 )
}

@ __next_id * NetStack st → i {
    : i id . st ip_id
    = . st ip_id & + id 1 65535
    ^ id
}

// Which MAC should carry a datagram for `dst`? On-link destinations
// resolve to themselves; everything else goes to the gateway. Broadcast
// and directed-broadcast go to the Ethernet broadcast address.
// 127.0.0.0/8 is this machine, whatever address the interface has —
// `ipv4_is_loopback` lives in net/inet.nu with the rest of the address
// predicates, because the DHCP client needs the same question answered.
@ __next_hop * NetStack st i dst → i {
    // A datagram for ourselves goes to our own MAC, so it comes back
    // through the same door every other frame does. Loopback is not a
    // special case in the stack — it is a destination that happens to
    // be us, and the driver above decides that a frame addressed to
    // our own MAC never reaches the wire.
    ? ( ipv4_is_loopback dst ) { ^ dst } {}
    ? == dst . st our_ip { ^ dst } {}
    ? ( ipv4_is_broadcast dst ) { ^ dst } {}
    ? && != . st netmask 0 == dst ( ipv4_subnet_broadcast . st our_ip . st netmask ) { ^ 4294967295 } {}
    ? && != . st netmask 0 ( ipv4_in_subnet dst . st our_ip . st netmask ) { ^ dst } {}
    ? != . st gateway 0 { ^ . st gateway } {}
    ^ dst
}

// ── receive ──────────────────────────────────────────────────────

@ __rx_arp * NetStack st ( Vec u ) frame EthHdr eh i now * PktBuf out → RxResult {
    : ArpPkt ap ( arp_parse frame . eh payload_off . eh payload_len )
    ? ! . ap valid {
        ( __count_drop st ( drop_foreign_arp ) )
        ^ ( __rx_drop ( drop_foreign_arp ) )
    } {}
    // Learn only from traffic that concerns us: a reply we asked for,
    // or a request for our own address. Never from broadcast chatter —
    // that is the classic ARP-spoofing surface.
    ? == . ap op ( arp_op_reply ) {
        ? == . ap target_ip . st our_ip {
            ( arp_cache_insert . st arp . ap sender_ip . ap sender_mac now )
            ^ @ RxResult { ( rx_arp_handled ) 0 . ap sender_ip . st our_ip 0 0 0 0 0 }
        } {}
        ( __count_drop st ( drop_foreign_arp ) )
        ^ ( __rx_drop ( drop_foreign_arp ) )
    } {}
    // A request for us: learn the asker, then answer.
    ? && == . ap op ( arp_op_request ) && != . st our_ip 0 == . ap target_ip . st our_ip {
        ( arp_cache_insert . st arp . ap sender_ip . ap sender_mac now )
        : i before ( pktbuf_total out )
        ( arp_push_reply . out bytes . st our_mac . st our_ip . ap sender_mac . ap sender_ip )
        ( pktbuf_mark out )
        = . st tx_frames + . st tx_frames 1
        ^ @ RxResult { ( rx_arp_handled ) 0 . ap sender_ip . st our_ip 0 0 0 0 - ( pktbuf_total out ) before }
    } {}
    ( __count_drop st ( drop_foreign_arp ) )
    ^ ( __rx_drop ( drop_foreign_arp ) )
}

@ __rx_icmp * NetStack st ( Vec u ) frame Ip4Hdr ih i now * PktBuf out → RxResult {
    : IcmpMsg im ( icmp_parse frame . ih payload_off . ih payload_len )
    ? ! . im valid {
        ( __count_drop st ( drop_bad_icmp ) )
        ^ ( __rx_drop ( drop_bad_icmp ) )
    } {}
    ? != . im mtype ( icmp_echo_request ) {
        // Errors and other types are handed up: the caller may care
        // about "fragmentation needed", and silently eating ICMP is
        // how path-MTU black holes become permanent.
        ^ @ RxResult { ( rx_none ) 0 . ih src . ih dst . im mtype . im code . im payload_off . im payload_len 0 }
    } {}
    // Answer the ping. The reply goes to the sender's MAC directly —
    // it just spoke to us, so no ARP round-trip is needed.
    : i before ( pktbuf_total out )
    : ( Vec u ) msg ( vec_new [u] )
    ( icmp_push_echo_reply msg im frame )
    ( eth_push_header . out bytes . ( eth_parse frame ) src . st our_mac ( ethertype_ipv4 ) )
    // From the address it was sent TO — a ping to 127.0.0.1 is answered
    // by 127.0.0.1, not by whatever DHCP handed the interface.
    ( ip4_push_header . out bytes . ih dst . ih src ( ip_proto_icmp ) ( vec_len [u] msg ) ( __next_id st ) 64 T )
    ( vec_extend [u] . out bytes msg )
    ( vec_free [u] msg )
    ( pktbuf_mark out )
    = . st tx_frames + . st tx_frames 1
    ^ @ RxResult { ( rx_icmp_echo ) 0 . ih src . ih dst . im id . im seq . im payload_off . im payload_len - ( pktbuf_total out ) before }
}

// Feed one received frame. Any reply is appended to `out`; the caller
// transmits whatever `out` gained.
@ stack_rx * NetStack st ( Vec u ) frame i now * PktBuf out → RxResult {
    = . st rx_frames + . st rx_frames 1
    : EthHdr eh ( eth_parse frame )
    ? ! . eh valid {
        ( __count_drop st ( drop_bad_eth ) )
        ^ ( __rx_drop ( drop_bad_eth ) )
    } {}
    ? ! ( eth_addressed_to_us . eh dst . st our_mac ) {
        ( __count_drop st ( drop_not_for_us ) )
        ^ ( __rx_drop ( drop_not_for_us ) )
    } {}
    ? == . eh ethertype ( ethertype_arp ) { ^ ( __rx_arp st frame eh now out ) } {}
    ? != . eh ethertype ( ethertype_ipv4 ) {
        ( __count_drop st ( drop_unknown_ethertype ) )
        ^ ( __rx_drop ( drop_unknown_ethertype ) )
    } {}
    : Ip4Hdr ih ( ip4_parse frame . eh payload_off . eh payload_len )
    ? ! . ih valid {
        : i reason ? == . ih reason ( ip4_err_fragment ) ( drop_fragment ) ( drop_bad_ip )
        ( __count_drop st reason )
        ^ ( __rx_drop reason )
    } {}
    // Accept datagrams for our address, for broadcast, and (before
    // DHCP completes) for 255.255.255.255 — the DHCP reply itself
    // arrives before we own an address, so a strict "must match our
    // IP" test here would make the lease unobtainable.
    // Loopback is always ours, even before DHCP has given us anything
    // else: a program that talks to 127.0.0.1 does not care whether
    // the machine has an address on any network.
    : b for_us ? ( ipv4_is_loopback . ih dst ) T ? != . st our_ip 0 {
        || || == . ih dst . st our_ip ( ipv4_is_broadcast . ih dst ) && != . st netmask 0 == . ih dst ( ipv4_subnet_broadcast . st our_ip . st netmask )
    } ( ipv4_is_broadcast . ih dst )
    ? ! for_us {
        ( __count_drop st ( drop_not_our_ip ) )
        ^ ( __rx_drop ( drop_not_our_ip ) )
    } {}
    ? == . ih proto ( ip_proto_icmp ) { ^ ( __rx_icmp st frame ih now out ) } {}
    ? == . ih proto ( ip_proto_tcp ) {
        ^ @ RxResult {
            ( rx_tcp ) 0 . ih src . ih dst 0 0 . ih payload_off . ih payload_len 0
        }
    } {}
    ? == . ih proto ( ip_proto_udp ) {
        : Udp4Hdr uh ( udp4_parse frame . ih payload_off . ih payload_len . ih src . ih dst )
        ? ! . uh valid {
            ( __count_drop st ( drop_bad_udp ) )
            ^ ( __rx_drop ( drop_bad_udp ) )
        } {}
        ^ @ RxResult {
            ( rx_udp ) 0 . ih src . ih dst . uh src_port . uh dst_port . uh payload_off . uh payload_len 0
        }
    } {}
    ( __count_drop st ( drop_unknown_proto ) )
    ^ ( __rx_drop ( drop_unknown_proto ) )
}

// ── transmit ─────────────────────────────────────────────────────

// Send a UDP datagram. If the next hop is not in the ARP cache, an ARP
// request is emitted instead and `tx_arp_pending` is returned — the
// caller retries after the reply arrives. Returning "pending" rather
// than queueing internally keeps the buffer-ownership story simple:
// this module never holds on to the caller's payload.
// Frame and send an already-built layer-4 datagram. Routing, ARP and
// the Ethernet/IPv4 headers live here and nowhere else, so TCP and UDP
// resolve their next hop by the same code and a fix to it fixes both.
// `dg` is BORROWED — the caller built it and the caller frees it.
//
// On a cache miss this emits an ARP request and answers `tx_arp_pending`
// rather than queueing the datagram. Keeping the queue outside means
// this module never holds a pointer to someone else's buffer, and the
// retry is the caller's to schedule — which for TCP is free, because a
// segment that did not go out is exactly what its retransmit timer is
// already for.
//
// `src_ip` is the address the datagram is sent FROM, and it is a
// parameter rather than always `our_ip` because a machine has more than
// one address. A reply to something addressed to 127.0.0.1 must come
// FROM 127.0.0.1: the sender checksummed it over that pseudo-header, so
// a datagram that says otherwise is a datagram the receiver computes a
// different checksum for and silently discards as corrupt. That is
// exactly what happened — a guest with an interface address could not
// talk to itself over loopback at all, and nothing anywhere reported a
// drop, because a TCP segment failing its checksum is not a frame-level
// drop. Zero means "whatever this interface's address is".
@ stack_tx_ip4 * NetStack st i src_ip i dst_ip i proto ( Vec u ) dg i dg_off i dg_len i now * PktBuf out → TxResult {
    : i src ? != src_ip 0 src_ip . st our_ip
    ? == src 0 { ^ @ TxResult { ( tx_no_address ) 0 } } {}
    : i hop ( __next_hop st dst_ip )
    : ~ i dst_mac 0
    ? || ( ipv4_is_broadcast hop ) ( ipv4_is_multicast hop ) {
        = dst_mac ( mac_broadcast )
    } {
        : ?i found ( arp_cache_lookup . st arp hop now )
        = dst_mac ?? found { T m → m F → 0 }
    }
    ? == dst_mac 0 {
        ? ( arp_cache_failed . st arp hop now ) { ^ @ TxResult { ( tx_unreachable ) 0 } } {}
        ? ( arp_cache_should_request . st arp hop now ) {
            : i before ( pktbuf_total out )
            ( arp_push_request . out bytes . st our_mac . st our_ip hop )
            ( pktbuf_mark out )
            = . st tx_frames + . st tx_frames 1
            ^ @ TxResult { ( tx_arp_pending ) - ( pktbuf_total out ) before }
        } {}
        ^ @ TxResult { ( tx_arp_pending ) 0 }
    } {}
    : i before ( pktbuf_total out )
    ( eth_push_header . out bytes dst_mac . st our_mac ( ethertype_ipv4 ) )
    ( ip4_push_header . out bytes src dst_ip proto dg_len ( __next_id st ) 64 T )
    ( vec_extend_range [u] . out bytes dg dg_off dg_len )
    ( pktbuf_mark out )
    = . st tx_frames + . st tx_frames 1
    ^ @ TxResult { ( tx_sent ) - ( pktbuf_total out ) before }
}

// `src_ip` as above: zero means this interface's address, and a socket
// bound to loopback passes 127.0.0.1 so its datagrams checksum the way
// their receiver — itself — expects.
@ stack_tx_udp * NetStack st i src_ip i dst_ip i src_port i dst_port ( Vec u ) payload i pay_off i pay_len i now * PktBuf out → TxResult {
    : i src ? != src_ip 0 src_ip . st our_ip
    : ( Vec u ) dg ( vec_new [u] )
    ( udp4_push dg src dst_ip src_port dst_port payload pay_off pay_len )
    : TxResult r ( stack_tx_ip4 st src dst_ip ( ip_proto_udp ) dg 0 ( vec_len [u] dg ) now out )
    ( vec_free [u] dg )
    ^ r
}

// Broadcast a UDP datagram from 0.0.0.0 — the shape DHCP needs before
// an address exists, which the ordinary send path cannot express.
@ stack_tx_udp_broadcast * NetStack st i src_ip i src_port i dst_port i dst_ip ( Vec u ) payload i pay_off i pay_len * PktBuf out → i {
    : i before ( pktbuf_total out )
    : ( Vec u ) dg ( vec_new [u] )
    ( udp4_push dg src_ip dst_ip src_port dst_port payload pay_off pay_len )
    ( eth_push_header . out bytes ( mac_broadcast ) . st our_mac ( ethertype_ipv4 ) )
    ( ip4_push_header . out bytes src_ip dst_ip ( ip_proto_udp ) ( vec_len [u] dg ) ( __next_id st ) 64 T )
    ( vec_extend [u] . out bytes dg )
    ( vec_free [u] dg )
    ( pktbuf_mark out )
    = . st tx_frames + . st tx_frames 1
    ^ - ( pktbuf_total out ) before
}

// Periodic maintenance: expire stale ARP entries. Returns how many
// were reclaimed. Timers that emit frames (ARP retry) are driven by
// the send path, so this stays cheap enough to call every turn.
@ stack_tick * NetStack st i now * PktBuf out → i {
    ^ ( arp_cache_expire . st arp now )
}
