// diag_aliased_struct_declared_later.nu — agora #730: a type of a module
// imported under an alias, used by value above the import, follows the
// rule a plainly imported one does — "declared LATER", spelled 'm::Point'.
// It was accepted without a field read (as a parameter, a binding) and
// refused as "type 'm__Point' has no field 'x'" with one.

@ show m::Point p → i { ^ 0 }

@ main → i {
    : m::Point p ( m::make_point 2 3 )
    ( nurl_println_int . p x )
    ^ ( show p )
}

$ `compiler/tests/alias_rewrite_types_mod.nu` m
