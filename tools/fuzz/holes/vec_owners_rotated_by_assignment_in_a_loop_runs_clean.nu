// vec_owners_rotated_by_assignment_in_a_loop_runs_clean: three Vec owners rotated by assignment in a loop (`= t a  = a b  = b t`), `a` and `b` read after it.
// Closed (agora #634): as for a String — in the second round `= t a` dropped the Vec `b` held since the round before (heap-use-after-free in `vec_len`). The assignment out of an owner is a move in the generated code now.
// map: §2.2 | A2 | runs-clean | - | agora #634: three Vec owners rotated by assignment in a loop
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) a ( vec_new [i] )
    : ~ ( Vec i ) b ( vec_new [i] )
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] a 1 )
    ( vec_push [i] b 2 )
    ( vec_push [i] b 3 )
    ( vec_push [i] t 4 )
    : ~ i k 0
    ~ < k 3 {
        = t a
        = a b
        = b t
        = k + k 1
    }
    ( nurl_println_int ( vec_len [i] a ) )
    ( nurl_println_int ( vec_len [i] b ) )
    ^ 0
}
