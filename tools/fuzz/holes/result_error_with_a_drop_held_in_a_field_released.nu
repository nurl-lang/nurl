// result_error_with_a_drop_held_in_a_field_released: a struct field `! i Res` holding its error, Res with a `% Drop`, was dropped by nobody — `__holds_user_drop` looked into a result's Ok payload only, so the struct was neither a handle nor a synth-drop struct, and its binding's drop emitted nothing (the Res and its Vec leaked). The same in an enum payload.
// Closed: a result's error is asked too (agora #539). A try over a cursor of such a parameter's field — `: !i Res q ( getr b )  \ q` with getr handing back `. b r` — hands the failure on as the caller's lent value, as `^ cur` does.
// main ad960922: LeakSanitizer (use_stacks=0): the Res and its Vec leaked.
// map: §7.6 | A2 | runs-clean | - | agora #539: a result field whose error has a Drop was released by nobody
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: B { ! i Res r i n }

: | Hold { One ! i Res None }

@ mkres i k → !i Res {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v k )
    ^ @ !i Res { F @ Res { v } }
}

@ main → i {
    : B b @ B { ( mkres 7 ) 3 }
    : Hold h @ Hold { One ( mkres 8 ) }
    ( nurl_println_int . b n )
    ^ 0
}
