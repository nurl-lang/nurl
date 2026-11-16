// map: §2.1 | A2 | rejected | - | agora #280: `= . g buf . h buf` after a sink took `. h buf`, then `. g buf` pushed to
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    : ~ Holder g @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : i n ( take . h buf )
    = . g buf . h buf
    ( vec_push [u] . g buf # u 65 )
    ^ 0
}
