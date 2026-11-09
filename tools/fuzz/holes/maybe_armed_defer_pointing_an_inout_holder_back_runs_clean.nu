// maybe_armed_defer_pointing_an_inout_holder_back_runs_clean: a defer armed in an arm points an inout holder back to a literal; the holder is pointed back unconditionally too.
// Control for agora #407: replaying a maybe-armed defer refuses nothing this program does.
// map: §2.10 | A2 | runs-clean | - | agora #407: a defer armed in an arm points an inout holder back to a literal; the holder is pointed back unconditionally too
$ `stdlib/core/string.nu`

: W { s v }

@ fill inout W w i k → i {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    ? > k 0 { ; { = w @ W { `literal from the defer` } } } {}
    = w @ W { `literal` }
    ^ k
}

@ main → i {
    : ~ W w @ W { `start` }
    : i _r ( fill w 1 )
    ( nurl_println . w v )
    ^ 0
}
