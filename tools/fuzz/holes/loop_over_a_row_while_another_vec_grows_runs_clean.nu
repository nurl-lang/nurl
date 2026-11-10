// loop_over_a_row_while_another_vec_grows_runs_clean: agora #493 — nested loops over rows and a row while an unrelated Vec grows in the body
// Control for agora #493: only a path that goes on to the loop's next element after the storage moved is refused.
// map: §2.5 | A2 | runs-clean | - | agora #493: nested loops over rows and a row while an unrelated Vec grows in the body
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    : ( Vec i ) r ( vec_new [i] )
    ( vec_push [i] r 1 )
    ( vec_push [( Vec i )] rows r )
    : ( Vec i ) other ( vec_new [i] )
    : ~ i sum 0
    ~ row rows {
        ~ x row {
            = sum + sum x
            : ~ i n 0
            ~ < n 100 { ( vec_push [i] other n ) = n + n 1 }
        }
    }
    ~ x other { = sum + sum x }
    ( vec_push [i] other 7 )
    ( nurl_println ( nurl_str_int sum ) )
    ^ 0
}
