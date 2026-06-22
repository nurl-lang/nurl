// stdlib/dist/heartbeat.nu — liveness heartbeat on a DEDICATED OS THREAD
// (§7.5 Phase 10, Tier 1). NURL fibers are cooperative: a compute handler
// that never yields starves every fiber on its worker — including a
// fiber-based failure detector — so a busy node can be wrongly declared dead.
//
// The fix is to put the ONE thing that must never starve — the "I am alive"
// heartbeat — on a real OS thread. The runtime is M:N (worker threads + a
// reactor thread), so the OS preempts threads: this heartbeat fires on its
// timer even when every worker fiber is pinned in a tight loop. Combined with
// net/membership's self-refutation, a node that is merely BUSY keeps its
// place in the cluster.
//
// The thread gossips the node's Alive self-fact (at its current incarnation,
// so it also carries any refutation) to the group over its OWN relay
// connection — never contending with the data-plane transport. The membership
// table is shared with the data plane under the caller-provided Mutex.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/net/membership.nu`
$ `stdlib/net/relay.nu`

& `c` @ nurl_atomic_i64_load *u p → i

& `c` @ nurl_atomic_i64_inc *u p → i

@ __hb_cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

// Build the encoded heartbeat payload: a gossip message carrying just this
// node's Alive self-fact at its current incarnation. Pure.
@ heartbeat_payload * PkMemberTable t → ( Vec u ) {
    : ( Vec s ) g ( vec_new [s] )
    ( vec_push [s] g # s ( pktable_self_fact t ) )
    : PkMsg m @ PkMsg { ( pk_ping ) 0 ( vec_new [u] ) g }
    : ( Vec u ) bytes ( pkmsg_encode m )
    ( pkmsg_free m )
    ^ bytes
}

: Heartbeat {
    Thread thr
    * i stop  // atomic flag: 0 = run, >0 = stop
    s env  // thread closure env, freed after join
    i live
}

// Start the heartbeat thread. It broadcasts the self-alive payload to `group`
// every `interval_ms`, reading the table under `mtx` (the caller must hold the
// SAME mtx around its own table mutations). `rc` is the heartbeat's own relay
// connection. Returns a *Heartbeat to stop later.
@ heartbeat_start * PkMemberTable t RelayClient rc ( Vec u ) group i interval_ms Mutex mtx → *Heartbeat {
    : *Heartbeat hb # *Heartbeat ( nurl_alloc Z Heartbeat )
    : *i stop # *i ( nurl_alloc 8 )
    = . stop 0 0
    = . hb stop stop
    = . hb live 0
    : ( Vec u ) grp ( __hb_cpy group )

    : ( @ v ) body \ → v {
        ~ == ( nurl_atomic_i64_load # *u stop ) 0 {
            ( sleep_ms interval_ms )
            ? == ( nurl_atomic_i64_load # *u stop ) 0 {
                ( mutex_lock mtx )
                : ( Vec u ) payload ( heartbeat_payload t )
                ( mutex_unlock mtx )
                ?? ( relay_broadcast rc grp payload ) { T _ → {} F _ → {} }
                ( vec_free [u] payload )
            } {}
        }
        ( vec_free [u] grp )
    }

    : !Thread ThreadErr tr ( thread_spawn body )
    ?? tr {
        T th → { = . hb thr th = . hb env # s # *u body 1 = . hb live 1 }
        F e → { ( vec_free [u] grp ) }
    }
    ^ hb
}

// Signal the heartbeat thread to stop, join it, and free its resources.
@ heartbeat_stop * Heartbeat hb → v {
    ? == . hb live 1 {
        ( nurl_atomic_i64_inc # *u . hb stop )  // 0 → 1: stop after current sleep
        ( thread_join . hb thr )
        ? != # i . hb env 0 { ( nurl_free . hb env ) } {}
        = . hb live 0
    } {}
    ( nurl_free # s . hb stop )
    ( nurl_free # s hb )
}
