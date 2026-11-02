// inout_holder_given_a_callee_local_view_by_a_defer: agora #336 — a defer stores a view of the callee's local into the inout holder, and the function returns by `^`.
// Closed: the caller's storage is asked what it views in the state after the defers ran, at every `^` and at the body's end (agora #336).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #336: a defer gives an inout holder a callee local's view, then `^`
$ `stdlib/core/string.nu`

: W { s v }

@ fill inout W w → i {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    ; { = w @ W { ( string_data b ) } }
    ^ 0
}

@ main → i {
    : ~ W w @ W { `literal` }
    : i _r ( fill w )
    ( nurl_println . w v )
    ^ 0
}
