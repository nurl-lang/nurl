// value_block_returning_a_closure_over_a_block_local_string: `^ { : String s … : ( @ i i ) f \\ … s … f }`: the closure holds a copy of the handle of s, which the function releases on the way out
// Closed: a value block whose tail is a closure binding of its own is that binding to the return's check, `|f` (__sx_operand_c, bck_sx_ids), and a binding its closed frame declared is still this function's (bck_local_source, `oos_`): checked as `^ f` is (agora #638).
// main 006aa3e: AddressSanitizer: heap-use-after-free (the caller's call read the freed String).
// map: §7.6 | A2 | rejected | - | agora #638: a returned value block's closure tail
$ `stdlib/core/string.nu`

@ mkn i n → ( @ i i ) { ^ \ i x → i { ^ + x n } }

@ make2 i n → ( @ i i ) {
    ^ { : String s ( string_from `a block-local string long enough for a heap buffer` ) : ( @ i i ) f \ i x → i { ^ + + x n ( string_len s ) } f }
}

@ main → i { : ( @ i i ) f ( make2 1 ) ( nurl_println_int ( f 1 ) ) ^ 0 }
