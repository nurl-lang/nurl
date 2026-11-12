// An aliased module's generic structs may be named above the import
// (agora #716, #724): every template, an aliased file's included, is
// collected before the first instance is made, so `( geo::Pair i )` has
// its fields here.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( geo::Pair i ) p @ ( geo::Pair i ) { 2 3 }
    ( nurl_println_int ( geo::pair_sum p ) )
    : ( geo::Nest i ) n @ ( geo::Nest i ) { @ ( geo::Pair i ) { 1 2 } 3 }
    ( nurl_println_int ( geo::nest_sum n ) )
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a long enough string to be on the heap` ) )
    : ( geo::Bag String ) b @ ( geo::Bag String ) { v 7 }
    ( nurl_println_int ( geo::bag_len b ) )
    ^ 0
}

$ `compiler/tests/generic_struct_aliased_import_mod.nu` geo
