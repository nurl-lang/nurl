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
// connection — never contending with the data-plane transport. It never
// touches the membership table, which stays the data plane's alone (its
// state is changed in place, with no lock): it holds the node's liveness
// (pktable_liveness, net/membership.nu) — a copy of the self pubkey and the
// table's incarnation counter, an Atomic — so a refute on the data plane is
// in the next heartbeat with no lock between the two threads.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/net/membership.nu`
$ `stdlib/net/relay.nu`
$ `stdlib/core/rcbox.nu`
$ `stdlib/std/atomic.nu`

@ __hb_cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

// The encoded heartbeat payload: a gossip message carrying just this node's
// Alive self-fact at its current incarnation. Pure.
@ __hb_payload_of PkMember self → ( Vec u ) {
    : ( Vec PkMember ) g ( vec_with_cap [PkMember] 1 )
    ( vec_push [PkMember] g self )
    : PkMsg m @ PkMsg { ( pk_ping ) 0 ( vec_new [u] ) g }
    ^ ( pkmsg_encode m )
}

@ heartbeat_payload PkMemberTable t → ( Vec u ) { ^ ( __hb_payload_of ( pktable_self_fact t ) ) }

// The same payload from the node's liveness alone (pktable_liveness): what
// the heartbeat thread sends, and the same bytes heartbeat_payload gives for
// the table it was taken from.
@ heartbeat_payload_of PkLiveness l → ( Vec u ) { ^ ( __hb_payload_of ( pk_liveness_fact l ) ) }

: HeartbeatImpl {
    Thread thr
    Atomic stop  // 0 = run, 1 = stop (the thread holds a copy of its own)
    i live
}

// A Heartbeat is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same heartbeat, and the last owner stops the thread
// (as heartbeat_stop does) and joins it.
: Heartbeat { ( Shared HeartbeatImpl ) ctl }

@ Heartbeat_share Heartbeat h → Heartbeat { ^ @ Heartbeat { ( shared_clone [HeartbeatImpl] . h ctl ) } }

@ Heartbeat_drop sink Heartbeat h → v {}

@ __Heartbeat_ptr Heartbeat h → *HeartbeatImpl { ^ ( shared_ptr [HeartbeatImpl] . h ctl ) }

// Stop and join a thread still running.
@ __hb_stop * HeartbeatImpl hb → v {
    ? == . hb live 1 {
        ( atomic_store . hb stop 1 )  // stop after the current sleep
        ( thread_join . hb thr )
        = . hb live 0
    } {}
}

% Drop HeartbeatImpl {
    @ drop HeartbeatImpl hb → v {
        ? == . hb live 1 {
            ( atomic_store . hb stop 1 )
            ( thread_join . hb thr )
        } {}
    }
}

// Start the heartbeat thread. It broadcasts the self-alive payload to `group`
// every `interval_ms`, at the incarnation the table `t` has then: the thread
// takes the node's liveness from `t` (pktable_liveness) and never the table,
// which the caller keeps changing as it likes, with no lock. `rc` is the
// heartbeat's own relay connection, handed over to the thread. Returns a
// Heartbeat to stop later (its last owner stops it).
@ heartbeat_start PkMemberTable t sink RelayClient rc ( Vec u ) group i interval_ms → Heartbeat {
    : ( Shared HeartbeatImpl ) hb__box ( shared_zero [HeartbeatImpl] )
    : *HeartbeatImpl hb ( shared_ptr [HeartbeatImpl] hb__box )
    : Atomic stop ( atomic_new 0 )
    = . hb stop ( Atomic_share stop )
    = . hb live 0
    : ( Vec u ) grp ( __hb_cpy group )
    : PkLiveness lv ( pktable_liveness t )

    : ( @ v ) body \ → v {
        ~ == ( atomic_load stop ) 0 {
            ( sleep_ms interval_ms )
            ? == ( atomic_load stop ) 0 {
                : ( Vec u ) payload ( heartbeat_payload_of lv )
                ?? ( relay_broadcast rc grp payload ) { T _ → {} F _ → {} }
            } {}
        }
    }

    : !Thread ThreadErr tr ( thread_spawn body )
    ?? tr {
        T th → { = . hb thr ( Thread_share th ) = . hb live 1 }
        F e → {}
    }
    ^ @ Heartbeat { hb__box }
}

// Signal the heartbeat thread to stop and join it. Optional: the last owner
// of the Heartbeat does the same.
@ heartbeat_stop Heartbeat hb__h → v {
    : *HeartbeatImpl hb ( __Heartbeat_ptr hb__h )
    ( __hb_stop hb )
}
