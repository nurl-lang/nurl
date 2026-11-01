// string_param_copied_into_an_inout_holder: agora #301 — an `inout` callee stores a copy of a String parameter (string_from), which owns its data; read after the String ended.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #301: an `inout` callee stores a copy of a String parameter (string_from), which owns its data; read after the String ended
$ `stdlib/core/string.nu`

: W { s v }
: O { String v }

@ keepcopy inout O w String src → v { = w @ O { ( string_from ( string_data src ) ) } }

@ main → i {
    : ~ O w @ O { ( string_from `literal` ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( keepcopy w b )
    }
    ( nurl_println ( string_data . w v ) )
    ^ 0
}
