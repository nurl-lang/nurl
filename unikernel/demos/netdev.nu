// unikernel/demos/netdev.nu — the sans-IO stack, on a real NIC.
//
// Everything below has been true for a while in pieces: the stack has
// run under a scripted clock since A1, over a loopback since A4, and
// the device has been discovered and negotiated since B5.1. This is
// the first program in which a frame the stack built leaves the
// machine and a frame from outside comes back.
//
// The proof is an ARP exchange with QEMU's user-mode network. It is
// deliberately the smallest thing that cannot happen by accident: the
// gateway only answers a well-formed request addressed to it, the
// reply only reaches us if the receive queue was posted correctly, and
// the cache only fills if what came back parsed.
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
$ `stdlib/net/stack.nu`
$ `stdlib/hal/mmio.nu`
$ `stdlib/hal/virtq.nu`
$ `stdlib/hal/virtio.nu`
$ `unikernel/drivers/virtionet.nu`

// QEMU's user-mode network hands out this address space whatever the
// host looks like: the guest is .15, the gateway .2, the DNS server .3.
@ my_ip → i { ^ ( ipv4_make 10 0 2 15 ) }

@ gw_ip → i { ^ ( ipv4_make 10 0 2 2 ) }

@ mask24 → i { ^ ( ipv4_make 255 255 255 0 ) }

@ ms → i { ^ / ( monotonic_ns ) 1000000 }

// Move whatever the stack has queued onto the wire, then whatever the
// wire has for us into the stack. One turn.
@ pump * VirtioNet nic * NetStack st * PktBuf out → i {
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

    : ~ i got 0
    : ~ b more T
    ~ more {
        : ( Vec u ) in ( vec_new [u] )
        : i len ( vnet_rx nic in )
        ? > len 0 {
            : RxResult r ( stack_rx st in ( ms ) out )
            = got + got 1
        } { = more F }
        ( vec_free [u] in )
    }
    ^ got
}

@ main → i {
    : *VirtioNet nic ( vnet_open 64 )
    ? ! ( vnet_ready nic ) {
        ( nurl_print `no virtio-net device\n` )
        ^ 1
    } {}
    ( nurl_print `nic ready: yes\n` )
    ( nurl_print `mac from config space: ` )
    ( nurl_print ? != ( vnet_mac nic ) 0 `yes` `no` )
    ( nurl_print `\n` )

    : *NetStack st ( stack_new ( vnet_mac nic ) ( my_ip ) ( mask24 ) ( gw_ip ) )
    : *PktBuf out ( pktbuf_new )

    // A UDP datagram to the gateway is the smallest thing that makes
    // the stack want a MAC address it does not have — so the first
    // frame out is an ARP request, and the answer has to travel the
    // whole path back.
    : ( Vec u ) payload ( vec_new [u] )
    ( bytes_extend_str payload `nurl` )
    : TxResult t ( stack_tx_udp st ( gw_ip ) 4000 9 payload 0 4 ( ms ) out )
    ( nurl_print `first send is ARP-pending: ` )
    ( nurl_print ? == . t status ( tx_arp_pending ) `yes` `no` )
    ( nurl_print `\n` )

    : ~ b resolved F
    : ~ i rounds 0
    ~ && ! resolved < rounds 2000 {
        ( pump nic st out )
        = resolved ?? ( arp_cache_lookup . st arp ( gw_ip ) ( ms ) ) { T _m → T F → F }
        = rounds + rounds 1
    }
    ( nurl_print `gateway MAC learned over the wire: ` )
    ( nurl_print ? resolved `yes` `no` )
    ( nurl_print `\n` )

    // With the address known the datagram goes for real. Nothing
    // answers port 9 (discard), so what is asserted is that the send
    // path completed rather than that anything replied.
    ? resolved {
        : TxResult t2 ( stack_tx_udp st ( gw_ip ) 4000 9 payload 0 4 ( ms ) out )
        ( nurl_print `datagram sent: ` )
        ( nurl_print ? == . t2 status ( tx_sent ) `yes` `no` )
        ( nurl_print `\n` )
        ( pump nic st out )
    } {}

    ( nurl_print `frames received: ` )
    ( nurl_print ? > . st rx_frames 0 `yes` `no` )
    ( nurl_print `\n` )

    ( vec_free [u] payload )
    ( pktbuf_free out )
    ( stack_free st )
    ( vnet_close nic )
    ^ ? resolved 0 1
}
