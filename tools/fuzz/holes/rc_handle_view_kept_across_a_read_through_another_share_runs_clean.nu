// rc_handle_view_kept_across_a_read_through_another_share_runs_clean: the control: a call through the other share that only reads leaves the view alone.
// Closed: a program's own handle over an Rc (a struct with an `( Rc T )` field) is read as that Rc by the same-value rule (__rc_field_type in bck_note_rc_arg): a call that may drop or replace what one such handle holds ends what borrows from another of the same type (agora #345).
// main 7b7dccb5: runs clean.
// map: §2.10 | B | runs-clean | - | agora #345: a view through one share of a program's Rc handle and an rc_set through another
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

@ x_len X x → i { ^ ( vec_len [i] . ( rc_get [Impl] . x ctl ) buf ) }

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
    : X y ( X_share a )
    : Impl v ( x_view y )
    : i ln ( x_len a )
    ( nurl_println_int ( vec_at [i] . v buf 0 ) )
    ^ 0
}
