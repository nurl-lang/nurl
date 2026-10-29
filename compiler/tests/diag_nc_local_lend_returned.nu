// diag_nc_local_lend_returned.nu — a value that cannot be copied (a `%
// Drop` value), handed back from a call that lends it out of a local, has
// no copy to stand in for the lend: the local is dropped on the way out
// and the caller would hold freed memory (agora #187). Judged at module
// end, when the callee's summary is final.

$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: W { D d }

@ getd W w → D { ^ . w d }

@ mk → D { ^ @ D { ( string_from `hello world, long enough for a heap buffer` ) } }

@ pick → D {
    : W w @ W { ( mk ) }
    ^ ( getd w )
}

@ main → i {
    : D a ( pick )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
