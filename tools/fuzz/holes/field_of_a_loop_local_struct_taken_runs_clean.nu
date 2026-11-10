// field_of_a_loop_local_struct_taken_runs_clean: a struct declared in a loop's body, its field taken by a `sink`: each round has a fresh struct, so nothing is taken twice.
// Control for agora #351.
// map: §2.1 | A2 | runs-clean | - | agora #351: a struct declared in a loop's body, its field taken by a `sink`: each round has a fresh struct, so nothing is taken twice
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : ~ i k 0
    : ~ i t 0
    ~ < k 3 {
        : Holder h @ Holder { ( vec_new [u] ) }
        ( vec_push [u] . h buf # u 66 )
        = t + t ( take . h buf )
        = k + k 1
    }
    ( nurl_println_int t )
    ^ 0
}
