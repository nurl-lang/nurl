// view_of_a_loop_element_over_a_box_lent_vec_kept_past_the_box: agora #471 — `~ x inner` over `: ( Vec String ) inner ( box_get [( Vec String )] bx )`; views pushed; the Box ends; `ws` read after
// Closed: what a loop over a borrow iterates is that borrow's owners (bck_borrow_owners): the element is a part of the Box's value (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of the element of a loop over a Vec lent out of a Box, kept past the Box
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string inside a boxed Vec, freed with the box` ) )
        : ( Box ( Vec String ) ) bx ( box_new [( Vec String )] t )
        : ( Vec String ) inner ( box_get [( Vec String )] bx )
        ~ x inner { ( vec_push [s] ws ( string_data x ) ) }
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
