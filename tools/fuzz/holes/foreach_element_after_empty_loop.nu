// foreach_element_after_empty_loop: agora #245 — `~ s xs { … }` over an empty Vec, then a read of `s`: the element stayed bound after its loop and was never written (foreach_element_after_empty_loop).
// Closed: as foreach_element_after_loop_cleared (agora #245).
// main: accepted; AddressSanitizer reported SEGV.
// map: §1 | A1 | rejected | - | agora #245: a foreach element read after a loop that never ran: the slot was never written
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ~ s xs { ( nurl_println_int ( string_len s ) ) }
    ( nurl_println_int ( string_len s ) )
    ^ 0
}
