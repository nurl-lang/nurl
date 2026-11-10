// rc_set_of_a_view_into_one_share_read_through_another: agora #392 — the direct twin: rc_set through r2 in main, read through r
// main 6e052d3a: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #392: the direct twin: rc_set through r2 in main, read through r
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: W { s v }

@ main → i {
    : ( Rc W ) r ( rc_new [W] @ W { `lit` } )
    : ( Rc W ) r2 ( rc_clone [W] r )
    {
        : String s ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( rc_set [W] r2 @ W { ( string_data s ) } )
    }
    ( nurl_println . ( rc_get [W] r ) v )
    ^ 0
}
