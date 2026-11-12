// diag_fn_and_struct_share_name.nu — agora #728: a function and a type
// share one namespace. `( Pt 4 )` read as the struct, and the error blamed
// the argument ("argument 1 to 'nurl_println_int' has type 'Pt'"). Refused
// at the later declaration, naming the earlier one.

@ Pt i x → i { ^ * x 3 }

: Pt { i x i y }

@ main → i {
    ( nurl_println_int ( Pt 4 ) )
    ^ 0
}
