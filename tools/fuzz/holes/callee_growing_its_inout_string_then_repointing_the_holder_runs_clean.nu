// callee_growing_its_inout_string_then_repointing_the_holder_runs_clean: agora #558 — `f` points its inout holder `w` at the inout String `s`, grows `s` (the buffer moves), and points `w` at it again before it returns: what the caller gets back views the new buffer.
// Control: refused on main by the exclusive-call check, which read the callee's exit pair (w views s) as an alias the arguments had before the call; the growth then ended the view the callee re-made.
// map: §2.10 | A2 | runs-clean | - | agora #558: an inout callee that grows the String its holder views and points the holder at it again
$ `stdlib/core/string.nu`

: W { s v }

@ f inout W w inout String s → v {
    = w @ W { ( string_data s ) }
    ( string_push_str s `and a long tail that makes the buffer move to a new place in memory for sure` )
    = w @ W { ( string_data s ) }
}

@ main → i {
    : ~ W w @ W { `x` }
    : ~ String s ( string_from `the first heap string, long enough to be on the heap for sure` )
    ( f w s )
    ( nurl_println . w v )
    ^ 0
}
