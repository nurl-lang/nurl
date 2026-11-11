// diag_type_named_as_import_alias.nu — the other way round from
// diag_import_alias_is_a_type.nu: a type is not named as an import alias
// is. Refused at the type, which is declared after the import.

$ `compiler/tests/alias_rewrite_types_mod.nu` geo

: | geo {
    North
    South
}

@ main → i {
    : geo::Point p ( geo::make_point 3 4 )
    ^ - . p x 3
}
