// diag_import_alias_double_underscore.nu — an import alias holds no `__`.
// The alias stands before each of the module's names with `__` between
// (`geo::Point` is `geo__Point`), and it is read back up to the first
// `__`: one of the alias's own moves where it ends.

$ `compiler/tests/alias_rewrite_types_mod.nu` my__geo

@ main → i {
    : my__geo::Point p ( my__geo::make_point 3 4 )
    ^ - . p x 3
}
