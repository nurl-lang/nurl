// string_param_viewed_into_a_vec_beside_an_inout_holder: agora #337 — a callee pushes a view of a String argument into a Vec-of-views handle beside an `inout` struct; the Vec is read after the String ends.
// Closed: the callee's walk answers holder/source pairs (g_fn_vkeeps `h>k`, as A2's outHolds), and the caller ties the argument at the holder's index to the one at the source's (`bK.H` rows, __vbuf_holders; agora #337).
// main: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #337: a String argument viewed into a Vec handle beside an inout holder
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
    }
    ( nurl_println ( vec_at [s] out 0 ) )
    ^ 0
}
