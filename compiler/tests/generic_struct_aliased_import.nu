// A module that declares generic structs can be imported under an alias
// (agora #724): its templates are read from the same rewritten source as
// every other name it declares, so `( geo::Pair i )` is the module's
// `Pair` here and in the module's own functions, a template that holds
// another (`( geo::Nest i )`) included, and what an instance owns is
// released with it.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `compiler/tests/generic_struct_aliased_import_mod.nu` geo

@ main → i {
    : ( geo::Pair i ) p @ ( geo::Pair i ) { 2 3 }
    ( nurl_println_int ( geo::pair_sum p ) )
    ( nurl_println_int ( geo::pair_sum ( geo::pair_of 10 20 ) ) )
    : ( geo::Nest i ) n @ ( geo::Nest i ) { @ ( geo::Pair i ) { 1 2 } 3 }
    ( nurl_println_int ( geo::nest_sum n ) )
    : geo::Tagged t @ geo::Tagged { @ ( geo::Pair i ) { 4 5 } 6 }
    ( nurl_println_int ( geo::tagged_sum t ) )
    ( nurl_println_int . . t p b )
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a long enough string to be on the heap` ) )
    : ( geo::Bag String ) b @ ( geo::Bag String ) { v 7 }
    ( nurl_println_int ( geo::bag_len b ) )
    ^ 0
}
