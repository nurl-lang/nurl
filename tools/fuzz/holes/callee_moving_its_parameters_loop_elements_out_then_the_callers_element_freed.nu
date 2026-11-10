// callee_moving_its_parameters_loop_elements_out_then_the_callers_element_freed: agora #588 — `~ y t { ( wipe t ) ( string_free y ) }`: a double free
// Closed: a `~` loop's element moved out of a parameter, or of a closure's capture, is a drop of that container's elements in the function's drop summary / the closure's effects (agora #588).
// main 6bd92ff: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #588: `~ y t { ( wipe t ) ( string_free y ) }`: a double free
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ wipe ( Vec String ) t → v { ~ x t { ( string_free x ) } }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `first string long enough for a heap buffer here` ) )
    ~ y t { ( wipe t ) ( string_free y ) }
    ^ 0
}
