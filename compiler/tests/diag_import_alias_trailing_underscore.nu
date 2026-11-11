// diag_import_alias_trailing_underscore.nu — an import alias does not end
// in `_`: with the `__` that follows it, the module's `Point` would be
// spelled `geo___Point`, and the alias read back up to the first `__`
// would lose the underscore to the name.

$ `compiler/tests/alias_rewrite_types_mod.nu` geo_

@ main → i {
    : geo_::Point p ( geo_::make_point 3 4 )
    ^ - . p x 3
}
