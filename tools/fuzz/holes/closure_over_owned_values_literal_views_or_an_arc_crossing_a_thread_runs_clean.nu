// closure_over_owned_values_literal_views_or_an_arc_crossing_a_thread_runs_clean: closures crossing to threads over a Vec of Strings they own, a Vec of literal views, and an Arc share
// Guard for agora #469's fix: only a view of this side's storage stops a copy crossing; what an Arc's payload holds is the one payload every share reads.
// main ff75baea: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #469 guard: owned values, literal views, an Arc share crossing
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: Cfg { ( Vec String ) names i n }

@ main → i {
    // A Vec of Strings it owns: moved in, nothing of this side's crosses.
    : ~ ( Vec String ) own ( vec_new [String] )
    ( vec_push [String] own ( string_from `owned by the Vec` ) )
    : ( @ v ) j1 \ → v { ( nurl_println_int ( vec_len [String] own ) ) }
    // A Vec of string literals: static views.
    : ~ ( Vec s ) lits ( vec_new [s] )
    ( vec_push [s] lits `a literal` )
    : ( @ v ) j2 \ → v { ( nurl_println ( vec_at [s] lits 0 ) ) }
    // An Arc shared with the thread.
    : ( Arc Cfg ) a ( arc_new [Cfg] @ Cfg { ( vec_new [String] ) 3 } )
    : ( Arc Cfg ) a2 ( arc_clone [Cfg] a )
    : ( @ v ) j3 \ → v { ( nurl_println_int . ( arc_get [Cfg] a2 ) n ) }
    : !Thread ThreadErr t1 ( thread_spawn j1 )
    : !Thread ThreadErr t2 ( thread_spawn j2 )
    : !Thread ThreadErr t3 ( thread_spawn j3 )
    : i _1 ?? t1 { T th → ( thread_join th ) F _ → 0 }
    : i _2 ?? t2 { T th → ( thread_join th ) F _ → 0 }
    : i _3 ?? t3 { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
