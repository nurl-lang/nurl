// lru_value_read_after_eviction: a value `lru_get` lent, read after an `lru_put` that evicted it (a one-entry cache): the eviction released the value under the reader. Its doc comment said "treat it as invalid after a later lru_put that may evict it".
// Closed: as h311 — the value borrows from the cache, and `lru_put` (which may drop what the cache holds) ends the borrow. The scrutinee's own call (`lru_get` reorders the cache) no longer ends the borrow of the payload it lent: its pending rows precede the arms (gen_match).
// main (before this PR): AddressSanitizer reported heap-use-after-free printing the value.
// map: §2.10 | A2 | rejected | h314 | a value lru_get lent, read after an lru_put that evicted it
$ `stdlib/std/lru.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( LruCache String ) c ( lru_new [String] 1 )
    ( lru_put [String] c `a` ( string_from `alpha` ) )
    ?? ( lru_get [String] c `a` ) {
        T v → {
            ( lru_put [String] c `b` ( string_from `bravo` ) )
            ( nurl_println ( string_data v ) )
        }
        F → {}
    }
    ^ 0
}
