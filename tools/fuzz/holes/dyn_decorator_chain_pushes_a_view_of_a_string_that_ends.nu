// dyn_decorator_chain_pushes_a_view_of_a_string_that_ends: the same with the String ending before the holder is read.
// Closed: the decorators' walks each assume the other leaves no view, and every call that relied on it is checked against the final answers once every walk has run (agora #394, formal's d_21 / d_78 on github#1532).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #394: the same with the String ending before the holder is read
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
    {
        : String s ( string_from `a heap string, long enough to be on the heap for sure` )
        ( put d hold s )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
