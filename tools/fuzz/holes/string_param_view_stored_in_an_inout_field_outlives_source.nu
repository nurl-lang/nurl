// string_param_view_stored_in_an_inout_field_outlives_source: agora #301 — an `inout` callee stores a view of a String parameter's buffer into a field of the caller's struct of views; the String ends in a block, the field is read after it.
// Closed: a callee that leaves one argument viewing another one's own storage (a String parameter's buffer, `string_data src`) leaves the caller's argument there depending on that one, as a view parameter stored whole does (g_fn_vkeeps, decided by the callee's walk where it returns; a temporary there is refused; agora #301, #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #301: an `inout` callee stores a view of a String parameter's buffer into a field of the caller's struct of views; the String ends in a block, the field is read after it
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = . w v ( string_data src ) }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( repoint w b )
    }
    ( nurl_println . w v )
    ^ 0
}
