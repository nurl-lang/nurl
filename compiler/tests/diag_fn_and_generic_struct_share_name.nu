// diag_fn_and_generic_struct_share_name.nu — agora #728: a function beside
// a generic struct of its name. `( Pt 4 )` was taken for the instance
// `Pt__4` ("expected a type, found '4'", or invalid IR reaching clang).

: Pt [A] { A x A y }

@ main → i {
    ( nurl_println_int ( Pt 4 ) )
    ^ 0
}

@ Pt i x → i { ^ * x 3 }
