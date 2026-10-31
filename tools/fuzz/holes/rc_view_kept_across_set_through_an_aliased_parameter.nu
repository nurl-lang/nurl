// rc_view_kept_across_set_through_an_aliased_parameter: an Rc parameter and a struct parameter whose field is the same value: a view of the first's value (rc_get) outlived a helper that replaced the value through the field.
// Closed: a call that may drop or replace what an `( Rc T )` holds ends the borrows of every handle of that type in the function, which may be the same value.
// main's compiler: heap-use-after-free.
// map: §6.2 | A2 | rejected | h246 | rc_get view outlives rc_set via struct-field param aliasing same Rc
$ `stdlib/std/rc.nu`
$ `stdlib/core/string.nu`

: P { String name i n }
: H { ( Rc P ) a }

@ reset ( Rc P ) r → v { ( rc_set [P] r @ P { ( string_from `b` ) 2 } ) }

@ show ( Rc P ) a H h → v {
    : P x ( rc_get [P] a )
    ( reset . h a )
    ( nurl_println ( string_data . x name ) )
}

@ main → i {
    : ( Rc P ) r ( rc_new [P] @ P { ( string_from `a string long enough to own a heap buffer` ) 1 } )
    : H h @ H { ( rc_clone [P] r ) }
    ( show r h )
    ^ 0
}
