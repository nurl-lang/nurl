// string_param_view_outlives_its_source_reallocated: agora #301 — a holder given a view of a String's buffer by an `inout` callee, then the String grown so its buffer moves, then the holder read.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #301: a holder given a view of a String's buffer by an `inout` callee, then the String grown so its buffer moves, then the holder read
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : String b ( string_from `the string, reallocated by the push` )
    : ~ W w @ W { `literal` }
    ( repoint w b )
    ( string_push_str b `and a long tail that makes the buffer move to a new place in memory for sure` )
    ( nurl_println . w v )
    ^ 0
}
