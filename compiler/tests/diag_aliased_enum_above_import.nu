// diag_aliased_enum_above_import.nu — an enum of a module imported under
// an alias, used by value above the import: "declared LATER", spelled the
// way the program writes it, 'm::Shade' (agora #730).

@ main → i {
    : m::Shade s m::Light
    ^ 0
}

$ `compiler/tests/alias_rewrite_types_mod.nu` m
