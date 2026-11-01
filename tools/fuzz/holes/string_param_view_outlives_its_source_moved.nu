// string_param_view_outlives_its_source_moved: agora #301 — a holder given a view of a String's buffer by an `inout` callee, then the String moved to a sink, then the holder read.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #301: a holder given a view of a String's buffer by an `inout` callee, then the String moved to a sink, then the holder read
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ eat sink String x → v { ( nurl_println ( string_data x ) ) }

@ main → i {
    : String b ( string_from `the string, moved to a sink` )
    : ~ W w @ W { `literal` }
    ( repoint w b )
    ( eat b )
    ( nurl_println . w v )
    ^ 0
}
