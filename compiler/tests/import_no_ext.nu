// import_no_ext.nu — an import path written WITHOUT a `.nu` extension
// resolves by retrying the same lookup tiers with `.nu` appended. The
// grammar's own import examples are extensionless (`$ `stdlib/core/string``),
// so this spelling must compile identically to the `.nu` one. The
// as-written path is still tried first, so a file that really has no
// extension keeps resolving as before.
//
// Determinism: pure byte arithmetic, no clock/socket/env. ASan-clean.

$ `stdlib/core/char`

@ main → i {
    // 'a'=97 → 'A'=65; is_upper(65) → 1
    ( nurl_print_int ( to_upper_ascii 97 ) )
    ( nurl_print_int ( is_upper 65 ) )
    ^ 0
}
