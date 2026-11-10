// callee_moving_its_parameters_loop_elements_out_inside_a_loop_over_the_argument: agora #588 — `~ y t { ( wipe t ) ( nurl_println ( string_data y ) ) }`: the element the loop is at was freed by the callee
// Closed: a `~` loop's element moved out of a parameter, or of a closure's capture, is a drop of that container's elements in the function's drop summary / the closure's effects (agora #588).
// main 6bd92ff: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #588: `~ y t { ( wipe t ) ( nurl_println ( string_data y ) ) }`: the element the loop is at was freed by the callee
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ wipe ( Vec String ) t → v { ~ x t { ( string_free x ) } }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `first string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `second string long enough for a heap buffer here` ) )
    ~ y t { ( wipe t ) ( nurl_println ( string_data y ) ) }
    ^ 0
}
