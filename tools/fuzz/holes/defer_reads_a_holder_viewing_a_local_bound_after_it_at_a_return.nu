// defer_reads_a_holder_viewing_a_local_bound_after_it_at_a_return: the same at an early `^` (PO b07c).
// Closed: as at the `\` exit (agora #408).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #408: the same at an early `^` (PO b07c)
$ `stdlib/core/string.nu`

: W { s v }

@ fill inout W w i k → i {
    ; { ( nurl_println . w v ) = w @ W { `literal from the defer` } }
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    ? > k 0 { ^ k } {}
    = w @ W { `literal` }
    ^ 0
}

@ main → i {
    : ~ W w @ W { `start` }
    : i _r ( fill w 1 )
    ( nurl_println . w v )
    ^ 0
}
