// diag_closure_join_lends.nu — a closure hands its result to its caller
// as the caller's own, and cannot answer per call which paths lent: a `?`
// whose value cannot be copied (a `% Drop` value) and that hands back the
// closure's capture on one path is refused (agora #186). The capture is
// the closure's for its next call; the caller would release it.

$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → D { ^ @ D { ( string_from `hello world, long enough for a heap buffer` ) } }

@ main → i {
    : D cap ( mk )
    : ( @ D b ) f \ b c → D { ^ ? c cap ( mk ) }
    : D a ( f F )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
