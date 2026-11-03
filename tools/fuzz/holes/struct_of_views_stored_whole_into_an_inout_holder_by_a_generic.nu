// struct_of_views_stored_whole_into_an_inout_holder_by_a_generic: a generic callee stores a struct of views whole into its inout holder.
// Closed: a view parameter stands for itself as a source of views in its function's walk (`pv_`, bck_sx_name): a holder given it names that parameter in the function's g_fn_vkeeps answer, and a view argument, written any way, is tied to the holder its callee's answer names (agora #380).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #380: a generic callee stores a struct of views whole into its inout holder
$ `stdlib/core/string.nu`

: W { s v }

@ put [T] inout T w T x → v { = w x }

@ main → i {
    : ~ W w @ W { `a literal` }
    {
        : String b ( string_from `a string freed at the end of its block` )
        : W x @ W { ( string_data b ) }
        ( put [W] w x )
    }
    ( nurl_println . w v )
    ^ 0
}
