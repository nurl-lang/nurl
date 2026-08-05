// unikernel/demos/dhcp.nu — the guest asks the network who it is.
//
// A machine that boots into a fixed address is a machine that can only
// boot in one place. This is the DHCP client from `net/dhcp.nu` — the
// same state machine 62 host assertions cover under a scripted clock —
// driven against QEMU's real DHCP server over the real virtio-net
// device, until it holds a real lease.
//
// Everything below the client is code that has been running for a
// while: eth/ipv4/udp4 built the datagram, virtionet put it on the
// wire, and the answer came back the same way. What DHCP adds is that
// the exchange is FOUR messages with the server choosing the content,
// so nothing here can pass by echoing itself.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/time.nu`
$ `stdlib/net/pktbuf.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/eth.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/arp.nu`
$ `stdlib/net/icmp.nu`
$ `stdlib/net/udp4.nu`
$ `stdlib/net/dhcp.nu`
$ `stdlib/net/stack.nu`
$ `stdlib/hal/mmio.nu`
$ `stdlib/hal/virtq.nu`
$ `stdlib/hal/virtio.nu`
$ `unikernel/drivers/virtionet.nu`

@ ms → i { ^ / ( monotonic_ns ) 1000000 }

// One turn: whatever the client wants to send goes out as a broadcast
// datagram from 0.0.0.0 (the shape DHCP needs before an address
// exists), and whatever arrives is fed back to it.
@ turn * VirtioNet nic * NetStack st * DhcpClient c i now → b {
    : *PktBuf out ( pktbuf_new )
    : i want ( dhcp_tick c now )
    ? != want 0 {
        : ( Vec u ) msg ( vec_new [u] )
        ( dhcp_push_message msg want . c xid . c mac
        ? == want ( dhcp_msg_request ) 0 0
        ? == want ( dhcp_msg_request ) . c our_ip 0
        ? == want ( dhcp_msg_request ) . c server_id 0 )
        : i _n ( stack_tx_udp_broadcast st ( dhcp_src_ip c ) ( dhcp_client_port )
        ( dhcp_server_port ) ( dhcp_dest_ip c ) msg 0 ( vec_len [u] msg ) out )
        ( vec_free [u] msg )
        : i n ( pktbuf_count out )
        : ~ i k 0
        ~ < k n {
            : ( Vec u ) f ( vec_new [u] )
            ( pktbuf_copy_to f out k )
            : b _ok ( vnet_tx nic f 0 ( vec_len [u] f ) )
            ( vec_free [u] f )
            = k + k 1
        }
        ( pktbuf_clear out )
    } {}

    : ~ b progressed F
    : ~ b more T
    ~ more {
        : ( Vec u ) in ( vec_new [u] )
        : i len ( vnet_rx nic in )
        ? > len 0 {
            : RxResult r ( stack_rx st in now out )
            ? && == . r kind ( rx_udp ) == . r dst_port ( dhcp_client_port ) {
                : DhcpMsg m ( dhcp_parse in . r payload_off . r payload_len )
                ? . m valid {
                    ? ( dhcp_handle c m now ) { = progressed T } {}
                } {}
            } {}
        } { = more F }
        ( vec_free [u] in )
    }
    ( pktbuf_free out )
    ^ progressed
}

@ main → i {
    : *VirtioNet nic ( vnet_open 64 )
    ? ! ( vnet_ready nic ) {
        ( nurl_print `no virtio-net device\n` )
        ^ 1
    } {}

    // No address yet — that is the point. The stack accepts a
    // broadcast reply before it owns an address, which is the one
    // exception `stack_rx` documents and the reason DHCP works at all.
    : *NetStack st ( stack_new ( vnet_mac nic ) 0 0 0 )
    : *DhcpClient c ( dhcp_client_new ( vnet_mac nic ) & ( ms ) 4294967295 )

    // Bounded by the CLOCK, not by a round count. The client's
    // retransmit backoff is measured in seconds and a busy loop gets
    // through twenty thousand rounds in microseconds — the first
    // version of this loop gave up in less time than DHCP takes to
    // answer, and reported "no lease" about a server that was about to
    // send one.
    : i deadline + ( ms ) 10000
    ~ && ! ( dhcp_bound c ) < ( ms ) deadline {
        ( turn nic st c ( ms ) )
    }

    ( nurl_print `lease acquired: ` )
    ( nurl_print ? ( dhcp_bound c ) `yes` `no` )
    ( nurl_print `\n` )
    ? ( dhcp_bound c ) {
        ( stack_set_address st . c our_ip . c subnet . c router )
        : String ip ( ipv4_str . c our_ip )
        : String gw ( ipv4_str . c router )
        ( nurl_print `address: ` ) ( nurl_print ( string_data ip ) ) ( nurl_print `\n` )
        ( nurl_print `gateway: ` ) ( nurl_print ( string_data gw ) ) ( nurl_print `\n` )
        ( nurl_print `netmask is a real one: ` )
        ( nurl_print ? != . c subnet 0 `yes` `no` )
        ( nurl_print `\n` )
        ( nurl_print `lease has a deadline: ` )
        ( nurl_print ? > . c lease_ms 0 `yes` `no` )
        ( nurl_print `\n` )
        ( string_free ip )
        ( string_free gw )
    } {}

    // Read the verdict before releasing the client: `dhcp_client_free`
    // consumes it, and the borrow checker is right to say so.
    : b ok ( dhcp_bound c )
    ( dhcp_client_free c )
    ( stack_free st )
    ( vnet_close nic )
    ^ ? ok 0 1
}
