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

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ __sim_cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

: SimMsg {
    i src
    i dst
    i at          // virtual delivery time
    ( Vec u ) bytes
}
@ sim_msg_free *SimMsg m → v { ( vec_free [u] . m bytes ) ( nurl_free # s m ) }

: SimNet {
    ( Vec s ) inflight   // *SimMsg, not yet delivered
    i n                  // node count
    i seed               // LCG state (deterministic RNG)
    i drop_pct           // 0..100 per-message drop probability
    i latency            // base delivery delay (virtual ticks)
    i jitter             // extra random delay 0..jitter (causes reorder)
    ( Vec i ) reach      // n*n reachability matrix; 1 = link up, 0 = partitioned
    i delivered          // counter (messages actually delivered)
    i dropped            // counter (dropped or partitioned away)
}

@ sim_net_new i n i seed i drop_pct i latency i jitter → *SimNet {
    : *SimNet net # *SimNet ( nurl_alloc Z SimNet )
    = . net inflight ( vec_new [s] )
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
    ^ net
}

@ sim_net_free *SimNet net → v {
    : i m ( vec_len [s] . net inflight )
    : ~ i k 0
    ~ < k m { : s pp ?? ( vec_get [s] . net inflight k ) { T x → x F → # s 0 } ? != # i pp 0 { ( sim_msg_free # *SimMsg pp ) } {} = k + k 1 }
    ( vec_free [s] . net inflight )
    ( vec_free [i] . net reach )
    ( nurl_free # s net )
}

// LCG (Knuth MMIX constants); wraps in i64. Returns a non-negative pseudo-int.
@ __sim_rand *SimNet net → i {
    = . net seed + * . net seed 6364136223846793005 1442695040888963407
    : i r . net seed
    ^ ? < r 0 - 0 r r
}
@ __sim_chance *SimNet net i pct → b { ^ < % ( __sim_rand net ) 100 pct }

@ sim_reachable *SimNet net i a i b → b {
    ^ == ?? ( vec_get [i] . net reach + * a . net n b ) { T x → x F → 0 } 1
}
@ sim_partition *SimNet net i a i b → v {
    ( vec_set [i] . net reach + * a . net n b 0 )
    ( vec_set [i] . net reach + * b . net n a 0 )
}
@ sim_heal *SimNet net i a i b → v {
    ( vec_set [i] . net reach + * a . net n b 1 )
    ( vec_set [i] . net reach + * b . net n a 1 )
}
// Heal every link (e.g. after a full partition scenario).
@ sim_heal_all *SimNet net → v {
    : i tot * . net n . net n
    : ~ i k 0
    ~ < k tot { ( vec_set [i] . net reach k 1 ) = k + k 1 }
}

// Submit a message src→dst at virtual time `now`. Silently lost if the link is
// partitioned or it loses the drop roll; otherwise scheduled for now + latency
// + a random jitter (which reorders deliveries). Bytes are copied.
@ sim_send *SimNet net i src i dst ( Vec u ) bytes i now → v {
    ? ! ( sim_reachable net src dst ) { = . net dropped + . net dropped 1 ^ v } {}
    ? & > . net drop_pct 0 ( __sim_chance net . net drop_pct ) { = . net dropped + . net dropped 1 ^ v } {}
    : i extra ? > . net jitter 0 % ( __sim_rand net ) . net jitter 0
    : *SimMsg m # *SimMsg ( nurl_alloc Z SimMsg )
    = . m src src
    = . m dst dst
    = . m at + + now . net latency extra
    = . m bytes ( __sim_cpy bytes )
    ( vec_push [s] . net inflight # s m )
}

// Pop all messages whose delivery time has arrived (at <= now). Caller owns
// the returned *SimMsg list — read src/dst/bytes, then free each with
// sim_msg_free and the container with vec_free [s].
@ sim_due *SimNet net i now → ( Vec s ) {
    : ( Vec s ) due ( vec_new [s] )
    : ( Vec s ) keep ( vec_new [s] )
    : i m ( vec_len [s] . net inflight )
    : ~ i k 0
    ~ < k m {
        : s pp ?? ( vec_get [s] . net inflight k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *SimMsg msg # *SimMsg pp
            ? <= . msg at now { ( vec_push [s] due pp ) = . net delivered + . net delivered 1 } { ( vec_push [s] keep pp ) }
        } {}
        = k + k 1
    }
    ( vec_free [s] . net inflight )
    = . net inflight keep
    ^ due
}

@ sim_inflight_count *SimNet net → i { ^ ( vec_len [s] . net inflight ) }
@ sim_delivered *SimNet net → i { ^ . net delivered }
@ sim_dropped *SimNet net → i { ^ . net dropped }
