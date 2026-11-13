// aliased_enum_above_import.nu — an enum of a module imported under an
// alias, used by value above the import (agora #730, #772): made from a
// variant and matched.

@ main → i {
    : m::Shade s m::Dark
    ^ ?? s { m::Light → 1 m::Dark → 0 }
}

$ `compiler/tests/alias_rewrite_types_mod.nu` m
