// dyn_decorator_chain_pushing_a_view_of_a_live_string_runs_clean: two forwarding decorators, the innermost impl pushing a view of a String that outlives the holder.
// Must keep compiling and running clean: the decorators' walks each assume the other leaves no view, and every call that relied on it is checked against the final answers once every walk has run (agora #394, formal's d_21 / d_78 on github#1532).
// main's compiler: compiled, ran clean.
// map: §2.7 | A2 | runs-clean | - | agora #394: two forwarding decorators, the innermost impl pushing a view of a String that outlives the holder
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Put [T] { @ put T self ( Vec s ) h String s → v }

: Lens { i k }
: FwA { % Put inner }
: FwB { % Put inner }

% Put FwA { @ put FwA d ( Vec s ) h String s → v { ( put . d inner h s ) } }

% Put FwB { @ put FwB d ( Vec s ) h String s → v { ( put . d inner h s ) } }

% Put Lens { @ put Lens c ( Vec s ) h String s → v { ( vec_push [s] h ( string_data s ) ) } }

@ main → i {
    : %Put d ( dyn Put @ FwA { ( dyn Put @ FwB { ( dyn Put @ Lens { 1 } ) } ) } )
    : ( Vec s ) hold ( vec_new [s] )
    : String s ( string_from `a heap string, long enough to be on the heap for sure` )
    ( put d hold s )
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
