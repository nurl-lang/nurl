// diag_sync_closure_gives_capture_away.nu
// A closure kept in an Arc is one environment every thread holding the
// Arc may run at once. A body that hands a value it captured to a
// function that takes it over can run once: the environment marks the
// value taken with a plain flag, so two threads running the closure
// together would both pass that check and both give the one value away —
// it would be released twice (agora #648). To the rule for a closure
// several threads run, a capture given away is a capture changed.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: App { ( Vec String ) log i n }

: Holder { ( @ i i ) f i tag }

@ eat sink ( Vec String ) w → v {
}

@ fin App x → v { ( eat . x log ) }

@ main → i {
    : ~ ( Vec String ) l ( vec_new [String] )
    ( vec_push [String] l ( string_from `one` ) )
    : App a @ App { l 1 }
    : ( @ i i ) work \ i k → i {
        ( fin a )
        ^ k
    }
    : Holder hd @ Holder { work 7 }
    : ( Arc Holder ) shared ( arc_new [Holder] hd )
    ^ 0
}
