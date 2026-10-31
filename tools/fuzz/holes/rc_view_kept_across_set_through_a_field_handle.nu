// rc_view_kept_across_set_through_a_field_handle: a view of an Rc's value (rc_get on a binding) outlived an rc_set made through a struct field holding another handle on the same value.
// Closed: a call that may drop or replace what an `( Rc T )` holds ends the borrows of every handle of that type in the function, which may be the same value.
// main's compiler: heap-use-after-free.
// map: §6.2 | A2 | rejected | h247 | rc_get view outlives rc_set through a struct field holding an Rc clone
$ `stdlib/std/rc.nu`
$ `stdlib/core/string.nu`

: P { String name i n }
: H { ( Rc P ) a }

@ main → i {
    : ( Rc P ) r ( rc_new [P] @ P { ( string_from `a string long enough to own a heap buffer` ) 1 } )
    : H h @ H { ( rc_clone [P] r ) }
    : P x ( rc_get [P] r )
    ( rc_set [P] . h a @ P { ( string_from `b` ) 2 } )
    ( nurl_println ( string_data . x name ) )
    ^ 0
}
