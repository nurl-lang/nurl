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
$ `stdlib/core/rcbox.nu`
$ `stdlib/std/arc.nu`

& `c` @ nurl_atomic_i64_load *u p → i

& `c` @ nurl_atomic_i64_inc *u p → i

@ __hb_cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

// Build the encoded heartbeat payload: a gossip message carrying just this
// node's Alive self-fact at its current incarnation. Pure.
@ heartbeat_payload PkMemberTable t → ( Vec u ) {
    : ( Vec PkMember ) g ( vec_with_cap [PkMember] 1 )
    ( vec_push [PkMember] g ( pktable_self_fact t ) )
    : PkMsg m @ PkMsg { ( pk_ping ) 0 ( vec_new [u] ) g }
    ^ ( pkmsg_encode m )
}

: HeartbeatImpl {
    Thread thr
    ( Arc i ) stop  // atomic flag: 0 = run, >0 = stop (the thread holds a share of its own)
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
        : i _o ( nurl_atomic_i64_inc # *u ( arc_ptr [i] . hb stop ) )  // 0 → 1: stop after current sleep
        ( thread_join . hb thr )
        = . hb live 0
    } {}
}

% Drop HeartbeatImpl {
    @ drop HeartbeatImpl hb → v {
        ? == . hb live 1 {
            : i _o ( nurl_atomic_i64_inc # *u ( arc_ptr [i] . hb stop ) )
            ( thread_join . hb thr )
        } {}
    }
}

// Start the heartbeat thread. It broadcasts the self-alive payload to `group`
// every `interval_ms`, reading the table under `mtx` (the caller must hold the
// SAME mtx around its own table mutations). `rc` is the heartbeat's own relay
// connection. Returns a Heartbeat to stop later (its last owner stops it).
@ heartbeat_start PkMemberTable t RelayClient rc ( Vec u ) group i interval_ms Mutex mtx → Heartbeat {
    : ( Shared HeartbeatImpl ) hb__box ( shared_zero [HeartbeatImpl] )
    : *HeartbeatImpl hb ( shared_ptr [HeartbeatImpl] hb__box )
    : ( Arc i ) stop ( arc_new [i] 0 )
    = . hb stop ( arc_clone [i] stop )
    = . hb live 0
    : ( Vec u ) grp ( __hb_cpy group )

    : ( @ v ) body \ → v {
        ~ == ( nurl_atomic_i64_load # *u ( arc_ptr [i] stop ) ) 0 {
            ( sleep_ms interval_ms )
            ? == ( nurl_atomic_i64_load # *u ( arc_ptr [i] stop ) ) 0 {
                ( mutex_lock mtx )
                : ( Vec u ) payload ( heartbeat_payload t )
                ( mutex_unlock mtx )
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
