// capture_given_a_calls_lend_of_another_string_capture_then_that_one_is_consumed_runs_clean: `= o ( gfirst other loc )` in a closure, String
// AGORA-904: accepted - `o` is given its own copy of the String `gfirst` lends it, so the caller may consume `other` and still read `o` (main 05206020: accepted with `o` a lend of `other`, heap-use-after-free)
// map: §7.4 | A2 | runs-clean | - | AGORA-904: a copyable value is copied in
$ `stdlib/core/string.nu`

@ eat sink String r → v { ( nurl_println ( string_data r ) ) }

@ gfirst String a String b → String { ^ a }

@ run i k → v {
    : ~ String o ( string_from `outer value long enough for the heap here` )
    : String other ( string_from `another outer value long enough for heap` )
    : ~ ( @ v ) f \ → v {
        : String loc ( string_from `closure local value long enough for heap` )
        = o ( gfirst other loc )
    }
    ( f )
    ( eat other )
    ( nurl_println ( string_data o ) )
}

@ main → i {
    ( run 0 )
    ^ 0
}
