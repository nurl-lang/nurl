// string_param_viewed_into_a_vec_beside_an_inout_holder_struct_read: agora #337 — as string_param_viewed_into_a_vec_beside_an_inout_holder, but only the `inout` struct, which the callee does not touch, is read after the String ends (the shape the fix must accept).
// Closed: the callee's walk answers holder/source pairs (g_fn_vkeeps `h>k`, as A2's outHolds), and the caller ties the argument at the holder's index to the one at the source's (`bK.H` rows, __vbuf_holders; agora #337).
// main: refused (the String was tied to the inout struct).
// map: §2.10 | A2 | runs-clean | - | agora #337: the inout holder the callee does not touch, read after the String ends
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ f inout W w ( Vec s ) out String src → v { ( vec_push [s] out ( string_data src ) ) }

@ main → i {
    : ~ W w @ W { `literal` }
    : ( Vec s ) out ( vec_new [s] )
    {
        : String s ( string_from `a string freed at the end of its block` )
        ( f w out s )
        ( nurl_println ( vec_at [s] out 0 ) )
    }
    ( nurl_println . w v )
    ^ 0
}
