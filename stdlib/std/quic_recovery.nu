// stdlib/std/quic_recovery.nu — loss detection and congestion control
// (RFC 9002): the sent-packet log per packet-number space, RTT
// estimation, ACK processing, packet- and time-threshold loss
// detection, the probe timeout (PTO) with exponential backoff, and
// NewReno (§7). Pure bookkeeping — the connection owns the clock (ms,
// monotonic), sends the packets, and puts lost frames back on its
// queues.
//
//   ( quic_rec_new max_datagram )                 → *QuicRecovery
//   ( quic_rec_free r )                           → v
//   ( quic_rec_set_peer r max_ack_delay ack_exp ) → v    from the peer's transport parameters
//   ( quic_rec_on_sent r space pn now size ack_eliciting frames ) → v   `frames` = retransmittable bytes, copied
//   ( quic_rec_on_ack r space ack now )           → i    0 ok · -1 the ACK names a packet never sent
//   ( quic_rec_on_timeout r now )                 → v    run whichever of loss-time / PTO is due
//   ( quic_rec_next_timeout r )                   → i    absolute ms of the earliest timer, 0 = none
//   ( quic_rec_take_lost r space )                → ( Vec u )  OWNED frames of packets declared lost
//   ( quic_rec_take_probe r )                     → i    space that needs a PTO probe, -1 none (clears it)
//   ( quic_rec_discard_space r space )            → v    Initial / Handshake keys dropped (§6.4)
//   ( quic_rec_can_send r size )                  → b    congestion window has room
//   ( quic_rec_pto r )                            → i    current PTO in ms
//   ( quic_rec_set_confirmed r )                  → v    handshake confirmed (PTO includes max_ack_delay)
//   ( quic_rec_bytes_in_flight r ) · ( quic_rec_cwnd r ) · ( quic_rec_srtt r )
//
// Spaces: 0 Initial, 1 Handshake, 2 Application (1-RTT).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/quic_frame.nu`

: QuicSentPkt {
    i pn
    i time_ms
    i size
    i ack_eliciting
    i in_flight
    ( Vec u ) frames
}

: QuicRecovery {
    ( Vec i ) sent0
    ( Vec i ) sent1
    ( Vec i ) sent2
    i largest_acked0
    i largest_acked1
    i largest_acked2
    i largest_sent0
    i largest_sent1
    i largest_sent2
    i loss_time0
    i loss_time1
    i loss_time2
    i last_ae_sent0
    i last_ae_sent1
    i last_ae_sent2
    ( Vec u ) lost0
    ( Vec u ) lost1
    ( Vec u ) lost2
    i latest_rtt
    i min_rtt
    i smoothed_rtt
    i rttvar
    i has_rtt_sample
    i max_ack_delay
    i ack_delay_exp
    i pto_count
    i probe_space
    i confirmed
    i bytes_in_flight
    i cwnd
    i ssthresh
    i recovery_start
    i max_datagram
}

@ quic_rec_kpacket_threshold → i { ^ 3 }

@ quic_rec_kgranularity → i { ^ 1 }

@ quic_rec_kinitial_rtt → i { ^ 333 }

@ quic_rec_new i max_datagram → *QuicRecovery {
    : *QuicRecovery r # *QuicRecovery ( nurl_alloc Z QuicRecovery )
    = . r sent0 ( vec_new [i] )
    = . r sent1 ( vec_new [i] )
    = . r sent2 ( vec_new [i] )
    = . r largest_acked0 -1
    = . r largest_acked1 -1
    = . r largest_acked2 -1
    = . r largest_sent0 -1
    = . r largest_sent1 -1
    = . r largest_sent2 -1
    = . r loss_time0 0
    = . r loss_time1 0
    = . r loss_time2 0
    = . r last_ae_sent0 0
    = . r last_ae_sent1 0
    = . r last_ae_sent2 0
    = . r lost0 ( vec_new [u] )
    = . r lost1 ( vec_new [u] )
    = . r lost2 ( vec_new [u] )
    = . r latest_rtt 0
    = . r min_rtt 0
    = . r smoothed_rtt ( quic_rec_kinitial_rtt )
    = . r rttvar / ( quic_rec_kinitial_rtt ) 2
    = . r has_rtt_sample 0
    = . r max_ack_delay 25
    = . r ack_delay_exp 3
    = . r pto_count 0
    = . r probe_space -1
    = . r confirmed 0
    = . r bytes_in_flight 0
    // kInitialWindow: min(10 * max_datagram, max(2 * max_datagram, 14720))
    : i w10 * 10 max_datagram
    : i w2 * 2 max_datagram
    : i floor ? > w2 14720 w2 14720
    = . r cwnd ? < w10 floor w10 floor
    = . r ssthresh 4611686018427387903
    = . r recovery_start 0
    = . r max_datagram max_datagram
    ^ r
}

@ __qr_pkt_free i h → v {
    : *QuicSentPkt p # *QuicSentPkt h
    ( vec_free [u] . p frames )
    ( nurl_free # s p )
}

@ __qr_free_list ( Vec i ) l → v {
    : ~ i k 0
    ~ < k ( vec_len [i] l ) {
        ( __qr_pkt_free ?? ( vec_get [i] l k ) { T x → x F → 0 } )
        = k + k 1
    }
    ( vec_free [i] l )
}

@ quic_rec_free * QuicRecovery r → v {
    ? == # i r 0 { ^ } {}
    ( __qr_free_list . r sent0 )
    ( __qr_free_list . r sent1 )
    ( __qr_free_list . r sent2 )
    ( vec_free [u] . r lost0 )
    ( vec_free [u] . r lost1 )
    ( vec_free [u] . r lost2 )
    ( nurl_free # s r )
}

@ quic_rec_set_peer * QuicRecovery r i max_ack_delay i ack_exp → v {
    = . r max_ack_delay max_ack_delay
    = . r ack_delay_exp ack_exp
}

@ quic_rec_set_confirmed * QuicRecovery r → v { = . r confirmed 1 }

@ quic_rec_bytes_in_flight * QuicRecovery r → i { ^ . r bytes_in_flight }

@ quic_rec_cwnd * QuicRecovery r → i { ^ . r cwnd }

@ quic_rec_srtt * QuicRecovery r → i { ^ . r smoothed_rtt }

@ __qr_sent * QuicRecovery r i space → ( Vec i ) {
    ? == space 0 { ^ . r sent0 } {}
    ? == space 1 { ^ . r sent1 } {}
    ^ . r sent2
}

@ __qr_lost * QuicRecovery r i space → ( Vec u ) {
    ? == space 0 { ^ . r lost0 } {}
    ? == space 1 { ^ . r lost1 } {}
    ^ . r lost2
}

@ __qr_largest_acked * QuicRecovery r i space → i {
    ? == space 0 { ^ . r largest_acked0 } {}
    ? == space 1 { ^ . r largest_acked1 } {}
    ^ . r largest_acked2
}

@ __qr_set_largest_acked * QuicRecovery r i space i v → v {
    ? == space 0 { = . r largest_acked0 v ^ } {}
    ? == space 1 { = . r largest_acked1 v ^ } {}
    = . r largest_acked2 v
}

@ __qr_largest_sent * QuicRecovery r i space → i {
    ? == space 0 { ^ . r largest_sent0 } {}
    ? == space 1 { ^ . r largest_sent1 } {}
    ^ . r largest_sent2
}

@ __qr_loss_time * QuicRecovery r i space → i {
    ? == space 0 { ^ . r loss_time0 } {}
    ? == space 1 { ^ . r loss_time1 } {}
    ^ . r loss_time2
}

@ __qr_set_loss_time * QuicRecovery r i space i v → v {
    ? == space 0 { = . r loss_time0 v ^ } {}
    ? == space 1 { = . r loss_time1 v ^ } {}
    = . r loss_time2 v
}

@ __qr_last_ae * QuicRecovery r i space → i {
    ? == space 0 { ^ . r last_ae_sent0 } {}
    ? == space 1 { ^ . r last_ae_sent1 } {}
    ^ . r last_ae_sent2
}

@ __qr_pkt ( Vec i ) l i k → *QuicSentPkt {
    ^ # *QuicSentPkt ?? ( vec_get [i] l k ) { T x → x F → 0 }
}

@ quic_rec_on_sent * QuicRecovery r i space i pn i now i size i ack_eliciting ( Vec u ) frames → v {
    : *QuicSentPkt p # *QuicSentPkt ( nurl_alloc Z QuicSentPkt )
    = . p pn pn
    = . p time_ms now
    = . p size size
    = . p ack_eliciting ack_eliciting
    // Only ack-eliciting packets count as in flight (§2 / §7.2): a peer
    // never has to acknowledge an ACK-only packet, so counting one would
    // fill the congestion window with bytes that are never released.
    = . p in_flight ? != ack_eliciting 0 1 0
    = . p frames ( bytes_slice frames 0 ( vec_len [u] frames ) )
    ( vec_push [i] ( __qr_sent r space ) # i p )
    ? != ack_eliciting 0 { = . r bytes_in_flight + . r bytes_in_flight size } {}
    ? == space 0 { = . r largest_sent0 pn } {}
    ? == space 1 { = . r largest_sent1 pn } {}
    ? == space 2 { = . r largest_sent2 pn } {}
    ? != ack_eliciting 0 {
        ? == space 0 { = . r last_ae_sent0 now } {}
        ? == space 1 { = . r last_ae_sent1 now } {}
        ? == space 2 { = . r last_ae_sent2 now } {}
    } {}
}

// ── RTT (§5) ────────────────────────────────────────────────────
@ __qr_update_rtt * QuicRecovery r i latest i ack_delay → v {
    = . r latest_rtt latest
    ? == . r has_rtt_sample 0 {
        = . r has_rtt_sample 1
        = . r min_rtt latest
        = . r smoothed_rtt latest
        = . r rttvar / latest 2
        ^
    } {}
    ? < latest . r min_rtt { = . r min_rtt latest } {}
    : ~ i delay ack_delay
    ? != . r confirmed 0 { ? > delay . r max_ack_delay { = delay . r max_ack_delay } {} } {}
    : ~ i adjusted latest
    ? >= - latest delay . r min_rtt { = adjusted - latest delay } {}
    : i diff ? > . r smoothed_rtt adjusted - . r smoothed_rtt adjusted - adjusted . r smoothed_rtt
    = . r rttvar / + * 3 . r rttvar diff 4
    = . r smoothed_rtt / + * 7 . r smoothed_rtt adjusted 8
}

@ quic_rec_pto * QuicRecovery r → i {
    : i four_var * 4 . r rttvar
    : i g ( quic_rec_kgranularity )
    ^ + . r smoothed_rtt ? > four_var g four_var g
}

// ── congestion (§7, NewReno) ───────────────────────────────────
@ __qr_in_recovery * QuicRecovery r i sent_time → b {
    ^ <= sent_time . r recovery_start
}

@ __qr_on_acked_cc * QuicRecovery r * QuicSentPkt p → v {
    ? == . p in_flight 0 { ^ } {}
    = . r bytes_in_flight - . r bytes_in_flight . p size
    ? < . r bytes_in_flight 0 { = . r bytes_in_flight 0 } {}
    ? ( __qr_in_recovery r . p time_ms ) { ^ } {}
    ? < . r cwnd . r ssthresh {
        = . r cwnd + . r cwnd . p size
    } {
        = . r cwnd + . r cwnd / * . r max_datagram . p size . r cwnd
    }
}

@ __qr_on_congestion_event * QuicRecovery r i sent_time i now → v {
    ? ( __qr_in_recovery r sent_time ) { ^ } {}
    = . r recovery_start now
    = . r ssthresh / . r cwnd 2
    : i floor * 2 . r max_datagram
    = . r cwnd ? > . r ssthresh floor . r ssthresh floor
}

// ── loss detection (§6.1) ─────────────────────────────────────
// Declare lost every packet in `space` that is either kPacketThreshold
// behind the largest acknowledged or older than the time threshold;
// queue their frames; arm the loss timer for the rest.
@ __qr_detect_lost * QuicRecovery r i space i now → v {
    : i la ( __qr_largest_acked r space )
    ? < la 0 { ^ } {}
    : i rtt ? > . r latest_rtt . r smoothed_rtt . r latest_rtt . r smoothed_rtt
    : ~ i delay / * 9 rtt 8
    ? < delay ( quic_rec_kgranularity ) { = delay ( quic_rec_kgranularity ) } {}
    : i lost_before - now delay
    ( __qr_set_loss_time r space 0 )
    : ( Vec i ) l ( __qr_sent r space )
    : ( Vec i ) keep ( vec_new [i] )
    : ( Vec u ) lostq ( __qr_lost r space )
    : ~ i latest_lost_time 0
    : ~ i any_lost 0
    : ~ i k 0
    ~ < k ( vec_len [i] l ) {
        : *QuicSentPkt p ( __qr_pkt l k )
        ? > . p pn la {
            ( vec_push [i] keep # i p )
        } {
            ? | <= . p time_ms lost_before <= . p pn - la ( quic_rec_kpacket_threshold ) {
                ( bytes_extend_bytes lostq . p frames )
                ? != . p in_flight 0 {
                    = . r bytes_in_flight - . r bytes_in_flight . p size
                    ? < . r bytes_in_flight 0 { = . r bytes_in_flight 0 } {}
                    = any_lost 1
                    ? > . p time_ms latest_lost_time { = latest_lost_time . p time_ms } {}
                } {}
                ( __qr_pkt_free # i p )
            } {
                : i due + . p time_ms delay
                : i cur ( __qr_loss_time r space )
                ? | == cur 0 < due cur { ( __qr_set_loss_time r space due ) } {}
                ( vec_push [i] keep # i p )
            }
        }
        = k + k 1
    }
    ( vec_free [i] l )
    ? == space 0 { = . r sent0 keep } {}
    ? == space 1 { = . r sent1 keep } {}
    ? == space 2 { = . r sent2 keep } {}
    ? != any_lost 0 { ( __qr_on_congestion_event r latest_lost_time now ) } {}
}

// ── ACK processing (§6.1 / §5.1) ──────────────────────────────
@ __qr_ri ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → ^ x F → ^ 0 }
}

@ quic_rec_on_ack * QuicRecovery r i space * QuicFrame ack i now → i {
    : i largest . ack a
    ? > largest ( __qr_largest_sent r space ) { ^ -1 } {}
    // Collect the acknowledged ranges as [lo, hi] pairs.
    : ( Vec i ) rng ( vec_new [i] )
    : ~ i hi largest
    : ~ i lo - largest . ack c
    ( vec_push [i] rng lo ) ( vec_push [i] rng hi )
    : ~ i k 0
    : i nints ? != . ack d 0 - ( vec_len [i] . ack ints ) 3 ( vec_len [i] . ack ints )
    ~ < + k 1 nints {
        : i gap ( __qr_ri . ack ints k )
        : i len ( __qr_ri . ack ints + k 1 )
        = hi - - lo gap 2
        = lo - hi len
        ? < lo 0 { ( vec_free [i] rng ) ^ -1 } {}
        ( vec_push [i] rng lo ) ( vec_push [i] rng hi )
        = k + k 2
    }
    : i prev_largest ( __qr_largest_acked r space )
    ? > largest prev_largest { ( __qr_set_largest_acked r space largest ) } {}
    // Walk the sent log once; newly acked packets leave it.
    : ( Vec i ) l ( __qr_sent r space )
    : ( Vec i ) keep ( vec_new [i] )
    : ~ i newly_ae 0
    : ~ i largest_pkt_time -1
    : ~ i largest_pkt_ae 0
    = k 0
    ~ < k ( vec_len [i] l ) {
        : *QuicSentPkt p ( __qr_pkt l k )
        : ~ b acked F
        : ~ i j 0
        ~ & ! acked < j ( vec_len [i] rng ) {
            ? & >= . p pn ( __qr_ri rng j ) <= . p pn ( __qr_ri rng + j 1 ) { = acked T } {}
            = j + j 2
        }
        ? acked {
            ? == . p pn largest { = largest_pkt_time . p time_ms = largest_pkt_ae . p ack_eliciting } {}
            ? != . p ack_eliciting 0 { = newly_ae 1 } {}
            ( __qr_on_acked_cc r p )
            ( __qr_pkt_free # i p )
        } { ( vec_push [i] keep # i p ) }
        = k + k 1
    }
    ( vec_free [i] l )
    ? == space 0 { = . r sent0 keep } {}
    ? == space 1 { = . r sent1 keep } {}
    ? == space 2 { = . r sent2 keep } {}
    ( vec_free [i] rng )
    // RTT sample only when the largest acked is newly acked and ack-eliciting.
    ? & >= largest_pkt_time 0 != largest_pkt_ae 0 {
        : i delay_ms / << . ack b . r ack_delay_exp 1000
        ( __qr_update_rtt r - now largest_pkt_time delay_ms )
    } {}
    ? != newly_ae 0 { = . r pto_count 0 } {}
    ( __qr_detect_lost r space now )
    ^ 0
}

@ quic_rec_take_lost * QuicRecovery r i space → ( Vec u ) {
    : ( Vec u ) q ( __qr_lost r space )
    : ( Vec u ) out ( bytes_slice q 0 ( vec_len [u] q ) )
    ( vec_clear [u] q )
    ^ out
}

// ── timers (§6.2) ─────────────────────────────────────────────
@ __qr_has_ae_in_flight * QuicRecovery r i space → b {
    : ( Vec i ) l ( __qr_sent r space )
    : ~ i k 0
    ~ < k ( vec_len [i] l ) {
        : *QuicSentPkt p ( __qr_pkt l k )
        ? != . p ack_eliciting 0 { ^ T } {}
        = k + k 1
    }
    ^ F
}

// The PTO deadline over all spaces (0 = none armed).
@ __qr_pto_time * QuicRecovery r → i {
    : i base ( quic_rec_pto r )
    : i backoff << 1 . r pto_count
    : ~ i best 0
    : ~ i space 0
    ~ < space 3 {
        ? ( __qr_has_ae_in_flight r space ) {
            : ~ i pto * base backoff
            ? & == space 2 != . r confirmed 0 { = pto + pto * . r max_ack_delay backoff } {}
            // 1-RTT packets are not probed before the handshake is confirmed.
            ? | != space 2 != . r confirmed 0 {
                : i t + ( __qr_last_ae r space ) pto
                ? | == best 0 < t best { = best t } {}
            } {}
        } {}
        = space + space 1
    }
    ^ best
}

@ __qr_earliest_loss * QuicRecovery r → i {
    : ~ i best 0
    : ~ i space 0
    ~ < space 3 {
        : i t ( __qr_loss_time r space )
        ? & != t 0 | == best 0 < t best { = best t } {}
        = space + space 1
    }
    ^ best
}

@ quic_rec_next_timeout * QuicRecovery r → i {
    : i lt ( __qr_earliest_loss r )
    ? != lt 0 { ^ lt } {}
    ^ ( __qr_pto_time r )
}

@ quic_rec_on_timeout * QuicRecovery r i now → v {
    : i lt ( __qr_earliest_loss r )
    ? & != lt 0 <= lt now {
        : ~ i space 0
        ~ < space 3 {
            : i t ( __qr_loss_time r space )
            ? & != t 0 <= t now { ( __qr_detect_lost r space now ) } {}
            = space + space 1
        }
        ^
    } {}
    : i pt ( __qr_pto_time r )
    ? & != pt 0 <= pt now {
        // Probe the earliest space with ack-eliciting data in flight.
        : ~ i space 0
        : ~ i chosen -1
        ~ & < space 3 < chosen 0 {
            ? & ( __qr_has_ae_in_flight r space ) | != space 2 != . r confirmed 0 { = chosen space } {}
            = space + space 1
        }
        = . r probe_space chosen
        = . r pto_count + . r pto_count 1
    } {}
}

@ quic_rec_take_probe * QuicRecovery r → i {
    : i s . r probe_space
    = . r probe_space -1
    ^ s
}

// The oldest unacknowledged ack-eliciting frames in `space`, for a
// probe (§6.2.4: new or previously sent data).
@ quic_rec_probe_frames * QuicRecovery r i space → ( Vec u ) {
    : ( Vec i ) l ( __qr_sent r space )
    : ~ i k 0
    ~ < k ( vec_len [i] l ) {
        : *QuicSentPkt p ( __qr_pkt l k )
        ? > ( vec_len [u] . p frames ) 0 { ^ ( bytes_slice . p frames 0 ( vec_len [u] . p frames ) ) } {}
        = k + k 1
    }
    ^ ( vec_new [u] )
}

@ quic_rec_discard_space * QuicRecovery r i space → v {
    : ( Vec i ) l ( __qr_sent r space )
    : ~ i k 0
    ~ < k ( vec_len [i] l ) {
        : *QuicSentPkt p ( __qr_pkt l k )
        ? != . p in_flight 0 { = . r bytes_in_flight - . r bytes_in_flight . p size } {}
        ( __qr_pkt_free # i p )
        = k + k 1
    }
    ( vec_clear [i] l )
    ? < . r bytes_in_flight 0 { = . r bytes_in_flight 0 } {}
    ( __qr_set_loss_time r space 0 )
    ( vec_clear [u] ( __qr_lost r space ) )
    = . r pto_count 0
}

@ quic_rec_can_send * QuicRecovery r i size → b {
    ^ <= + . r bytes_in_flight size . r cwnd
}

// The datagram size changed (the peer's max_udp_payload_size is known).
@ quic_rec_new_max_datagram * QuicRecovery r i max_datagram → v {
    = . r max_datagram max_datagram
}
