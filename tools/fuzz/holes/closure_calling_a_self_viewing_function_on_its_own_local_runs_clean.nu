// closure_calling_a_self_viewing_function_on_its_own_local_runs_clean: a closure gives its own local struct to h and reads the view while the field lives
// Closed: the tie comes after the call's own effects, so a callee that grows the field and then views it leaves a good view (agora #584).
// main 4e090402: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #584: a closure gives its own local struct to h and reads the view while the field lives
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ h inout P p → v { = . p w @ W { ( string_data . p s ) } }

@ main → i {
    : ( @ v ) c \ → v {
        : ~ P q @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
        ( h q )
        ( nurl_println . . q w v )
    }
    ( c )
    ^ 0
}
