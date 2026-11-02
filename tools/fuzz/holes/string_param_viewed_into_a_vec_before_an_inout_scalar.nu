// string_param_viewed_into_a_vec_before_an_inout_scalar: agora #337 — a callee pushes a view of a String argument into its first argument, a Vec handle, beside an `inout` scalar; the Vec is read after the String ends.
// Closed: the callee's walk answers holder/source pairs (g_fn_vkeeps `h>k`, as A2's outHolds), and the caller ties the argument at the holder's index to the one at the source's (`bK.H` rows, __vbuf_holders; agora #337).
// main: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #337: a String argument viewed into a Vec handle before an inout scalar
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f ( Vec s ) out inout i n String src → v { ( vec_push [s] out ( string_data src ) ) = n 1 }

@ main → i {
    : ( Vec s ) out ( vec_new [s] )
    : ~ i n 0
    {
        : String s ( string_from `a string freed at the end of its block` )
        ( f out n s )
    }
    ( nurl_println ( vec_at [s] out 0 ) )
    ^ 0
}
