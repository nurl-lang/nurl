// closure_capturing_a_view_of_a_loop_element_kept_past_the_container: agora #471 — inside `~ x t`, `= f \ → i { ^ ( strlen v ) }` with `: s v ( string_data x )`; `t` ends; `f` called after
// Closed: a `~` loop's element is a part of what the loop iterates (`fe_`: the container's owners, path-precise): its own storage, viewed or borrowed, is reached through an element of them (`^`), as a `( vec_at xs k )` binding's is — growth leaves the view be; its elements dropped or replaced, a new value, or its end, end it (agora #471).
// main 0c11a93: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a closure capturing a view of a loop element, kept past the container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string freed at the end of its block, seen by a closure` ) )
        ~ x t {
            : s v ( string_data x )
            = f \ → i { ^ ( strlen v ) }
        }
    }
    ( nurl_println_int ( f ) )
    ^ 0
}
