// clone_hook_returns_its_argument_through_an_option: agora #334 — the clone hook that returns its argument, reached through an `?X` parameter wrapped in a result (formal's u4).
// Closed: a handle's copy hook (`S_clone` / `S_share`) may lend nothing of its parameter; one whose final summary hands its argument back, whole or in part, is refused where it is written, since every copy it makes would be a second owner of one value (resolve_clone_hooks, agora #334).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #334: a clone hook that returns its argument, through an option
$ `stdlib/core/vec.nu`

: X { ( Vec i ) v }

@ X_drop sink X x → v {}

@ X_clone X x → X { ^ x }

@ mk → ?X {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 41 )
    ^ @ ?X { T @ X { b } }
}

@ step ? X h → !i i { ^ @ !i i { T 0 } }

@ wrap ? X h → !?X i {
    : !i i r ( step h )
    ^ ?? r {
        T _ → @ !?X i { T h }
        F e → @ !?X i { F e }
    }
}

@ main → i {
    : ~ i k 0
    ~ < k 3 {
        ?? ( wrap ( mk ) ) { T y → { ?? y { T z → { ( nurl_println_int ( vec_at [i] . z v 0 ) ) } F → {} } } F _ → {} }
        = k + k 1
    }
    ^ 0
}
