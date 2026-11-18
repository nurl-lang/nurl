// closure_capturing_nothing_stored_into_a_loop_element_field_runs_clean: AGORA-851 guard — `~ c cs { = . c f \ → i { ^ 2 } }` stores a closure with no environment into the loop's copy: lost (warned), nothing leaks, so it stays accepted
// map: §7.6 | A2 | runs-clean | - | AGORA-851 guard: a closure capturing nothing owns no environment to leak
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: C { ( @ i ) f i n }

@ main → i {
    : ( Vec C ) cs ( vec_new [C] )
    ( vec_push [C] cs @ C { \ → i { ^ 2 } 1 } )
    ~ c cs { = . c f \ → i { ^ 3 } }
    ( nurl_println_int ( vec_len [C] cs ) )
    ^ 0
}
