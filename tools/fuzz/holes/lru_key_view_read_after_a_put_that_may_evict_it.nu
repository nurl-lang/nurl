// lru_key_view_read_after_a_put_that_may_evict_it: AGORA-877 — a view of an LRU cache's key string, read after an `lru_put` that may evict that key
// Closed: the walk refused it; the ownership engine accepted it until it read the cache's raw bodies itself (lru_put replaces `. c keys` elements).
// Engine before this PR: runs-clean.
// map: §2.10 | A2 | rejected | - | AGORA-877: a view of an LRU key read after a put that may evict it
$ `stdlib/core/string.nu`
$ `stdlib/std/lru.nu`
@ main → i {
    : ( LruCache i ) c ( lru_new [i] 1 )
    : ?i e1 ( lru_put [i] c `a` 1 )
    ?? e1 { T _ → {} F _ → {} }
    ?? ( vec_get [String] . c keys 0 ) {
        T k → {
            : s p ( string_data k )
            : ?i e2 ( lru_put [i] c `b` 2 )
            ?? e2 { T _ → {} F _ → {} }
            ( nurl_print p )
        }
        F _ → {}
    }
    ( lru_free [i] c )
    ^ 0
}
