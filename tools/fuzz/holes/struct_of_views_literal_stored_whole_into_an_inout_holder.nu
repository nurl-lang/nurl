// struct_of_views_literal_stored_whole_into_an_inout_holder: a struct-of-views literal argument stored whole into an inout holder, read after its source ends.
// Closed: a view parameter stands for itself as a source of views in its function's walk (`pv_`, bck_sx_name): a holder given it names that parameter in the function's g_fn_vkeeps answer, and a view argument, written any way, is tied to the holder its callee's answer names (agora #380).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #380: a struct-of-views literal argument stored whole into an inout holder, read after its source ends
$ `stdlib/core/string.nu`

: W { s v }

@ put inout W w W x → v { = w x }

@ main → i {
    : ~ W w @ W { `a literal` }
    {
        : String b ( string_from `a string freed at the end of its block` )
        ( put w @ W { ( string_data b ) } )
    }
    ( nurl_println . w v )
    ^ 0
}
