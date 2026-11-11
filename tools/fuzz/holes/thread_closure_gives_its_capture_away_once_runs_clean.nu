// thread_closure_gives_its_capture_away_once_runs_clean: control for agora #648 — a `thread_spawn` body that hands its captured struct to a taker (declared `sink`, and one inferred): the closure runs once, on one thread, so its env's taken mark is read by that thread alone. Stays accepted, and releases the value once.
// map: §6.5 | A3 | runs-clean | - | agora #648 control: a thread's own closure gives its capture away once, on the one thread that runs it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: App { ( Vec String ) log i n }

@ eat sink ( Vec String ) w → v {
}

@ fin App x → v { ( eat . x log ) }

@ eatapp sink App x → v {
}

@ mk i n → App {
    : ~ ( Vec String ) l ( vec_new [String] )
    ( vec_push [String] l ( string_from `one` ) )
    ( vec_push [String] l ( string_from `two` ) )
    ^ @ App { l n }
}

@ main → i {
    : App a ( mk 1 )
    : App b ( mk 2 )
    : ~ ( Vec Thread ) ts ( vec_new [Thread] )
    ?? ( thread_spawn \ → v { ( fin a ) } ) { T th → ( vec_push [Thread] ts th ) F e → {} }
    ?? ( thread_spawn \ → v { ( eatapp b ) } ) { T th → ( vec_push [Thread] ts th ) F e → {} }
    : ~ i j 0
    ~ < j ( vec_len [Thread] ts ) { ( thread_join ( vec_at [Thread] ts j ) ) = j + j 1 }
    ( puts `done` )
    ^ 0
}
