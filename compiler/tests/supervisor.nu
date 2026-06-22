// supervisor.nu — offline tests for stdlib/std/supervisor.nu.
//
// Deterministic: runs each child's supervision loop synchronously
// (supervise_one, no fibers), with backoff 0 (no sleeping). Each child
// captures a heap counter that survives restarts (the supervisor re-invokes
// the same closure), so we can assert exactly how many times it ran and how
// many restarts happened.
//
//   1. Transient child panics 3× then returns → restarted 3×, then stops.
//   2. Temporary child panics → never restarted.
//   3. Always-panicking child hits the restart-intensity cap → supervisor
//      gives up after max_restarts.

$ `stdlib/core/string.nu`
$ `stdlib/std/supervisor.nu`

@ make_counter → *i {
    : *i p # *i ( nurl_alloc Z i )
    ( nurl_poke p 0 0 )
    ^ p
}

@ report s label * i ctr Supervisor s2 → v {
    ( nurl_print label )
    ( nurl_print `counter=` ) ( nurl_print_int ( nurl_peek ctr 0 ) )
    ( nurl_print ` restarts=` ) ( nurl_print_int ( child_restarts s2 0 ) )
    ( nurl_print `\n` )
}

@ main → i {
    // ── 1. Transient: panic until the 4th run, then succeed ──────
    : *i c1 ( make_counter )
    : Supervisor s1 ( supervisor_new 10 100000 )
    ( supervisor_add s1 `flaky` @ RestartPolicy { RTransient }
    \ → v {
        : i n + 1 ( nurl_peek c1 0 )
        ( nurl_poke c1 0 n )
        ? < n 4 { ( panic `boom` ) } {}
    } )
    ( supervise_one s1 0 )
    ( report `transient: ` c1 s1 )
    ( supervisor_free s1 )
    ( nurl_free # s c1 )

    // ── 2. Temporary: a single panic is terminal ─────────────────
    : *i c2 ( make_counter )
    : Supervisor s2 ( supervisor_new 10 100000 )
    ( supervisor_add s2 `oneshot` @ RestartPolicy { RTemporary }
    \ → v {
        : i n + 1 ( nurl_peek c2 0 )
        ( nurl_poke c2 0 n )
        ( panic `nope` )
    } )
    ( supervise_one s2 0 )
    ( report `temporary: ` c2 s2 )
    ( supervisor_free s2 )
    ( nurl_free # s c2 )

    // ── 3. Always crashes → restart-intensity cap (max 2) ────────
    : *i c3 ( make_counter )
    : Supervisor s3 ( supervisor_new 2 100000 )
    ( supervisor_add s3 `hopeless` @ RestartPolicy { RPermanent }
    \ → v {
        : i n + 1 ( nurl_peek c3 0 )
        ( nurl_poke c3 0 n )
        ( panic `again` )
    } )
    ( supervise_one s3 0 )
    ( report `intensity: ` c3 s3 )
    ( supervisor_free s3 )
    ( nurl_free # s c3 )

    // ── policy names ─────────────────────────────────────────────
    ( nurl_print_str ( restart_policy_name # RestartPolicy RPermanent ) )
    ( nurl_print_str ( restart_policy_name # RestartPolicy RTransient ) )
    ( nurl_print_str ( restart_policy_name # RestartPolicy RTemporary ) )
    ^ 0
}
