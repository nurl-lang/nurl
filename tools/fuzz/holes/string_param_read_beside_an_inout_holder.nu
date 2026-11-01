// string_param_read_beside_an_inout_holder: agora #301 — an `inout` callee only reads a String parameter beside the holder; the String ends in a block, the holder read after it.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #301: an `inout` callee only reads a String parameter beside the holder; the String ends in a block, the holder read after it
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ peek inout W w String src → v { ( nurl_println ( string_data src ) ) }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `the inner string, only read by the callee` )
        ( peek w b )
    }
    ( nurl_println . w v )
    ^ 0
}
