// string_param_view_by_a_call_in_a_closure_outlives_source: agora #301 — a closure that hands one capture and a String capture to a callee storing a view of the String's buffer; the String ends in a block, the holder read after it.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #301: a closure that hands one capture and a String capture to a callee storing a view of the String's buffer; the String ends in a block, the holder read after it
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        : ( @ v ) f \ → v { ( repoint w b ) }
        ( f )
    }
    ( nurl_println . w v )
    ^ 0
}
