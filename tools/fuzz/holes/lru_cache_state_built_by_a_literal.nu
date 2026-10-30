// lru_cache_state_built_by_a_literal: `@ ( LruCache i ) { ( string_data k ) … }`: the cache kept its
// three control words behind a raw `s ctl` pointer into its `meta` Vec,
// and a literal pointed it at a one-byte string; every accessor read and
// wrote 24 bytes through it. LruCache is generic, so it cannot be a `raw`
// struct.
// Closed: the words are an LruCtl in a Box, which always holds one and
// cannot be built by a literal. A literal can still box nonsense words
// (here head, tail and count 9999 against empty slot arrays); every slot
// index is checked where it is used, so the cache reads nothing past them.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
// map: §3.3d | B | runs-clean | h500 | `@ ( LruCache i ) { ( string_data k ) … }`: the cache kept its three control words behind a raw `s ctl` pointer into its `meta` Vec, and a literal pointed it at a one-byte string; every accessor…
$ `stdlib/core/box.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/lru.nu`

@ main → i {
    : ( LruCache i ) c @ ( LruCache i ) { ( box_new [LruCtl] @ LruCtl { 9999 9999 9999 } ) 4 ( map_new [s i] ) ( vec_new [String] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) }
    ( nurl_println_int ( lru_len [i] c ) )
    ( lru_put [i] c `a` 1 )
    ( nurl_println_int ( lru_len [i] c ) )
    ^ 0
}
