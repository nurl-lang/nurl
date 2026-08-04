// net_tcp.nu — Phase A1b test for stdlib/net/{tcpseg,tcp}.nu.
//
// Two sans-IO TCP connections wired segment-to-segment in memory under
// a scripted clock. Covers the paths that only misbehave after hours
// of real traffic — sequence wraparound, retransmission timeouts,
// zero-window deadlock, TIME_WAIT — in microseconds.
//
// The harness delivers ONE segment at a time and can drop segments on
// demand, which is how loss recovery gets tested without a network.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/tcpseg.nu`
$ `stdlib/net/tcp.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ ip_c → i { ^ ( ipv4_make 10 0 2 15 ) }

@ ip_s → i { ^ ( ipv4_make 10 0 2 16 ) }

// Deliver segment `idx` of `from` into connection `to`. Returns how
// many bytes `to` emitted in response.
@ hand * TcpOut from i idx * TcpConn to * TcpOut reply i now i src_ip i dst_ip → i {
    : i start ( tcpout_seg_start from idx )
    : i len ( tcpout_seg_len from idx )
    : TcpSeg sg ( tcpseg_parse . from bytes start len src_ip dst_ip )
    ? ! . sg valid { ^ -1 } {}
    ^ ( tcp_input to sg . from bytes now reply )
}

// Deliver every segment in `from` to `to`, then clear `from`.
@ hand_all * TcpOut from * TcpConn to * TcpOut reply i now i src_ip i dst_ip → i {
    : i n ( tcpout_count from )
    : ~ i k 0
    : ~ i bad 0
    ~ < k n {
        ? < ( hand from k to reply now src_ip dst_ip ) 0 { = bad + bad 1 } {}
        = k + k 1
    }
    ( tcpout_clear from )
    ^ bad
}

@ main → i {
    // ── sequence arithmetic, including wraparound ────────────────
    ( pb `seq_lt basic: ` ( seq_lt 100 200 ) )
    ( pb `seq_gt basic: ` ( seq_gt 200 100 ) )
    ( pb `seq_lt not reflexive: ` ! ( seq_lt 100 100 ) )
    ( pb `seq_leq reflexive: ` ( seq_leq 100 100 ) )
    // Across the 2^32 wrap: 0xFFFFFFF0 precedes 0x00000010.
    ( pb `wrap: ffffff f0 < 10: ` ( seq_lt 4294967280 16 ) )
    ( pb `wrap: 10 > fffffff0: ` ( seq_gt 16 4294967280 ) )
    ( pb `wrap add crosses zero: ` == ( seq_add 4294967280 32 ) 16 )
    ( pb `wrap diff is small: ` == ( seq_diff 16 4294967280 ) 32 )
    ( pb `wrap diff negative: ` == ( seq_diff 4294967280 16 ) -32 )
    // Half-space boundary: exactly 2^31 apart is "greater" one way.
    ( pb `half-space boundary: ` ( seq_lt 0 2147483647 ) )
    ( pb `beyond half-space flips: ` ( seq_gt 0 2147483649 ) )
    ( pb `in window basic: ` ( seq_in_window 105 100 10 ) )
    ( pb `window excludes end: ` ! ( seq_in_window 110 100 10 ) )
    ( pb `window includes start: ` ( seq_in_window 100 100 10 ) )
    ( pb `zero window holds nothing: ` ! ( seq_in_window 100 100 0 ) )
    ( pb `window wraps: ` ( seq_in_window 5 4294967290 16 ) )

    // ── segment codec ────────────────────────────────────────────
    : ( Vec u ) buf ( vec_new [u] )
    : ( Vec u ) pay ( vec_new [u] )
    ( bytes_extend_str pay `GET / HTTP/1.1` )
    ( tcpseg_push buf ( ip_c ) ( ip_s ) 12345 80 1000 2000 | ( tcp_ack ) ( tcp_psh ) 65535 1460 0 pay 0 14 )
    : TcpSeg ps ( tcpseg_parse buf 0 ( vec_len [u] buf ) ( ip_c ) ( ip_s ) )
    ( pb `segment parses: ` . ps valid )
    ( pb `src port: ` == . ps src_port 12345 )
    ( pb `dst port: ` == . ps dst_port 80 )
    ( pb `seq: ` == . ps seq 1000 )
    ( pb `ack: ` == . ps ack 2000 )
    ( pb `payload len: ` == . ps payload_len 14 )
    ( pb `no options on non-SYN: ` == . ps data_off 20 )
    ( pb `seq_len counts payload: ` == ( tcpseg_seq_len ps ) 14 )
    // Corrupting a payload byte must break the checksum.
    : b _cp ( vec_set [u] buf 25 # u 0 )
    ( pb `corrupt segment rejected: ` ! . ( tcpseg_parse buf 0 ( vec_len [u] buf ) ( ip_c ) ( ip_s ) ) valid )

    // SYN carries MSS + window scale.
    : ( Vec u ) synbuf ( vec_new [u] )
    : ( Vec u ) empty ( vec_new [u] )
    ( tcpseg_push synbuf ( ip_c ) ( ip_s ) 12345 80 5000 0 ( tcp_syn ) 65535 1460 7 empty 0 0 )
    : TcpSeg syn ( tcpseg_parse synbuf 0 ( vec_len [u] synbuf ) ( ip_c ) ( ip_s ) )
    ( pb `SYN parses: ` . syn valid )
    ( pb `SYN carries options: ` == . syn data_off 28 )
    ( pb `MSS option read: ` == . syn mss 1460 )
    ( pb `window scale read: ` == . syn wscale 7 )
    ( pb `SYN occupies 1 seq: ` == ( tcpseg_seq_len syn ) 1 )
    ( pb `absent wscale is -1, not 0: ` == . ps wscale -1 )

    // ── three-way handshake ──────────────────────────────────────
    : *TcpConn cl ( tcp_new )
    : *TcpConn sv ( tcp_new )
    : *TcpOut oc ( tcpout_new )
    : *TcpOut os ( tcpout_new )
    ( tcp_listen sv ( ip_s ) 80 )
    = . sv iss 700000
    = . sv remote_ip ( ip_c )
    ( tcp_connect cl ( ip_c ) 12345 ( ip_s ) 80 100000 0 oc )
    ( pb `client sends one SYN: ` == ( tcpout_count oc ) 1 )
    ( pb `client is SYN_SENT: ` == . cl state ( tcp_syn_sent ) )

    : i _h1 ( hand_all oc sv os 1 ( ip_c ) ( ip_s ) )
    ( pb `server is SYN_RCVD: ` == . sv state ( tcp_syn_rcvd ) )
    ( pb `server sends SYN-ACK: ` == ( tcpout_count os ) 1 )
    ( pb `server learned client MSS: ` == . sv mss 1460 )

    : i _h2 ( hand_all os cl oc 2 ( ip_s ) ( ip_c ) )
    ( pb `client is ESTABLISHED: ` ( tcp_is_established cl ) )
    ( pb `client ACKs the SYN-ACK: ` == ( tcpout_count oc ) 1 )

    : i _h3 ( hand_all oc sv os 3 ( ip_c ) ( ip_s ) )
    ( pb `server is ESTABLISHED: ` ( tcp_is_established sv ) )
    ( pb `handshake produced an RTT sample: ` > . cl srtt 0 )

    // ── data transfer ────────────────────────────────────────────
    : ( Vec u ) msg ( vec_new [u] )
    ( bytes_extend_str msg `hello from the unikernel` )
    ( pb `write accepts all 24 bytes: ` == ( tcp_write cl msg 0 24 65536 ) 24 )
    : i _p1 ( tcp_pump cl 10 oc )
    ( pb `one data segment emitted: ` == ( tcpout_count oc ) 1 )
    : i _d1 ( hand_all oc sv os 10 ( ip_c ) ( ip_s ) )
    ( pb `server queued 24 bytes: ` == ( tcp_recv_queue_len sv ) 24 )
    : ( Vec u ) got ( vec_new [u] )
    ( pb `read drains 24: ` == ( tcp_read sv got 100 ) 24 )
    ( pb `receive queue now empty: ` == ( tcp_recv_queue_len sv ) 0 )
    : ~ b same T
    : ~ i k 0
    ~ < k 24 {
        : i a ?? ( vec_get [u] got k ) { T x → # i x F → -1 }
        : i b ?? ( vec_get [u] msg k ) { T x → # i x F → -2 }
        ? != a b { = same F } {}
        = k + k 1
    }
    ( pb `bytes arrive intact: ` same )
    // The server's ACK releases the client's send buffer.
    : i _a1 ( hand_all os cl oc 12 ( ip_s ) ( ip_c ) )
    ( pb `client send queue drained by ACK: ` == ( tcp_send_queue_len cl ) 0 )
    ( pb `retransmit timer disarmed: ` == . cl rtx_deadline 0 )

    // ── retransmission after loss ────────────────────────────────
    ( pb `write 10 more: ` == ( tcp_write cl msg 0 10 65536 ) 10 )
    : i _p2 ( tcp_pump cl 100 oc )
    ( pb `data segment emitted: ` == ( tcpout_count oc ) 1 )
    ( pb `rtx timer armed on send: ` > . cl rtx_deadline 0 )
    // DROP it: clear the buffer without delivering.
    ( tcpout_clear oc )
    // Bind the timing to the connection's own RTO — a hard-coded
    // millisecond here would only be testing the test's guess about
    // Jacobson's estimator, not the retransmit logic.
    : i deadline . cl rtx_deadline
    : i rto_before . cl rto_ms
    : i srtt_before_loss . cl srtt
    ( pb `nothing retransmits before RTO: ` == ( tcp_tick cl - deadline 1 oc ) 0 )
    : i rtx ( tcp_tick cl deadline oc )
    ( pb `RTO fires a retransmit: ` > rtx 0 )
    ( pb `retransmit count incremented: ` == . cl rtx_count 1 )
    ( pb `RTO doubled on backoff: ` == . cl rto_ms * rto_before 2 )
    ( pb `RTO respects the 200ms floor: ` >= rto_before ( tcp_rto_min_ms ) )
    // This time let it through.
    : i _d2 ( hand_all oc sv os deadline ( ip_c ) ( ip_s ) )
    ( pb `server got the retransmitted data: ` == ( tcp_recv_queue_len sv ) 10 )
    : i _a2 ( hand_all os cl oc deadline ( ip_s ) ( ip_c ) )
    ( pb `client queue drained after recovery: ` == ( tcp_send_queue_len cl ) 0 )
    ( pb `rtx count reset by good ACK: ` == . cl rtx_count 0 )
    : i _dr ( tcp_read sv got 100 )

    // Karn's rule: the ACK that finally arrives after a retransmit
    // must NOT feed the RTT estimator — its timing is ambiguous (was
    // it the original or the copy that got through?). Sampling it
    // inflates SRTT without bound on a lossy path.
    ( pb `retransmit cleared the RTT sample: ` == . cl rtt_seq -1 )
    ( pb `SRTT unchanged by ambiguous ACK: ` == . cl srtt srtt_before_loss )

    // ── zero window → persist probe ──────────────────────────────
    // Force the peer's advertised window to zero, then queue data: it
    // must not be sent, and a probe must eventually go out.
    = . cl snd_wnd 0
    ( pb `write while window is zero: ` == ( tcp_write cl msg 0 8 65536 ) 8 )
    ( tcpout_clear oc )
    : i _p3 ( tcp_pump cl 3000 oc )
    ( pb `zero window blocks transmission: ` == ( tcpout_count oc ) 0 )
    = . cl probe_deadline 3500
    : i probe ( tcp_tick cl 3600 oc )
    ( pb `persist timer emits a probe: ` > probe 0 )
    ( pb `probe is exactly one byte: ` == ( tcpseg_seq_len ( tcpseg_parse . oc bytes ( tcpout_seg_start oc 0 ) ( tcpout_seg_len oc 0 ) ( ip_c ) ( ip_s ) ) ) 1 )
    ( pb `probe interval backs off: ` > . cl probe_deadline 3600 )
    ( tcpout_clear oc )
    // Window reopens → the queued data flows.
    = . cl snd_wnd 65535
    : i _p4 ( tcp_pump cl 4000 oc )
    ( pb `reopened window releases data: ` == ( tcpout_count oc ) 1 )

    // ── out-of-window segment is ACKed, not swallowed ────────────
    : ( Vec u ) oldbuf ( vec_new [u] )
    ( tcpseg_push oldbuf ( ip_s ) ( ip_c ) 80 12345 ( seq_sub . cl rcv_nxt 5000 ) . cl snd_nxt ( tcp_ack ) 65535 0 0 empty 0 0 )
    : TcpSeg oldseg ( tcpseg_parse oldbuf 0 ( vec_len [u] oldbuf ) ( ip_s ) ( ip_c ) )
    ( tcpout_clear oc )
    : i oldn ( tcp_input cl oldseg oldbuf 5000 oc )
    ( pb `stale segment answered with an ACK: ` > oldn 0 )
    ( pb `stale segment did not close us: ` ( tcp_is_established cl ) )

    // ── RST on an ESTABLISHED connection ─────────────────────────
    // Distinct code path from the SYN_SENT reset above: this one goes
    // through the synchronised-state handler.
    : ( Vec u ) rst2 ( vec_new [u] )
    ( tcpseg_push rst2 ( ip_s ) ( ip_c ) 80 12345 . cl rcv_nxt . cl snd_nxt | ( tcp_rst ) ( tcp_ack ) 0 0 0 empty 0 0 )
    : TcpSeg rseg2 ( tcpseg_parse rst2 0 ( vec_len [u] rst2 ) ( ip_s ) ( ip_c ) )
    ( pb `established connection is up before RST: ` ( tcp_is_established cl ) )
    ( tcpout_clear oc )
    : i _rs ( tcp_input cl rseg2 rst2 5100 oc )
    ( pb `in-window RST tears it down: ` ( tcp_is_closed cl ) )
    ( pb `RST is not answered with a segment: ` == ( tcpout_count oc ) 0 )

    // ── malformed TCP option must not hang the parser ────────────
    // A length byte below 2 does not advance the option cursor. A
    // parser that trusts it loops forever on a hostile SYN — a remote
    // hang, reachable before any connection exists.
    : ( Vec u ) badopt ( vec_new [u] )
    ( tcpseg_push badopt ( ip_c ) ( ip_s ) 12345 80 5000 0 ( tcp_syn ) 65535 1460 3 empty 0 0 )
    : b _o1 ( vec_set [u] badopt 20 # u 2 )  // kind = MSS
    : b _o2 ( vec_set [u] badopt 21 # u 0 )  // length = 0 → must stop
    // recompute the checksum so this is an OPTION test, not a
    // checksum test
    : b _o3 ( vec_set [u] badopt 16 # u 0 )
    : b _o4 ( vec_set [u] badopt 17 # u 0 )
    : i bs ( inet_sum_add ( ip4_pseudo_sum ( ip_c ) ( ip_s ) ( ip_proto_tcp ) ( vec_len [u] badopt ) ) badopt 0 ( vec_len [u] badopt ) )
    : i bck ( inet_finish bs )
    : b _o5 ( vec_set [u] badopt 16 # u & >> bck 8 255 )
    : b _o6 ( vec_set [u] badopt 17 # u & bck 255 )
    : TcpSeg bseg ( tcpseg_parse badopt 0 ( vec_len [u] badopt ) ( ip_c ) ( ip_s ) )
    ( pb `zero-length option terminates the walk: ` && . bseg valid == . bseg mss 0 )

    // ── stale window update must not shrink the window ───────────
    // A reordered ACK carrying an old, smaller window would otherwise
    // stall the sender permanently (RFC 793 SND.WL1/WL2 rule).
    : *TcpConn w ( tcp_new )
    : *TcpOut ow ( tcpout_new )
    : *TcpConn wp ( tcp_new )
    : *TcpOut owp ( tcpout_new )
    ( tcp_listen wp ( ip_s ) 80 )
    = . wp iss 950000
    = . wp remote_ip ( ip_c )
    ( tcp_connect w ( ip_c ) 8888 ( ip_s ) 80 250000 0 ow )
    : i _w1 ( hand_all ow wp owp 1 ( ip_c ) ( ip_s ) )
    : i _w2 ( hand_all owp w ow 2 ( ip_s ) ( ip_c ) )
    : i _w3 ( hand_all ow wp owp 3 ( ip_c ) ( ip_s ) )
    // Fresh window update: large.
    : ( Vec u ) big ( vec_new [u] )
    ( tcpseg_push big ( ip_s ) ( ip_c ) 80 8888 . w rcv_nxt . w snd_nxt ( tcp_ack ) 60000 0 0 empty 0 0 )
    : i _wb ( tcp_input w ( tcpseg_parse big 0 ( vec_len [u] big ) ( ip_s ) ( ip_c ) ) big 10 ow )
    ( pb `window update applied: ` == . w snd_wnd 60000 )
    // Now a STALE segment (older seq, older ack) advertising a tiny
    // window arrives late. It must be ignored for window purposes.
    : ( Vec u ) stale ( vec_new [u] )
    // NOTE: seq must equal rcv_nxt so the segment is *acceptable* —
    // otherwise it is rejected before the window rule is ever reached
    // and this would test nothing. What makes it stale is the older ACK.
    ( tcpseg_push stale ( ip_s ) ( ip_c ) 80 8888 . w rcv_nxt ( seq_sub . w snd_nxt 1 ) ( tcp_ack ) 1 0 0 empty 0 0 )
    : i _ws ( tcp_input w ( tcpseg_parse stale 0 ( vec_len [u] stale ) ( ip_s ) ( ip_c ) ) stale 11 ow )
    ( pb `stale ACK does not shrink the window: ` == . w snd_wnd 60000 )
    ( tcp_free w ) ( tcp_free wp ) ( tcpout_free ow ) ( tcpout_free owp )
    ( vec_free [u] big ) ( vec_free [u] stale )

    // ── graceful close: FIN → TIME_WAIT → CLOSED ────────────────
    : *TcpConn a ( tcp_new )
    : *TcpConn b ( tcp_new )
    : *TcpOut oa ( tcpout_new )
    : *TcpOut ob ( tcpout_new )
    ( tcp_listen b ( ip_s ) 80 )
    = . b iss 900000
    = . b remote_ip ( ip_c )
    ( tcp_connect a ( ip_c ) 5555 ( ip_s ) 80 200000 0 oa )
    : i _c1 ( hand_all oa b ob 1 ( ip_c ) ( ip_s ) )
    : i _c2 ( hand_all ob a oa 2 ( ip_s ) ( ip_c ) )
    : i _c3 ( hand_all oa b ob 3 ( ip_c ) ( ip_s ) )
    ( pb `second pair established: ` && ( tcp_is_established a ) ( tcp_is_established b ) )

    ( tcpout_clear oa ) ( tcpout_clear ob )
    ( tcp_close a 100 oa )
    ( pb `active close sends FIN: ` == ( tcpout_count oa ) 1 )
    ( pb `closer is FIN_WAIT_1: ` == . a state ( tcp_fin_wait_1 ) )
    : i _f1 ( hand_all oa b ob 100 ( ip_c ) ( ip_s ) )
    ( pb `peer is CLOSE_WAIT: ` == . b state ( tcp_close_wait ) )
    ( pb `peer saw the FIN: ` . b fin_rcvd )
    : i _f2 ( hand_all ob a oa 100 ( ip_s ) ( ip_c ) )
    ( pb `closer is FIN_WAIT_2: ` == . a state ( tcp_fin_wait_2 ) )
    ( tcpout_clear ob )
    ( tcp_close b 200 ob )
    ( pb `peer sends its FIN: ` == ( tcpout_count ob ) 1 )
    ( pb `peer is LAST_ACK: ` == . b state ( tcp_last_ack ) )
    : i _f3 ( hand_all ob a oa 200 ( ip_s ) ( ip_c ) )
    ( pb `closer is TIME_WAIT: ` == . a state ( tcp_time_wait ) )
    : i _f4 ( hand_all oa b ob 200 ( ip_c ) ( ip_s ) )
    ( pb `peer is CLOSED: ` == . b state ( tcp_closed ) )
    // TIME_WAIT must persist for 2MSL, then reap itself.
    : i _t1 ( tcp_tick a 210 oa )
    ( pb `TIME_WAIT holds before 2MSL: ` == . a state ( tcp_time_wait ) )
    : i _t2 ( tcp_tick a 40000 oa )
    ( pb `TIME_WAIT expires after 2MSL: ` == . a state ( tcp_closed ) )

    // ── RST tears the connection down ────────────────────────────
    : *TcpConn r ( tcp_new )
    : *TcpOut orr ( tcpout_new )
    ( tcp_connect r ( ip_c ) 6666 ( ip_s ) 80 300000 0 orr )
    : ( Vec u ) rstbuf ( vec_new [u] )
    ( tcpseg_push rstbuf ( ip_s ) ( ip_c ) 80 6666 0 ( seq_add 300000 1 ) | ( tcp_rst ) ( tcp_ack ) 0 0 0 empty 0 0 )
    : TcpSeg rseg ( tcpseg_parse rstbuf 0 ( vec_len [u] rstbuf ) ( ip_s ) ( ip_c ) )
    : i _r1 ( tcp_input r rseg rstbuf 10 orr )
    ( pb `RST to SYN_SENT closes it: ` ( tcp_is_closed r ) )

    // ── give-up: endless retransmits eventually reset ────────────
    : *TcpConn g ( tcp_new )
    : *TcpOut og ( tcpout_new )
    ( tcp_connect g ( ip_c ) 7777 ( ip_s ) 80 400000 0 og )
    : ~ i t 1000
    : ~ i guard 0
    ~ && ! ( tcp_is_closed g ) < guard 40 {
        : i _tk ( tcp_tick g t og )
        = t + t 120000
        = guard + guard 1
    }
    ( pb `unanswered SYN gives up eventually: ` ( tcp_is_closed g ) )
    ( pb `gave up within max retries: ` <= . g rtx_count + ( tcp_max_rtx ) 1 )

    ( tcp_free cl ) ( tcp_free sv ) ( tcp_free a ) ( tcp_free b )
    ( tcp_free r ) ( tcp_free g )
    ( tcpout_free oc ) ( tcpout_free os ) ( tcpout_free oa )
    ( tcpout_free ob ) ( tcpout_free orr ) ( tcpout_free og )
    ( vec_free [u] buf ) ( vec_free [u] pay ) ( vec_free [u] synbuf )
    ( vec_free [u] empty ) ( vec_free [u] msg ) ( vec_free [u] got )
    ( vec_free [u] oldbuf ) ( vec_free [u] rstbuf )
    ( vec_free [u] rst2 ) ( vec_free [u] badopt )
    ^ 0
}
