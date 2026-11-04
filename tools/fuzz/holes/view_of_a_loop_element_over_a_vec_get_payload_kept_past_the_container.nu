// view_of_a_loop_element_over_a_vec_get_payload_kept_past_the_container: agora #471 — `~ x . ( vec_get [( Vec String )] vv 0 ) 1` pushes views of `x` into `ws`; `( vec_clear [( Vec String )] vv )`, then `ws` is read
// Closed: a container path rooted at a call is a part of what the call lends: the loop element's `fe_` names the bindings the call lends (bck_sx_hroots), not an id its text read as (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of a loop element over a vec_get payload, kept past the container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ( Vec String ) r0 ( vec_new [String] )
    ( vec_push [String] r0 ( string_from `an inner string dropped by vec_clear after the loop` ) )
    ( vec_push [( Vec String )] vv r0 )
    ~ x . ( vec_get [( Vec String )] vv 0 ) 1 { ( vec_push [s] ws ( string_data x ) ) }
    ( vec_clear [( Vec String )] vv )
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
