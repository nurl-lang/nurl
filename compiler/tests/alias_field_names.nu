// alias_field_names.nu — agora #729: an import alias renames the module's
// top-level names, never the fields of its structs. `: Pt { i x i y }`
// beside `@ x Pt p → i` read `. p x` as `. p fl__x` ("has no field 'x'"),
// for an importer of the module and for a generic struct's instances —
// and a parameter named like one of its functions is still labelled `x:`
// by a caller.

$ `compiler/tests/alias_field_names_mod.nu` fl

@ main → i {
    : fl::Pt p @ fl::Pt { 1 2 }
    ( nurl_println_int + ( fl::x p ) . p x )
    : fl::Named n @ fl::Named { `nurl` 4 }
    ( nurl_println ( fl::name n ) )
    ( nurl_println_int . n len )
    : [i ns [i | 5 6 7]
    ( nurl_println_int ( fl::len ns ) )
    : fl::Pt q ( fl::moved p )
    ( nurl_println_int . q x )
    ( nurl_println_int ( fl::stretch @ fl::Line { p q } ) )
    ( nurl_println_int ( fl::scale x : 3 ) )
    ( nurl_println_int ( fl::scale k : 5 x : 2 ) )
    : ( fl::Pair i ) pr @ ( fl::Pair i ) { 1 2 }
    ( nurl_println_int + ( fl::first pr ) . pr second )
    ^ 0
}
