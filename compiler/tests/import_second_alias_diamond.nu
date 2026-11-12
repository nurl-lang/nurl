// import_second_alias_diamond.nu — agora #694: a program imports a module
// plainly and a library that imports the same module under an alias. The
// library's `m::Point` is the program's `Point`: both compile, in this
// order. (The other order is diag_import_plain_after_alias.nu.)

$ `compiler/tests/alias_rewrite_types_mod.nu`
$ `compiler/tests/import_second_alias_mod.nu`

@ main → i {
    : Point q ( make_point 3 4 )
    ( nurl_println_int + ( origin_x ) . q x )
    ^ 0
}
