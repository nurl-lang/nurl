// view_of_a_field_containers_loop_element_kept_past_the_field_replaced: agora #471 — `~ x . r xs { ( vec_push [s] ws ( string_data x ) ) }`, then `= . r xs ( vec_new [String] )`; `ws` read after
// Closed: a `~` loop's element is a part of what the loop iterates (`fe_`: the container's owners, path-precise): its own storage, viewed or borrowed, is reached through an element of them (`^`), as a `( vec_at xs k )` binding's is — growth leaves the view be; its elements dropped or replaced, a new value, or its end, end it (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of the element of a loop over a field, kept past the field given a new value
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { ( Vec String ) xs String name }

@ main → i {
    : ( Vec s ) ws ( vec_new [s] )
    : ~ R r @ R { ( vec_new [String] ) ( string_from `the name` ) }
    ( vec_push [String] . r xs ( string_from `a string long enough for a heap buffer here` ) )
    ~ x . r xs { ( vec_push [s] ws ( string_data x ) ) }
    = . r xs ( vec_new [String] )
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
