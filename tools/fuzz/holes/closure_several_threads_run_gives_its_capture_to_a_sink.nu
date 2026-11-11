// closure_several_threads_run_gives_its_capture_to_a_sink: agora #648 — a closure in a struct in an Arc, run by eight threads at once, hands its captured struct whole to a declared `sink` parameter: every thread ran the one env, and two of them gave the same value away.
// Closed: a capture the closure's body takes over is a change of it to the rule for a closure several threads may run at once (an `&name@line@>@0` atom, __sync_verdict): rejected where the closure is kept in the Arc.
// main's compiler: accepted; AddressSanitizer: attempting double-free (the env's taken mark is a plain i1, so two threads pass its check together).
// map: §6.5 | A3 | rejected | - | agora #648: a closure several threads run hands its whole capture to a declared `sink`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`

: App { ( Vec String ) log i n }

: Holder { ( @ i i ) f i tag }

@ eat sink ( Vec String ) w → v {
}

@ eatapp sink App x → v {
}

@ hit ( Arc Holder ) a i n → i {
    : Holder h ( arc_get [Holder] a )
    : ( @ i i ) g . h f
    ^ ( g n )
}

@ main → i {
    : Atomic gate ( atomic_new 0 )
    : ~ ( Vec String ) l ( vec_new [String] )
    ( vec_push [String] l ( string_from `one` ) )
    ( vec_push [String] l ( string_from `two` ) )
    : App a @ App { l 2 }
    : Atomic gw ( mem_dup gate )
    : ( @ i i ) work \ i k → i {
        ~ == ( atomic_load gw ) 0 {
        }
        ( eatapp a )
        ^ k
    }
    : Holder hd @ Holder { work 7 }
    : ( Arc Holder ) shared ( arc_new [Holder] hd )
    : ~ ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc Holder ) mine ( arc_clone [Holder] shared )
        ?? ( thread_spawn \ → v { ( hit mine 1 ) } ) { T th → ( vec_push [Thread] ts th ) F e → {} }
        = t + t 1
    }
    ( atomic_store gate 1 )
    : ~ i j 0
    ~ < j ( vec_len [Thread] ts ) { ( thread_join ( vec_at [Thread] ts j ) ) = j + j 1 }
    ^ 0
}
