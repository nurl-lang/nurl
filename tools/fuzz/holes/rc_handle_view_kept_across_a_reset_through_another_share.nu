// rc_handle_view_kept_across_a_reset_through_another_share: a view of the Rc state taken through one share of `X { ( Rc Impl ) ctl }` (rc_get in an accessor), the state replaced through another share (rc_set in an accessor), then the view read: freed memory.
// Closed: a program's own handle over an Rc (a struct with an `( Rc T )` field) is read as that Rc by the same-value rule (__rc_field_type in bck_note_rc_arg): a call that may drop or replace what one such handle holds ends what borrows from another of the same type (agora #345).
// main 7b7dccb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | B | rejected | - | agora #345: a view through one share of a program's Rc handle and an rc_set through another
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: Impl { ( Vec i ) buf }
: X { ( Rc Impl ) ctl }

@ X_share X x → X { ^ @ X { ( rc_clone [Impl] . x ctl ) } }

@ X_drop sink X x → v {}

@ mk → X {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 41 )
    ^ @ X { ( rc_new [Impl] @ Impl { b } ) }
}

@ x_view X x → Impl { ^ ( rc_get [Impl] . x ctl ) }

@ x_reset X x → v { ( rc_set [Impl] . x ctl @ Impl { ( vec_new [i] ) } ) }

@ step X x → !i i { ^ @ !i i { T 0 } }

@ wrap X x → !X i {
    : !i i r ( step x )
    ^ ?? r {
        T _ → @ !X i { T x }
        F e → @ !X i { F e }
    }
}

@ main → i {
    : X a ( mk )
    : !X i r ( wrap a )
    ?? r {
        T y → {
            : Impl v ( x_view y )
            ( x_reset a )
            ( nurl_println_int ( vec_at [i] . v buf 0 ) )
        }
        F _ → {}
    }
    ^ 0
}
