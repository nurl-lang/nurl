// stdlib/dist/sim.nu — deterministic discrete-event network simulator for the
// distributed stack (§7.5 Phase 13, the chaos harness). Because every layer
// is a pure, time-injected state machine (fd_tick(now), pktable_sweep(now),
// suspicion_expired(s, now), the codecs, the ring, the CRDTs, the lease), the
// real stdlib logic can be driven inside a fully simulated world: a virtual
// clock the harness advances, and an in-process message bus the harness fully
// controls. No sockets, no wall-clock, no flakiness — a seeded RNG makes every
// run byte-reproducible, and faults (drop, latency/jitter→reorder, partition,
// heal) are injected BEFORE the logic sees anything, so the headline assertions
// can genuinely fail.
//
// Nodes are integer indices 0..n-1. Messages carry opaque bytes (the real
// PkMsg / JobMsg / CRDT encodings). The harness routes a node's real encoded
// output through this bus instead of a socket.
//
// SimNet and SimMsg are handles: every copy is the same bus / message, and
// the last owner releases it (sim_net_free / sim_msg_free are early
// releases, optional). sim_due hands the due messages over in a Vec.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`

@ __sim_cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

: SimMsgImpl {
    i src
    i dst
    i at  // virtual delivery time
    ( Vec u ) bytes
}

// A SimMsg is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same message, and the last owner releases it.
: SimMsg { s ctl }

@ SimMsg_share SimMsg h → SimMsg { ^ @ SimMsg { # s ( rcbox_share # i . h ctl ) } }

@ SimMsg_drop sink SimMsg h → v {
    ( mem_forget h )
    ( rcbox_release [SimMsgImpl] # i . h ctl )
}

@ __SimMsg_ptr SimMsg h → *SimMsgImpl { ^ ( rcbox_ptr [SimMsgImpl] # i . h ctl ) }

// Let go of `m` now rather than at the end of its owner's scope.
@ sim_msg_free sink SimMsg m → v {}

@ sim_msg_src SimMsg m__h → i {
    : *SimMsgImpl m ( __SimMsg_ptr m__h )
    ^ . m src
}

@ sim_msg_dst SimMsg m__h → i {
    : *SimMsgImpl m ( __SimMsg_ptr m__h )
    ^ . m dst
}

// The virtual time it is (was) due.
@ sim_msg_at SimMsg m__h → i {
    : *SimMsgImpl m ( __SimMsg_ptr m__h )
    ^ . m at
}

// The payload, lent (the message owns it).
@ sim_msg_bytes SimMsg m__h → ( Vec u ) {
    : *SimMsgImpl m ( __SimMsg_ptr m__h )
    ^ . m bytes
}

: SimNetImpl {
    ( Vec SimMsg ) inflight  // not yet delivered
    i n  // node count
    i seed  // LCG state (deterministic RNG)
    i drop_pct  // 0..100 per-message drop probability
    i latency  // base delivery delay (virtual ticks)
    i jitter  // extra random delay 0..jitter (causes reorder)
    ( Vec i ) reach  // n*n reachability matrix; 1 = link up, 0 = partitioned
    i delivered  // counter (messages actually delivered)
    i dropped  // counter (dropped or partitioned away)
}

// A SimNet is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: SimNet { s ctl }

@ SimNet_share SimNet h → SimNet { ^ @ SimNet { # s ( rcbox_share # i . h ctl ) } }

@ SimNet_drop sink SimNet h → v {
    ( mem_forget h )
    ( rcbox_release [SimNetImpl] # i . h ctl )
}

@ __SimNet_ptr SimNet h → *SimNetImpl { ^ ( rcbox_ptr [SimNetImpl] # i . h ctl ) }

@ sim_net_new i n i seed i drop_pct i latency i jitter → SimNet {
    : i net__box ( rcbox_zero [SimNetImpl] )
    : *SimNetImpl net ( rcbox_ptr [SimNetImpl] net__box )
    = . net inflight ( vec_new [SimMsg] )
    = . net n n
    = . net seed seed
    = . net drop_pct drop_pct
    = . net latency latency
    = . net jitter jitter
    = . net delivered 0
    = . net dropped 0
    : ( Vec i ) reach ( vec_new [i] )
    : i tot * n n
    : ~ i k 0
    ~ < k tot { ( vec_push [i] reach 1 ) = k + k 1 }
    = . net reach reach
    ^ @ SimNet { # s net__box }
}

// Let go of `net` now rather than at the end of its owner's scope.
@ sim_net_free sink SimNet net → v {}

// LCG (Knuth MMIX constants); wraps in i64. Returns a non-negative pseudo-int.
@ __sim_rand * SimNetImpl net → i {
    = . net seed + * . net seed 6364136223846793005 1442695040888963407
    : i r . net seed
    ^ ? < r 0 - 0 r r
}

@ _sim_rand SimNet net__h → i {
    : *SimNetImpl net ( __SimNet_ptr net__h )
    ^ ( __sim_rand net )
}

@ __sim_chance * SimNetImpl net i pct → b { ^ < % ( __sim_rand net ) 100 pct }

@ __sim_reachable * SimNetImpl net i a i b → b {
    ^ == ?? ( vec_get [i] . net reach + * a . net n b ) { T x → x F → 0 } 1
}

@ sim_reachable SimNet net__h i a i b → b {
    : *SimNetImpl net ( __SimNet_ptr net__h )
    ^ ( __sim_reachable net a b )
}

@ sim_partition SimNet net__h i a i b → v {
    : *SimNetImpl net ( __SimNet_ptr net__h )
    ( vec_set [i] . net reach + * a . net n b 0 )
    ( vec_set [i] . net reach + * b . net n a 0 )
}

@ sim_heal SimNet net__h i a i b → v {
    : *SimNetImpl net ( __SimNet_ptr net__h )
    ( vec_set [i] . net reach + * a . net n b 1 )
    ( vec_set [i] . net reach + * b . net n a 1 )
}
// Heal every link (e.g. after a full partition scenario).
@ sim_heal_all SimNet net__h → v {
    : *SimNetImpl net ( __SimNet_ptr net__h )
    : i tot * . net n . net n
    : ~ i k 0
    ~ < k tot { ( vec_set [i] . net reach k 1 ) = k + k 1 }
}

// Submit a message src→dst at virtual time `now`. Silently lost if the link is
// partitioned or it loses the drop roll; otherwise scheduled for now + latency
// + a random jitter (which reorders deliveries). Bytes are copied.
@ sim_send SimNet net__h i src i dst ( Vec u ) bytes i now → v {
    : *SimNetImpl net ( __SimNet_ptr net__h )
    ? ! ( __sim_reachable net src dst ) { = . net dropped + . net dropped 1 ^ v } {}
    ? & > . net drop_pct 0 ( __sim_chance net . net drop_pct ) { = . net dropped + . net dropped 1 ^ v } {}
    : i extra ? > . net jitter 0 % ( __sim_rand net ) . net jitter 0
    : i m__box ( rcbox_zero [SimMsgImpl] )
    : *SimMsgImpl m ( rcbox_ptr [SimMsgImpl] m__box )
    = . m src src
    = . m dst dst
    = . m at + + now . net latency extra
    = . m bytes ( __sim_cpy bytes )
    ( vec_push [SimMsg] . net inflight @ SimMsg { # s m__box } )
}

// Take every message whose delivery time has arrived (at <= now), in
// submission order. The caller owns the returned messages: read them with
// sim_msg_src / sim_msg_dst / sim_msg_bytes; they go with the Vec.
@ sim_due SimNet net__h i now → ( Vec SimMsg ) {
    : *SimNetImpl net ( __SimNet_ptr net__h )
    : ( Vec SimMsg ) due ( vec_new [SimMsg] )
    // The messages still in flight are compacted to the front in place
    // (order kept); the due ones end up behind them and are cut off.
    : ( Vec SimMsg ) q . net inflight
    : i m ( vec_len [SimMsg] q )
    : ~ i keep 0
    : ~ i k 0
    ~ < k m {
        ?? ( vec_get [SimMsg] q k ) {
            T msg → {
                : *SimMsgImpl mp ( __SimMsg_ptr msg )
                ? <= . mp at now {
                    ( vec_push [SimMsg] due msg )
                    = . net delivered + . net delivered 1
                } {
                    ? != keep k { : b _sw ( vec_swap [SimMsg] q keep k ) } {}
                    = keep + keep 1
                }
            }
            F → {}
        }
        = k + k 1
    }
    : b _cut ( vec_truncate [SimMsg] q keep )
    ^ due
}

@ sim_inflight_count SimNet net__h → i {
    : *SimNetImpl net ( __SimNet_ptr net__h )
    ^ ( vec_len [SimMsg] . net inflight )
}

@ sim_delivered SimNet net__h → i {
    : *SimNetImpl net ( __SimNet_ptr net__h )
    ^ . net delivered
}

@ sim_dropped SimNet net__h → i {
    : *SimNetImpl net ( __SimNet_ptr net__h )
    ^ . net dropped
}
