// diag_colon_decl_junk.nu — ':' at the top level introduces a struct, an
// enum or a global constant. Anything else used to be skipped one token
// at a time, silently.

: 42

@ main → i {
    ^ 0
}
