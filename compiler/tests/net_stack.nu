// net_stack.nu — Phase A1a acceptance test for stdlib/net/stack.nu.
//
// Two sans-IO stacks are wired frame-to-frame in memory, with a
// scripted clock, and made to complete the exchanges a real host does:
// ARP resolution, a UDP round-trip, a ping answered, and routing via a
// gateway for an off-link destination. No sockets, no device, no
// wall clock — the same code that will later sit behind virtio-net.
//
// Also pins the drop accounting: every frame the stack discards must
// land in exactly one labelled bucket, so a driver can report honest
// counters instead of "some packets go missing".

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/pktbuf.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/eth.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/arp.nu`
$ `stdlib/net/icmp.nu`
$ `stdlib/net/udp4.nu`
$ `stdlib/net/stack.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ mac_a → i { ^ 2199023255553 }  // 02:00:00:00:00:01

@ mac_b → i { ^ 2199023255554 }  // 02:00:00:00:00:02

@ mac_gw → i { ^ 2199023255807 }  // 02:00:00:00:00:ff

@ ip_a → i { ^ ( ipv4_make 10 0 2 15 ) }

@ ip_b → i { ^ ( ipv4_make 10 0 2 16 ) }

@ ip_gw → i { ^ ( ipv4_make 10 0 2 1 ) }

@ mask24 → i { ^ 4294967040 }

// Move everything in `wire` into `dst` stack, returning the number of
// frames delivered. One frame per buffer keeps the harness honest —
// the real driver hands over one frame at a time too.
@ deliver * NetStack dst ( Vec u ) wire i now * PktBuf reply → RxResult {
    ^ ( stack_rx dst wire now reply )
}

@ main → i {
    : *NetStack a ( stack_new ( mac_a ) ( ip_a ) ( mask24 ) ( ip_gw ) )
    : *NetStack b ( stack_new ( mac_b ) ( ip_b ) ( mask24 ) ( ip_gw ) )

    : ( Vec u ) payload ( vec_new [u] )
    ( bytes_extend_str payload `hello unikernel` )

    // ── A sends UDP to B: ARP must resolve first ─────────────────
    : *PktBuf w1 ( pktbuf_new )
    : TxResult t1 ( stack_tx_udp a 0 ( ip_b ) 4000 7000 payload 0 15 1000 w1 )
    ( pb `first send is ARP-pending: ` == . t1 status ( tx_arp_pending ) )
    ( pb `an ARP request was emitted: ` > . t1 emitted 0 )
    ( pb `one frame out, and it is the 42-byte ARP request: ` && == ( pktbuf_count w1 ) 1 == ( pktbuf_len w1 0 ) 42 )

    // B receives the ARP request and answers it.
    : *PktBuf w2 ( pktbuf_new )
    : RxResult r1 ( deliver b . w1 bytes 1000 w2 )
    ( pb `B handled the ARP: ` == . r1 kind ( rx_arp_handled ) )
    ( pb `B emitted a reply: ` == ( pktbuf_count w2 ) 1 )
    ( pb `B learned A's address: ` ?? ( arp_cache_lookup . b arp ( ip_a ) 1000 ) { T m → == m ( mac_a ) F → F } )

    // A receives the reply and learns B.
    : *PktBuf w3 ( pktbuf_new )
    : RxResult r2 ( deliver a . w2 bytes 1000 w3 )
    ( pb `A handled the ARP reply: ` == . r2 kind ( rx_arp_handled ) )
    ( pb `A emitted nothing back: ` == ( pktbuf_count w3 ) 0 )
    ( pb `A learned B's address: ` ?? ( arp_cache_lookup . a arp ( ip_b ) 1000 ) { T m → == m ( mac_b ) F → F } )

    // ── retry: now the datagram actually goes out ────────────────
    : *PktBuf w4 ( pktbuf_new )
    : TxResult t2 ( stack_tx_udp a 0 ( ip_b ) 4000 7000 payload 0 15 1000 w4 )
    ( pb `retry sends for real: ` == . t2 status ( tx_sent ) )
    // 14 eth + 20 ip + 8 udp + 15 payload = 57
    ( pb `frame is 57 bytes: ` && == ( pktbuf_count w4 ) 1 == ( pktbuf_len w4 0 ) 57 )

    : *PktBuf w5 ( pktbuf_new )
    : RxResult r3 ( deliver b . w4 bytes 1000 w5 )
    ( pb `B received a UDP datagram: ` == . r3 kind ( rx_udp ) )
    ( pb `src ip is A: ` == . r3 src_ip ( ip_a ) )
    ( pb `dst ip is B: ` == . r3 dst_ip ( ip_b ) )
    ( pb `src port: ` == . r3 src_port 4000 )
    ( pb `dst port: ` == . r3 dst_port 7000 )
    ( pb `payload length: ` == . r3 payload_len 15 )
    : ~ b pay_ok T
    : ~ i k 0
    ~ < k 15 {
        : i got ?? ( vec_get [u] . w4 bytes + . r3 payload_off k ) { T x → # i x F → -1 }
        : i want ?? ( vec_get [u] payload k ) { T x → # i x F → -2 }
        ? != got want { = pay_ok F } {}
        = k + k 1
    }
    ( pb `payload bytes survive the round trip: ` pay_ok )

    // ── B replies to A: no ARP needed, B already learned A ───────
    : *PktBuf w6 ( pktbuf_new )
    : TxResult t3 ( stack_tx_udp b 0 ( ip_a ) 7000 4000 payload 0 15 1100 w6 )
    ( pb `reply needs no new ARP: ` == . t3 status ( tx_sent ) )
    : *PktBuf w7 ( pktbuf_new )
    : RxResult r4 ( deliver a . w6 bytes 1100 w7 )
    ( pb `A received the reply: ` == . r4 kind ( rx_udp ) )
    ( pb `reply ports swapped: ` && == . r4 src_port 7000 == . r4 dst_port 4000 )

    // ── ping: B pings A, A must answer ───────────────────────────
    : ( Vec u ) echo_pay ( vec_new [u] )
    : ~ i e 0
    ~ < e 24 { ( vec_push [u] echo_pay # u + 65 % e 26 ) = e + e 1 }
    : ( Vec u ) icmp_msg ( vec_new [u] )
    ( icmp_push icmp_msg ( icmp_echo_request ) 0 999 3 echo_pay 0 24 )
    : ( Vec u ) ping ( vec_new [u] )
    ( eth_push_header ping ( mac_a ) ( mac_b ) ( ethertype_ipv4 ) )
    ( ip4_push_header ping ( ip_b ) ( ip_a ) ( ip_proto_icmp ) ( vec_len [u] icmp_msg ) 77 64 T )
    ( vec_extend [u] ping icmp_msg )

    : *PktBuf pong ( pktbuf_new )
    : RxResult r5 ( deliver a ping 1200 pong )
    ( pb `A answered the ping: ` == . r5 kind ( rx_icmp_echo ) )
    ( pb `a reply frame was emitted: ` == ( pktbuf_count pong ) 1 )

    // Parse the answer the way the pinging host would.
    : EthHdr peh ( eth_parse . pong bytes )
    ( pb `pong addressed to B: ` == . peh dst ( mac_b ) )
    : Ip4Hdr pih ( ip4_parse . pong bytes . peh payload_off . peh payload_len )
    ( pb `pong ip valid (checksum ok): ` . pih valid )
    ( pb `pong from A to B: ` && == . pih src ( ip_a ) == . pih dst ( ip_b ) )
    : IcmpMsg pim ( icmp_parse . pong bytes . pih payload_off . pih payload_len )
    ( pb `pong icmp valid (checksum ok): ` . pim valid )
    ( pb `pong is an echo reply: ` == . pim mtype ( icmp_echo_reply ) )
    ( pb `pong mirrors id and seq: ` && == . pim id 999 == . pim seq 3 )
    ( pb `pong mirrors payload length: ` == . pim payload_len 24 )
    : ~ b echo_ok T
    : ~ i j 0
    ~ < j 24 {
        : i got ?? ( vec_get [u] . pong bytes + . pim payload_off j ) { T x → # i x F → -1 }
        : i want ?? ( vec_get [u] echo_pay j ) { T x → # i x F → -2 }
        ? != got want { = echo_ok F } {}
        = j + j 1
    }
    ( pb `pong mirrors payload bytes: ` echo_ok )

    // ── routing: an off-link destination goes via the gateway ────
    : *PktBuf w8 ( pktbuf_new )
    : TxResult t4 ( stack_tx_udp a 0 ( ipv4_make 8 8 8 8 ) 4000 53 payload 0 15 2000 w8 )
    ( pb `off-link send is ARP-pending: ` == . t4 status ( tx_arp_pending ) )
    : EthHdr geh ( eth_parse . w8 bytes )
    : ArpPkt gap ( arp_parse . w8 bytes . geh payload_off . geh payload_len )
    // THE POINT: we must ARP for the GATEWAY, not for 8.8.8.8.
    ( pb `ARPs for the gateway, not the destination: ` == . gap target_ip ( ip_gw ) )

    // Once the gateway answers, the datagram leaves with the gateway's
    // MAC but 8.8.8.8 still in the IP header.
    ( arp_cache_insert . a arp ( ip_gw ) ( mac_gw ) 2000 )
    : *PktBuf w9 ( pktbuf_new )
    : TxResult t5 ( stack_tx_udp a 0 ( ipv4_make 8 8 8 8 ) 4000 53 payload 0 15 2000 w9 )
    ( pb `off-link send now succeeds: ` == . t5 status ( tx_sent ) )
    : EthHdr feh ( eth_parse . w9 bytes )
    ( pb `ethernet dst is the gateway MAC: ` == . feh dst ( mac_gw ) )
    : Ip4Hdr fih ( ip4_parse . w9 bytes . feh payload_off . feh payload_len )
    ( pb `ip dst is still 8.8.8.8: ` == . fih dst ( ipv4_make 8 8 8 8 ) )

    // ── unreachable: ARP gives up rather than queueing forever ───
    : *PktBuf w10 ( pktbuf_new )
    : TxResult u1 ( stack_tx_udp a 0 ( ipv4_make 10 0 2 99 ) 4000 9 payload 0 15 3000 w10 )
    ( pb `unknown host: first attempt ARPs: ` == . u1 status ( tx_arp_pending ) )
    : TxResult u2 ( stack_tx_udp a 0 ( ipv4_make 10 0 2 99 ) 4000 9 payload 0 15 4100 w10 )
    : TxResult u3 ( stack_tx_udp a 0 ( ipv4_make 10 0 2 99 ) 4000 9 payload 0 15 5200 w10 )
    : TxResult u4 ( stack_tx_udp a 0 ( ipv4_make 10 0 2 99 ) 4000 9 payload 0 15 6300 w10 )
    ( pb `after max retries: unreachable: ` == . u4 status ( tx_unreachable ) )

    // ── drop accounting ─────────────────────────────────────────
    : ( Vec u ) junk ( vec_new [u] )
    ( vec_push [u] junk # u 1 ) ( vec_push [u] junk # u 2 )
    : *PktBuf sink ( pktbuf_new )
    : RxResult d1 ( deliver a junk 5000 sink )
    ( pb `runt frame dropped as bad_eth: ` && == . d1 kind ( rx_dropped ) == . d1 reason ( drop_bad_eth ) )

    : ( Vec u ) elsewhere ( vec_new [u] )
    ( eth_push_header elsewhere ( mac_gw ) ( mac_b ) ( ethertype_ipv4 ) )
    ( ip4_push_header elsewhere ( ip_b ) ( ip_gw ) ( ip_proto_udp ) 0 1 64 T )
    : RxResult d2 ( deliver a elsewhere 5000 sink )
    ( pb `frame for another MAC dropped: ` == . d2 reason ( drop_not_for_us ) )

    : ( Vec u ) v6 ( vec_new [u] )
    ( eth_push_header v6 ( mac_a ) ( mac_b ) ( ethertype_ipv6 ) )
    ( vec_push [u] v6 # u 96 )
    : RxResult d3 ( deliver a v6 5000 sink )
    ( pb `IPv6 dropped as unknown ethertype: ` == . d3 reason ( drop_unknown_ethertype ) )

    // A fragment must be counted as a fragment, not as a bad packet —
    // the two mean very different things when reading counters.
    : ( Vec u ) fr ( vec_new [u] )
    ( eth_push_header fr ( mac_a ) ( mac_b ) ( ethertype_ipv4 ) )
    ( ip4_push_header fr ( ip_b ) ( ip_a ) ( ip_proto_udp ) 8 5 64 F )
    : b _s1 ( vec_set [u] fr 20 # u 32 )  // MF
    : b _s2 ( vec_set [u] fr 24 # u 0 )
    : b _s3 ( vec_set [u] fr 25 # u 0 )
    : i fck ( inet_checksum fr 14 20 )
    : b _s4 ( vec_set [u] fr 24 # u & >> fck 8 255 )
    : b _s5 ( vec_set [u] fr 25 # u & fck 255 )
    : ~ i pad 0
    ~ < pad 8 { ( vec_push [u] fr # u 0 ) = pad + pad 1 }
    : RxResult d4 ( deliver a fr 5000 sink )
    ( pb `fragment counted as fragment: ` == . d4 reason ( drop_fragment ) )

    ( pb `bad_eth counter is 1: ` == ( stack_drop_count a ( drop_bad_eth ) ) 1 )
    ( pb `not_for_us counter is 1: ` == ( stack_drop_count a ( drop_not_for_us ) ) 1 )
    ( pb `unknown_ethertype counter is 1: ` == ( stack_drop_count a ( drop_unknown_ethertype ) ) 1 )
    ( pb `fragment counter is 1: ` == ( stack_drop_count a ( drop_fragment ) ) 1 )
    ( pb `no spurious bad_udp drops: ` == ( stack_drop_count a ( drop_bad_udp ) ) 0 )

    // ── addressless stack (pre-DHCP) ────────────────────────────
    : *NetStack c ( stack_new ( mac_gw ) 0 0 0 )
    : *PktBuf w11 ( pktbuf_new )
    : TxResult t6 ( stack_tx_udp c 0 ( ip_a ) 68 67 payload 0 15 100 w11 )
    ( pb `no address → tx refused: ` == . t6 status ( tx_no_address ) )
    // …but a broadcast datagram from 0.0.0.0 still goes out: that is
    // exactly the shape DHCP DISCOVER needs.
    : i n_bc ( stack_tx_udp_broadcast c 0 68 67 4294967295 payload 0 15 w11 )
    ( pb `broadcast from 0.0.0.0 works: ` > n_bc 0 )
    : EthHdr bceh ( eth_parse . w11 bytes )
    ( pb `DHCP-shaped frame is broadcast: ` ( mac_is_broadcast . bceh dst ) )
    ( stack_free c )

    ( stack_free a )
    ( stack_free b )
    ( vec_free [u] payload ) ( pktbuf_free w1 ) ( pktbuf_free w2 )
    ( pktbuf_free w3 ) ( pktbuf_free w4 ) ( pktbuf_free w5 )
    ( pktbuf_free w6 ) ( pktbuf_free w7 ) ( pktbuf_free w8 )
    ( pktbuf_free w9 ) ( pktbuf_free w10 ) ( pktbuf_free w11 )
    ( vec_free [u] echo_pay ) ( vec_free [u] icmp_msg ) ( vec_free [u] ping )
    ( pktbuf_free pong ) ( vec_free [u] junk ) ( pktbuf_free sink )
    ( vec_free [u] elsewhere ) ( vec_free [u] v6 ) ( vec_free [u] fr )
    ^ 0
}
