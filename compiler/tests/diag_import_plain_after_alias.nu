// diag_import_plain_after_alias.nu — agora #694: a module the library
// import_second_alias_mod.nu imports as `m` is compiled with its names
// spelled `m::name`; a plain import of it after that cannot make them bare
// as well. Refused at the plain import, naming both spellings — it was
// skipped silently, and `: Point q …` failed as "undefined identifier 'q'".

$ `compiler/tests/import_second_alias_mod.nu`
$ `compiler/tests/alias_rewrite_types_mod.nu`

@ main → i {
    : Point q ( make_point 3 4 )
    ^ - + ( origin_x ) . q x 8
}
