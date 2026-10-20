// foreach_var_shadows_moved.nu — a `~ x xs` loop's element binding is a
// binding of its own, whatever an earlier binding of that name went
// through.
//
// `h` is first a String handed to a `sink` (moved), and in the second
// function a `??` arm's payload moved out through the match's result;
// then `~ h ts` names each element `h`. The borrow checker used to read
// the element as the moved binding ("use of moved value 'h'"). An outer
// binding still in scope keeps its own state after the loop
// (borrow_foreach_var_outer_still_moved.nu).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Res { ( Vec i ) items }

@ eat sink String x → i { ^ ( string_len x ) }

@ mk → !Res i { ^ @ !Res i { T @ Res { ( vec_new [i] ) } } }

@ after_a_sink → i {
    : String h ( string_from `abc` )
    : i a ( eat h )
    : ( Vec String ) ts ( vec_new [String] )
    ( vec_push [String] ts ( string_from `de` ) )
    ( vec_push [String] ts ( string_from `fgh` ) )
    : ~ i n 0
    ~ h ts { = n + n ( string_len h ) }
    ^ + a n
}

@ after_an_arm → i {
    : Res r ?? ( mk ) { T h → h F _ → { ^ -1 } }
    : ( Vec String ) ts ( vec_new [String] )
    ( vec_push [String] ts ( string_from `ijkl` ) )
    : ~ i n 0
    ~ h ts { = n + n ( eat ( string_clone h ) ) }
    ^ + n ( vec_len [i] . r items )
}

@ main → i {
    ( nurl_println ( nurl_str_cat `after a sink: ` ( nurl_str_int ( after_a_sink ) ) ) )
    ( nurl_println ( nurl_str_cat `after an arm: ` ( nurl_str_int ( after_an_arm ) ) ) )
    ^ 0
}
