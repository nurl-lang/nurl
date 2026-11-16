// map: §7.6 | A2 | rejected | - | agora #846: `: ( @ i i ) g { : String s … : ( @ i i ) f \ … s … f }  ^ g` (#835 item 1b): a closure over a value block's local handed back
$ `stdlib/core/string.nu`

@ make2 i n → ( @ i i ) {
    : ( @ i i ) g { : String s ( string_from `a block-local string long enough for a heap buffer` ) : ( @ i i ) f \ i x → i { ^ + + x n ( string_len s ) } f }
    ^ g
}

@ main → i { : ( @ i i ) f ( make2 1 ) ( nurl_println_int ( f 1 ) ) ^ 0 }
