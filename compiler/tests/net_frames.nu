// net_frames.nu — offline test for the sans-IO frame layers:
// stdlib/net/{eth,ipv4,arp,icmp,udp4}.nu. Deterministic, no sockets,
// no clock — every timing input is scripted.
//
// The load-bearing cases here are the ones that silently corrupt a
// hand-rolled stack rather than failing loudly:
//   * Ethernet pads short frames to 60 bytes → the IP payload length
//     must come from total_len, never from the frame length.
//   * A UDP checksum that computes to 0 must go on the wire as 0xffff.
//   * Fragments must be rejected distinctly, not parsed as whole
//     datagrams.

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
$ `stdlib/net/stack.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ our_mac → i { ^ 2199023255553 }  // 02:00:00:00:00:01

@ peer_mac → i { ^ 2199023255554 }  // 02:00:00:00:00:02

@ our_ip → i { ^ ( ipv4_make 10 0 2 15 ) }

@ peer_ip → i { ^ ( ipv4_make 10 0 2 2 ) }

// A second peer on our own subnet that we have never exchanged a
// packet with, and a host beyond the router that we have not either.
@ stranger_ip → i { ^ ( ipv4_make 10 0 2 77 ) }

@ stranger_mac → i { ^ 2199023255629 }  // 02:00:00:00:00:4d

@ far_ip → i { ^ ( ipv4_make 198 51 100 9 ) }

@ router_mac → i { ^ 2199023255551 }  // 02:00:00:00:00:ff

@ our_mask → i { ^ ( ipv4_mask_from_prefix 24 ) }

@ our_gw → i { ^ ( ipv4_make 10 0 2 1 ) }

// Build an Ethernet+IPv4 frame from an arbitrary sender — the sender's
// MAC and IP separately, because the whole question below is whether
// the two get bound together.
@ mk_udp_frame_from i src_mac i src_ip → ( Vec u ) {
    : ( Vec u ) pay ( vec_new [u] )
    ( vec_push [u] pay # u 1 )
    : ( Vec u ) dg ( vec_new [u] )
    ( udp4_push dg src_ip ( our_ip ) 4243 53 pay 0 1 )
    : ( Vec u ) f ( vec_new [u] )
    ( eth_push_header f ( our_mac ) src_mac ( ethertype_ipv4 ) )
    ( ip4_push_header f src_ip ( our_ip ) ( ip_proto_udp ) ( vec_len [u] dg ) 4661 64 T )
    ( vec_extend [u] f dg )
    ~ < ( vec_len [u] f ) 60 { ( vec_push [u] f # u 0 ) }
    ( vec_free [u] dg )
    ( vec_free [u] pay )
    ^ f
}

// How long the stack takes to put an answer to `dst` on the wire,
// measured the way the wire measures it: the caller is TCP, so a
// datagram that did not go out is retried when the retransmit timer
// fires and not before. Answers the simulated milliseconds between the
// request arriving and the answer leaving, or -1 if it never left.
//
// This is the (delta-t, frame) shape the golden keeps. Recording only
// the frame passes whether the answer left at once or a second later,
// which is exactly the bug that hid here: the ARP resolved in 0.3 ms
// and the SYN-ACK it displaced left 856 ms after that, measured on a
// Firecracker tap with no DHCP and no slirp in the picture.
@ answer_delay_ms * NetStack st i dst i t0 → i {
    : ( Vec u ) dg ( vec_new [u] )
    ( vec_push [u] dg # u 7 )
    : ~ i now t0
    : ~ i sent_at -1
    : *PktBuf out ( pktbuf_new )
    ~ && == sent_at -1 <= now + t0 4000 {
        ( pktbuf_clear out )
        : TxResult t ( stack_tx_ip4 st 0 dst ( ip_proto_udp ) dg 0 1 now out )
        ? == . t status ( tx_sent ) { = sent_at now } { = now + now 1000 }
    }
    ( pktbuf_free out )
    ( vec_free [u] dg )
    ^ ? == sent_at -1 -1 - sent_at t0
}

// Build a full Ethernet+IPv4 frame carrying `payload`, as a peer would.
@ mk_ip_frame i proto ( Vec u ) payload i pad_to → ( Vec u ) {
    : ( Vec u ) f ( vec_new [u] )
    ( eth_push_header f ( our_mac ) ( peer_mac ) ( ethertype_ipv4 ) )
    ( ip4_push_header f ( peer_ip ) ( our_ip ) proto ( vec_len [u] payload ) 4660 64 T )
    ( vec_extend [u] f payload )
    // Ethernet pads to a 60-byte minimum frame — emulate the wire.
    ~ < ( vec_len [u] f ) pad_to { ( vec_push [u] f # u 0 ) }
    ^ f
}

@ main → i {
    // ── Ethernet ─────────────────────────────────────────────────
    : ( Vec u ) small ( vec_new [u] )
    ( eth_push_header small ( our_mac ) ( peer_mac ) ( ethertype_arp ) )
    : EthHdr eh ( eth_parse small )
    ( pb `eth parse valid: ` . eh valid )
    ( pb `eth dst: ` == . eh dst ( our_mac ) )
    ( pb `eth src: ` == . eh src ( peer_mac ) )
    ( pb `eth type arp: ` == . eh ethertype ( ethertype_arp ) )
    ( pb `eth payload off: ` == . eh payload_off 14 )
    : ( Vec u ) runt ( vec_new [u] )
    ( vec_push [u] runt # u 1 )
    ( pb `eth runt rejected: ` ! . ( eth_parse runt ) valid )
    ( pb `addressed to us: ` ( eth_addressed_to_us ( our_mac ) ( our_mac ) ) )
    ( pb `broadcast to us: ` ( eth_addressed_to_us ( mac_broadcast ) ( our_mac ) ) )
    ( pb `other unicast not ours: ` ! ( eth_addressed_to_us ( peer_mac ) ( our_mac ) ) )

    // ── IPv4 with Ethernet padding (the trap) ────────────────────
    // 4-byte UDP payload → 12-byte UDP datagram → 32-byte IP datagram
    // → 46-byte frame, padded to 60. total_len says 32.
    : ( Vec u ) udp_pay ( vec_new [u] )
    ( vec_push [u] udp_pay # u 222 ) ( vec_push [u] udp_pay # u 173 )
    ( vec_push [u] udp_pay # u 190 ) ( vec_push [u] udp_pay # u 239 )
    : ( Vec u ) udp_dg ( vec_new [u] )
    ( udp4_push udp_dg ( peer_ip ) ( our_ip ) 4242 53 udp_pay 0 4 )
    : ( Vec u ) padded ( mk_ip_frame ( ip_proto_udp ) udp_dg 60 )
    ( pb `padded frame is 60 bytes: ` == ( vec_len [u] padded ) 60 )
    : EthHdr peh ( eth_parse padded )
    : Ip4Hdr ph ( ip4_parse padded . peh payload_off . peh payload_len )
    ( pb `ip parse valid: ` . ph valid )
    ( pb `ip src: ` == . ph src ( peer_ip ) )
    ( pb `ip dst: ` == . ph dst ( our_ip ) )
    ( pb `ip proto udp: ` == . ph proto ( ip_proto_udp ) )
    // THE TRAP: eth payload_len is 46, but the IP payload is 12.
    ( pb `eth payload_len is padded (46): ` == . peh payload_len 46 )
    ( pb `ip payload_len from total_len (12): ` == . ph payload_len 12 )
    : Udp4Hdr uh ( udp4_parse padded . ph payload_off . ph payload_len . ph src . ph dst )
    ( pb `udp parse valid: ` . uh valid )
    ( pb `udp src port: ` == . uh src_port 4242 )
    ( pb `udp dst port: ` == . uh dst_port 53 )
    ( pb `udp payload_len is 4, not padding: ` == . uh payload_len 4 )
    ( pb `udp payload byte 0: ` == ?? ( vec_get [u] padded . uh payload_off ) { T x → # i x F → 0 } 222 )
    ( pb `udp payload byte 3: ` == ?? ( vec_get [u] padded + . uh payload_off 3 ) { T x → # i x F → 0 } 239 )

    // Feeding the *padded* length to udp4_parse must still work — the
    // length rule lives in the UDP header too.
    : Udp4Hdr uh2 ( udp4_parse padded . ph payload_off 46 . ph src . ph dst )
    ( pb `udp ignores trailing padding: ` && . uh2 valid == . uh2 payload_len 4 )

    // ── IPv4 rejections ──────────────────────────────────────────
    : ( Vec u ) bad ( mk_ip_frame ( ip_proto_udp ) udp_dg 60 )
    : b _c ( vec_set [u] bad 24 # u 255 )  // corrupt the IP checksum field
    ( pb `bad ip checksum rejected: ` == . ( ip4_parse bad 14 46 ) reason ( ip4_err_checksum ) )

    : ( Vec u ) frag ( mk_ip_frame ( ip_proto_udp ) udp_dg 60 )
    : b _f ( vec_set [u] frag 20 # u 32 )  // set MF in flags/frag field
    // recompute the header checksum so it fails *as a fragment*, not
    // as a checksum error — otherwise the test proves nothing.
    : b _f2 ( vec_set [u] frag 24 # u 0 )
    : b _f3 ( vec_set [u] frag 25 # u 0 )
    : i fck ( inet_checksum frag 14 20 )
    : b _f4 ( vec_set [u] frag 24 # u & >> fck 8 255 )
    : b _f5 ( vec_set [u] frag 25 # u & fck 255 )
    ( pb `fragment rejected distinctly: ` == . ( ip4_parse frag 14 46 ) reason ( ip4_err_fragment ) )

    : ( Vec u ) trunc ( vec_new [u] )
    ( eth_push_header trunc ( our_mac ) ( peer_mac ) ( ethertype_ipv4 ) )
    ( ip4_push_header trunc ( peer_ip ) ( our_ip ) ( ip_proto_udp ) 100 4660 64 T )
    ( pb `truncated (total_len > avail) rejected: ` == . ( ip4_parse trunc 14 20 ) reason ( ip4_err_truncated ) )

    // ── ICMP echo round-trip ─────────────────────────────────────
    : ( Vec u ) echo_pay ( vec_new [u] )
    : ~ i k 0
    ~ < k 32 { ( vec_push [u] echo_pay # u + 97 % k 26 ) = k + k 1 }
    : ( Vec u ) icmp_msg ( vec_new [u] )
    ( icmp_push icmp_msg ( icmp_echo_request ) 0 4919 7 echo_pay 0 32 )
    : ( Vec u ) ping ( mk_ip_frame ( ip_proto_icmp ) icmp_msg 60 )
    : EthHdr peh2 ( eth_parse ping )
    : Ip4Hdr pih ( ip4_parse ping . peh2 payload_off . peh2 payload_len )
    : IcmpMsg im ( icmp_parse ping . pih payload_off . pih payload_len )
    ( pb `icmp parse valid: ` . im valid )
    ( pb `icmp is echo request: ` == . im mtype ( icmp_echo_request ) )
    ( pb `icmp id: ` == . im id 4919 )
    ( pb `icmp seq: ` == . im seq 7 )
    ( pb `icmp payload_len: ` == . im payload_len 32 )

    // Build the reply the way the stack will, then parse it back.
    : ( Vec u ) reply_icmp ( vec_new [u] )
    ( icmp_push_echo_reply reply_icmp im ping )
    : ( Vec u ) reply ( vec_new [u] )
    ( eth_push_header reply ( peer_mac ) ( our_mac ) ( ethertype_ipv4 ) )
    ( ip4_push_header reply ( our_ip ) ( peer_ip ) ( ip_proto_icmp ) ( vec_len [u] reply_icmp ) 4661 64 T )
    ( vec_extend [u] reply reply_icmp )
    : EthHdr reh ( eth_parse reply )
    : Ip4Hdr rih ( ip4_parse reply . reh payload_off . reh payload_len )
    : IcmpMsg rim ( icmp_parse reply . rih payload_off . rih payload_len )
    ( pb `reply parses (checksum ok): ` . rim valid )
    ( pb `reply is echo reply: ` == . rim mtype ( icmp_echo_reply ) )
    ( pb `reply mirrors id: ` == . rim id 4919 )
    ( pb `reply mirrors seq: ` == . rim seq 7 )
    ( pb `reply mirrors payload len: ` == . rim payload_len 32 )
    : ~ b same T
    : ~ i j 0
    ~ < j 32 {
        : i a ?? ( vec_get [u] ping + . im payload_off j ) { T x → # i x F → -1 }
        : i b ?? ( vec_get [u] reply + . rim payload_off j ) { T x → # i x F → -2 }
        ? != a b { = same F } {}
        = j + j 1
    }
    ( pb `reply mirrors payload bytes: ` same )
    ( pb `reply src/dst swapped: ` && == . rih src ( our_ip ) == . rih dst ( peer_ip ) )

    // Corrupting the ICMP payload must break its checksum.
    : b _ic ( vec_set [u] reply + . rim payload_off 5 # u 0 )
    ( pb `corrupt icmp rejected: ` ! . ( icmp_parse reply . rih payload_off . rih payload_len ) valid )

    // ── UDP checksum: the 0 → 0xffff rule ────────────────────────
    // Sweep 2-byte payloads. Two invariants: the transmitted checksum
    // is never 0x0000, and every datagram we emit verifies on receive.
    // The sweep must also actually HIT the substitution case, or it
    // would pass on a stack that never implemented the rule.
    : ~ b never_zero T
    : ~ b all_verify T
    : ~ i hits 0
    : ~ i p 0
    ~ < p 65536 {
        : ( Vec u ) sp ( vec_new [u] )
        ( vec_push [u] sp # u >> p 8 )
        ( vec_push [u] sp # u & p 255 )
        : ( Vec u ) dg ( vec_new [u] )
        ( udp4_push dg ( peer_ip ) ( our_ip ) 1234 5678 sp 0 2 )
        : i ck ?? ( bytes_read_u16_be dg 6 ) { T x → # i x F → -1 }
        ? == ck 0 { = never_zero F } {}
        ? == ck 65535 { = hits + hits 1 } {}
        : Udp4Hdr vh ( udp4_parse dg 0 10 ( peer_ip ) ( our_ip ) )
        ? ! . vh valid { = all_verify F } {}
        ( vec_free [u] sp )
        ( vec_free [u] dg )
        = p + p 1
    }
    ( pb `udp checksum never transmitted as 0: ` never_zero )
    ( pb `every emitted udp datagram verifies: ` all_verify )
    ( pb `sweep exercised the 0xffff substitution: ` > hits 0 )

    // Receive side: checksum 0 means "not computed" and is accepted.
    : ( Vec u ) nock ( vec_new [u] )
    ( udp4_push nock ( peer_ip ) ( our_ip ) 1 2 udp_pay 0 4 )
    : b _n1 ( vec_set [u] nock 6 # u 0 )
    : b _n2 ( vec_set [u] nock 7 # u 0 )
    ( pb `udp checksum 0 accepted unverified: ` . ( udp4_parse nock 0 12 ( peer_ip ) ( our_ip ) ) valid )
    // …but a WRONG non-zero checksum is rejected.
    : b _n3 ( vec_set [u] nock 6 # u 1 )
    ( pb `wrong udp checksum rejected: ` == . ( udp4_parse nock 0 12 ( peer_ip ) ( our_ip ) ) reason ( udp4_err_checksum ) )
    // A length field larger than the bytes present is rejected.
    : b _n4 ( vec_set [u] nock 4 # u 255 )
    ( pb `udp bogus length rejected: ` == . ( udp4_parse nock 0 12 ( peer_ip ) ( our_ip ) ) reason ( udp4_err_length ) )

    // ── ARP wire format ──────────────────────────────────────────
    : ( Vec u ) req ( vec_new [u] )
    ( arp_push_request req ( our_mac ) ( our_ip ) ( peer_ip ) )
    ( pb `arp request frame len 42: ` == ( vec_len [u] req ) 42 )
    : EthHdr aeh ( eth_parse req )
    ( pb `arp request is broadcast: ` ( mac_is_broadcast . aeh dst ) )
    ( pb `arp ethertype: ` == . aeh ethertype ( ethertype_arp ) )
    : ArpPkt ap ( arp_parse req . aeh payload_off . aeh payload_len )
    ( pb `arp parse valid: ` . ap valid )
    ( pb `arp op request: ` == . ap op ( arp_op_request ) )
    ( pb `arp sender mac: ` == . ap sender_mac ( our_mac ) )
    ( pb `arp sender ip: ` == . ap sender_ip ( our_ip ) )
    ( pb `arp target ip: ` == . ap target_ip ( peer_ip ) )
    ( pb `arp target mac unknown: ` == . ap target_mac 0 )

    : ( Vec u ) rep ( vec_new [u] )
    ( arp_push_reply rep ( peer_mac ) ( peer_ip ) ( our_mac ) ( our_ip ) )
    : EthHdr reh2 ( eth_parse rep )
    ( pb `arp reply unicast to us: ` == . reh2 dst ( our_mac ) )
    : ArpPkt ap2 ( arp_parse rep . reh2 payload_off . reh2 payload_len )
    ( pb `arp reply op: ` == . ap2 op ( arp_op_reply ) )
    ( pb `arp reply sender is peer: ` && == . ap2 sender_mac ( peer_mac ) == . ap2 sender_ip ( peer_ip ) )
    ( pb `arp reply target is us: ` && == . ap2 target_mac ( our_mac ) == . ap2 target_ip ( our_ip ) )

    // Non-Ethernet/IPv4 ARP must be rejected, not mis-parsed.
    : b _a1 ( vec_set [u] rep 14 # u 0 )
    : b _a2 ( vec_set [u] rep 15 # u 6 )  // hardware type 6 = token ring
    ( pb `foreign arp htype rejected: ` ! . ( arp_parse rep 14 28 ) valid )

    // ── ARP cache with a scripted clock ──────────────────────────
    : *ArpCache c ( arp_cache_new 4 )
    ( pb `cold lookup misses: ` ?? ( arp_cache_lookup c ( peer_ip ) 1000 ) { T m → F F → T } )
    ( pb `first send asks: ` ( arp_cache_should_request c ( peer_ip ) 1000 ) )
    ( pb `immediate retry suppressed: ` ! ( arp_cache_should_request c ( peer_ip ) 1100 ) )
    ( pb `retry after 1s allowed: ` ( arp_cache_should_request c ( peer_ip ) 2000 ) )
    ( pb `not failed yet: ` ! ( arp_cache_failed c ( peer_ip ) 2000 ) )
    ( pb `third retry allowed: ` ( arp_cache_should_request c ( peer_ip ) 3100 ) )
    ( pb `fourth suppressed (max retries): ` ! ( arp_cache_should_request c ( peer_ip ) 4200 ) )
    ( pb `now reported failed: ` ( arp_cache_failed c ( peer_ip ) 4200 ) )
    ( arp_cache_insert c ( peer_ip ) ( peer_mac ) 5000 )
    ( pb `resolved lookup hits: ` ?? ( arp_cache_lookup c ( peer_ip ) 5000 ) { T m → == m ( peer_mac ) F → F } )
    ( pb `resolved stops requests: ` ! ( arp_cache_should_request c ( peer_ip ) 9000 ) )
    ( pb `no longer failed: ` ! ( arp_cache_failed c ( peer_ip ) 9000 ) )
    ( pb `lookup after ttl misses: ` ?? ( arp_cache_lookup c ( peer_ip ) 70000 ) { T m → F F → T } )
    ( pb `expire reclaims 1: ` == ( arp_cache_expire c 70000 ) 1 )
    ( pb `expire again reclaims 0: ` == ( arp_cache_expire c 70000 ) 0 )

    // The table is bounded: filling past `max` must not grow it, so a
    // remote peer cannot drive the cache into the whole heap.
    : ~ i q 0
    ~ < q 20 {
        ( arp_cache_insert c ( ipv4_make 10 0 9 q ) + 1000 q 80000 )
        = q + q 1
    }
    ( pb `cache stays bounded at max: ` == ( vec_len [ArpEntry] . c entries ) 4 )
    ( pb `most recent insert survived: ` ?? ( arp_cache_lookup c ( ipv4_make 10 0 9 19 ) 80000 ) { T m → == m 1019 F → F } )
    ( arp_cache_free c )

    // ── (delta-t, frame): WHEN the answer goes out ───────────────
    //
    // A peer on our own subnet that the cache has never heard of sends
    // us a datagram, and we answer it. The frame that comes back is
    // the same frame either way; the question the golden has to keep
    // is how long it took, because the whole defect was invisible to a
    // golden that kept only the frame.

    : *NetStack ls ( stack_new ( our_mac ) ( our_ip ) ( our_mask ) ( our_gw ) )
    : ( Vec u ) from_stranger ( mk_udp_frame_from ( stranger_mac ) ( stranger_ip ) )
    : *PktBuf lout ( pktbuf_new )
    : RxResult lr ( stack_rx ls from_stranger 1000 lout )
    ( pb `stranger's datagram accepted: ` == . lr kind ( rx_udp ) )
    ( pktbuf_clear lout )
    ( pb `answer to the stranger leaves at once (delta-t 0 ms): `
    == ( answer_delay_ms ls ( stranger_ip ) 1000 ) 0 )

    // The same measurement against a peer that has said nothing, so the
    // assertion above cannot pass for the wrong reason. Here the first
    // attempt emits an ARP request in the datagram's place; the peer
    // answers it three milliseconds later; and the datagram itself does
    // not leave until the caller retries, which for TCP is a
    // retransmit timer away. Delta-t 1000, for a resolution that took 3.
    : *NetStack qs ( stack_new ( our_mac ) ( our_ip ) ( our_mask ) ( our_gw ) )
    : i silent ( ipv4_make 10 0 2 88 )
    : ( Vec u ) qdg ( vec_new [u] )
    ( vec_push [u] qdg # u 7 )
    : *PktBuf qout ( pktbuf_new )
    : TxResult q1 ( stack_tx_ip4 qs 0 silent ( ip_proto_udp ) qdg 0 1 1000 qout )
    ( pb `a silent peer displaces the datagram with an ARP request: `
    == . q1 status ( tx_arp_pending ) )
    ( pktbuf_clear qout )
    : ( Vec u ) qrep ( vec_new [u] )
    ( arp_push_frame qrep ( arp_op_reply ) ( our_mac ) 2199023255630 silent ( our_mac ) ( our_ip ) )
    : RxResult qr ( stack_rx qs qrep 1003 qout )
    ( pb `the ARP reply lands 3 ms later: ` == . qr kind ( rx_arp_handled ) )
    ( pktbuf_clear qout )
    : TxResult q2 ( stack_tx_ip4 qs 0 silent ( ip_proto_udp ) qdg 0 1 2000 qout )
    ( pb `and the datagram waits for the retry, not for the ARP (delta-t 1000 ms): `
    == . q2 status ( tx_sent ) )
    ( pktbuf_free qout )
    ( vec_free [u] qdg ) ( vec_free [u] qrep )
    ( stack_free qs )

    // And the lie we must not learn: a datagram from beyond the router
    // arrives with the ROUTER's MAC in the Ethernet header. Binding the
    // far host's IP to it records a next hop that is not one.
    : ( Vec u ) from_far ( mk_udp_frame_from ( router_mac ) ( far_ip ) )
    : RxResult fr ( stack_rx ls from_far 1000 lout )
    ( pb `off-subnet datagram accepted: ` == . fr kind ( rx_udp ) )
    ( pktbuf_clear lout )
    ( pb `off-subnet sender is NOT learned: `
    ?? ( arp_cache_lookup . ls arp ( far_ip ) 1000 ) { T m → F F → T } )

    ( pktbuf_free lout )
    ( vec_free [u] from_stranger ) ( vec_free [u] from_far )
    ( stack_free ls )

    // Vec is a manually-managed handle (docs/MEMORY.md §7.4).
    ( vec_free [u] small ) ( vec_free [u] runt ) ( vec_free [u] udp_pay )
    ( vec_free [u] udp_dg ) ( vec_free [u] padded ) ( vec_free [u] bad )
    ( vec_free [u] frag ) ( vec_free [u] trunc ) ( vec_free [u] echo_pay )
    ( vec_free [u] icmp_msg ) ( vec_free [u] ping ) ( vec_free [u] reply_icmp )
    ( vec_free [u] reply ) ( vec_free [u] nock ) ( vec_free [u] req )
    ( vec_free [u] rep )
    ^ 0
}
