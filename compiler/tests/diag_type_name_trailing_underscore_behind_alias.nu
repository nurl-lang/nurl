// diag_type_name_trailing_underscore_behind_alias.nu — a module's type
// imported under an alias is judged by the module's own name: `Cell_`
// behind `cells` is spelled `cells__Cell_`, and its last `_` runs into the
// separator of a type made from it just as a program's own
// (diag_type_name_trailing_underscore_struct.nu). The message names the
// module's name, not the spelling.

$ `compiler/tests/alias_trailing_underscore_mod.nu` cells

@ main → i {
    : cells::Cell_ c ( cells::make_cell 3 )
    ^ - . c n 3
}
