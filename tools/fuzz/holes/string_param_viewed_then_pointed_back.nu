// string_param_viewed_then_pointed_back: agora #301 — an `inout` callee points the holder at a String parameter's buffer and back at a literal before it returns.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #301: an `inout` callee points the holder at a String parameter's buffer and back at a literal before it returns
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ reset inout W w String src → v {
    = w @ W { ( string_data src ) }
    ( nurl_println . w v )
    = w @ W { `a literal again` }
}

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `the inner string, viewed only during the call` )
        ( reset w b )
    }
    ( nurl_println . w v )
    ^ 0
}
