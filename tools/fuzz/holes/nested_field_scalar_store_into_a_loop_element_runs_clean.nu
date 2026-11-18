// nested_field_scalar_store_into_a_loop_element_runs_clean: AGORA-851 guard — `~ p os { = . . p inner k 7 }` stores a scalar into the loop's copy: lost (warned), but nothing leaks, so it stays accepted
// map: §7.6 | A2 | runs-clean | - | AGORA-851 guard: a scalar nested store into a loop element owns nothing
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: In { String name i k }

: Out { In inner i n }

@ main → i {
    : ( Vec Out ) os ( vec_new [Out] )
    ( vec_push [Out] os @ Out { @ In { ( string_from `an original name long enough to live on the heap` ) 1 } 2 } )
    ~ p os { = . . p inner k 7 }
    ( nurl_println ( string_data . . ( vec_at [Out] os 0 ) inner name ) )
    ^ 0
}
