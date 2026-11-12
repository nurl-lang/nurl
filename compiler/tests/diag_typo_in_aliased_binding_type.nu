// The same typo in an aliased module's type, `: geo::Ptt p …`: an unknown
// type (agora #725).
$ `compiler/tests/alias_rewrite_types_mod.nu` geo

@ main → i {
    : geo::Pointt p ( geo::make_point 3 4 )
    ( nurl_println_int . p x )
    ^ 0
}
