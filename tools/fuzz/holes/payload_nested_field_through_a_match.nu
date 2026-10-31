// payload_nested_field_through_a_match: agora #178 — a payload's nested field (`. . q p s`) handed back through a `??` arm (payload_nested_field_through_a_match).
// Closed: a `?` / `??` arm that hands out a field of a parameter — or of a payload binding or cursor over one — lends that parameter back in part (mem_note_field_part; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h706 | agora #178: a payload's nested field (`. . q p s`) handed back through a `??` arm
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: Q { P p i k }

: | H {
    W Q
    Non
}

@ deep H h → String { ^ ?? h { W q → . . q p s Non → ( mk ) } }

@ main → i {
    : String t ( deep @ H { W @ Q { @ P { ( mk ) 1 } 2 } } )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
