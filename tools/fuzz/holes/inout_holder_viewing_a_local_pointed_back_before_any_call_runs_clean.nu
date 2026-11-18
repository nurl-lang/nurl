// inout_holder_viewing_a_local_pointed_back_before_any_call_runs_clean: AGORA-382 guard — an inout holder given a view of a local and pointed back before anything that may panic: nothing can unwind while it views the local, accepted
// map: §2.14 | A2 | runs-clean | - | AGORA-382 guard: no call between the store of a local's view and the repoint
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }

@ fill inout W w i k → v {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    = w @ W { `literal again` }
    ? > k 2 { ( panic `unwind` ) } {}
}

@ main → i {
    : ~ W w @ W { `literal` }
    : !v PanicInfo r ( recover \ → v { ( fill w 3 ) } )
    ( nurl_println . w v )
    ^ 0
}
