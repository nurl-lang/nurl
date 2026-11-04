// view_of_a_loop_element_over_a_nested_field_of_a_vec_at_call_kept_past_vec_clear: agora #471 — `~ x . . ( vec_at [Out] os 0 ) inner items` pushes views of `x` into `ws`; `( vec_clear [Out] os )`, then `ws` is read
// Closed: a container path rooted at a call is a part of what the call lends: the loop element's `fe_` names the bindings the call lends (bck_sx_hroots), not an id its text read as (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of a loop element over a nested field of a vec_at call, kept past the container cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: In { ( Vec String ) items i n }
: Out { In inner i m }

@ main → i {
    : ( Vec String ) other ( vec_new [String] )
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string in a nested field of a struct element, dropped by vec_clear` ) )
    : ( Vec Out ) os ( vec_new [Out] )
    ( vec_push [Out] os @ Out { @ In { t 1 } 2 } )
    ~ x . . ( vec_at [Out] os 0 ) inner items { ( vec_push [s] ws ( string_data x ) ) }
    ( vec_clear [Out] os )
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
