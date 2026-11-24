// closure_run_by_a_closure_empties_its_capture_then_pushed: closure `h` runs closure `f`, whose body hands the capture `w` to an `inout` handle parameter that may hand it to a `sink`. Running `h` empties `w`, and the caller pushes through it.
// Closed: `h`'s body replays `f`'s effects, which carry the call on `w` on to `h`'s own effects, and the row at `( h )` marks `w` moved on some paths (`__bck_empties_mark`, AGORA-996).
// main's compiler: compiled with no `unsafe`; the push stored through the null data pointer.
// map: §2.11 | A2 | rejected | h983 | a closure that runs a closure handing its capture to an emptying inout callee, and the caller pushes through the capture (AGORA-996)
$ `stdlib/core/vec.nu`

@ eat sink ( Vec i ) v → i { ^ # i ( vec_len [i] v ) }

@ g3 inout ( Vec i ) p i c → i { ? == c 1 { ^ ( eat p ) } {} ^ 0 }

@ main → i {
    : ~ ( Vec i ) w ( vec_new [i] )
    : ( @ i ) f \ → i { ^ ( g3 w 1 ) }
    : ( @ i ) h \ → i { ^ ( f ) }
    ( h )
    ( vec_push [i] w 2 )
    ^ 0
}
