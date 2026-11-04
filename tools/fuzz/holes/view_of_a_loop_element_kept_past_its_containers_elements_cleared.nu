// view_of_a_loop_element_kept_past_its_containers_elements_cleared: agora #471 — `ws` given views of `~ x t`'s elements; `( vec_clear [String] t )` after the loop; `ws` read after
// Closed: a `~` loop's element is a part of what the loop iterates (`fe_`: the container's owners, path-precise): its own storage, viewed or borrowed, is reached through an element of them (`^`), as a `( vec_at xs k )` binding's is — growth leaves the view be; its elements dropped or replaced, a new value, or its end, end it (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of a loop element kept past `vec_clear` of the container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string dropped by vec_clear after the loop` ) )
    : ~ ( Vec s ) ws ( vec_new [s] )
    ~ x t { ( vec_push [s] ws ( string_data x ) ) }
    ( vec_clear [String] t )
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
