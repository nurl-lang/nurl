// callee_rc_set_of_a_view_into_one_share_read_through_another: agora #392 — `@ f i k ( Rc W ) r String s → v { ( rc_set [W] r @ W { ( string_data s ) } ) }` called on r2 = rc_clone r: the Rc's state, read through r after s ends, views s (PO s04)
// main 6e052d3a: accepted; heap-use-after-free (the store tied only the share it went through).
// map: §2.10 | A2 | rejected | - | agora #392: `@ f i k ( Rc W ) r String s → v { ( rc_set [W] r @ W { ( string_data s ) } ) }` called on r2 = rc_clone r: the Rc's state, read through r after s ends, views s (PO s04)
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: W { s v }

@ f i k ( Rc W ) r String s → v { ( rc_set [W] r @ W { ( string_data s ) } ) }

@ main → i {
    : ( Rc W ) r ( rc_new [W] @ W { `lit` } )
    : ( Rc W ) r2 ( rc_clone [W] r )
    {
        : String s ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( f 1 r2 s )
    }
    ( nurl_println . ( rc_get [W] r ) v )
    ^ 0
}
