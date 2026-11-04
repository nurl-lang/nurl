// view_of_a_dyn_elements_method_result_kept_past_the_container_cleared: agora #471 — a dyn method's impl hands back a view of its loop element's own storage or of a view it holds; the caller clears its Vec of trait objects, then reads the answer
// Closed: the answer `^0 %0` ends with the container's elements dropped (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view a dyn method hands back from a loop over its container's elements, kept past the container cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Named [T] { @ nm T self → s }

: Item { String label i n }

% Named Item { @ nm Item it → s { ^ ( string_data . it label ) } }

@ first_named ( Vec % Named ) p → s {
    ~ x p { ^ ( nm x ) }
    ^ `none`
}

@ main → i {
    : ( Vec % Named ) t ( vec_new [% Named] )
    ( vec_push [% Named] t ( dyn Named @ Item { ( string_from `an item label the caller drops before reading its view` ) 1 } ) )
    : s v ( first_named t )
    ( vec_clear [% Named] t )
    ( nurl_println v )
    ^ 0
}
