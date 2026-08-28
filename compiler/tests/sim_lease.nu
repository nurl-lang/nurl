// sim_lease.nu — §7.5 Phase 13 chaos-harness scenario for FENCING (dist/lease).
//
// The split-ownership hazard: during a ring change two nodes can BRIEFLY both
// believe they own a key. CRDT state survives that (merges commute), but an
// external SIDE EFFECT executed twice does not. dist/lease guards the resource
// with a fencing token (epoch monotonicity) + idempotency key (task_id), giving
// AT-MOST-ONCE across the window in EITHER ordering. This scenario proves it
// over dist/sim's deterministic bus, with loss + reorder + retries:
//
//   model: the OLD owner (epoch e_old) and the NEW owner (epoch e_new > e_old)
//   both dispatch the SAME logical task (same idem = task_id, as dist/job keeps
//   the task_id across a re-home) to a shared RESOURCE node, which admits via
//   lease_admit and performs the effect (a counter++) only when admitted.
//
//   (A) old-first  → old admitted, new's EXECUTE deduped by idempotency  → 1
//   (B) new-first  → new admitted, old's EXECUTE fenced by stale epoch   → 1
//   (C) concurrent under 35% loss + reorder, both retrying               → 1
//
// Seeded → byte-reproducible; every "effect ran exactly once" can genuinely fail.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/dist/lease.nu`
$ `stdlib/dist/sim.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ pi s label i v → v { ( nurl_print label ) ( nurl_println_int v ) }

@ bytes4 i a i b i c i d → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) ( vec_push [u] v # u a ) ( vec_push [u] v # u b ) ( vec_push [u] v # u c ) ( vec_push [u] v # u d ) ^ v }

// EXECUTE wire: [epoch:u64][idem:u64][keylen:u16][key…]
@ build_exec ( Vec u ) key i epoch i idem → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( bytes_push_u64_be b # u64 epoch )
    ( bytes_push_u64_be b # u64 idem )
    ( bytes_push_u16_be b # u16 ( vec_len [u] key ) )
    ( vec_extend [u] b key )
    ^ b
}

// dispatch an EXECUTE from `src` to the resource node `r` over the bus
@ dispatch_exec * SimNet net i src i r ( Vec u ) key i epoch i idem i now → v {
    : ( Vec u ) b ( build_exec key epoch idem )
    ( sim_send net src r b now )
    ( vec_free [u] b )
}

// resource side: deliver every due EXECUTE, admit via the lease, and return how
// many effects were actually performed in this batch.
@ deliver_exec * SimNet net * LeaseTable lease i now → i {
    : ( Vec s ) due ( sim_due net now )
    : i dn ( vec_len [s] due )
    : ~ i ran 0
    : ~ i k 0
    ~ < k dn {
        : s mp ?? ( vec_get [s] due k ) { T x → x F → # s 0 }
        ? != # i mp 0 {
            : *SimMsg sm # *SimMsg mp
            : i epoch # i ?? ( bytes_read_u64_be . sm bytes 0 ) { T x → x F → # u64 0 }
            : i idem # i ?? ( bytes_read_u64_be . sm bytes 8 ) { T x → x F → # u64 0 }
            : i klen # i ?? ( bytes_read_u16_be . sm bytes 16 ) { T x → x F → # u16 0 }
            : ( Vec u ) key ( vec_with_cap [u] klen )
            : ~ i j 0
            ~ < j klen { ?? ( vec_get [u] . sm bytes + 18 j ) { T x → ( vec_push [u] key x ) F → {} } = j + j 1 }
            ? ( lease_admit lease key epoch idem ) { = ran + ran 1 } {}
            ( vec_free [u] key )
            ( sim_msg_free sm )
        } {}
        = k + k 1
    }
    ( vec_free [s] due )
    ^ ran
}

// run `rounds`: old owner dispatches iff `old_on`, new owner iff `new_on`;
// both retry every round (at-least-once); count total effects performed.
@ run_window * SimNet net * LeaseTable lease ( Vec u ) key i e_old i e_new i idem i r_idx b old_on b new_on i rounds i now0 → i {
    : ~ i now now0
    : ~ i total 0
    : ~ i r 0
    ~ < r rounds {
        = now + now 1
        ? old_on { ( dispatch_exec net 0 r_idx key e_old idem now ) } {}
        ? new_on { ( dispatch_exec net 1 r_idx key e_new idem now ) } {}
        = total + total ( deliver_exec net lease now )
        = r + r 1
    }
    ^ total
}

@ main → i {
    : i R 2  // node 0 = old owner, 1 = new owner, 2 = resource
    : ( Vec u ) key ( bytes4 42 42 42 42 )
    : i e_old 7
    : i e_new 8
    : i idem 5000000001  // the task_id, identical across both owners (re-home)

    // ── (A) old-first: idempotency dedups the new owner ──────────────
    : *SimNet na ( sim_net_new 3 1111 0 1 0 )
    : *LeaseTable la ( lease_new )
    : i a_old ( run_window na la key e_old e_new idem R T F 6 0 )  // only old, settles to admitted
    : i a_both ( run_window na la key e_old e_new idem R T T 6 6 )  // now new joins, retrying
    ( pi `A old-first: effects during old-only phase = ` a_old )
    ( pi `A old-first: effects after new joins      = ` a_both )
    ( pb `A old-first: effect ran EXACTLY once total: ` == + a_old a_both 1 )
    ( pb `A old-first: fence advanced to new epoch:   ` == ( lease_token la key ) e_new )
    ( lease_free la ) ( sim_net_free na )

    // ── (B) new-first: stale epoch fences the old owner ──────────────
    : *SimNet nb ( sim_net_new 3 2222 0 1 0 )
    : *LeaseTable lb ( lease_new )
    : i b_new ( run_window nb lb key e_old e_new idem R F T 6 0 )  // only new
    : i b_both ( run_window nb lb key e_old e_new idem R T T 6 6 )  // old joins, retrying — fenced
    ( pi `B new-first: effects during new-only phase = ` b_new )
    ( pi `B new-first: effects after old joins       = ` b_both )
    ( pb `B new-first: effect ran EXACTLY once total: ` == + b_new b_both 1 )
    ( pb `B new-first: token stays at new epoch:      ` == ( lease_token lb key ) e_new )
    ( lease_free lb ) ( sim_net_free nb )

    // ── (C) concurrent under 35% loss + reorder, both retrying ───────
    : *SimNet nc ( sim_net_new 3 33330 35 1 3 )
    : *LeaseTable lc ( lease_new )
    : i c_total ( run_window nc lc key e_old e_new idem R T T 60 0 )
    ( pi `C concurrent: total effects performed      = ` c_total )
    ( pb `C concurrent: effect ran AT MOST once:      ` <= c_total 1 )
    ( pb `C concurrent: effect ran AT LEAST once:     ` >= c_total 1 )
    ( pb `C concurrent: messages were actually dropped: ` > ( sim_dropped nc ) 0 )
    ( lease_free lc ) ( sim_net_free nc )

    ( vec_free [u] key )
    ^ 0
}
