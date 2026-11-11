// fixture: module; alias_trailing_underscore_mod.nu — a module whose struct's
// name ends in `_` (diag_type_name_trailing_underscore_behind_alias.nu).

: Cell_ { i n }

@ make_cell i n → Cell_ { ^ @ Cell_ { n } }
