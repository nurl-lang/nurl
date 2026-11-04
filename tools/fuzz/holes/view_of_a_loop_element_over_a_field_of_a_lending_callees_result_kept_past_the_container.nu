// view_of_a_loop_element_over_a_field_of_a_lending_callees_result_kept_past_the_container: agora #471 — `~ x . ( pick bs ) items`, `@ pick ( Vec B ) bs → B { ^ ( vec_at [B] bs 0 ) }`, pushes views of `x` into `ws`; `( vec_clear [B] bs )`, then `ws` is read
// Closed: a container path rooted at a call is a part of what the call lends: the loop element's `fe_` names the bindings the call lends (bck_sx_hroots), not an id its text read as (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of a loop element over a field of a lending callee's result, kept past the container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: B { ( Vec String ) items i n }

@ pick ( Vec B ) bs → B { ^ ( vec_at [B] bs 0 ) }

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ( Vec B ) bs ( vec_new [B] )
    ( vec_push [B] bs @ B { ( vec_new [String] ) 0 } )
    ( vec_push [String] . ( vec_at [B] bs 0 ) items ( string_from `a string in a field of a struct element, dropped by vec_clear` ) )
    ~ x . ( pick bs ) items { ( vec_push [s] ws ( string_data x ) ) }
    ( vec_clear [B] bs )
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
