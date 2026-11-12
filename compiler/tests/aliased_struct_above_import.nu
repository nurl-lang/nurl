// aliased_struct_above_import.nu — a struct of a module imported under an
// alias, used by value above the import (agora #730, #772): as a parameter,
// a binding and with a field read. It was accepted without the field read
// and refused as "type 'm__Point' has no field 'x'" with one.

@ show m::Point p → i { ^ . p y }

@ main → i {
    : m::Point p ( m::make_point 2 3 )
    ( nurl_println_int . p x )
    ^ - ( show p ) 3
}

$ `compiler/tests/alias_rewrite_types_mod.nu` m
