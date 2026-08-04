// net_tcp_fuzz.nu — structural fuzz of the TCP state machine.
//
// Deterministic (an LCG seeded by a constant), so a failure reproduces
// exactly and the golden file stays stable. Hostile segments are
// generated against a live connection and the stack is required to
// uphold its invariants no matter what arrives:
//
//   1. It must never hang. Every segment is processed in bounded work
//      — the malformed-option loop guard is the case that matters, and
//      it is a remote hang reachable from an unauthenticated SYN.
//   2. It must never emit a segment claiming to acknowledge data the
//      peer never sent (ack beyond snd_nxt).
//   3. The receive queue may only grow with in-order data, so it can
//      never exceed the advertised window.
//   4. State must stay inside the RFC 793 set — no wandering into an
//      undefined value through some arithmetic path.
//   5. `reset` and CLOSED stay paired. Resurrection after a reset is
//      structurally impossible today — every site that sets `reset`
//      also sets CLOSED, and tcb_input returns immediately in CLOSED —
//      so the useful check is the pairing itself: if a future edit sets
//      one without the other, a reset connection becomes reachable
//      again and this trips.
//
// This is the "oracle = state invariants" shape from the structural
// fuzzer campaign, applied to a protocol instead of to a compiler.

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

// A tiny LCG — the point is reproducibility, not randomness quality.
@ lcg i st → i { ^ & + * st 6364136223846793005 1442695040888963407 4294967295 }

@ main → i {
    : ~ i seed 20260804
    : ~ b no_bad_ack T
    : ~ b state_sane T
    : ~ b no_resurrect T
    : ~ b rcvq_bounded T
    : ~ i handled 0
    : ~ i accepted 0

    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) pay ( vec_new [u] )
    : ~ i pk 0
    ~ < pk 64 { ( vec_push [u] pay # u & pk 255 ) = pk + pk 1 }

    : ~ i round 0
    ~ < round 400 {
        // A fresh connection every few rounds, alternating between an
        // active open and a listening socket so both entry paths get
        // hammered.
        : *Tcb c ( tcb_new )
        : *TcpOut out ( tcpout_new )
        ? == % round 2 0 {
            ( tcb_connect c ( ip_c ) 12345 ( ip_s ) 80 + 100000 * round 7 0 out )
        } {
            ( tcb_listen c ( ip_c ) 12345 )
            = . c iss + 500000 * round 13
            = . c remote_ip ( ip_s )
            = . c remote_port 80
        }

        : ~ i step 0
        ~ < step 12 {
            = seed ( lcg seed )
            : i r seed
            // Build a segment from the fuzzed word. Sequence and ack
            // are drawn both from near the connection's real values
            // (to get past the acceptability test often enough to
            // exercise the interesting paths) and from anywhere in the
            // 32-bit space (to probe the rejection paths).
            : i near & >> r 28 1
            : i sq ? == near 1 ( seq_add . c rcv_nxt - & >> r 4 7 3 ) & r 4294967295
            : i ak ? == near 1 ( seq_add . c snd_nxt - & >> r 8 7 3 ) & >> r 3 4294967295
            : i fl & >> r 12 63
            : i wn & >> r 16 65535
            : i plen % & >> r 24 15 9
            : ( Vec u ) sb ( vec_new [u] )
            ( tcpseg_push sb ( ip_s ) ( ip_c ) 80 12345 sq ak fl wn 1460 0 pay 0 plen )
            // Corrupt an option byte now and then — this is the path
            // where a missing length guard becomes an infinite loop.
            ? == & >> r 20 7 0 {
                ? > ( vec_len [u] sb ) 21 {
                    : b _m1 ( vec_set [u] sb 20 # u & >> r 5 255 )
                    : b _m2 ( vec_set [u] sb 21 # u & >> r 9 3 )
                    // fix the checksum so the segment reaches the
                    // option parser instead of being rejected early
                    : b _m3 ( vec_set [u] sb 16 # u 0 )
                    : b _m4 ( vec_set [u] sb 17 # u 0 )
                    : i ss ( inet_sum_add ( ip4_pseudo_sum ( ip_s ) ( ip_c ) ( ip_proto_tcp ) ( vec_len [u] sb ) ) sb 0 ( vec_len [u] sb ) )
                    : i ck ( inet_finish ss )
                    : b _m5 ( vec_set [u] sb 16 # u & >> ck 8 255 )
                    : b _m6 ( vec_set [u] sb 17 # u & ck 255 )
                } {}
            } {}

            : b was_reset . c reset
            : i snd_nxt_before . c snd_nxt
            : TcpSeg sg ( tcpseg_parse sb 0 ( vec_len [u] sb ) ( ip_s ) ( ip_c ) )
            ? . sg valid {
                = accepted + accepted 1
                ( tcpout_clear out )
                : i _n ( tcb_input c sg sb + 1000 * step 50 out )
                = handled + handled 1

                // (2) every emitted segment must acknowledge only data
                // that actually exists.
                : i nseg ( tcpout_count out )
                : ~ i si 0
                ~ < si nseg {
                    : TcpSeg es ( tcpseg_parse . out bytes ( tcpout_seg_start out si ) ( tcpout_seg_len out si ) ( ip_c ) ( ip_s ) )
                    ? . es valid {
                        ? == & . es flags 16 16 {
                            ? ( seq_gt . es ack . c rcv_nxt ) { = no_bad_ack F } {}
                        } {}
                    } {}
                    = si + si 1
                }

                // (4) the state must stay in the RFC 793 set.
                ? || < . c state 0 > . c state 10 { = state_sane F } {}

                // (5) reset ⇒ CLOSED, always. Checked as the pairing
                // rather than as "never re-establishes", because the
                // latter is vacuous while the pairing holds — and it is
                // the pairing that a future edit could break.
                ? && . c reset != . c state ( tcp_closed ) { = no_resurrect F } {}
                ? && was_reset ( tcb_is_established c ) { = no_resurrect F } {}

                // (3) in-order-only delivery bounds the receive queue.
                ? > ( tcb_recv_queue_len c ) . c rcv_wnd { = rcvq_bounded F } {}
            } {}
            ( vec_free [u] sb )

            // Interleave timer work — retransmits and probes have to
            // survive hostile input too.
            : i _t ( tcb_tick c + 2000 * step 100 out )
            ? || < . c state 0 > . c state 10 { = state_sane F } {}
            = step + step 1
        }
        ( tcb_free c )
        ( tcpout_free out )
        = round + round 1
    }

    // Reaching here at all is invariant (1): 400 connections × 12
    // hostile segments each, no hang.
    ( pb `fuzz completed without hanging: ` T )
    ( pb `segments were actually accepted: ` > accepted 100 )
    ( pb `no ACK beyond what the peer sent: ` no_bad_ack )
    ( pb `state stayed inside RFC 793: ` state_sane )
    ( pb `reset and CLOSED stay paired: ` no_resurrect )
    ( pb `receive queue stayed within the window: ` rcvq_bounded )
    ( vec_free [u] empty )
    ( vec_free [u] pay )
    ^ 0
}
