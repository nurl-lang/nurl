// closure_reassigned_in_a_value_block_and_handed_out: a value block whose tail is a `: ~` closure binding the block gave a second literal with `=`, taken by an assignment, by a plain closure parameter and by a `sink` one; and a block with a `;` defer that calls its closure, taken by a `:`.
// Closed: an assignment settles the env its literal made (`__last_closure_env__`), as a `:` does, so the statement around the block does not take the block's binding's env for its own right-hand side's — both released it. A block binding a defer may still call keeps its env (agora #627).
// main 2498b4e: accepted; AddressSanitizer: heap-use-after-free in the closure's drop (the first three).
// map: §7.4 | A2 | runs-clean | - | agora #627: a closure binding reassigned inside a value block and handed out as the block's value
$ `stdlib/core/string.nu`

@ app ( @ i i ) f i a → i { ^ ( f a ) }

@ eat sink ( @ i i ) f i a → i { ^ ( f a ) }

@ run String tag i n → i {
    : ( @ i i ) g { : ( @ i i ) f \ i x → i { ^ + + x n ( string_len tag ) } ; { ( nurl_println_int ( f 1 ) ) } f }
    ^ ( eat g 2 )
}

@ main → i {
    : String tag ( string_from `a captured tag long enough for a heap buffer` )
    : i k 3
    : ~ ( @ i i ) a \ i x → i { ^ + x 1 }
    = a { : ~ ( @ i i ) h \ i x → i { ^ + + x 3 ( string_len tag ) } = h \ i x → i { ^ + + x 6 ( string_len tag ) } h }
    ( nurl_println_int ( a 1 ) )
    ( nurl_println_int ( app { : ~ ( @ i i ) h \ i x → i { ^ + + x k ( string_len tag ) } = h \ i x → i { ^ + + x * 2 k ( string_len tag ) } h } 1 ) )
    ( nurl_println_int ( eat { : ~ ( @ i i ) h \ i x → i { ^ + + x k ( string_len tag ) } = h \ i x → i { ^ + + x * 2 k ( string_len tag ) } h } 1 ) )
    ( nurl_println_int ( run tag 1 ) )
    ^ 0
}
