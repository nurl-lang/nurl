// struct_of_views_binding_stored_whole_into_an_inout_holder: a bound struct of views stored whole into an inout holder, read after its source ends.
// Closed: a view parameter stands for itself as a source of views in its function's walk (`pv_`, bck_sx_name): a holder given it names that parameter in the function's g_fn_vkeeps answer, and a view argument, written any way, is tied to the holder its callee's answer names (agora #380).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #380: a bound struct of views stored whole into an inout holder, read after its source ends
$ `stdlib/core/string.nu`
: W { s v }
@ put inout W w W x → v { = w x }
@ main → i {
    : ~ W w @ W { `a literal` }
    {
        : String b ( string_from `a string freed at the end of its block` )
        : W x @ W { ( string_data b ) }
        ( put w x )
    }
    ( nurl_println . w v )
    ^ 0
}
