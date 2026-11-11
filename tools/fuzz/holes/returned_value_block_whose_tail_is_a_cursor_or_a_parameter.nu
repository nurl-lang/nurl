// returned_value_block_whose_tail_is_a_cursor_or_a_parameter: `^ { … : String t ( vec_at [String] u 0 ) t }`, `u` the block's own Vec; `^ { : i z 1 p }`, `p` a parameter.
// Closed: a returned value block whose tail is a binding hands that binding back as `^ t` does (gen_ret reads the block's tail binding as its operand): a lend out of this frame's own is copied, a parameter is lent back. Handed back as the block stood, the caller's String viewed an element of `u`, released on the way out, or was the argument's own buffer, dropped by both (agora #649).
// main b82c116: accepted; AddressSanitizer: heap-use-after-free (the cursor), attempting double-free (the parameter).
// map: §7.1 | A2 | runs-clean | - | agora #649: a value block returned straight whose tail binding is a cursor of an element of another block binding, or a parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cursor i n → String {
    ^ { : ~ ( Vec String ) u ( vec_new [String] ) ( vec_push [String] u ( string_from `an element long enough for a heap buffer` ) ) : String t ( vec_at [String] u 0 ) t }
}

@ param String p → String { ^ { : i z 1 p } }

@ own i n → String { ^ { : String s ( string_from `an owned block string long enough for the heap` ) s } }

@ main → i {
    : String r ( cursor 1 )
    ( nurl_println ( string_data r ) )
    : String q ( string_from `a caller string long enough for a heap buffer` )
    : String c ( param q )
    ( nurl_println_int + ( string_len c ) ( string_len q ) )
    : String a ( own 1 )
    ( nurl_println_int ( string_len a ) )
    ^ 0
}
