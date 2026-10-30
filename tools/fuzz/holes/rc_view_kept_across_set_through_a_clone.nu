// rc_view_kept_across_set_through_a_clone: a view of an Rc's value (rc_get) outlived an rc_set made through another handle on the same value (rc_clone): the old value was dropped under the view.
// Closed: a call that may drop or replace what an `( Rc T )` holds ends the borrows of every handle of that type in the function, which may be the same value.
// main's compiler: heap-use-after-free.
// map: §6.2 | A2 | rejected | h245 | rc_get view outlives rc_set through a cloned Rc handle
$ `stdlib/std/rc.nu`
$ `stdlib/core/string.nu`

: P { String name i n }

@ main → i {
    : ( Rc P ) r ( rc_new [P] @ P { ( string_from `a string long enough to own a heap buffer` ) 1 } )
    : ( Rc P ) r2 ( rc_clone [P] r )
    : P x ( rc_get [P] r )
    ( rc_set [P] r2 @ P { ( string_from `b` ) 2 } )
    ( nurl_println ( string_data . x name ) )
    ^ 0
}
