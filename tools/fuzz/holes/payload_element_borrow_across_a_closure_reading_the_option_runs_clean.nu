// payload_element_borrow_across_a_closure_reading_the_option_runs_clean: agora #424 — a closure that only reads the option's payload, called while an element borrow lives
// Control for agora #424.
// map: §2.10 | A2 | runs-clean | - | agora #424: a closure that only reads the option's payload, called while an element borrow lives
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ( Vec String ) inner0 ( vec_new [String] )
    ( vec_push [String] inner0 ( string_from `an element string long enough for a heap buffer` ) )
    : ?( Vec String ) o @ ?( Vec String ) { T inner0 }
    : ( @ i ? ( Vec String ) ) rd \ ? ( Vec String ) b → i { ?? b { T xs → { ^ ( vec_len [String] xs ) } F → { ^ 0 } } }
    ?? o { T inner → {
            : String s0 ( vec_at [String] inner 0 )
            ( nurl_println_int ( rd o ) )
            ( nurl_println_int ( string_len s0 ) )
        } F → {} }
    ^ 0
}
