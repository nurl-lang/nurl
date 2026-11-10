// rc_set_of_a_literal_into_one_share_read_through_another_runs_clean: agora #392 — rc_set of a literal-only W through one share, read through another
// Control for agora #392.
// map: §2.10 | A2 | runs-clean | - | agora #392: rc_set of a literal-only W through one share, read through another
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: W { s v }

@ main → i {
    : ( Rc W ) r ( rc_new [W] @ W { `lit` } )
    : ( Rc W ) r2 ( rc_clone [W] r )
    ( rc_set [W] r2 @ W { `another literal` } )
    ( nurl_println . ( rc_get [W] r ) v )
    ^ 0
}
