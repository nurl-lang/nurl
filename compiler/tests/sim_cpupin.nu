// sim_cpupin.nu — §7.5 Phase 13 chaos-harness scenario: a CPU-pinned node is
// NOT evicted. The non-obvious distributed-compute failure mode (ASYNC.md):
// a node doing real work misses probe acks, a peer suspects it, and the busy
// node gets ejected mid-computation. The Tier-1 defence: the heartbeat runs on
// a dedicated OS thread (so it fires even under a 100%-CPU pin) and the node
// self-refutes a stale suspicion (bumps its incarnation past the accuser's), so
// its next heartbeat — at a higher incarnation — reinstates it.
//
// This drives the REAL net/failuredetector + net/membership + dist/heartbeat
// over dist/sim's deterministic bus:
//   * P (peer) probes B and D; NEITHER ever acks (both model a node that won't
//     service probe RPCs promptly), so P suspects both;
//   * B is CPU-pinned-but-alive: it still emits heartbeats and, on hearing it
//     is suspected, REFUTES → its heartbeat at the higher incarnation wins → P
//     keeps B ALIVE;
//   * D is genuinely dead: no heartbeat, no refute → P's suspicion expires and
//     the sweep EVICTS D to dead.
// The D case proves the harness CAN evict (so "B stays alive" can genuinely
// fail); the contrast is the whole point. Seeded → byte-reproducible.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/net/membership.nu`
$ `stdlib/net/failuredetector.nu`
$ `stdlib/dist/heartbeat.nu`
$ `stdlib/dist/sim.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ pk i id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + id k ) = k + k 1 } ^ v }

// P broadcasts its membership view to B (so B can hear it is suspected).
@ send_p_gossip * SimNet net * PkMemberTable tp i now → v {
    : ( Vec s ) g ( pktable_gossip tp 16 )
    : PkMsg m @ PkMsg { ( pk_ping ) 0 ( vec_new [u] ) g }
    : ( Vec u ) bytes ( pkmsg_encode m )
    ( sim_send net 0 1 bytes now )
    ( pkmsg_free m ) ( vec_free [u] bytes )
}
// B's dedicated heartbeat thread emits its self-alive fact to P every round.
@ send_b_heartbeat * SimNet net * PkMemberTable tb i now → v {
    : ( Vec u ) bytes ( heartbeat_payload tb )
    ( sim_send net 1 0 bytes now )
    ( vec_free [u] bytes )
}

// deliver due messages: a msg to P (dst 0) merges into P's table via the FD;
// a msg to B (dst 1) merges into B's table (where the self-suspect → refute).
@ deliver * SimNet net * FdState fd * PkMemberTable tb i now → v {
    : ( Vec s ) due ( sim_due net now )
    : i dn ( vec_len [s] due )
    : ~ i k 0
    ~ < k dn {
        : s mp ?? ( vec_get [s] due k ) { T x → x F → # s 0 }
        ? != # i mp 0 {
            : *SimMsg sm # *SimMsg mp
            : PkMsg pm ( pkmsg_decode . sm bytes )
            ? == . sm dst 0 { ( fd_on_gossip fd pm now ) } { ( pktable_apply_gossip tb pm now ) }
            ( pkmsg_free pm )
            ( sim_msg_free sm )
        } {}
        = k + k 1
    }
    ( vec_free [s] due )
}

// one round; returns 1 if P currently suspects B (so the caller can prove the
// probe genuinely failed before the heartbeat saved B). `probe_on` gates new
// probes — the settle phase runs heartbeat+gossip only so the end state is
// deterministic.
@ cp_round * SimNet net * FdState fd * PkMemberTable tp * PkMemberTable tb ( Vec u ) bpk i now b probe_on → i {
    ? probe_on { : FdAction a ( fd_tick fd now ) ( fd_action_free a ) } {}  // probe; ack never comes
    ( send_p_gossip net tp now )
    ( send_b_heartbeat net tb now )
    ( deliver net fd tb now )
    ? probe_on { : ( Vec s ) dead ( fd_sweep fd now ) ( __pk_dead_free dead ) } {}
    ^ ? == ( pktable_state_of tp bpk ) ( pk_suspect ) 1 0
}

@ main → i {
    : ( Vec u ) ppk ( pk 0 )
    : ( Vec u ) bpk ( pk 1 )
    : ( Vec u ) dpk ( pk 2 )

    : *SimNet net ( sim_net_new 3 4242 0 1 0 )  // clean bus; this is a liveness test
    : *PkMemberTable tp ( pktable_new ppk 4 10 3 4 )
    ( pktable_apply tp bpk ( pk_alive ) 1 0 )  // P bootstraps both peers alive@1
    ( pktable_apply tp dpk ( pk_alive ) 1 0 )
    : *PkMemberTable tb ( pktable_new bpk 4 10 3 4 )  // B's own table (self-refutes here)
    : *FdState fd ( fd_new # s tp 2 1 2 3 )

    // ── churn: P probes both, neither acks; B heartbeats + refutes ───
    : ~ b b_suspected F
    : ~ i now 0
    : ~ i r 0
    ~ < r 30 {
        = now + now 2
        ? == ( cp_round net fd tp tb bpk now T ) 1 { = b_suspected T } {}
        = r + r 1
    }
    // ── settle: heartbeat + gossip only, so the end state is stable ───
    : ~ i s 0
    ~ < s 12 { = now + now 2 ( cp_round net fd tp tb bpk now F ) = s + s 1 }

    ( pb `B was genuinely suspected at some point (probe failed): ` b_suspected )
    ( pb `CPU-pinned B is STILL ALIVE (heartbeat + refute won): ` == ( pktable_state_of tp bpk ) ( pk_alive ) )
    ( pb `silent D was EVICTED to dead (harness can evict): ` == ( pktable_state_of tp dpk ) ( pk_dead ) )

    ( fd_free fd )
    ( pktable_free tp ) ( pktable_free tb )
    ( sim_net_free net )
    ( vec_free [u] ppk ) ( vec_free [u] bpk ) ( vec_free [u] dpk )
    ^ 0
}
