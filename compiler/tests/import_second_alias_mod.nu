// fixture: module; import_second_alias_mod.nu — a library that imports
// alias_rewrite_types_mod.nu under the alias `m` (import_second_alias*.nu,
// agora #694).

$ `compiler/tests/alias_rewrite_types_mod.nu` m

@ origin_x → i {
    : m::Point p ( m::make_point 5 6 )
    ^ . p x
}
