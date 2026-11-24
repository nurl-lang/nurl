// recover_closure_capture_handed_to_an_emptying_inout_then_pushed: the closure handed to `recover` hands its capture `w` to an `inout` handle parameter whose callee may hand it to a `sink`, and the caller pushes through `w` after `recover` returns.
// Closed: `recover` runs the closure, whose body's calls on its captures replay at the call (`pendeff` rows), and the row marks the capture moved on some paths (`__bck_empties_mark`, AGORA-996).
// main's compiler: compiled with no `unsafe`; the push stored through the null data pointer (ASan: SEGV, a WRITE to the zero page).
// map: §2.11 | A2 | rejected | h982 | the closure handed to recover hands its capture to an emptying inout callee, and the caller pushes through it (AGORA-996)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

@ eat sink ( Vec i ) v → i { ^ # i ( vec_len [i] v ) }

@ g3 inout ( Vec i ) p i c → i { ? == c 1 { ^ ( eat p ) } {} ^ 0 }

@ main → i {
    : ~ ( Vec i ) w ( vec_new [i] )
    : !v PanicInfo pr ( recover \ → v {
        ( g3 w 1 )
    } )
    ( vec_push [i] w 2 )
    ^ 0
}
