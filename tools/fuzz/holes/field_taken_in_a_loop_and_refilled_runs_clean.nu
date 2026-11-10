// field_taken_in_a_loop_and_refilled_runs_clean: a Vec field taken by a `sink` and given a new value in the same round of a loop: every round takes a whole Vec.
// Control for agora #351.
// map: §2.1 | A2 | runs-clean | - | agora #351: a Vec field taken by a `sink` and given a new value in the same round of a loop: every round takes a whole Vec
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    : ~ i k 0
    : ~ i t 0
    ~ < k 3 {
        ( vec_push [u] . h buf # u 66 )
        = t + t ( take . h buf )
        = . h buf ( vec_new [u] )
        = k + k 1
    }
    ( nurl_println_int t )
    ^ 0
}
