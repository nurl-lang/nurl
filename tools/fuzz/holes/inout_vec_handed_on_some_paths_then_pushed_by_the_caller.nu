// inout_vec_handed_on_some_paths_then_pushed_by_the_caller: a function hands its `inout` Vec parameter to a `sink` on one path only. On that path the caller's slot is emptied (a null handle), and the caller pushed onto it after the call.
// Closed: a callee that may hand its `inout` handle parameter on (g_fn_empties, built from the replacement summary's edges) leaves the caller's argument moved on some paths: any use before a new value is refused. Its zero drops as nothing, so its release is unchanged.
// main's compiler: compiled with no `unsafe`; vec_push stored through data pointer 0, which the optimiser took for unreachable code: the program re-entered main until the stack overflowed.
// map: §7.6 | A2 | rejected | h977 | inout Vec handed to a sink on some paths by the callee, then pushed by the caller
$ `stdlib/core/vec.nu`

@ eat sink ( Vec i ) v → i { ^ # i ( vec_len [i] v ) }

@ g3 inout ( Vec i ) p i c → i {
    ? == c 1 { ^ ( eat p ) } {}
    ^ 0
}

@ main → i {
    : ~ ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 1 )
    ( nurl_println_int ( g3 w 1 ) )
    ( vec_push [i] w 2 )
    ( nurl_println_int # i ( vec_len [i] w ) )
    ^ 0
}
