// map_iterator_outlives_its_map: an iterator over a HashMap (`map_iter`) called after the map was released read its freed control block. The iterator captured a raw pointer to the block, not the map, so no summary said it borrows the map; its own doc comment asked the caller not to do this.
// Closed: `map_iter` captures the map handle and reads the block on each call, so its result holds a view of the map (h299); releasing, replacing or changing the map while the iterator is still used is rejected.
// main (before this PR): AddressSanitizer reported heap-use-after-free reading the map's control block.
// map: §2.11 | A2 | rejected | h301 | map_iter captured a raw pointer to the map's control block: called after the map was released (UAF)
$ `stdlib/std/hashmap.nu`

@ main → i {
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i a i b → b { ^ ( eq_int a b ) }
    : ( HashMap i i ) m ( map_new [i i] )
    ( map_set [i i] m 1 10 hi ei )
    : ( @ ?( Pair i i ) i ) it ( map_iter [i i] m )
    ( map_free [i i] m )
    : ?( Pair i i ) g ( it 0 )
    ?? g {
        T p → { ( nurl_println_int ( pair_second [i i] p ) ) }
        F → { ( nurl_println `none` ) }
    }
    ^ 0
}
