// clone_hook_returns_its_argument_into_a_kept_literal: agora #334 — the clone hook that returns its argument, through a local literal the function keeps and returns: the struct's field aliases the caller's temporary (formal's u3, a hole before #1470 too).
// Closed: a handle's copy hook (`S_clone` / `S_share`) may lend nothing of its parameter; one whose final summary hands its argument back, whole or in part, is refused where it is written, since every copy it makes would be a second owner of one value (resolve_clone_hooks, agora #334).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #334: a clone hook that returns its argument, through a kept local literal
$ `stdlib/core/vec.nu`

: X { ( Vec i ) v }

@ X_drop sink X x → v {}

@ X_clone X x → X { ^ x }

: H { X x i n }

@ mk → X {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 41 )
    ^ @ X { b }
}

@ hold X x → H {
    : H h @ H { x 1 }
    ^ h
}

@ main → i {
    : H h ( hold ( mk ) )
    ( nurl_println_int ( vec_at [i] . . h x v 0 ) )
    ^ 0
}
