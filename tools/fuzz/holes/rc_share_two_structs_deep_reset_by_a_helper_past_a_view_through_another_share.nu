// rc_share_two_structs_deep_reset_by_a_helper_past_a_view_through_another_share: `: X { Inner in }`, `: Inner { ( Rc Impl ) ctl }`: `( x_reset a )` replaces the payload of `. . a in ctl` while `v` is read through `y`, a share of `a`
// Closed: a struct's Rcs are those of its fields at any depth, not only its direct fields (agora #712).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #712: a share two structs deep reset by a helper, past a view through another share
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: Impl { ( Vec i ) buf }
: Inner { ( Rc Impl ) ctl }
: X { Inner in }

@ X_share X x → X { ^ @ X { @ Inner { ( rc_clone [Impl] . . x in ctl ) } } }

@ X_drop sink X x → v {}

@ mk → X {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 41 )
    ^ @ X { @ Inner { ( rc_new [Impl] @ Impl { b } ) } }
}

@ x_view X x → Impl { ^ ( rc_get [Impl] . . x in ctl ) }

@ x_reset X x → v { ( rc_set [Impl] . . x in ctl @ Impl { ( vec_new [i] ) } ) }

@ main → i {
    : X a ( mk )
    : X y ( X_share a )
    : Impl v ( x_view y )
    ( x_reset a )
    ( nurl_println_int ( vec_at [i] . v buf 0 ) )
    ^ 0
}
