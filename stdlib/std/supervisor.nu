// stdlib/std/supervisor.nu — OTP-style fiber supervision.
//
// **Phase 2 (TODO §7.2)** resilience capstone — the missing piece of
// "supervisointi + reconnect + backoff + circuit breaker" (backoff +
// circuit breaker shipped with the cluster resilience layer). Modelled on
// Erlang/OTP, which the roadmap notes is philosophically closest to NURL's
// fibers-as-actors.
//
// A supervisor restarts child tasks that crash (panic) or, for permanent
// children, that simply return. Each child is a `( @ v )` start closure;
// the supervisor runs it under `recover`, and on a crash restarts it per
// its RestartPolicy, with exponential backoff and a restart-intensity
// limit (give up if a child restarts more than `max_restarts` times within
// `window_ms`, so a hopeless child can't spin forever).
//
//   RPermanent — always restart (on crash AND on normal return)
//   RTransient — restart only on a crash; a clean return stops it
//   RTemporary — never restart
//
// Strategy: one-for-one (each child supervised independently). One-for-all
// / rest-for-one are a follow-up.
//
// ── Child closures are RE-INVOKED on restart ─────────────────────────
//
// Unlike std/panic.nu's `recover` (which frees the closure env after one
// call), the supervisor keeps the child's closure alive across restarts —
// so a child MAY hold captured state that persists between restarts (e.g.
// a retry counter, a connection handle). The env is released once, at
// `supervisor_free`. A child body must therefore be safe to run more than
// once.
//
// ── API ──────────────────────────────────────────────────────────────
//
//   ( supervisor_new i max_restarts i window_ms )      → Supervisor
//   ( supervisor_add Supervisor s s name RestartPolicy p ( @ v ) start ) → v
//   ( supervisor_run Supervisor s )                    → v   (spawns a fiber per child)
//   ( supervise_one  Supervisor s i idx )              → v   (run one child's loop synchronously)
//   ( child_restarts Supervisor s i idx )              → i
//   ( supervisor_free Supervisor s )                   → v

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/panic.nu`

: | RestartPolicy {
    RPermanent
    RTransient
    RTemporary
}

@ restart_policy_name RestartPolicy p → s {
    ^ ?? p {
        RPermanent → `permanent`
        RTransient → `transient`
        RTemporary → `temporary`
    }
}

: ChildImpl {
    String name
    ( @ v ) start
    RestartPolicy policy
    i restarts
}

: ChildSpec { s ctl }

: SupImpl {
    ( Vec ChildSpec ) children
    i max_restarts
    i window_ms
    i base_backoff_ms
    i max_backoff_ms
}

: Supervisor { s ctl }

@ supervisor_new i max_restarts i window_ms → Supervisor {
    : *SupImpl sup # *SupImpl ( nurl_alloc Z SupImpl )
    = . sup children ( vec_new [ChildSpec] )
    = . sup max_restarts max_restarts
    = . sup window_ms window_ms
    = . sup base_backoff_ms 0
    = . sup max_backoff_ms 1000
    ^ @ Supervisor { # s sup }
}

// Tune the per-restart backoff (default 0 = restart immediately).
@ supervisor_set_backoff Supervisor s i base_ms i max_ms → v {
    : *SupImpl sup # *SupImpl . s ctl
    = . sup base_backoff_ms base_ms
    = . sup max_backoff_ms max_ms
}

@ supervisor_add Supervisor s s name RestartPolicy policy ( @ v ) start → v {
    : *SupImpl sup # *SupImpl . s ctl
    : *ChildImpl child # *ChildImpl ( nurl_alloc Z ChildImpl )
    = . child name ( string_from name )
    = . child start start
    = . child policy policy
    = . child restarts 0
    ( vec_push [ChildSpec] . sup children @ ChildSpec { # s child } )
}

@ __child_at *SupImpl sup i idx → *ChildImpl {
    ^ ?? ( vec_get [ChildSpec] . sup children idx ) {
        T c → # *ChildImpl . c ctl
        F → # *ChildImpl 0
    }
}

// Run a child closure under panic recovery WITHOUT freeing its env — the
// supervisor re-invokes the same closure on the next restart. (std/panic.nu's
// `recover` frees the env, which would dangle on restart.)
@ __sup_recover ( @ v ) closure → !v PanicInfo {
    : *u fnp # *u closure 0
    : *u env # *u closure 1
    : i rv ( nurl_recover fnp env )
    ? == rv 0 { ^ @ !v PanicInfo { T 0 } } {}
    : String msg ( string_from ( nurl_panic_last_msg ) )
    ^ @ !v PanicInfo { F @ PanicInfo { msg } }
}

@ __sup_grow i delay i cap → i {
    : i n ? <= delay 0 1 * delay 2
    ? > n cap { ^ cap } {}
    ^ n
}

// Supervise one child: run → on stop, decide restart per policy + intensity.
// Blocks until the child is no longer restarted.
@ __supervise_loop *SupImpl sup *ChildImpl child → v {
    : ~ b done F
    : ~ i delay . sup base_backoff_ms
    : ~ i win_start ( monotonic_ns )
    : ~ i win_count 0
    ~ ! done {
        : ( @ v ) st . child start
        : !v PanicInfo r ( __sup_recover st )
        : ~ b crashed F
        ?? r {
            T _ → {}
            F pi → { = crashed T ( panic_info_free pi ) }
        }
        : b restart_on_crash ?? . child policy { RTemporary → F  _ → T }
        : b restart_on_exit  ?? . child policy { RPermanent → T  _ → F }
        : b want_restart ? crashed restart_on_crash restart_on_exit
        ? ! want_restart {
            = done T
        } {
            = . child restarts + . child restarts 1
            // Restart-intensity window: too many restarts too fast → give up.
            : i now ( monotonic_ns )
            ? > / - now win_start 1000000 . sup window_ms
            { = win_start now  = win_count 0 } {}
            = win_count + win_count 1
            ? > win_count . sup max_restarts
            { = done T }
            { ( sleep_ms delay )
                = delay ( __sup_grow delay . sup max_backoff_ms ) }
        }
    }
}

// Run one child's supervision loop synchronously (no fiber). Useful for
// tests and single-child supervisors.
@ supervise_one Supervisor s i idx → v {
    : *SupImpl sup # *SupImpl . s ctl
    : *ChildImpl child ( __child_at sup idx )
    ( __supervise_loop sup child )
}

// Spawn a supervising fiber per child. Requires runtime_init / runtime_run
// by the caller.
@ supervisor_run Supervisor s → v {
    : *SupImpl sup # *SupImpl . s ctl
    : i n ( vec_len [ChildSpec] . sup children )
    : ~ i k 0
    ~ < k n {
        : *ChildImpl child ( __child_at sup k )
        ( spawn \ → v { ( __supervise_loop sup child ) } )
        = k + k 1
    }
}

@ child_restarts Supervisor s i idx → i {
    : *SupImpl sup # *SupImpl . s ctl
    : *ChildImpl child ( __child_at sup idx )
    ^ . child restarts
}

@ supervisor_free Supervisor s → v {
    : *SupImpl sup # *SupImpl . s ctl
    : ( @ v ChildSpec ) freeing \ ChildSpec c → v {
        : *ChildImpl ci # *ChildImpl . c ctl
        ( string_free . ci name )
        : ( @ v ) st . ci start
        ( nurl_free # s # *u st 1 )
        ( nurl_free # s ci )
    }
    ( vec_free_with [ChildSpec] . sup children freeing )
    ( nurl_free # s # *u freeing 1 )
    ( nurl_free # s sup )
}
