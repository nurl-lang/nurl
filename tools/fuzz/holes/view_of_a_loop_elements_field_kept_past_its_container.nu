// view_of_a_loop_elements_field_kept_past_its_container: agora #471 — `~ x ps { ( vec_push [s] ws ( string_data . x name ) ) }` over a block-local `( Vec P )`; `ws` read after the block
// Closed: a `~` loop's element is a part of what the loop iterates (`fe_`: the container's owners, path-precise): its own storage, viewed or borrowed, is reached through an element of them (`^`), as a `( vec_at xs k )` binding's is — growth leaves the view be; its elements dropped or replaced, a new value, or its end, end it (agora #471).
// main 0c11a93: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of a loop element's String field kept past the container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( Vec P ) ps ( vec_new [P] )
        ( vec_push [P] ps @ P { ( string_from `a field string freed with its struct's Vec` ) 1 } )
        ~ x ps { ( vec_push [s] ws ( string_data . x name ) ) }
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
