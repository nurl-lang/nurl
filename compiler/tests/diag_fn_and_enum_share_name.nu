// diag_fn_and_enum_share_name.nu — agora #728: an enum and a function of
// one name, the function first.

@ Shade i x → i { ^ x }

: | Shade { Light Dark }

@ main → i { ^ ( Shade 0 ) }
