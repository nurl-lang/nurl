// bare_view_of_a_loop_element_over_a_field_of_a_second_params_vec_at_handed_back: agora #471 — `@ first i k ( Vec B ) bs → s` hands back `( string_data x )` from `~ x . ( vec_at [B] bs k ) items`; the caller clears `bs`, then reads the view
// Closed: a container path rooted at a call is a part of what the call lends: the loop element's `fe_` names the bindings the call lends (bck_sx_hroots), not an id its text read as (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a loop element over a field of a second parameter's vec_at, handed back past the container cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: B { ( Vec String ) items i n }

@ first i k ( Vec B ) bs → s {
    ~ x . ( vec_at [B] bs k ) items { ^ ( string_data x ) }
    ^ `none`
}

@ main → i {
    : ( Vec B ) bs ( vec_new [B] )
    ( vec_push [B] bs @ B { ( vec_new [String] ) 0 } )
    ( vec_push [String] . ( vec_at [B] bs 0 ) items ( string_from `a string the caller clears before reading its view` ) )
    : s v ( first 0 bs )
    ( vec_clear [B] bs )
    ( nurl_println v )
    ^ 0
}
