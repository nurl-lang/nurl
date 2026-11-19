// inout_holder_viewing_what_the_caller_passed_across_a_call_runs_clean: AGORA-382 guard — an inout holder given a view of the caller's own string, then a call that may panic: the unwind frees nothing it views, accepted
// map: §2.14 | A2 | runs-clean | - | AGORA-382 guard: a view of a parameter held across a call
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }

@ fill inout W w String src i k → v {
    = w @ W { ( string_data src ) }
    ? > k 2 { ( panic `unwind` ) } {}
}

@ main → i {
    : String src ( string_from `the caller's string, alive after the recover, long enough` )
    : ~ W w @ W { `literal` }
    ( fill w src 1 )
    ( nurl_println . w v )
    ^ 0
}
