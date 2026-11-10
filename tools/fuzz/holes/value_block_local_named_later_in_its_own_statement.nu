// value_block_local_named_later_in_its_own_statement: `( two { : String s … s } s )`, with an outer `s`.
// Closed: refused. The second `s` is meant as the outer one, but from the block's `}` on the name reaches the block's binding — here one the first argument already handed to a `sink` (agora #575).
// main 2498b4e: accepted; the second argument was the block's `s`: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #575: a value block's local named again in the statement that takes the block's value
$ `stdlib/core/string.nu`

@ two sink String a String b → i { ^ + ( string_len a ) ( string_len b ) }

@ main → i {
    : ~ String s ( string_from `outer` )
    ( nurl_println_int ( two { : String s ( string_from `inner string long enough for a heap buffer` ) s } s ) )
    ^ 0
}
