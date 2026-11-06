// loop_element_kept_by_a_callee_both_copied_and_emptied: agora #484 — a `~` loop's element handed to a callee that keeps it (`~ x t { ( vec_push [String] keep x ) }`, a `( Vec ( Vec i ) )`'s element, a user function that pushes its parameter, a slice literal's element): the callee was handed a copy of the borrowed element AND the element's slot was emptied, so the element itself left the container and nothing released it.
// Closed: the slot is emptied only where the callee consumes the element and is not handed a copy (the store flag and the element's lend, as a field read's slot already was, h299); kept by copy, the element stays its container's.
// main (before this PR): LeakSanitizer, every element of every shape.
// map: §7.6 | A2 | runs-clean | - | agora #484: a loop element kept by a callee was copied and its slot emptied as well; the element leaked (leak)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ keepit inout ( Vec String ) k String s → v { ( vec_push [String] k s ) }

@ main → i {
    : ~ ( Vec String ) keep ( vec_new [String] )
    : ( Vec ( Vec i ) ) keepv ( vec_new [( Vec i )] )
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string moved out of its Vec into keep` ) )
        ( vec_push [String] t ( string_from `a string handed to a function that keeps it` ) )
        ~ x t { ( vec_push [String] keep x ) }
        ~ x t { ( keepit keep x ) }
        : ( Vec ( Vec i ) ) tv ( vec_new [( Vec i )] )
        : ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a 7 )
        ( vec_push [( Vec i )] tv a )
        ~ x tv { ( vec_push [( Vec i )] keepv x ) }
        : [String sl [String | ( string_from `a slice literal's element kept by vec_push` )]
        ~ x sl { ( vec_push [String] keep x ) }
    }
    ~ x keep { ( nurl_println ( string_data x ) ) }
    ( nurl_println ( nurl_str_int ( vec_len [i] ( vec_at [( Vec i )] keepv 0 ) ) ) )
    ^ 0
}
