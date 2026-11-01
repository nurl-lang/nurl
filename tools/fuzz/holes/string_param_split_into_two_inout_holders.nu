// string_param_split_into_two_inout_holders: agora #337 — a realistic split: `split head tail line` leaves both holders viewing the line; `tail` is read after it ends.
// Closed: the callee's walk answers holder/source pairs (g_fn_vkeeps `h>k`, as A2's outHolds), and the caller ties the argument at the holder's index to the one at the source's (`bK.H` rows, __vbuf_holders; agora #337).
// main: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #337: a String argument viewed into two inout holders, the second read after it ends
$ `stdlib/core/string.nu`

: Part { s text }

@ split inout Part head inout Part tail String src → v {
    = head @ Part { ( string_data src ) }
    = tail @ Part { ( string_data src ) }
}

@ main → i {
    : ~ Part head @ Part { `none` }
    : ~ Part tail @ Part { `none` }
    {
        : String line ( string_from `key=value, a line freed at the end of its block` )
        ( split head tail line )
        ( nurl_println . head text )
    }
    ( nurl_println . tail text )
    ^ 0
}
