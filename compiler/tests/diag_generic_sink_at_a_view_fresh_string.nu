// A generic's `sink A` made at a raw string takes over nothing (AGORA-1028),
// so a fresh string handed straight to one would be owned by nothing: the
// `( Pair s i )` views it, and no one releases it. Refused, as a fresh string
// handed to `vec_push [s]` is. (Before the fix, the callee took it over and
// stored it in the Pair, which never released it: a leak.) The bound
// spelling is the migration, accepted in
// generic_sink_at_a_view_takes_nothing.nu.
$ `stdlib/core/pair.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Pair i i ) p0 ( pair_new [i i] 1 2 )
    : ( Pair s i ) p ( pair_new [s i] ( nurl_str_cat `a` `b` ) 1 )
    ( nurl_println ( pair_first [s i] p ) )
    ^ - ( pair_first [i i] p0 ) 1
}
