// diag_nested_field_store_param.nu — a nested field store through a
// by-value parameter is rejected, exactly as the single-hop store is.
//
// Parameters are immutable bindings that arrive by value, so writing one
// mutates a copy the caller never sees. The single-hop path has always
// rejected `= . m field value` on a parameter; the nested path has to reject
// `= . . m field sub value` for the same reason, and point at the same two
// cures — take the argument `inout`, or copy it into a mutable local.
//
// Some parameter shapes do get a load alloca, so "has an alloca" cannot
// decide this. The `__param` marker does, with `__inout` carved out.

$ `stdlib/core/string.nu`

: Deep { i8 dx }

: Mid { Deep dm i32 mz }

@ f Mid m → i {
    = . . m dm dx 5
    ^ 0
}

@ main → i {
    ( nurl_print ( nurl_str_int ( f @ Mid { @ Deep { # i8 1 } # i32 2 } ) ) )
    ^ 0
}
