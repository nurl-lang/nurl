// element_of_an_element_cleared_inline_past_a_view_of_a_string_inside: agora #349 — `( vec_clear ( vec_at ( vec_at w 0 ) 0 ) )` with a view of a String inside it kept
// Closed: an argument that is no binding is named by its source expression (`@sx`), and the walk ends the views of the storage it reaches by the final summaries (agora #349).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: an element of an element cleared inline past a view of a String inside
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec ( Vec ( Vec String ) ) ) w ( vec_new [( Vec ( Vec String ) )] )
    ( vec_push [( Vec ( Vec String ) )] w ( vec_new [( Vec String )] ) )
    ( vec_push [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) 0 ) ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) 0 ) 0 ) )
    ( vec_clear [String] ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) 0 ) )
    ( puts d )
    ^ 0
}
