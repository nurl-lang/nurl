// diag_falloff_no_value.nu — a value-returning function whose body
// falls off the end without a value. Used to lower `ret i64 undef` —
// VALID IR returning garbage the caller then trusted; now the shared
// return battery (ret_ty_agree) rejects it at the fall-off site with
// the same voice as the '^' checks, plus the unbalanced-brace hint
// (an extra '}' truncating a body is the other way this fires).

@ f → i {
    ( nurl_print `side effect only\n` )
}

@ main → i {
    : i y ( f )
    ^ y
}
