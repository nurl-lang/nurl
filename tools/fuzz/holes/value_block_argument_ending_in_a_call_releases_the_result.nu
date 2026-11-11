// value_block_argument_ending_in_a_call_releases_the_result: `( string_len { : String s … ( string_concat s s ) } )`; the same nested in another call's argument; a tail call that lends the block's binding, or an outer one.
// Closed: a block argument that ends in a call is that call's result for what the argument leaves the caller to drop after the call (mem_arg_temps is asked with the block's effective token, a call's). Asked as a block, the call's own result was released by nobody (agora #628 item 1).
// main b82c116: accepted; LeakSanitizer: the tail call's result, once per run of the statement.
// map: §7.1 | A2 | runs-clean | - | agora #628: a value block ending in a call, passed as a non-sink argument, leaks the call's result
$ `stdlib/core/string.nu`

@ idg [T] T x → T { ^ x }

@ main → i {
    : String outer ( string_from `an outer string long enough for a heap buffer` )
    ( nurl_println_int ( string_len { : String s ( string_from `a block string long enough for a heap buffer` ) ( string_concat s s ) } ) )
    : String r ( string_concat { : String s ( string_from `a second block string long enough for the heap` ) ( string_concat s s ) } outer )
    ( nurl_println_int ( string_len r ) )
    ( nurl_println_int ( string_len { : String s ( string_from `a third block string, lent by the tail call here` ) ( idg [String] s ) } ) )
    ( nurl_println_int ( string_len { ( idg [String] outer ) } ) )
    ^ 0
}
