// view_of_a_loop_element_kept_past_its_container_given_a_new_value: agora #471 — `ws` given views of `~ x t`'s elements; `= t ( vec_new [String] )` after the loop; `ws` read after
// Closed: a `~` loop's element is a part of what the loop iterates (`fe_`: the container's owners, path-precise): its own storage, viewed or borrowed, is reached through an element of them (`^`), as a `( vec_at xs k )` binding's is — growth leaves the view be; its elements dropped or replaced, a new value, or its end, end it (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of a loop element kept past the container given a new value
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string dropped when t is given a new Vec` ) )
    : ~ ( Vec s ) ws ( vec_new [s] )
    ~ x t { ( vec_push [s] ws ( string_data x ) ) }
    = t ( vec_new [String] )
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
