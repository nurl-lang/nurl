// enum_payload_element_borrow_across_a_clearer_of_the_enum: agora #424 — `?? o { Fullbag inner → { : String s0 ( vec_at [String] inner 0 ) ( clr o ) … s0 } }`, clr vec_clearing the enum's payload in place: the element borrow ends at the call (claude-holes a28, claude-formal #569 item 6)
// main 9635d947: accepted; heap-use-after-free (#565 keeps the payload for an in-place clear, rightly, but its element borrows lived on).
// map: §2.10 | A2 | rejected | - | agora #424: `?? o { Fullbag inner → { : String s0 ( vec_at [String] inner 0 ) ( clr o ) … s0 } }`, clr vec_clearing the enum's payload in place: the element borrow ends at the call (claude-holes a28, claude-formal #569 item 6)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: | Bag { Nobag Fullbag ( Vec String ) }

@ clr Bag b → v { ?? b { Fullbag xs → { ( vec_clear [String] xs ) } Nobag → {} } }

@ main → i {
    : ( Vec String ) inner0 ( vec_new [String] )
    ( vec_push [String] inner0 ( string_from `an element string long enough for a heap buffer` ) )
    : Bag o @ Bag { Fullbag inner0 }
    ?? o { Fullbag inner → {
            : String s0 ( vec_at [String] inner 0 )
            ( clr o )
            ( nurl_println_int ( string_len s0 ) )
        } Nobag → {} }
    ^ 0
}
