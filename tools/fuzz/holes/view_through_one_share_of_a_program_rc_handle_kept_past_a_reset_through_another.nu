// view_through_one_share_of_a_program_rc_handle_kept_past_a_reset_through_another: agora #345 — a program's own handle over an Rc (`X { ( Rc Impl ) ctl }`, shared by rc_clone): a view of the state taken through one share (an accessor's rc_get) is read after rc_set through another share (claude-formal s5)
// main a403b200: accepted; heap-use-after-free (the same-Rc rule fired only for bindings of an `( Rc T )` type).
// map: §2.10 | A2 | rejected | - | agora #345: a program's own handle over an Rc (`X { ( Rc Impl ) ctl }`, shared by rc_clone): a view of the state taken through one share (an accessor's rc_get) is read after rc_set through another share (claude-formal s5)
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
