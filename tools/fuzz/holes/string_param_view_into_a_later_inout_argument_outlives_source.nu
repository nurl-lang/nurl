// string_param_view_into_a_later_inout_argument_outlives_source: agora #301 — the same with the `inout` struct of views the callee's second parameter and the String its first.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #301: the same with the `inout` struct of views the callee's second parameter and the String its first
$ `stdlib/core/string.nu`

: W { s v }

@ repoint String src inout W w → v { = w @ W { ( string_data src ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( repoint b w )
    }
    ( nurl_println . w v )
    ^ 0
}
