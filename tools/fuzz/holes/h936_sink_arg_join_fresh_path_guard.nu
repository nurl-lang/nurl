// H936_SINK_ARG_JOIN_FRESH_PATH_GUARD: the sink join taking its fresh arm: owned, moved, nothing copied or leaked (sink_arg_join_fresh_path_guard).
// Closed: A `?` / `??` handed to a `sink` parameter — bare or a block's tail — is copied on the paths where its published ownership (`__last_join_own__`) says an arm lent; one that cannot be copied is rejected (gen_call's sink-argument checks).
// main: accepted and ran clean (kept as a guard).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { String s }
: H { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ slen String t → i { ^ ( string_len t ) }

@ keep sink String t → i { ^ ( string_len t ) }

@ main → i {
    : b c F
    : W w ( mkw )
    ( nurl_println_int ( keep ? c ( gets w ) ( string_from `x` ) ) )
    ^ 0
}
