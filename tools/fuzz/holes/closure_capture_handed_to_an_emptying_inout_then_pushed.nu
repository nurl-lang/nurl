// closure_capture_handed_to_an_emptying_inout_then_pushed: a closure body hands its capture `w`, taken by pointer, to an `inout` handle parameter whose callee may hand it to a `sink`. Running the closure empties the caller's `w` on that path, and the caller pushes through it.
// Closed: a closure's run replays the calls its body makes on its captures (`pendeff` rows), and the row now marks the capture moved on some paths as the call written there does (`__bck_empties_mark`, AGORA-996).
// main's compiler: compiled with no `unsafe`; the push stored through the null data pointer (ASan: SEGV, a WRITE to the zero page, in `_nurl_main`).
// map: §2.11 | A2 | rejected | h981 | a closure hands its by-pointer capture to an emptying inout callee, and the caller pushes through the capture after running it (AGORA-996)
$ `stdlib/core/vec.nu`

@ eat sink ( Vec i ) v → i { ^ # i ( vec_len [i] v ) }

@ g3 inout ( Vec i ) p i c → i { ? == c 1 { ^ ( eat p ) } {} ^ 0 }

@ main → i {
    : ~ ( Vec i ) w ( vec_new [i] )
    : ( @ i ) f \ → i { ^ ( g3 w 1 ) }
    ( f )
    ( vec_push [i] w 2 )
    ^ 0
}
