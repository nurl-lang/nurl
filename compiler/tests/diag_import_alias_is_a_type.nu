// diag_import_alias_is_a_type.nu — an import alias is not the name of a
// type. Behind the alias the module's `Point` is spelled `Pair__Point`,
// which is how the compiler spells `( Pair Point )`: the module's types
// would be read as instances of the program's generic `Pair`. Refused at
// the import, wherever the type is declared.

$ `compiler/tests/alias_rewrite_types_mod.nu` Pair

: Pair [T] { T a T b }

@ main → i {
    : Pair::Point p ( Pair::make_point 3 4 )
    ^ - . p x 3
}
