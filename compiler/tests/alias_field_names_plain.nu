// alias_field_names_plain.nu — the module of alias_field_names.nu imported
// without an alias reads the same (agora #729).

$ `compiler/tests/alias_field_names_mod.nu`

@ main → i {
    : Pt p @ Pt { 1 2 }
    ( nurl_println_int + ( x p ) . p x )
    : Named n @ Named { `nurl` 4 }
    ( nurl_println ( name n ) )
    ( nurl_println_int . n len )
    : [i ns [i | 5 6 7]
    ( nurl_println_int ( len ns ) )
    : Pt q ( moved p )
    ( nurl_println_int . q x )
    ( nurl_println_int ( stretch @ Line { p q } ) )
    ^ 0
}
