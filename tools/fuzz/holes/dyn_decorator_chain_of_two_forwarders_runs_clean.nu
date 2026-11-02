// dyn_decorator_chain_of_two_forwarders_runs_clean: two decorators forwarding to each other through a dyn chain, the innermost impl storing an owned copy.
// Must keep compiling and running clean: the decorators' walks each assume the other leaves no view, and every call that relied on it is checked against the final answers once every walk has run (agora #394, formal's d_21 / d_78 on github#1532).
// main's compiler: compiled, ran clean.
// map: §2.7 | A2 | runs-clean | - | agora #394: two decorators forwarding to each other through a dyn chain, the innermost impl storing an owned copy
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Add [T] { @ add T self ( Vec String ) h String s → v }

: Cp { i k }
: FwA { % Add inner }
: FwB { % Add inner }

% Add FwA { @ add FwA d ( Vec String ) h String s → v { ( add . d inner h s ) } }

% Add FwB { @ add FwB d ( Vec String ) h String s → v { ( add . d inner h s ) } }

% Add Cp { @ add Cp c ( Vec String ) h String s → v { ( vec_push [String] h ( string_from ( string_data s ) ) ) } }

@ main → i {
    : %Add d ( dyn Add @ FwA { ( dyn Add @ FwB { ( dyn Add @ Cp { 1 } ) } ) } )
    : ( Vec String ) hold ( vec_new [String] )
    : String s ( string_from `a heap string, long enough to be on the heap for sure` )
    ( add d hold s )
    ( nurl_println ( string_data ( vec_at [String] hold 0 ) ) )
    ^ 0
}
