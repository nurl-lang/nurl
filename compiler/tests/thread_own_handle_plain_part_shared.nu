// thread_own_handle_plain_part_shared.nu — a handle of the program's own
// whose shared state is behind an Arc, with a plain Vec beside it, is
// shared with a thread like any handle made of Sync parts (docs/MEMORY.md
// §6.5): `Reg_share` gives each share a Vec of its own, so the spawner
// keeps using its `r` after a thread's closure captured a share of it.
//
// The other half of the rule is diag_sync_closure_own_handle_plain_vec.nu:
// ONE such handle, captured by a closure several threads run, is one Vec
// they would all grow — sharing a handle and changing through one are two
// questions (agora #639).
//
// Spawns a real pthread, so it carries the same declaration as
// thread_basic / arc_threads.
// requires: live

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/core/vec.nu`

: Reg { ( Arc Atomic ) hits ( Vec i ) mine }

@ Reg_share Reg x → Reg { ^ @ Reg { ( arc_clone [Atomic] . x hits ) ( vec_new [i] ) } }

@ Reg_drop sink Reg x → v {}

@ mkreg → Reg { ^ @ Reg { ( arc_new [Atomic] ( atomic_new 0 ) ) ( vec_new [i] ) } }

@ reg_hit Reg r i n → v {
    : ~ i k 0
    ~ < k n {
        : i before ( atomic_add ( arc_get [Atomic] . r hits ) 1 )
        = k + k 1
    }
}

@ main → i {
    : Reg r ( mkreg )
    : !Thread ThreadErr t ( thread_spawn \ → v { ( reg_hit r 500 ) } )
    ( reg_hit r 500 )
    ?? t {
        T th → { ( thread_join th ) }
        F _ → {}
    }
    ( nurl_println ( nurl_str_int ( atomic_load ( arc_get [Atomic] . r hits ) ) ) )
    ( nurl_println ( nurl_str_int ( vec_len [i] . r mine ) ) )
    ^ 0
}
