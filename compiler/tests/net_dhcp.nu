// net_dhcp.nu — offline test for stdlib/net/dhcp.nu. The whole lease
// life cycle — DISCOVER/OFFER/REQUEST/ACK, T1 renew, T2 rebind, expiry
// and NAK — driven by a scripted clock, so hours of lease time run in
// microseconds. No sockets.
//
// The renewal timers are the part that only fails after a lease has
// been held for a while, i.e. never during manual testing; a scripted
// clock is the only way they get covered at all.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/eth.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/udp4.nu`
$ `stdlib/net/dhcp.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ cl_mac → i { ^ 2199023255553 }

@ srv_ip → i { ^ ( ipv4_make 10 0 2 2 ) }

@ off_ip → i { ^ ( ipv4_make 10 0 2 15 ) }

// A minimal DHCP server reply: BOOTP header + the options we consume.
@ mk_reply i msg_type i xid i mac i yiaddr i lease i t1 i t2 → ( Vec u ) {
    : ( Vec u ) m ( vec_new [u] )
    ( vec_push [u] m # u ( dhcp_op_reply ) )
    ( vec_push [u] m # u 1 ) ( vec_push [u] m # u 6 ) ( vec_push [u] m # u 0 )
    ( bytes_push_u32_be m # u32 & xid 4294967295 )
    ( bytes_push_u16_be m # u16 0 ) ( bytes_push_u16_be m # u16 0 )
    ( bytes_push_u32_be m # u32 0 )  // ciaddr
    ( bytes_push_u32_be m # u32 & yiaddr 4294967295 )  // yiaddr
    ( bytes_push_u32_be m # u32 & ( srv_ip ) 4294967295 )  // siaddr
    ( bytes_push_u32_be m # u32 0 )  // giaddr
    ( eth_push_mac m mac )
    : ~ i pad 0
    ~ < pad 202 { ( vec_push [u] m # u 0 ) = pad + pad 1 }
    ( bytes_push_u32_be m # u32 ( dhcp_magic ) )
    ( vec_push [u] m # u ( dhcp_opt_msg_type ) )
    ( vec_push [u] m # u 1 )
    ( vec_push [u] m # u & msg_type 255 )
    ( vec_push [u] m # u ( dhcp_opt_server_id ) )
    ( vec_push [u] m # u 4 )
    ( bytes_push_u32_be m # u32 & ( srv_ip ) 4294967295 )
    ( vec_push [u] m # u ( dhcp_opt_subnet ) )
    ( vec_push [u] m # u 4 )
    ( bytes_push_u32_be m # u32 4294967040 )
    ( vec_push [u] m # u ( dhcp_opt_router ) )
    ( vec_push [u] m # u 4 )
    ( bytes_push_u32_be m # u32 & ( srv_ip ) 4294967295 )
    ( vec_push [u] m # u ( dhcp_opt_dns ) )
    ( vec_push [u] m # u 4 )
    ( bytes_push_u32_be m # u32 & ( ipv4_make 10 0 2 3 ) 4294967295 )
    ? > lease 0 {
        ( vec_push [u] m # u ( dhcp_opt_lease ) )
        ( vec_push [u] m # u 4 )
        ( bytes_push_u32_be m # u32 & lease 4294967295 )
    } {}
    ? > t1 0 {
        ( vec_push [u] m # u ( dhcp_opt_renewal ) )
        ( vec_push [u] m # u 4 )
        ( bytes_push_u32_be m # u32 & t1 4294967295 )
    } {}
    ? > t2 0 {
        ( vec_push [u] m # u ( dhcp_opt_rebind ) )
        ( vec_push [u] m # u 4 )
        ( bytes_push_u32_be m # u32 & t2 4294967295 )
    } {}
    ( vec_push [u] m # u ( dhcp_opt_end ) )
    ^ m
}

@ main → i {
    : *DhcpClient c ( dhcp_client_new ( cl_mac ) 305419896 )
    ( pb `starts unbound: ` ! ( dhcp_bound c ) )

    // ── INIT → SELECTING ─────────────────────────────────────────
    ( pb `first tick sends DISCOVER: ` == ( dhcp_tick c 0 ) ( dhcp_msg_discover ) )
    ( pb `discover broadcasts: ` == ( dhcp_dest_ip c ) 4294967295 )
    ( pb `discover src is 0.0.0.0: ` == ( dhcp_src_ip c ) 0 )
    ( pb `no immediate resend: ` == ( dhcp_tick c 100 ) 0 )
    ( pb `resend after backoff: ` == ( dhcp_tick c 4000 ) ( dhcp_msg_discover ) )
    ( pb `backoff doubled (no send at 6s): ` == ( dhcp_tick c 6000 ) 0 )
    ( pb `resend at 12s: ` == ( dhcp_tick c 12000 ) ( dhcp_msg_discover ) )

    // Our own DISCOVER must round-trip through the parser.
    : ( Vec u ) disc ( vec_new [u] )
    ( dhcp_push_message disc ( dhcp_msg_discover ) 305419896 ( cl_mac ) 0 0 0 )
    : DhcpMsg dm ( dhcp_parse disc 0 ( vec_len [u] disc ) )
    ( pb `own discover parses: ` . dm valid )
    ( pb `discover op is request: ` == . dm op ( dhcp_op_request ) )
    ( pb `discover xid: ` == . dm xid 305419896 )
    ( pb `discover carries our mac: ` == . dm chaddr_mac ( cl_mac ) )
    ( pb `discover msg type: ` == . dm msg_type ( dhcp_msg_discover ) )

    // ── foreign replies are ignored ──────────────────────────────
    : ( Vec u ) wrong_xid ( mk_reply ( dhcp_msg_offer ) 4008636142 ( cl_mac ) ( off_ip ) 3600 0 0 )
    : DhcpMsg wx ( dhcp_parse wrong_xid 0 ( vec_len [u] wrong_xid ) )
    ( pb `foreign xid parses as a message: ` . wx valid )
    ( pb `foreign xid ignored: ` ! ( dhcp_handle c wx 13000 ) )
    : ( Vec u ) wrong_mac ( mk_reply ( dhcp_msg_offer ) 305419896 2199023255599 ( off_ip ) 3600 0 0 )
    : DhcpMsg wm ( dhcp_parse wrong_mac 0 ( vec_len [u] wrong_mac ) )
    ( pb `foreign chaddr ignored: ` ! ( dhcp_handle c wm 13000 ) )
    ( pb `still selecting: ` ! ( dhcp_bound c ) )

    // ── OFFER → REQUESTING ───────────────────────────────────────
    : ( Vec u ) offer ( mk_reply ( dhcp_msg_offer ) 305419896 ( cl_mac ) ( off_ip ) 3600 0 0 )
    : DhcpMsg om ( dhcp_parse offer 0 ( vec_len [u] offer ) )
    ( pb `offer parses: ` . om valid )
    ( pb `offer yiaddr: ` == . om yiaddr ( off_ip ) )
    ( pb `offer server id: ` == . om server_id ( srv_ip ) )
    ( pb `offer accepted: ` ( dhcp_handle c om 13000 ) )
    ( pb `now requesting: ` == . c state ( dhcp_state_requesting ) )
    ( pb `not bound yet: ` ! ( dhcp_bound c ) )
    ( pb `request retransmits: ` == ( dhcp_tick c 17000 ) ( dhcp_msg_request ) )

    // ── ACK → BOUND ──────────────────────────────────────────────
    // lease 3600 s, no explicit T1/T2 → RFC defaults 1800 / 3150.
    : ( Vec u ) ack ( mk_reply ( dhcp_msg_ack ) 305419896 ( cl_mac ) ( off_ip ) 3600 0 0 )
    : DhcpMsg am ( dhcp_parse ack 0 ( vec_len [u] ack ) )
    ( pb `ack accepted: ` ( dhcp_handle c am 20000 ) )
    ( pb `bound: ` ( dhcp_bound c ) )
    ( pb `got our address: ` == . c our_ip ( off_ip ) )
    ( pb `got subnet mask: ` == . c subnet 4294967040 )
    ( pb `got router: ` == . c router ( srv_ip ) )
    ( pb `got dns: ` == . c dns ( ipv4_make 10 0 2 3 ) )
    ( pb `T1 defaults to lease/2: ` == . c t1_ms + 20000 1800000 )
    ( pb `T2 defaults to 7/8 lease: ` == . c t2_ms + 20000 3150000 )
    ( pb `lease deadline: ` == . c lease_ms + 20000 3600000 )
    ( pb `bound is quiet: ` == ( dhcp_tick c 100000 ) 0 )
    ( pb `still quiet just before T1: ` == ( dhcp_tick c 1819999 ) 0 )

    // ── T1 → RENEWING ────────────────────────────────────────────
    ( pb `T1 triggers renew: ` == ( dhcp_tick c 1820000 ) ( dhcp_msg_request ) )
    ( pb `state renewing: ` == . c state ( dhcp_state_renewing ) )
    ( pb `renew unicasts to server: ` == ( dhcp_dest_ip c ) ( srv_ip ) )
    ( pb `renew src is our address: ` == ( dhcp_src_ip c ) ( off_ip ) )
    ( pb `renew still counts as bound: ` ( dhcp_bound c ) )

    // Renewal ACK extends the lease from the new "now".
    : ( Vec u ) ack2 ( mk_reply ( dhcp_msg_ack ) 305419896 ( cl_mac ) ( off_ip ) 3600 1800 3150 )
    : DhcpMsg am2 ( dhcp_parse ack2 0 ( vec_len [u] ack2 ) )
    ( pb `renewal ack accepted: ` ( dhcp_handle c am2 1830000 ) )
    ( pb `back to bound: ` == . c state ( dhcp_state_bound ) )
    ( pb `lease extended: ` == . c lease_ms + 1830000 3600000 )
    ( pb `explicit T1 honoured: ` == . c t1_ms + 1830000 1800000 )

    // ── T2 → REBINDING (server silent) ───────────────────────────
    : i _r1 ( dhcp_tick c 3630000 )  // T1 again → RENEWING
    ( pb `renewing again at T1: ` == . c state ( dhcp_state_renewing ) )
    : i r2 ( dhcp_tick c 4980000 )  // T2 → REBINDING
    ( pb `T2 triggers rebind: ` == r2 ( dhcp_msg_request ) )
    ( pb `state rebinding: ` == . c state ( dhcp_state_rebinding ) )
    ( pb `rebind broadcasts: ` == ( dhcp_dest_ip c ) 4294967295 )
    ( pb `rebind keeps our address as src: ` == ( dhcp_src_ip c ) ( off_ip ) )

    // ── expiry → INIT ────────────────────────────────────────────
    : i _r3 ( dhcp_tick c 5430001 )
    ( pb `expiry drops the address: ` == . c our_ip 0 )
    ( pb `expiry returns to INIT: ` == . c state ( dhcp_state_init ) )
    ( pb `no longer bound: ` ! ( dhcp_bound c ) )
    ( pb `INIT re-discovers: ` == ( dhcp_tick c 5430002 ) ( dhcp_msg_discover ) )
    ( dhcp_client_free c )

    // ── NAK drops the claim immediately ──────────────────────────
    : *DhcpClient c2 ( dhcp_client_new ( cl_mac ) 305419896 )
    : i _d ( dhcp_tick c2 0 )
    : ( Vec u ) offer2 ( mk_reply ( dhcp_msg_offer ) 305419896 ( cl_mac ) ( off_ip ) 3600 0 0 )
    : b _o ( dhcp_handle c2 ( dhcp_parse offer2 0 ( vec_len [u] offer2 ) ) 1000 )
    : ( Vec u ) ack3 ( mk_reply ( dhcp_msg_ack ) 305419896 ( cl_mac ) ( off_ip ) 3600 0 0 )
    : b _a ( dhcp_handle c2 ( dhcp_parse ack3 0 ( vec_len [u] ack3 ) ) 2000 )
    ( pb `bound before nak: ` ( dhcp_bound c2 ) )
    : ( Vec u ) nak ( mk_reply ( dhcp_msg_nak ) 305419896 ( cl_mac ) 0 0 0 0 )
    ( pb `nak accepted: ` ( dhcp_handle c2 ( dhcp_parse nak 0 ( vec_len [u] nak ) ) 3000 ) )
    ( pb `nak drops address at once: ` == . c2 our_ip 0 )
    ( pb `nak returns to INIT: ` == . c2 state ( dhcp_state_init ) )
    ( dhcp_client_free c2 )

    // ── codec robustness ─────────────────────────────────────────
    : ( Vec u ) tiny ( vec_new [u] )
    ( vec_push [u] tiny # u 2 )
    ( pb `short message rejected: ` ! . ( dhcp_parse tiny 0 1 ) valid )

    : ( Vec u ) nomagic ( mk_reply ( dhcp_msg_ack ) 305419896 ( cl_mac ) ( off_ip ) 3600 0 0 )
    : b _nm ( vec_set [u] nomagic 236 # u 0 )
    ( pb `bad magic cookie rejected: ` ! . ( dhcp_parse nomagic 0 ( vec_len [u] nomagic ) ) valid )

    // A truncated option length must terminate the walk, not run off
    // the end or spin — this is the classic parser DoS in DHCP.
    : ( Vec u ) badopt ( mk_reply ( dhcp_msg_ack ) 305419896 ( cl_mac ) ( off_ip ) 3600 0 0 )
    : b _b1 ( vec_set [u] badopt 240 # u 53 )
    : b _b2 ( vec_set [u] badopt 241 # u 200 )  // claims 200 bytes, has ~30
    : DhcpMsg bm ( dhcp_parse badopt 0 ( vec_len [u] badopt ) )
    ( pb `overlong option terminates walk: ` && . bm valid == . bm msg_type 0 )

    // Zero-length lease → the client's own default, never a zero lease
    // (a zero lease would expire the address on the next tick).
    : ( Vec u ) nolease ( mk_reply ( dhcp_msg_ack ) 305419896 ( cl_mac ) ( off_ip ) 0 0 0 )
    : *DhcpClient c3 ( dhcp_client_new ( cl_mac ) 305419896 )
    : i _d3 ( dhcp_tick c3 0 )
    : ( Vec u ) offer3 ( mk_reply ( dhcp_msg_offer ) 305419896 ( cl_mac ) ( off_ip ) 0 0 0 )
    : b _o3 ( dhcp_handle c3 ( dhcp_parse offer3 0 ( vec_len [u] offer3 ) ) 1000 )
    : b _a3 ( dhcp_handle c3 ( dhcp_parse nolease 0 ( vec_len [u] nolease ) ) 2000 )
    ( pb `missing lease → 1h default: ` == . c3 lease_ms + 2000 3600000 )
    ( pb `bound with defaulted lease: ` ( dhcp_bound c3 ) )
    ( dhcp_client_free c3 )

    // ── a server that is lying, or broken ────────────────────────
    //
    // A DHCP server is the first party a guest talks to on a network it
    // does not own, and it is unauthenticated by construction: anyone on
    // the segment can answer first. None of these is exotic — a wrong
    // `yiaddr` is one typo in a server config — and every one of them
    // takes the machine off the network without anything failing, which
    // is the worst way for a configuration bug to present.
    : ~ ( Vec u ) hostile ( vec_new [u] )
    : ~ b refused_all T
    : ~ i hk 0
    ~ < hk 4 {
        : i bad ? == hk 0 0 ? == hk 1 ( ipv4_make 127 0 0 1 ) ? == hk 2 ( ipv4_make 224 0 0 1 ) 4294967295
        : *DhcpClient hc ( dhcp_client_new ( cl_mac ) 305419896 )
        : i _ht ( dhcp_tick hc 0 )
        ( vec_free [u] hostile )
        = hostile ( mk_reply ( dhcp_msg_offer ) 305419896 ( cl_mac ) bad 3600 0 0 )
        : b took ( dhcp_handle hc ( dhcp_parse hostile 0 ( vec_len [u] hostile ) ) 1000 )
        ? || took != . hc our_ip 0 { = refused_all F } {}
        ( dhcp_client_free hc )
        = hk + hk 1
    }
    ( pb `an unusable address is refused (0, 127.x, multicast, broadcast): ` refused_all )

    // A mask is a run of ones then a run of zeros. 255.0.255.0 is not
    // one, and taking it makes "is this destination on my link" mean
    // something nobody wrote down.
    : *DhcpClient c4 ( dhcp_client_new ( cl_mac ) 305419896 )
    : i _d4 ( dhcp_tick c4 0 )
    : ( Vec u ) offer4 ( mk_reply ( dhcp_msg_offer ) 305419896 ( cl_mac ) ( off_ip ) 3600 0 0 )
    : b _o4 ( dhcp_handle c4 ( dhcp_parse offer4 0 ( vec_len [u] offer4 ) ) 1000 )
    : ( Vec u ) ack4 ( mk_reply ( dhcp_msg_ack ) 305419896 ( cl_mac ) ( off_ip ) 3600 0 0 )
    // The subnet option's value is at 251..254 (four bytes after the
    // magic at 236, the message-type option and the server id).
    : b _m4 ( vec_set [u] ack4 252 # u 0 )  // 255.255.255.0 → 255.0.255.0
    : b _a4 ( dhcp_handle c4 ( dhcp_parse ack4 0 ( vec_len [u] ack4 ) ) 2000 )
    ( pb `bound despite the bad mask: ` ( dhcp_bound c4 ) )
    ( pb `a non-contiguous mask falls back to /24: ` == . c4 subnet ( ipv4_mask_from_prefix 24 ) )
    ( dhcp_client_free c4 )

    // Every option byte, fuzzed: the walk must terminate and the client
    // must never end up bound to something it was not offered.
    : ~ i fseed 20260806
    : ~ b fuzz_ok T
    : ~ i fk 0
    ( vec_free [u] hostile )
    = hostile ( mk_reply ( dhcp_msg_ack ) 305419896 ( cl_mac ) ( off_ip ) 3600 0 0 )
    : i hlen ( vec_len [u] hostile )
    ~ < fk 600 {
        = fseed & + * fseed 6364136223846793005 1442695040888963407 4294967295
        : i at + 240 % >> fseed 7 - hlen 240
        : i was ?? ( vec_get [u] hostile at ) { T x → # i x F → 0 }
        : b _f1 ( vec_set [u] hostile at # u & >> fseed 17 255 )
        : DhcpMsg fm ( dhcp_parse hostile 0 hlen )
        : *DhcpClient fc ( dhcp_client_new ( cl_mac ) 305419896 )
        : i _ft ( dhcp_tick fc 0 )
        : b _fh ( dhcp_handle fc fm 1000 )
        ? && ( dhcp_bound fc ) ! ( ipv4_is_assignable . fc our_ip ) { = fuzz_ok F } {}
        ? && ( dhcp_bound fc ) ! ( ipv4_mask_is_contiguous . fc subnet ) { = fuzz_ok F } {}
        ( dhcp_client_free fc )
        : b _f2 ( vec_set [u] hostile at # u & was 255 )
        = fk + fk 1
    }
    ( pb `600 mutated option streams left the client sane: ` fuzz_ok )

    // Vec is a manually-managed handle (docs/MEMORY.md §7.4).
    ( vec_free [u] disc ) ( vec_free [u] wrong_xid ) ( vec_free [u] wrong_mac )
    ( vec_free [u] offer ) ( vec_free [u] ack ) ( vec_free [u] ack2 )
    ( vec_free [u] offer2 ) ( vec_free [u] ack3 ) ( vec_free [u] nak )
    ( vec_free [u] tiny ) ( vec_free [u] nomagic ) ( vec_free [u] badopt )
    ( vec_free [u] nolease ) ( vec_free [u] offer3 )
    ( vec_free [u] hostile ) ( vec_free [u] offer4 ) ( vec_free [u] ack4 )
    ^ 0
}
