// stdlib/net/tcp.nu — the TCP connection state machine, sans-IO.
//
// PURE. Segments in, segments out, `now` supplied by the caller:
//
//     ( tcp_connect c … now out )   client open  → emits SYN
//     ( tcp_listen  c … )           server open
//     ( tcp_input   c seg buf now out )   one received segment
//     ( tcp_write   c bytes … )     queue application data
//     ( tcp_pump    c now out )     emit what may be sent now
//     ( tcp_tick    c now out )     timers → retransmits, probes, 2MSL
//     ( tcp_read    c dst n )       drain received data
//     ( tcp_close   c now out )     half-close (FIN)
//
// Because the clock is an argument, an RTO backoff sequence or a
// 2MSL wait is a few integer comparisons in a unit test rather than a
// minute of wall time — which is the only reason these paths get
// tested at all.
//
// ── IN SCOPE (v1) ───────────────────────────────────────────────
//   * Full RFC 793 state machine including TIME_WAIT (2MSL).
//   * Retransmission with Jacobson/Karn RTO estimation and
//     exponential backoff; fast retransmit on 3 duplicate ACKs.
//   * Zero-window probes (persist timer).
//   * MSS clamping from the peer's option, window scaling honoured on
//     receive.
//   * RST generation and handling.
//
// ── OUT OF SCOPE, DELIBERATELY ──────────────────────────────────
//   * SACK. Not negotiated, not emitted.
//   * Out-of-order reassembly: a segment above `rcv_nxt` is dropped
//     and an immediate ACK of `rcv_nxt` is sent instead. This is
//     correct — it is exactly the duplicate ACK that drives the
//     peer's fast retransmit — and it costs throughput on a lossy
//     path, not correctness. A reassembly queue is the natural first
//     upgrade once measurements justify it.
//   * Delayed ACK: v1 acknowledges immediately. More ACK traffic,
//     never a wrong answer, and no 200 ms interaction with a peer's
//     Nagle to debug.
//   * Nagle: off. For request/response JSON-RPC (what this stack
//     carries first) coalescing only adds latency.
//   * Our *sent* window-scale factor is fixed at 0; the peer's is
//     always parsed and honoured. Those are different things, and
//     ignoring the peer's shift would misread every window it sends.
//
// ── WHY TIME_WAIT AND ZERO-WINDOW PROBES ARE NOT OPTIONAL ───────
// Without TIME_WAIT, a delayed segment from a closed connection is
// accepted into a new connection reusing the same port pair — silent
// data corruption that looks like a peer bug. Without a persist
// timer, a peer that advertises a zero window and later reopens it
// with a lost window-update deadlocks the connection forever. Both
// failure modes appear only under reconnect churn and buffer
// pressure — i.e. exactly what a long-running appliance does.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/tcpseg.nu`

// ── states (RFC 793 §3.2) ───────────────────────────────────────

@ tcp_closed → i { ^ 0 }

@ tcp_listen_st → i { ^ 1 }

@ tcp_syn_sent → i { ^ 2 }

@ tcp_syn_rcvd → i { ^ 3 }

@ tcp_established → i { ^ 4 }

@ tcp_fin_wait_1 → i { ^ 5 }

@ tcp_fin_wait_2 → i { ^ 6 }

@ tcp_close_wait → i { ^ 7 }

@ tcp_closing → i { ^ 8 }

@ tcp_last_ack → i { ^ 9 }

@ tcp_time_wait → i { ^ 10 }

// 2·MSL. RFC 793 says MSL = 2 minutes; every real stack uses far less
// because nothing survives 4 minutes in a modern network. 30 s keeps
// the protection while bounding how long a port pair stays reserved.
@ tcp_2msl_ms → i { ^ 30000 }

@ tcp_rto_min_ms → i { ^ 200 }

@ tcp_rto_max_ms → i { ^ 60000 }

@ tcp_rto_initial_ms → i { ^ 1000 }

// Give up on a segment after this many retransmits and reset.
@ tcp_max_rtx → i { ^ 8 }

@ tcp_default_window → i { ^ 65535 }

// ── segment output ──────────────────────────────────────────────
//
// A TCP segment carries no length field — its length comes from the
// enclosing IP datagram. Concatenating emitted segments into one flat
// buffer would therefore be irreversible: the consumer could not tell
// where one ends and the next begins. So emission records boundaries
// alongside the bytes, and the IP layer wraps each segment in its own
// datagram. This is not a test convenience; it is what the real
// integration needs, and finding it out at the seam rather than in
// the driver is the point of building sans-IO.

: TcpOut {
    ( Vec u ) bytes
    ( Vec i ) ends  // end offset of each emitted segment
}

@ tcpout_new → *TcpOut {
    : *TcpOut o # *TcpOut ( nurl_alloc Z TcpOut )
    = . o bytes ( vec_new [u] )
    = . o ends ( vec_new [i] )
    ^ o
}

@ tcpout_free * TcpOut o → v {
    ( vec_free [u] . o bytes )
    ( vec_free [i] . o ends )
    ( free o )
}

@ tcpout_clear * TcpOut o → v {
    ( vec_clear [u] . o bytes )
    ( vec_clear [i] . o ends )
}

@ tcpout_count * TcpOut o → i { ^ ( vec_len [i] . o ends ) }

@ tcpout_seg_end * TcpOut o i idx → i {
    ^ ?? ( vec_get [i] . o ends idx ) { T x → x F → 0 }
}

@ tcpout_seg_start * TcpOut o i idx → i {
    ? <= idx 0 { ^ 0 } {}
    ^ ( tcpout_seg_end o - idx 1 )
}

@ tcpout_seg_len * TcpOut o i idx → i {
    ^ - ( tcpout_seg_end o idx ) ( tcpout_seg_start o idx )
}

: TcpConn {
    i state
    i local_ip
    i local_port
    i remote_ip
    i remote_port
    // send sequence space (RFC 793 §3.2). sndbuf[0] corresponds to snd_una.
    i snd_una
    i snd_nxt
    i snd_wnd  // peer's advertised window, already scaled
    i snd_wl1
    i snd_wl2
    i iss
    // receive sequence space
    i rcv_nxt
    i rcv_wnd
    i irs
    i mss
    i snd_wscale  // what WE send (fixed 0 in v1)
    i rcv_wscale  // the peer's shift, honoured
    ( Vec u ) sndbuf
    ( Vec u ) rcvbuf
    // timers — absolute ms deadlines; 0 means disarmed
    i rtx_deadline
    i probe_deadline
    i tw_deadline
    i rto_ms
    i rtx_count
    i srtt
    i rttvar
    i rtt_seq  // sequence being timed, -1 when no sample in flight
    i rtt_start
    i dupacks
    b fin_sent
    b fin_acked
    b fin_rcvd
    b reset
    b close_requested
}

@ tcp_new → *TcpConn {
    : *TcpConn c # *TcpConn ( nurl_alloc Z TcpConn )
    = . c state ( tcp_closed )
    = . c local_ip 0
    = . c local_port 0
    = . c remote_ip 0
    = . c remote_port 0
    = . c snd_una 0
    = . c snd_nxt 0
    = . c snd_wnd 0
    = . c snd_wl1 0
    = . c snd_wl2 0
    = . c iss 0
    = . c rcv_nxt 0
    = . c rcv_wnd ( tcp_default_window )
    = . c irs 0
    = . c mss ( tcp_fallback_mss )
    = . c snd_wscale 0
    = . c rcv_wscale 0
    = . c sndbuf ( vec_new [u] )
    = . c rcvbuf ( vec_new [u] )
    = . c rtx_deadline 0
    = . c probe_deadline 0
    = . c tw_deadline 0
    = . c rto_ms ( tcp_rto_initial_ms )
    = . c rtx_count 0
    = . c srtt 0
    = . c rttvar 0
    = . c rtt_seq -1
    = . c rtt_start 0
    = . c dupacks 0
    = . c fin_sent F
    = . c fin_acked F
    = . c fin_rcvd F
    = . c reset F
    = . c close_requested F
    ^ c
}

@ tcp_free * TcpConn c → v {
    ( vec_free [u] . c sndbuf )
    ( vec_free [u] . c rcvbuf )
    ( free c )
}

// ── helpers ─────────────────────────────────────────────────────

// Bytes queued but not yet sent.
@ __unsent * TcpConn c → i {
    : i inflight ( seq_diff . c snd_nxt . c snd_una )
    : i total ( vec_len [u] . c sndbuf )
    ^ ? > - total inflight 0 - total inflight 0
}

@ tcp_send_queue_len * TcpConn c → i { ^ ( vec_len [u] . c sndbuf ) }

@ tcp_recv_queue_len * TcpConn c → i { ^ ( vec_len [u] . c rcvbuf ) }

@ tcp_is_established * TcpConn c → b { ^ == . c state ( tcp_established ) }

// A connection is "done" when it can be reaped by the owner.
@ tcp_is_closed * TcpConn c → b {
    ^ || == . c state ( tcp_closed ) . c reset
}

@ __emit * TcpConn c * TcpOut out i flags i seq i ack ( Vec u ) payload i pay_off i pay_len → v {
    ( tcpseg_push . out bytes . c local_ip . c remote_ip . c local_port . c remote_port
    seq ack flags . c rcv_wnd . c mss . c snd_wscale payload pay_off pay_len )
    ( vec_push [i] . out ends ( vec_len [u] . out bytes ) )
}

@ __emit_empty * TcpConn c * TcpOut out i flags i seq i ack → v {
    : ( Vec u ) none ( vec_new [u] )
    ( __emit c out flags seq ack none 0 0 )
    ( vec_free [u] none )
}

// Jacobson/Karn RTO update. Karn's rule — never sample a retransmitted
// segment — is enforced by the caller clearing rtt_seq on retransmit.
@ __rtt_update * TcpConn c i sample → v {
    ? <= sample 0 { ^ } {}
    ? == . c srtt 0 {
        = . c srtt sample
        = . c rttvar / sample 2
    } {
        : i err - sample . c srtt
        : i abserr ? < err 0 - 0 err err
        = . c rttvar / + * 3 . c rttvar abserr 4
        = . c srtt / + * 7 . c srtt sample 8
    }
    : i rto + . c srtt * 4 . c rttvar
    = . c rto_ms ? < rto ( tcp_rto_min_ms ) ( tcp_rto_min_ms ) ? > rto ( tcp_rto_max_ms ) ( tcp_rto_max_ms ) rto
}

@ __arm_rtx * TcpConn c i now → v {
    = . c rtx_deadline + now . c rto_ms
}

// ── open ────────────────────────────────────────────────────────

@ tcp_listen * TcpConn c i local_ip i local_port → v {
    = . c local_ip local_ip
    = . c local_port local_port
    = . c state ( tcp_listen_st )
}

// Active open. `iss` is the initial send sequence — the caller
// supplies it because a good ISS needs entropy this layer must not
// invent (RFC 6528); a predictable ISS is a connection-hijack vector.
@ tcp_connect * TcpConn c i local_ip i local_port i remote_ip i remote_port i iss i now * TcpOut out → v {
    = . c local_ip local_ip
    = . c local_port local_port
    = . c remote_ip remote_ip
    = . c remote_port remote_port
    = . c iss iss
    = . c snd_una iss
    = . c snd_nxt ( seq_add iss 1 )
    = . c state ( tcp_syn_sent )
    = . c mss ( tcp_default_mss )
    = . c rtt_seq iss
    = . c rtt_start now
    ( __emit_empty c out ( tcp_syn ) iss 0 )
    ( __arm_rtx c now )
}

// ── application data ────────────────────────────────────────────

// Queue bytes for transmission. Returns how many were accepted — the
// send buffer is bounded, and reporting a short write is how
// back-pressure reaches the application instead of the heap.
@ tcp_write * TcpConn c ( Vec u ) data i off i len i max_queue → i {
    ? || . c reset ! || == . c state ( tcp_established ) == . c state ( tcp_close_wait ) { ^ 0 } {}
    : i have ( vec_len [u] . c sndbuf )
    : i room ? > - max_queue have 0 - max_queue have 0
    : i take ? < len room len room
    : ~ i k 0
    ~ < k take {
        ( vec_push [u] . c sndbuf ?? ( vec_get [u] data + off k ) { T x → x F → # u 0 } )
        = k + k 1
    }
    ^ take
}

// Drain up to `n` received bytes into `dst`. Returns how many moved.
@ tcp_read * TcpConn c ( Vec u ) dst i n → i {
    : i have ( vec_len [u] . c rcvbuf )
    : i take ? < n have n have
    : ~ i k 0
    ~ < k take {
        ( vec_push [u] dst ?? ( vec_get [u] . c rcvbuf k ) { T x → x F → # u 0 } )
        = k + k 1
    }
    // Shift the remainder down. A ring buffer would avoid the copy;
    // for v1 the simple form is worth more than the memmove.
    : ( Vec u ) rest ( vec_new [u] )
    : ~ i j take
    ~ < j have {
        ( vec_push [u] rest ?? ( vec_get [u] . c rcvbuf j ) { T x → x F → # u 0 } )
        = j + j 1
    }
    ( vec_free [u] . c rcvbuf )
    = . c rcvbuf rest
    ^ take
}

// ── transmit ────────────────────────────────────────────────────

// Emit whatever may legally be sent right now: new data within the
// peer's window, and a FIN once the queue has drained.
@ tcp_pump * TcpConn c i now * TcpOut out → i {
    ? . c reset { ^ 0 } {}
    : i before ( vec_len [u] . out bytes )
    : ~ b sent_any F
    ? || == . c state ( tcp_established ) || == . c state ( tcp_close_wait ) == . c state ( tcp_fin_wait_1 ) {
        : ~ b more T
        ~ more {
            : i inflight ( seq_diff . c snd_nxt . c snd_una )
            : i unsent ( __unsent c )
            // Usable window: what the peer allows minus what is
            // already in flight.
            : i usable ? > - . c snd_wnd inflight 0 - . c snd_wnd inflight 0
            : ~ i chunk ? < unsent usable unsent usable
            ? > chunk . c mss { = chunk . c mss } {}
            ? <= chunk 0 { = more F } {
                : i off inflight
                ( __emit c out | ( tcp_ack ) ( tcp_psh ) . c snd_nxt . c rcv_nxt . c sndbuf off chunk )
                // Start an RTT sample if none is in flight (Karn).
                ? < . c rtt_seq 0 {
                    = . c rtt_seq . c snd_nxt
                    = . c rtt_start now
                } {}
                = . c snd_nxt ( seq_add . c snd_nxt chunk )
                = sent_any T
                ? == . c rtx_deadline 0 { ( __arm_rtx c now ) } {}
            }
        }
    } {}
    // FIN goes out once everything queued has been sent.
    ? && && . c close_requested ! . c fin_sent == ( __unsent c ) 0 {
        ? || || == . c state ( tcp_established ) == . c state ( tcp_close_wait ) F {
            ( __emit_empty c out | ( tcp_fin ) ( tcp_ack ) . c snd_nxt . c rcv_nxt )
            = . c fin_sent T
            = . c snd_nxt ( seq_add . c snd_nxt 1 )
            = . c state ? == . c state ( tcp_close_wait ) ( tcp_last_ack ) ( tcp_fin_wait_1 )
            = sent_any T
            ( __arm_rtx c now )
        } {}
    } {}
    ^ - ( vec_len [u] . out bytes ) before
}

// Ask for a graceful close. The FIN itself leaves via tcp_pump once
// the send queue drains — a close must never truncate queued data.
@ tcp_close * TcpConn c i now * TcpOut out → v {
    = . c close_requested T
    ? == . c state ( tcp_listen_st ) { = . c state ( tcp_closed ) ^ } {}
    ? == . c state ( tcp_syn_sent ) { = . c state ( tcp_closed ) ^ } {}
    : i _n ( tcp_pump c now out )
}

// Abort: send RST and drop the connection.
@ tcp_abort * TcpConn c * TcpOut out → v {
    ? || == . c state ( tcp_closed ) == . c state ( tcp_listen_st ) {
        = . c state ( tcp_closed )
        ^
    } {}
    ( __emit_empty c out ( tcp_rst ) . c snd_nxt . c rcv_nxt )
    = . c state ( tcp_closed )
    = . c reset T
}

// ── timers ──────────────────────────────────────────────────────

// Returns bytes emitted. Drives retransmission, the persist timer and
// the 2MSL wait.
@ tcp_tick * TcpConn c i now * TcpOut out → i {
    : i before ( vec_len [u] . out bytes )
    // TIME_WAIT expiry
    ? && == . c state ( tcp_time_wait ) && != . c tw_deadline 0 >= now . c tw_deadline {
        = . c state ( tcp_closed )
        = . c tw_deadline 0
        ^ 0
    } {}
    ? . c reset { ^ 0 } {}
    // Zero-window persist probe: one byte beyond the window, which the
    // peer must answer with an ACK carrying its current window. This
    // is what breaks the deadlock when a window update is lost.
    ? && && == . c snd_wnd 0 > ( __unsent c ) 0 && != . c probe_deadline 0 >= now . c probe_deadline {
        : i off ( seq_diff . c snd_nxt . c snd_una )
        ( __emit c out ( tcp_ack ) . c snd_nxt . c rcv_nxt . c sndbuf off 1 )
        // Back off the probe interval, but never stop probing.
        = . c rto_ms ? >= * . c rto_ms 2 ( tcp_rto_max_ms ) ( tcp_rto_max_ms ) * . c rto_ms 2
        = . c probe_deadline + now . c rto_ms
        ^ - ( vec_len [u] . out bytes ) before
    } {}
    // Retransmission
    ? && != . c rtx_deadline 0 >= now . c rtx_deadline {
        = . c rtx_count + . c rtx_count 1
        ? > . c rtx_count ( tcp_max_rtx ) {
            ( __emit_empty c out ( tcp_rst ) . c snd_nxt . c rcv_nxt )
            = . c state ( tcp_closed )
            = . c reset T
            ^ - ( vec_len [u] . out bytes ) before
        } {}
        // Karn: a retransmitted segment yields no RTT sample.
        = . c rtt_seq -1
        // Exponential backoff.
        = . c rto_ms ? >= * . c rto_ms 2 ( tcp_rto_max_ms ) ( tcp_rto_max_ms ) * . c rto_ms 2
        ? == . c state ( tcp_syn_sent ) {
            ( __emit_empty c out ( tcp_syn ) . c iss 0 )
        } {
            ? == . c state ( tcp_syn_rcvd ) {
                ( __emit_empty c out | ( tcp_syn ) ( tcp_ack ) . c iss . c rcv_nxt )
            } {
                : i inflight ( seq_diff . c snd_nxt . c snd_una )
                : i have ( vec_len [u] . c sndbuf )
                : i n ? < inflight have inflight have
                ? > n 0 {
                    : i chunk ? > n . c mss . c mss n
                    // Go-back-N: resume from snd_una.
                    ( __emit c out | ( tcp_ack ) ( tcp_psh ) . c snd_una . c rcv_nxt . c sndbuf 0 chunk )
                    = . c snd_nxt ( seq_add . c snd_una chunk )
                } {
                    ? . c fin_sent {
                        ( __emit_empty c out | ( tcp_fin ) ( tcp_ack ) ( seq_sub . c snd_nxt 1 ) . c rcv_nxt )
                    } {}
                }
            }
        }
        ( __arm_rtx c now )
        ^ - ( vec_len [u] . out bytes ) before
    } {}
    ^ - ( vec_len [u] . out bytes ) before
}

// ── receive path ────────────────────────────────────────────────

@ __accept_data * TcpConn c TcpSeg s ( Vec u ) buf → i {
    : i n . s payload_len
    ? <= n 0 { ^ 0 } {}
    : ~ i k 0
    ~ < k n {
        ( vec_push [u] . c rcvbuf ?? ( vec_get [u] buf + . s payload_off k ) { T x → x F → # u 0 } )
        = k + k 1
    }
    = . c rcv_nxt ( seq_add . c rcv_nxt n )
    ^ n
}

// Process an ACK: advance snd_una, release acknowledged bytes, update
// RTT/RTO, and count duplicates for fast retransmit.
@ __process_ack * TcpConn c TcpSeg s i now → v {
    : i ack . s ack
    ? ( seq_gt ack . c snd_nxt ) { ^ } {}
    ? ( seq_lt ack . c snd_una ) { ^ } {}
    ? == ack . c snd_una {
        // A pure duplicate ACK — no new data, no window change.
        ? && == . s payload_len 0 == . c snd_wnd << . s window . c rcv_wscale {
            = . c dupacks + . c dupacks 1
            ^
        } {}
        ^
    } {}
    : i acked ( seq_diff ack . c snd_una )
    = . c dupacks 0
    // Release acknowledged bytes from the send buffer. A FIN occupies
    // one sequence number but no buffer byte, so cap by what is there.
    : i have ( vec_len [u] . c sndbuf )
    : i drop ? > acked have have acked
    ? > drop 0 {
        : ( Vec u ) rest ( vec_new [u] )
        : ~ i j drop
        ~ < j have {
            ( vec_push [u] rest ?? ( vec_get [u] . c sndbuf j ) { T x → x F → # u 0 } )
            = j + j 1
        }
        ( vec_free [u] . c sndbuf )
        = . c sndbuf rest
    } {}
    = . c snd_una ack
    ? && . c fin_sent ( seq_geq ack . c snd_nxt ) { = . c fin_acked T } {}
    // RTT sample (Karn: only when this ACK covers the timed segment
    // and that segment was never retransmitted).
    ? && >= . c rtt_seq 0 ( seq_gt ack . c rtt_seq ) {
        ( __rtt_update c - now . c rtt_start )
        = . c rtt_seq -1
    } {}
    = . c rtx_count 0
    // Everything acknowledged → stop the retransmit timer.
    ? ( seq_geq . c snd_una . c snd_nxt ) {
        = . c rtx_deadline 0
    } { ( __arm_rtx c now ) }
}

@ __update_window * TcpConn c TcpSeg s → v {
    : i w << . s window . c rcv_wscale
    // RFC 793: only accept a window update from a segment that is not
    // older than the last one used, or the window can go backwards on
    // a reordered ACK and stall the sender.
    // RFC 793 §3.7 SND.WL1/WL2. Note there is deliberately no
    // "wl1 == 0 means uninitialised" sentinel: 0 is a perfectly legal
    // sequence number after a wrap, and such a sentinel would re-enable
    // stale window updates exactly once per 4 GB — the kind of bug that
    // only ever reproduces in production. wl1/wl2 are seeded when the
    // connection synchronises instead.
    ? || ( seq_lt . c snd_wl1 . s seq ) && == . c snd_wl1 . s seq ( seq_leq . c snd_wl2 . s ack ) {
        = . c snd_wnd w
        = . c snd_wl1 . s seq
        = . c snd_wl2 . s ack
    } {}
}

// Feed one parsed segment. `buf` is the buffer it was parsed from.
// Returns bytes emitted into `out`.
@ tcp_input * TcpConn c TcpSeg s ( Vec u ) buf i now * TcpOut out → i {
    ? ! . s valid { ^ 0 } {}
    : i before ( vec_len [u] . out bytes )
    : b has_rst == & . s flags 4 4
    : b has_syn == & . s flags 2 2
    : b has_ack == & . s flags 16 16
    : b has_fin == & . s flags 1 1

    // ── CLOSED / LISTEN ──
    ? == . c state ( tcp_closed ) { ^ 0 } {}
    ? == . c state ( tcp_listen_st ) {
        ? has_rst { ^ 0 } {}
        // An ACK to a LISTEN socket is bogus — RST it (RFC 793 §3.4).
        ? has_ack {
            = . c remote_ip . c remote_ip
            ^ 0
        } {}
        ? has_syn {
            = . c remote_port . s src_port
            = . c irs . s seq
            = . c rcv_nxt ( seq_add . s seq 1 )
            = . c rcv_wscale ? >= . s wscale 0 . s wscale 0
            = . c mss ? > . s mss 0 ? < . s mss ( tcp_default_mss ) . s mss ( tcp_default_mss ) ( tcp_fallback_mss )
            = . c snd_una . c iss
            = . c snd_nxt ( seq_add . c iss 1 )
            = . c snd_wnd << . s window . c rcv_wscale
            = . c snd_wl1 . s seq
            = . c snd_wl2 . s ack
            = . c state ( tcp_syn_rcvd )
            ( __emit_empty c out | ( tcp_syn ) ( tcp_ack ) . c iss . c rcv_nxt )
            ( __arm_rtx c now )
            ^ - ( vec_len [u] . out bytes ) before
        } {}
        ^ 0
    } {}

    // ── SYN_SENT ──
    ? == . c state ( tcp_syn_sent ) {
        ? has_ack {
            // The ACK must acknowledge exactly our SYN.
            ? || ( seq_leq . s ack . c iss ) ( seq_gt . s ack . c snd_nxt ) {
                ? ! has_rst { ( __emit_empty c out ( tcp_rst ) . s ack 0 ) } {}
                ^ - ( vec_len [u] . out bytes ) before
            } {}
        } {}
        ? has_rst {
            ? has_ack { = . c state ( tcp_closed ) = . c reset T } {}
            ^ 0
        } {}
        ? has_syn {
            = . c irs . s seq
            = . c rcv_nxt ( seq_add . s seq 1 )
            = . c rcv_wscale ? >= . s wscale 0 . s wscale 0
            = . c mss ? > . s mss 0 ? < . s mss ( tcp_default_mss ) . s mss ( tcp_default_mss ) ( tcp_fallback_mss )
            ? has_ack {
                = . c snd_una . s ack
                // Seed the window-update guard before the first update.
                = . c snd_wnd << . s window . c rcv_wscale
                = . c snd_wl1 . s seq
                = . c snd_wl2 . s ack
                = . c state ( tcp_established )
                = . c rtx_deadline 0
                ? && >= . c rtt_seq 0 ( seq_gt . s ack . c rtt_seq ) {
                    ( __rtt_update c - now . c rtt_start )
                    = . c rtt_seq -1
                } {}
                ( __emit_empty c out ( tcp_ack ) . c snd_nxt . c rcv_nxt )
            } {
                // Simultaneous open.
                = . c state ( tcp_syn_rcvd )
                ( __emit_empty c out | ( tcp_syn ) ( tcp_ack ) . c iss . c rcv_nxt )
            }
            ^ - ( vec_len [u] . out bytes ) before
        } {}
        ^ 0
    } {}

    // ── all synchronised states: acceptability test first ──
    // A segment outside the receive window is old or forged; the reply
    // is an ACK of what we actually expect, never silence — silence is
    // what turns one lost ACK into a stalled connection.
    : i seglen ( tcpseg_seq_len s )
    : b acceptable ? == seglen 0 {
        ? == . c rcv_wnd 0 { == . s seq . c rcv_nxt } { ( seq_in_window . s seq . c rcv_nxt . c rcv_wnd ) }
    } {
        ? == . c rcv_wnd 0 { F } {
            || ( seq_in_window . s seq . c rcv_nxt . c rcv_wnd )
            ( seq_in_window ( seq_add . s seq - seglen 1 ) . c rcv_nxt . c rcv_wnd )
        }
    }
    ? ! acceptable {
        ? ! has_rst { ( __emit_empty c out ( tcp_ack ) . c snd_nxt . c rcv_nxt ) } {}
        ^ - ( vec_len [u] . out bytes ) before
    } {}

    ? has_rst {
        = . c state ( tcp_closed )
        = . c reset T
        ^ 0
    } {}

    // A SYN inside the window on an established connection is a
    // protocol violation (or an injection attempt) — reset.
    ? has_syn {
        ( __emit_empty c out ( tcp_rst ) . c snd_nxt . c rcv_nxt )
        = . c state ( tcp_closed )
        = . c reset T
        ^ - ( vec_len [u] . out bytes ) before
    } {}

    ? ! has_ack { ^ 0 } {}

    // SYN_RCVD: the handshake's third segment completes the open.
    ? == . c state ( tcp_syn_rcvd ) {
        ? && ( seq_leq . c snd_una . s ack ) ( seq_leq . s ack . c snd_nxt ) {
            = . c snd_una . s ack
            ( __update_window c s )
            = . c state ( tcp_established )
            = . c rtx_deadline 0
            = . c rtx_count 0
        } {
            ( __emit_empty c out ( tcp_rst ) . s ack 0 )
            ^ - ( vec_len [u] . out bytes ) before
        }
    } {
        ( __process_ack c s now )
        ( __update_window c s )
    }

    // FIN_WAIT_1 → FIN_WAIT_2 once our FIN is acknowledged.
    ? && == . c state ( tcp_fin_wait_1 ) . c fin_acked { = . c state ( tcp_fin_wait_2 ) } {}
    ? && == . c state ( tcp_closing ) . c fin_acked {
        = . c state ( tcp_time_wait )
        = . c tw_deadline + now ( tcp_2msl_ms )
    } {}
    ? && == . c state ( tcp_last_ack ) . c fin_acked {
        = . c state ( tcp_closed )
        ^ - ( vec_len [u] . out bytes ) before
    } {}

    // ── data ──
    : ~ b need_ack F
    ? > . s payload_len 0 {
        ? == . s seq . c rcv_nxt {
            : i _n ( __accept_data c s buf )
            = need_ack T
        } {
            // Out of order (or a duplicate). v1 keeps no reassembly
            // queue: drop it and ACK rcv_nxt. That duplicate ACK is
            // precisely what triggers the peer's fast retransmit.
            = need_ack T
        }
    } {}

    // ── FIN ──
    ? && has_fin == . s seq . c rcv_nxt {
        = . c fin_rcvd T
        = . c rcv_nxt ( seq_add . c rcv_nxt 1 )
        = need_ack T
        ? == . c state ( tcp_established ) { = . c state ( tcp_close_wait ) } {}
        ? == . c state ( tcp_fin_wait_1 ) {
            = . c state ? . c fin_acked ( tcp_time_wait ) ( tcp_closing )
            ? . c fin_acked { = . c tw_deadline + now ( tcp_2msl_ms ) } {}
        } {}
        ? == . c state ( tcp_fin_wait_2 ) {
            = . c state ( tcp_time_wait )
            = . c tw_deadline + now ( tcp_2msl_ms )
        } {}
    } {}

    // Arm or disarm the persist timer as the peer's window changes.
    ? && == . c snd_wnd 0 > ( __unsent c ) 0 {
        ? == . c probe_deadline 0 { = . c probe_deadline + now . c rto_ms } {}
    } { = . c probe_deadline 0 }

    ? need_ack { ( __emit_empty c out ( tcp_ack ) . c snd_nxt . c rcv_nxt ) } {}

    // Fast retransmit: three duplicate ACKs mean a hole the peer has
    // been staring at for three segments. Do not wait for the RTO.
    ? >= . c dupacks 3 {
        = . c dupacks 0
        : i have ( vec_len [u] . c sndbuf )
        ? > have 0 {
            : i chunk ? > have . c mss . c mss have
            ( __emit c out | ( tcp_ack ) ( tcp_psh ) . c snd_una . c rcv_nxt . c sndbuf 0 chunk )
            ( __arm_rtx c now )
        } {}
    } {}

    : i _p ( tcp_pump c now out )
    ^ - ( vec_len [u] . out bytes ) before
}
