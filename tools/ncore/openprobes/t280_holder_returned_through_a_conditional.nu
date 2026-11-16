// map: §2.1 | A2 | rejected | - | agora #280: `^ ? c h h2` after a sink took `. h buf`
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ f b c → Holder {
    : Holder h @ Holder { ( vec_new [u] ) }
    : Holder h2 @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : i n ( take . h buf )
    ^ ? c h h2
}

@ main → i {
    : Holder g ( f T )
    ( vec_push [u] . g buf # u 65 )
    ^ 0
}
