// string_param_viewed_into_a_vec_handle_not_first: agora #337 — a callee with no `inout` parameter pushes a view of a String argument into a Vec handle that is not its first argument.
// Closed: the callee's walk answers holder/source pairs (g_fn_vkeeps `h>k`, as A2's outHolds), and the caller ties the argument at the holder's index to the one at the source's (`bK.H` rows, __vbuf_holders; agora #337).
// main: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #337: a String argument viewed into a Vec handle that is not the first argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f i k ( Vec s ) out String src → v { ( vec_push [s] out ( string_data src ) ) }

@ main → i {
    : ( Vec s ) out ( vec_new [s] )
    {
        : String s ( string_from `a string freed at the end of its block` )
        ( f 1 out s )
    }
    ( nurl_println ( vec_at [s] out 0 ) )
    ^ 0
}
