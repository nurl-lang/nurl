// import_alias_underscore_names.nu — an import alias may hold single
// underscores and start with them; what it may not is hold `__` or end in
// `_` (diag_import_alias_double_underscore.nu,
// diag_import_alias_trailing_underscore.nu), and a type behind an alias
// is named by the module's own name: `my_geo::Point` is `my_geo__Point`,
// which is no instance of a generic type.

$ `compiler/tests/alias_rewrite_types_mod.nu` my_geo
$ `compiler/tests/should_fail_alias_import_mod.nu` _calc

@ main → i {
    : my_geo::Point p ( my_geo::make_point 3 4 )
    ( nurl_println ( nurl_str_int ( _calc::ai_add . p x . p y ) ) )
    ( nurl_println ( nurl_str_int ( _calc::ai_double my_geo::PI_FIXED ) ) )
    ^ 0
}
