// view_through_one_share_of_a_program_rc_handle_kept_past_a_read_through_another_runs_clean: agora #345 — the other share only read through an accessor while the view lives
// Control for agora #345.
// map: §2.10 | A2 | runs-clean | - | agora #345: the other share only read through an accessor while the view lives
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

@ x_len X x → i { : Impl q ( rc_get [Impl] . x ctl ) ^ ( vec_len [i] . q buf ) }

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
            ( nurl_println_int ( x_len a ) )
            ( nurl_println_int ( vec_at [i] . v buf 0 ) )
        }
        F _ → {}
    }
    ^ 0
}
