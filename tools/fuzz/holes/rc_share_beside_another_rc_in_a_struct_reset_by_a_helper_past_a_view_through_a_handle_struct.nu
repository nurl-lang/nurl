// rc_share_beside_another_rc_in_a_struct_reset_by_a_helper_past_a_view_through_a_handle_struct: `: Y { ( Rc Meta ) m ( Rc Impl ) ctl }` built with a clone of `. a ctl`, `( y_reset y )` replacing that payload while `v` is read through `a`, a handle struct `X { ( Rc Impl ) ctl }`
// Closed: two structs of different types may hold one Rc value: the rule compares the Rc types they reach, not the structs' names (agora #712).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #712: a struct holding a share beside another Rc reset by a helper, past a view through another struct type
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: Impl { ( Vec i ) buf }
: Meta { i k }
: X { ( Rc Impl ) ctl }
: Y { ( Rc Meta ) m ( Rc Impl ) ctl }

@ X_share X x → X { ^ @ X { ( rc_clone [Impl] . x ctl ) } }

@ X_drop sink X x → v {}

@ Y_drop sink Y y → v {}

@ mk → X {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 41 )
    ^ @ X { ( rc_new [Impl] @ Impl { b } ) }
}

@ x_view X x → Impl { ^ ( rc_get [Impl] . x ctl ) }

@ y_reset Y y → v { ( rc_set [Impl] . y ctl @ Impl { ( vec_new [i] ) } ) }

@ main → i {
    : X a ( mk )
    : Y y @ Y { ( rc_new [Meta] @ Meta { 1 } ) ( rc_clone [Impl] . a ctl ) }
    : Impl v ( x_view a )
    ( y_reset y )
    ( nurl_println_int ( vec_at [i] . v buf 0 ) )
    ^ 0
}
