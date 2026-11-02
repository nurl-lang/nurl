// inout_holder_repointed_by_a_defer_after_viewing_a_local: agora #336 — guard: the holder views the callee's local, and a defer points it back at a literal before the caller gets it.
// Runs clean: the view is asked of the state after the defers ran (agora #336), so a defer that repoints the holder ends it, at a `^` as at the body's end.
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #336: a defer repoints an inout holder that viewed a callee local, then `^`
$ `stdlib/core/string.nu`

: W { s v }

@ fill inout W w → i {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    ; { = w @ W { `literal from the defer` } }
    = w @ W { ( string_data b ) }
    ( nurl_println . w v )
    ^ 0
}

@ main → i {
    : ~ W w @ W { `literal` }
    : i _r ( fill w )
    ( nurl_println . w v )
    ^ 0
}
