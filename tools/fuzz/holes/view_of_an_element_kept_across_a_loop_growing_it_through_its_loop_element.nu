// view_of_an_element_kept_across_a_loop_growing_it_through_its_loop_element: agora #350 — `: s v ( string_data ( vec_at [String] t 0 ) )`, then `~ x t { ( string_push_str x … ) }`; `v` read after the loop
// Closed: a change made through a `~` loop's element is made to an element of what the loop iterates (`fe_`): its buffer moving ends the views into the container's elements, as through a `vec_at` binding (bck_borrow_sweep's `wsrc`; agora #350, #471).
// main 0c11a93: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #350: a view of an element kept across a loop that grows the element through its loop element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `short` ) )
    : s v ( string_data ( vec_at [String] t 0 ) )
    ~ x t {
        : ~ i k 0
        ~ < k 64 { ( string_push_str x ` and a long tail, so the buffer moves` ) = k + k 1 }
    }
    ( nurl_println v )
    ^ 0
}
