// borrow_foreach_var_outer_still_moved.nu — a loop's element binding
// shadows an outer binding of the same name only inside the loop.
//
// `h` is moved into `eat`; `~ h ts` binds each element as `h` for the
// body (foreach_var_shadows_moved.nu). After the loop `h` is the outer
// binding again — still moved, so reading it is a use after move.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String h ( string_from `abc` )
    : i a ( eat h )
    : ( Vec String ) ts ( vec_new [String] )
    ( vec_push [String] ts ( string_from `de` ) )
    : ~ i n 0
    ~ h ts { = n + n ( string_len h ) }
    ^ + + a n ( string_len h )
}
