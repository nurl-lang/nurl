// stdlib/net/dhcp.nu — DHCPv4 client (RFC 2131/2132), sans-IO.
//
// PURE — the client is a state machine plus a message codec. It never
// reads a clock or a socket: `dhcp_tick(client, now)` is told the
// time, and returns whether a message should be sent. That is what
// makes lease timing (T1/T2/expiry, retransmit backoff) testable in
// microseconds with a scripted clock instead of in real minutes.
//
// STATE MACHINE (RFC 2131 §4.4)
//
//   INIT ──discover──▶ SELECTING ──offer──▶ REQUESTING ──ack──▶ BOUND
//                                                │                │
//                                                nak              │ T1
//                                                ▼                ▼
//                                              INIT ◀──expiry── RENEWING
//                                                                 │ T2
//                                                                 ▼
//                                                            REBINDING
//
// The renewal timers are the part hand-rolled clients skip, and the
// failure mode is nasty: everything works for the lease duration
// (typically hours in a test lab, minutes in a hypervisor), then the
// address silently goes stale. A unikernel appliance is exactly the
// thing left running past its first T1, so RENEWING/REBINDING are in
// v1 scope, not deferred.
//
// XID DISCIPLINE: the transaction id is chosen per exchange and every
// reply is matched against it AND against our MAC in the chaddr field.
// A reply with a foreign xid is another guest's lease landing in our
// broadcast domain — accepting it means fighting over an address.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/eth.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/udp4.nu`

// ── constants ────────────────────────────────────────────────────

@ dhcp_server_port → i { ^ 67 }

@ dhcp_client_port → i { ^ 68 }

@ dhcp_op_request → i { ^ 1 }

@ dhcp_op_reply → i { ^ 2 }

@ dhcp_magic → i { ^ 1669485411 }  // 99.130.83.99

@ dhcp_msg_discover → i { ^ 1 }

@ dhcp_msg_offer → i { ^ 2 }

@ dhcp_msg_request → i { ^ 3 }

@ dhcp_msg_ack → i { ^ 5 }

@ dhcp_msg_nak → i { ^ 6 }

@ dhcp_opt_subnet → i { ^ 1 }

@ dhcp_opt_router → i { ^ 3 }

@ dhcp_opt_dns → i { ^ 6 }

@ dhcp_opt_lease → i { ^ 51 }

@ dhcp_opt_msg_type → i { ^ 53 }

@ dhcp_opt_server_id → i { ^ 54 }

@ dhcp_opt_param_list → i { ^ 55 }

@ dhcp_opt_renewal → i { ^ 58 }  // T1

@ dhcp_opt_rebind → i { ^ 59 }  // T2

@ dhcp_opt_end → i { ^ 255 }

@ dhcp_state_init → i { ^ 0 }

@ dhcp_state_selecting → i { ^ 1 }

@ dhcp_state_requesting → i { ^ 2 }

@ dhcp_state_bound → i { ^ 3 }

@ dhcp_state_renewing → i { ^ 4 }

@ dhcp_state_rebinding → i { ^ 5 }

// Retransmit backoff, doubling from 4 s and capped — RFC 2131 §4.1
// asks for randomised backoff; we have no entropy at this layer, so
// the caller may perturb `dhcp_retry_base_ms` per boot instead.
@ dhcp_retry_base_ms → i { ^ 4000 }

@ dhcp_retry_max_ms → i { ^ 64000 }

// ── message codec ────────────────────────────────────────────────

: DhcpMsg {
    i op
    i xid
    i yiaddr  // the address being offered/assigned to us
    i siaddr
    i chaddr_mac
    i msg_type
    i server_id
    i subnet
    i router
    i dns
    i lease_secs
    i t1_secs
    i t2_secs
    b valid
}

@ __dhcp_empty → DhcpMsg { ^ @ DhcpMsg { 0 0 0 0 0 0 0 0 0 0 0 0 0 F } }

// Walk the options field, collecting the ones we act on. Unknown
// options are skipped by length — a malformed length must terminate
// the walk rather than loop or read past the end.
@ dhcp_parse ( Vec u ) buf i off i len → DhcpMsg {
    ? < len 240 { ^ ( __dhcp_empty ) } {}
    : i magic ?? ( bytes_read_u32_be buf + off 236 ) { T x → # i x F → 0 }
    ? != magic ( dhcp_magic ) { ^ ( __dhcp_empty ) } {}
    : ~ i msg_type 0
    : ~ i server_id 0
    : ~ i subnet 0
    : ~ i router 0
    : ~ i dns 0
    : ~ i lease 0
    : ~ i t1 0
    : ~ i t2 0
    : ~ i k 240
    : ~ b done F
    ~ && ! done < k len {
        : i code ?? ( vec_get [u] buf + off k ) { T x → # i x F → 255 }
        ? == code 255 { = done T } {
            ? == code 0 { = k + k 1 } {
                ? >= + k 2 len { = done T } {
                    : i olen ?? ( vec_get [u] buf + off + k 1 ) { T x → # i x F → 0 }
                    : i vstart + k 2
                    ? > + vstart olen len { = done T } {
                        ? && == code ( dhcp_opt_msg_type ) >= olen 1 {
                            = msg_type ?? ( vec_get [u] buf + off vstart ) { T x → # i x F → 0 }
                        } {}
                        ? && == code ( dhcp_opt_server_id ) >= olen 4 {
                            = server_id ?? ( bytes_read_u32_be buf + off vstart ) { T x → # i x F → 0 }
                        } {}
                        ? && == code ( dhcp_opt_subnet ) >= olen 4 {
                            = subnet ?? ( bytes_read_u32_be buf + off vstart ) { T x → # i x F → 0 }
                        } {}
                        ? && == code ( dhcp_opt_router ) >= olen 4 {
                            = router ?? ( bytes_read_u32_be buf + off vstart ) { T x → # i x F → 0 }
                        } {}
                        ? && == code ( dhcp_opt_dns ) >= olen 4 {
                            = dns ?? ( bytes_read_u32_be buf + off vstart ) { T x → # i x F → 0 }
                        } {}
                        ? && == code ( dhcp_opt_lease ) >= olen 4 {
                            = lease ?? ( bytes_read_u32_be buf + off vstart ) { T x → # i x F → 0 }
                        } {}
                        ? && == code ( dhcp_opt_renewal ) >= olen 4 {
                            = t1 ?? ( bytes_read_u32_be buf + off vstart ) { T x → # i x F → 0 }
                        } {}
                        ? && == code ( dhcp_opt_rebind ) >= olen 4 {
                            = t2 ?? ( bytes_read_u32_be buf + off vstart ) { T x → # i x F → 0 }
                        } {}
                        = k + vstart olen
                    }
                }
            }
        }
    }
    : ~ i mac 0
    : ~ i j 0
    ~ < j 6 {
        = mac | << mac 8 ?? ( vec_get [u] buf + off + 28 j ) { T x → # i x F → 0 }
        = j + j 1
    }
    ^ @ DhcpMsg {
        ?? ( vec_get [u] buf off ) { T x → # i x F → 0 }
        ?? ( bytes_read_u32_be buf + off 4 ) { T x → # i x F → 0 }
        ?? ( bytes_read_u32_be buf + off 16 ) { T x → # i x F → 0 }
        ?? ( bytes_read_u32_be buf + off 20 ) { T x → # i x F → 0 }
        mac
        msg_type
        server_id
        subnet
        router
        dns
        lease
        t1
        t2
        T
    }
}

@ __push_opt_u32 ( Vec u ) out i code i value → v {
    ( vec_push [u] out # u code )
    ( vec_push [u] out # u 4 )
    ( bytes_push_u32_be out # u32 & value 4294967295 )
}

// Build the BOOTP/DHCP message body (no UDP/IP headers).
@ dhcp_push_message ( Vec u ) out i msg_type i xid i mac i ciaddr i requested_ip i server_id → v {
    ( vec_push [u] out # u ( dhcp_op_request ) )
    ( vec_push [u] out # u 1 )  // htype: Ethernet
    ( vec_push [u] out # u 6 )  // hlen
    ( vec_push [u] out # u 0 )  // hops
    ( bytes_push_u32_be out # u32 & xid 4294967295 )
    ( bytes_push_u16_be out # u16 0 )  // secs
    // Broadcast flag: we cannot receive a unicast reply before we own
    // an address, because the reply's destination IP would not match
    // anything we accept. Asking the server to broadcast is what makes
    // the first exchange work at all on a stack without a raw-socket
    // bypass.
    ( bytes_push_u16_be out # u16 32768 )
    ( bytes_push_u32_be out # u32 & ciaddr 4294967295 )
    ( bytes_push_u32_be out # u32 0 )  // yiaddr
    ( bytes_push_u32_be out # u32 0 )  // siaddr
    ( bytes_push_u32_be out # u32 0 )  // giaddr
    ( eth_push_mac out mac )
    : ~ i pad 0
    ~ < pad 202 { ( vec_push [u] out # u 0 ) = pad + pad 1 }  // chaddr tail + sname + file
    ( bytes_push_u32_be out # u32 ( dhcp_magic ) )
    ( vec_push [u] out # u ( dhcp_opt_msg_type ) )
    ( vec_push [u] out # u 1 )
    ( vec_push [u] out # u & msg_type 255 )
    ? != requested_ip 0 { ( __push_opt_u32 out 50 requested_ip ) } {}
    ? != server_id 0 { ( __push_opt_u32 out ( dhcp_opt_server_id ) server_id ) } {}
    ( vec_push [u] out # u ( dhcp_opt_param_list ) )
    ( vec_push [u] out # u 4 )
    ( vec_push [u] out # u ( dhcp_opt_subnet ) )
    ( vec_push [u] out # u ( dhcp_opt_router ) )
    ( vec_push [u] out # u ( dhcp_opt_dns ) )
    ( vec_push [u] out # u ( dhcp_opt_lease ) )
    ( vec_push [u] out # u ( dhcp_opt_end ) )
}

// ── client state machine ─────────────────────────────────────────

: DhcpClient {
    i state
    i mac
    i xid
    i our_ip
    i server_id
    i subnet
    i router
    i dns
    i lease_ms  // absolute deadline: lease expiry
    i t1_ms  // absolute: renew
    i t2_ms  // absolute: rebind
    i next_send_ms  // absolute: next (re)transmit
    i backoff_ms
    i sends
}

@ dhcp_client_new i mac i xid → *DhcpClient {
    : *DhcpClient c # *DhcpClient ( nurl_alloc Z DhcpClient )
    = . c state ( dhcp_state_init )
    = . c mac mac
    = . c xid xid
    = . c our_ip 0
    = . c server_id 0
    = . c subnet 0
    = . c router 0
    = . c dns 0
    = . c lease_ms 0
    = . c t1_ms 0
    = . c t2_ms 0
    = . c next_send_ms 0
    = . c backoff_ms ( dhcp_retry_base_ms )
    = . c sends 0
    ^ c
}

@ dhcp_client_free * DhcpClient c → v { ( free c ) }

@ dhcp_bound * DhcpClient c → b {
    ^ || || == . c state ( dhcp_state_bound ) == . c state ( dhcp_state_renewing ) == . c state ( dhcp_state_rebinding )
}

// What the caller should transmit now, if anything: 0 = nothing,
// otherwise a DHCP message type. Advances retransmit backoff and the
// lease timers. Call it on every event-loop turn.
@ dhcp_tick * DhcpClient c i now → i {
    ? == . c state ( dhcp_state_init ) {
        = . c state ( dhcp_state_selecting )
        = . c next_send_ms + now ( dhcp_retry_base_ms )
        = . c backoff_ms ( dhcp_retry_base_ms )
        = . c sends 1
        ^ ( dhcp_msg_discover )
    } {}
    // Lease expiry outranks everything: an expired address must not be
    // used for another packet, so we fall all the way back to INIT.
    ? && ( dhcp_bound c ) >= now . c lease_ms {
        = . c state ( dhcp_state_init )
        = . c our_ip 0
        = . c server_id 0
        = . c next_send_ms now
        ^ 0
    } {}
    ? && == . c state ( dhcp_state_bound ) >= now . c t1_ms {
        = . c state ( dhcp_state_renewing )
        = . c next_send_ms + now ( dhcp_retry_base_ms )
        = . c backoff_ms ( dhcp_retry_base_ms )
        = . c sends 1
        ^ ( dhcp_msg_request )
    } {}
    ? && == . c state ( dhcp_state_renewing ) >= now . c t2_ms {
        // T2: the leasing server is not answering — broadcast to any.
        = . c state ( dhcp_state_rebinding )
        = . c server_id 0
        = . c next_send_ms + now ( dhcp_retry_base_ms )
        = . c backoff_ms ( dhcp_retry_base_ms )
        = . c sends 1
        ^ ( dhcp_msg_request )
    } {}
    ? < now . c next_send_ms { ^ 0 } {}
    // First transmission of a state, or a retransmission of one.
    //
    // `sends == 0` means nothing has gone out for the state we are in,
    // which happens when the state was entered by a REPLY rather than
    // by this function: `dhcp_handle` moves SELECTING → REQUESTING on
    // an OFFER and leaves the sending to us. That first REQUEST is not
    // a retransmission and must not be charged a backoff — RFC 2131
    // sends it immediately and starts the timer afterwards. Doubling
    // here instead put a full `dhcp_retry_base_ms` between the OFFER
    // and the REQUEST, which is four seconds of a boot spent waiting
    // for a server that had already answered.
    ? == . c sends 0 {
        = . c backoff_ms ( dhcp_retry_base_ms )
    } {
        = . c backoff_ms ? >= * . c backoff_ms 2 ( dhcp_retry_max_ms ) ( dhcp_retry_max_ms ) * . c backoff_ms 2
    }
    = . c next_send_ms + now . c backoff_ms
    = . c sends + . c sends 1
    ? == . c state ( dhcp_state_selecting ) { ^ ( dhcp_msg_discover ) } {}
    ? || || == . c state ( dhcp_state_requesting ) == . c state ( dhcp_state_renewing ) == . c state ( dhcp_state_rebinding ) {
        ^ ( dhcp_msg_request )
    } {}
    ^ 0
}

// Feed a parsed reply. Returns T if it changed our state.
//
// Every reply is matched on xid AND chaddr: a foreign xid is another
// client's lease arriving in the same broadcast domain, and honouring
// it means two guests claiming one address.
@ dhcp_handle * DhcpClient c DhcpMsg m i now → b {
    ? ! . m valid { ^ F } {}
    ? != . m op ( dhcp_op_reply ) { ^ F } {}
    ? != . m xid . c xid { ^ F } {}
    ? != . m chaddr_mac . c mac { ^ F } {}
    // An address a host cannot own is not an offer, it is a way to take
    // this machine off the network without anything failing: zero,
    // 127.x, multicast and the broadcast address are all things a server
    // can put in `yiaddr`, and a client that accepts one configures
    // itself into silence. Ignore the message and keep asking — the
    // retransmit timer is already the answer to "the server is useless".
    ? && || == . m msg_type ( dhcp_msg_offer ) == . m msg_type ( dhcp_msg_ack ) ! ( ipv4_is_assignable . m yiaddr ) {
        ^ F
    } {}
    ? && == . m msg_type ( dhcp_msg_offer ) == . c state ( dhcp_state_selecting ) {
        = . c our_ip . m yiaddr
        = . c server_id . m server_id
        = . c state ( dhcp_state_requesting )
        = . c backoff_ms ( dhcp_retry_base_ms )
        // Send the REQUEST on the next turn, not one backoff from now.
        // The offer is in hand; the timer exists for the case where the
        // server does not answer, and it starts once we have asked.
        = . c next_send_ms now
        = . c sends 0
        ^ T
    } {}
    ? == . m msg_type ( dhcp_msg_ack ) {
        ? || || == . c state ( dhcp_state_requesting ) == . c state ( dhcp_state_renewing ) == . c state ( dhcp_state_rebinding ) {
            = . c our_ip . m yiaddr
            ? != . m server_id 0 { = . c server_id . m server_id } {}
            // A mask is a run of ones followed by a run of zeros.
            // Anything else makes `ipv4_in_subnet` and the directed
            // broadcast mean something other than what they are named
            // after, so a mask that is not one is treated as a mask that
            // was not sent.
            = . c subnet ? ( ipv4_mask_is_contiguous . m subnet ) . m subnet ( ipv4_mask_from_prefix 24 )
            = . c router . m router
            = . c dns . m dns
            : i lease ? > . m lease_secs 0 . m lease_secs 3600
            // T1/T2 default to RFC 2131's 0.5 / 0.875 of the lease
            // when the server does not send them explicitly.
            : i t1 ? > . m t1_secs 0 . m t1_secs / lease 2
            : i t2 ? > . m t2_secs 0 . m t2_secs / * lease 7 8
            = . c lease_ms + now * lease 1000
            = . c t1_ms + now * t1 1000
            = . c t2_ms + now * t2 1000
            = . c state ( dhcp_state_bound )
            = . c backoff_ms ( dhcp_retry_base_ms )
            = . c sends 0
            ^ T
        } {}
        ^ F
    } {}
    ? == . m msg_type ( dhcp_msg_nak ) {
        // NAK at any point means our claim is invalid — the address
        // must be dropped immediately, not used until expiry.
        = . c state ( dhcp_state_init )
        = . c our_ip 0
        = . c server_id 0
        = . c lease_ms 0
        = . c next_send_ms now
        ^ T
    } {}
    ^ F
}

// The destination for a message in the current state: RENEWING
// unicasts to the leasing server, everything else broadcasts.
@ dhcp_dest_ip * DhcpClient c → i {
    ? && == . c state ( dhcp_state_renewing ) != . c server_id 0 { ^ . c server_id } {}
    ^ 4294967295
}

@ dhcp_src_ip * DhcpClient c → i {
    ? || == . c state ( dhcp_state_renewing ) == . c state ( dhcp_state_rebinding ) { ^ . c our_ip } {}
    ^ 0
}
