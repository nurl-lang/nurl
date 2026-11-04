// view_of_a_loop_element_kept_past_a_break_out_of_its_loop: agora #471 — `~ x t { ( vec_push [s] ws ( string_data x ) ) break }` over a block-local Vec; `ws` read after the block
// Closed: a `~` loop's element is a part of what the loop iterates (`fe_`: the container's owners, path-precise): its own storage, viewed or borrowed, is reached through an element of them (`^`), as a `( vec_at xs k )` binding's is — growth leaves the view be; its elements dropped or replaced, a new value, or its end, end it (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of a loop element pushed before a `break`, kept past the container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string freed at the end of its block, first` ) )
        ( vec_push [String] t ( string_from `a string freed at the end of its block, second` ) )
        ~ x t {
            ( vec_push [s] ws ( string_data x ) )
            break
        }
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
