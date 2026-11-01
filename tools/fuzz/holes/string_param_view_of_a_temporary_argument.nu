// string_param_view_of_a_temporary_argument: agora #301 — an `inout` callee given a temporary String it stores a view of; the temporary is released after the call, the holder read after it.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #301: an `inout` callee given a temporary String it stores a view of; the temporary is released after the call, the holder read after it
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    ( repoint w ( string_from `a temporary, freed after the call` ) )
    ( nurl_println . w v )
    ^ 0
}
