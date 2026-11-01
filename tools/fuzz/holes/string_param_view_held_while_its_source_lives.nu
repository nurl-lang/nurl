// string_param_view_held_while_its_source_lives: agora #301 — an `inout` callee gives a holder a view of an older String's buffer; read while the String lives (the shape the fix must keep).
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #301: an `inout` callee gives a holder a view of an older String's buffer; read while the String lives (the shape the fix must keep)
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : String b ( string_from `the outer string, which outlives the holder` )
    : ~ W w @ W { `literal` }
    ( repoint w b )
    ( nurl_println . w v )
    ^ 0
}
