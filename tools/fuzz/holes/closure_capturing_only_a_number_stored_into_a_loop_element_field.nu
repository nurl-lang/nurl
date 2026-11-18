// closure_capturing_only_a_number_stored_into_a_loop_element_field: AGORA-851 (CodeRabbit on github#1970) — `~ c cs { = . c f \ → i { ^ + k 1 } }` with k a number: the closure's environment holds k, and the loop's copy keeps it where nothing releases it
// AGORA-851: refused - a closure that captures anything, a number too, has an environment the field would own
// map: §7.6 | A2 | rejected | - | AGORA-851: a capturing closure, a number its only capture, stored into a loop element's field leaks its environment
$ `stdlib/core/vec.nu`

: C { ( @ i ) f i n }

@ main → i {
    : ( Vec C ) cs ( vec_new [C] )
    ( vec_push [C] cs @ C { \ → i { ^ 2 } 1 } )
    : i k 41
    ~ c cs { = . c f \ → i { ^ + k 1 } }
    ( nurl_println_int ( vec_len [C] cs ) )
    ^ 0
}
