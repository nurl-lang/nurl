// closure_moving_its_captures_loop_elements_out_while_a_view_of_one_lives: agora #588 — a closure whose `~ x t { ( string_free x ) }` frees the elements of its capture, run with a view of t's element read after
// Closed: a `~` loop's element moved out of a parameter, or of a closure's capture, is a drop of that container's elements in the function's drop summary / the closure's effects (agora #588).
// main 6bd92ff: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #588: a closure whose `~ x t { ( string_free x ) }` frees the elements of its capture, run with a view of t's element read after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `first string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `second string long enough for a heap buffer here` ) )
    : s v ( string_data ( vec_at [String] t 1 ) )
    : ( @ v ) wipe \ → v { ~ x t { ( string_free x ) } }
    ( wipe )
    ( nurl_println v )
    ^ 0
}
