// defer_pointing_back_a_holder_that_views_a_local_bound_after_it_runs_clean: a defer only points an inout holder back; the local the holder viewed is bound after the defer and drops before it runs.
// Control for agora #408: ending the post-defer local first refuses no defer that does not read through the holder.
// map: §2.10 | A2 | runs-clean | - | agora #408: a defer only points an inout holder back; the local the holder viewed is bound after the defer and drops before it runs
$ `stdlib/core/string.nu`

: W { s v }

@ fill inout W w i k → i {
    ; { = w @ W { `literal from the defer` } }
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    ? > k 0 { ^ k } {}
    = w @ W { `literal` }
    ^ 0
}

@ main → i {
    : ~ W w @ W { `start` }
    : i _r ( fill w 1 )
    ( nurl_println . w v )
    ^ 0
}
