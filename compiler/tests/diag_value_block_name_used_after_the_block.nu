// diag_value_block_name_used_after_the_block.nu — a value block's names end
// at its `}` (agora #575). `s` was the block's own: what it holds lives on
// to the end of the enclosing scope, but it cannot be named there. It used
// to compile, and read the block's binding.
$ `stdlib/core/string.nu`

@ main → i {
    : String e { : String s ( string_from `inner` ) ( string_from `copy` ) }
    ( nurl_println ( string_data s ) )
    ( nurl_println ( string_data e ) )
    ^ 0
}
