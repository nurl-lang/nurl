// second_payload_binding_of_an_enum_cleared_under_a_borrow_of_the_first: agora #460 — `?? e { Some xs → { : String s0 ( vec_at [String] xs 0 ) ?? e { Some ys → { ( vec_clear [String] ys ) } … } … s0 } }`: xs and ys are one Vec, and clearing ys ends the borrow taken through xs (claude-holes x04)
// main: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #460: `?? e { Some xs → { : String s0 ( vec_at [String] xs 0 ) ?? e { Some ys → { ( vec_clear [String] ys ) } … } … s0 } }`: xs and ys are one Vec, and clearing ys ends the borrow taken through xs (claude-holes x04)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { Some ( Vec String ) None }

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : E e @ E { Some inner }
    ?? e { Some xs → {
            : String s0 ( vec_at [String] xs 0 )
            ?? e { Some ys → { ( vec_clear [String] ys ) } None → {} }
            ( nurl_println_int ( string_len s0 ) )
        } None → {} }
    ^ 0
}
