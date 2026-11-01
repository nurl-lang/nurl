// string_param_viewed_by_a_local_holder: agora #301 — a function hands its String parameter and its own local holder to a callee storing a view; the holder dies with the function.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #301: a function hands its String parameter and its own local holder to a callee storing a view; the holder dies with the function
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ local_only String src → v {
    : ~ W w @ W { `literal` }
    ( repoint w src )
    ( nurl_println . w v )
}

@ main → i {
    {
        : String b ( string_from `the inner string` )
        ( local_only b )
    }
    ^ 0
}
