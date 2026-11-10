// payload_element_borrow_across_a_clearer_of_the_option: agora #424 — `?? o { T inner → { : String s0 ( vec_at [String] inner 0 ) ( clr o ) … s0 } }`, clr clearing the option's payload Vec: the element borrow ends at the call (claude-holes a29n)
// main ea4ddd1f: accepted; heap-use-after-free. Refused on main 7b7dccb5 already (the option cursor's payload is released at the call).
// map: §2.10 | A2 | rejected | - | agora #424: `?? o { T inner → { : String s0 ( vec_at [String] inner 0 ) ( clr o ) … s0 } }`, clr clearing the option's payload Vec: the element borrow ends at the call (claude-holes a29n)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ clr ? ( Vec String ) b → v { ?? b { T xs → { ( vec_clear [String] xs ) } F → {} } }

@ main → i {
    : ( Vec String ) inner0 ( vec_new [String] )
    ( vec_push [String] inner0 ( string_from `an element string long enough for a heap buffer` ) )
    : ?( Vec String ) o @ ?( Vec String ) { T inner0 }
    ?? o { T inner → {
            : String s0 ( vec_at [String] inner 0 )
            ( clr o )
            ( nurl_println_int ( string_len s0 ) )
        } F → {} }
    ^ 0
}
