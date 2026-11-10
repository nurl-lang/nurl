// payload_element_borrow_across_a_closure_clearing_the_option: agora #424 — the same with the clearer a closure value: its drop summary did not follow a payload matched out of its own parameter (claude-holes a29)
// main 7b7dccb5: accepted; heap-use-after-free (__drop_note_via returned early in a closure body of a function with no parameters).
// map: §2.10 | A2 | rejected | - | agora #424: the same with the clearer a closure value: its drop summary did not follow a payload matched out of its own parameter (claude-holes a29)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ( Vec String ) inner0 ( vec_new [String] )
    ( vec_push [String] inner0 ( string_from `an element string long enough for a heap buffer` ) )
    : ?( Vec String ) o @ ?( Vec String ) { T inner0 }
    : ( @ v ? ( Vec String ) ) clr \ ? ( Vec String ) b → v { ?? b { T xs → { ( vec_clear [String] xs ) } F → {} } }
    ?? o { T inner → {
            : String s0 ( vec_at [String] inner 0 )
            ( clr o )
            ( nurl_println_int ( string_len s0 ) )
        } F → {} }
    ^ 0
}
