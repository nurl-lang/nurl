// lru_get_value_released: h311 through the standard library: `lru_get` returns the cached value from a `??` arm, so its result was taken for the caller's own — releasing it freed the value the cache still held, and the next `lru_get` read it. Its doc comment said "do not free it".
// Closed: as h311 — `lru_get` / `lru_peek` lend the cache.
// main (before this PR): AddressSanitizer reported heap-use-after-free on the second lru_get.
// map: §7.6 | A2 | rejected | h313 | h311 through lru_get: releasing the cached value freed what the cache held
$ `stdlib/std/lru.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( LruCache String ) c ( lru_new [String] 2 )
    ( lru_put [String] c `a` ( string_from `alpha` ) )
    ?? ( lru_get [String] c `a` ) { T v → { ( string_free v ) } F → {} }
    ?? ( lru_get [String] c `a` ) { T v → { ( nurl_println ( string_data v ) ) } F → {} }
    ^ 0
}
