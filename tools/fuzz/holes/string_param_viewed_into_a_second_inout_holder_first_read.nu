// string_param_viewed_into_a_second_inout_holder_first_read: agora #337 — as string_param_viewed_into_a_second_inout_holder, but only the FIRST holder, which keeps its literal, is read after the String ends (the shape the fix must accept).
// Closed: the callee's walk answers holder/source pairs (g_fn_vkeeps `h>k`, as A2's outHolds), and the caller ties the argument at the holder's index to the one at the source's (`bK.H` rows, __vbuf_holders; agora #337).
// main: refused (the String was tied to the first holder).
// map: §2.10 | A2 | runs-clean | - | agora #337: the holder the callee does not touch, read after the String ends
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
        ( nurl_println . b v )
    }
    ( nurl_println . a v )
    ^ 0
}
