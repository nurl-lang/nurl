// closure_over_a_value_block_local_bound_then_handed_back: `: ( @ i i ) g { : String s … : ( @ i i ) f \ … s … f }  ^ g` — refused before #846 too (h310); kept beside its twins.
// map: §2.3 | A2 | rejected | - | agora #846: a closure over a value block's binding, bound then handed back
$ `stdlib/core/string.nu`

@ make2 i n → ( @ i i ) {
    : ( @ i i ) g { : String s ( string_from `a block-local string long enough for a heap buffer` ) : ( @ i i ) f \ i x → i { ^ + + x n ( string_len s ) } f }
    ^ g
}

@ main → i { : ( @ i i ) f ( make2 1 ) ( nurl_println_int ( f 1 ) ) ^ 0 }
