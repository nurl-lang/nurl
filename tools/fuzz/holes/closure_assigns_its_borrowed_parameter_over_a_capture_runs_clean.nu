// closure_assigns_its_borrowed_parameter_over_a_capture_runs_clean: a closure assigns its borrowed String parameter over a by-pointer capture; run by a callee with a local of its own, the capture borrows a released value.
// Closed: the closure's parameter is lent for the call only, and what the body stores of it is copied - assigned whole over a capture too, which then owns the copy (agora #864).
// main's compiler: accepted; ASan reported heap-use-after-free reading the capture after the call.
// map: §2.11 | A2 | runs-clean | - | agora #864: a closure assigns its borrowed String parameter over a by-pointer capture; run by a callee with a local of its own, the capture borrows a released value; the capture now owns a copy
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ once ( @ v String ) f → v {
    : String tmp ( string_from `a string long enough to live on the heap, for sure` )
    ( f tmp )
}

@ borrowed → i {
    : ~ String best ( string_from `first` )
    ( once \ String r → v { = best r } )
    ^ ( string_len best )
}

@ main → i {
    ( nurl_print_int ( borrowed ) ) ( nurl_print `\n` )
    ^ 0
}
