// view_of_an_element_kept_across_a_loop_over_a_vec_at_calls_field_growing_it: agora #471 — a view of a String in `. ( vec_at [B] bs 0 ) items` is kept across `~ x . ( vec_at [B] bs 0 ) items`, whose body grows `x` with `string_push_str` until its buffer moves; then the view is read
// Closed: a container path rooted at a call is a part of what the call lends: the loop element's `fe_` names the bindings the call lends (bck_sx_hroots), not an id its text read as (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of an element kept across a loop over a vec_at call's field that grows the element through its loop element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: B { ( Vec String ) items i n }

@ main → i {
    : ( Vec String ) other ( vec_new [String] )
    : ( Vec B ) bs ( vec_new [B] )
    ( vec_push [B] bs @ B { ( vec_new [String] ) 0 } )
    ( vec_push [String] . ( vec_at [B] bs 0 ) items ( string_from `short` ) )
    : B b ( vec_at [B] bs 0 )
    : String e ( vec_at [String] . b items 0 )
    : s v ( string_data e )
    ~ x . ( vec_at [B] bs 0 ) items {
        : ~ i k 0
        ~ < k 64 { ( string_push_str x ` and a long tail, so the buffer moves` ) = k + k 1 }
    }
    ( nurl_println v )
    ^ 0
}
