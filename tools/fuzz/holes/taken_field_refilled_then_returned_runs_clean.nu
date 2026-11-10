// taken_field_refilled_then_returned_runs_clean: `^ . h buf` after the taken field was given a new value: the caller gets a whole Vec.
// Control for agora #351.
// map: §2.1 | A2 | runs-clean | - | agora #351: `^ . h buf` after the taken field was given a new value: the caller gets a whole Vec
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ f → ( Vec u ) {
    : Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : i n ( take . h buf )
    = . h buf ( vec_new [u] )
    ^ . h buf
}

@ main → i {
    : ( Vec u ) v ( f )
    ( vec_push [u] v # u 65 )
    ( nurl_println_int ( vec_len [u] v ) )
    ^ 0
}
