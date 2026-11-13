// returned_closures_over_views_of_a_live_parameter_or_owned_strings_run_clean: a returned closure over a Vec of views of the caller's String, run while the String lives; one over a Vec of Strings it owns, run after the caller's String is freed
// Guard for agora #467's fix: the caller's binding depends on the argument only when the closure holds a view of it.
// main ff75baea: accepted, clean.
// map: §2.2 | A2 | runs-clean | - | agora #467 guard: returned closures over live views or owned values
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// The closure handed back holds views of the caller's String: used while
// it lives, it runs clean.
@ mk String s → ( @ v ) {
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h ( string_data s ) )
    ^ \ → v { ( nurl_println ( vec_at [s] h 0 ) ) }
}

// …and one over a Vec of Strings it owns: nothing of the caller's.
@ mk_own String s → ( @ v ) {
    : ~ ( Vec String ) h ( vec_new [String] )
    ( vec_push [String] h ( string_from ( string_data s ) ) )
    ^ \ → v { ( nurl_println_int ( vec_len [String] h ) ) }
}

@ main → i {
    : String s ( string_from `a heap string long enough to be on the heap for sure` )
    : ( @ v ) f ( mk s )
    ( f )
    : ~ ( @ v ) g \ → v {}
    {
        : String t ( string_from `another heap string, freed before g runs` )
        = g ( mk_own t )
    }
    ( g )
    ^ 0
}
