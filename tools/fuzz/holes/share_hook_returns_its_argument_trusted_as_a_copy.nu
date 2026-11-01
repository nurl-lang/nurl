// share_hook_returns_its_argument_trusted_as_a_copy: agora #334 — a program's own X_share hook returns its argument; the copy a literal makes through it reads the temporary its caller freed (formal's u2).
// Closed: a handle's copy hook (`S_clone` / `S_share`) may lend nothing of its parameter; one whose final summary hands its argument back, whole or in part, is refused where it is written, since every copy it makes would be a second owner of one value (resolve_clone_hooks, agora #334).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #334: a share hook that returns its argument, trusted as a copy
$ `stdlib/core/vec.nu`

: X { ( Vec i ) v }

@ X_drop sink X x → v {}

@ X_share X x → X { ^ x }

@ mk → X {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 41 )
    ^ @ X { b }
}

@ step X x → !i i { ^ @ !i i { T 0 } }

@ wrap X x → !X i {
    : !i i r ( step x )
    ^ ?? r {
        T _ → @ !X i { T x }
        F e → @ !X i { F e }
    }
}

@ main → i {
    : ~ i k 0
    ~ < k 3 {
        ?? ( wrap ( mk ) ) { T y → { ( nurl_println_int ( vec_at [i] . y v 0 ) ) } F _ → {} }
        = k + k 1
    }
    ^ 0
}
