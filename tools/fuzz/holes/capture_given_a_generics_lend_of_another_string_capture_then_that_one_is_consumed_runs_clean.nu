// capture_given_a_generics_lend_of_another_string_capture_then_that_one_is_consumed_runs_clean: `= o ( gfirst [String] other loc )` in a closure
// AGORA-904 neighbour: accepted - a generic instance's lend of another capture is given its own copy, as a plain call's is
// map: §7.4 | A2 | runs-clean | - | AGORA-904: the generic shape
$ `stdlib/core/string.nu`

@ eat sink String r → v { ( nurl_println ( string_data r ) ) }

@ gfirst [T] T a T b → T { ^ a }

@ run i k → v {
    : ~ String o ( string_from `outer value long enough for the heap here` )
    : String other ( string_from `another outer value long enough for heap` )
    : ~ ( @ v ) f \ → v {
        : String loc ( string_from `closure local value long enough for heap` )
        = o ( gfirst [String] other loc )
    }
    ( f )
    ( eat other )
    ( nurl_println ( string_data o ) )
}

@ main → i {
    ( run 0 )
    ^ 0
}
