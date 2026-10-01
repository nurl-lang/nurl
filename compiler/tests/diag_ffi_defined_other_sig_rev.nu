// diag_ffi_defined_other_sig_rev.nu — the same conflict with the
// definition compiled first: the FFI declaration that follows it reports
// (diag_ffi_defined_other_sig.nu).

@ nurl_test_sig_fn i x i y → i { ^ + x y }

& `c` @ nurl_test_sig_fn f x → f

@ main → i {
    ( nurl_println ( nurl_str_int ( nurl_test_sig_fn 1 2 ) ) )
    ^ 0
}
