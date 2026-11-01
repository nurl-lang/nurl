// string_param_viewed_into_a_second_inout_holder: agora #337 — a callee leaves its SECOND `inout` holder viewing a String argument's buffer; the caller's second argument is read after the String ends.
// Closed: the callee's walk answers holder/source pairs (g_fn_vkeeps `h>k`, as A2's outHolds), and the caller ties the argument at the holder's index to the one at the source's (`bK.H` rows, __vbuf_holders; agora #337).
// main: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #337: a String argument viewed into the callee's second inout holder
$ `stdlib/core/string.nu`

: W { s v }

@ second inout W first inout W other String src → v {
    = other @ W { ( string_data src ) }
}

@ main → i {
    : ~ W a @ W { `a literal` }
    : ~ W b @ W { `b literal` }
    {
        : String s ( string_from `a string freed at the end of its block` )
        ( second a b s )
    }
    ( nurl_println . b v )
    ^ 0
}
