// map: §2.10 | A2 | runs-clean | - | agora #479: `?? o { T s → { ^ \ → … s … } }` with a struct field as the argument: the caller's field is freed twice
// AGORA-869: runs clean under ASan/LSan with the default compile (main 3358873a: faulted); the ticket's other shapes stay open.
$ `stdlib/core/string.nu`

: H { ? String o i n }

@ cap ? String o → ( @ i ) {
    ?? o { T s → { ^ \ → i { ^ ( string_len s ) } } F → {} }
    ^ \ → i { ^ 0 }
}

@ main → i {
    : H h @ H { @ ?String { T ( string_from `a field payload long enough for the heap buffer, surely` ) } 3 }
    : ( @ i ) c ( cap . h o )
    ( nurl_println_int ( c ) )
    ?? . h o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
