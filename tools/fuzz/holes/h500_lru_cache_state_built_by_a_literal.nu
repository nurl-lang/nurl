// H500: `@ ( LruCache i ) { ( string_data k ) … }`: the cache kept its
// three control words behind a raw `s ctl` pointer into its `meta` Vec,
// and a literal pointed it at a one-byte string; every accessor read and
// wrote 24 bytes through it. LruCache is generic, so it cannot be a `raw`
// struct.
// Closed: each operation takes the words' address from `meta` after
// checking that it holds three (a literal with a shorter `meta` panics).
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/lru.nu`

@ main → i {
    : ( LruCache i ) c @ ( LruCache i ) { ( vec_new [i] ) 4 ( map_new [s i] ) ( vec_new [String] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) }
    ( nurl_println_int ( lru_len [i] c ) )
    ( lru_put [i] c `a` 1 )
    ( nurl_println_int ( lru_len [i] c ) )
    ^ 0
}
