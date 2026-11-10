// diag_value_block_name_shadowing_an_outer_one.nu — the block's `s` has the
// name of an outer `s`. What the block bound lives on to the end of the
// enclosing scope under that name, so `s` after the block would be the
// block's binding, not the outer one the source means: refused, and the
// message says to rename the block's binding (agora #575). It used to
// compile and print "inner".
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String s ( string_from `outer` )
    : String e { : String s ( string_from `inner` ) ( string_from `copy` ) }
    ( nurl_println ( string_data s ) )
    ( nurl_println ( string_data e ) )
    ^ 0
}
