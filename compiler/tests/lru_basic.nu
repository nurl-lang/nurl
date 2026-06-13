// lru_basic.nu — std/lru.nu acceptance.
//
// Exercises eviction order (LRU dropped first), get-as-touch (a fetched
// key survives the next eviction), replace-returns-old, remove, the
// MRU→LRU each walk, and — with owned String values — the
// lru_free_with drop discipline (ASan/LSan confirm no leak).

$ `stdlib/core/string.nu`
$ `stdlib/std/lru.nu`

@ mkstr s raw → String {
    : String s ( string_with_cap 4 )
    ( string_push_str s raw )
    ^ s
}

@ getshow s label ( LruCache i ) c s key → v {
    ( nurl_print label ) ( nurl_print `=` )
    ?? ( lru_get [i] c key ) { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `MISS` ) }
    ( nurl_print `\n` )
}

@ main → i {
    : ( LruCache i ) c ( lru_new [i] 3 )
    ( nurl_print `cap=` ) ( nurl_print ( nurl_str_int ( lru_cap [i] c ) ) )
    ( nurl_print ` empty=` ) ( nurl_print ? ( lru_is_empty [i] c ) `T` `F` ) ( nurl_print `\n` )

    // fill to capacity
    : ?i e1 ( lru_put [i] c `a` 1 )
    : ?i e2 ( lru_put [i] c `b` 2 )
    : ?i e3 ( lru_put [i] c `c` 3 )
    ?? e1 { T _ → ( nurl_print `bug1\n` ) F _ → {} }
    ?? e2 { T _ → ( nurl_print `bug2\n` ) F _ → {} }
    ?? e3 { T _ → ( nurl_print `bug3\n` ) F _ → {} }
    ( nurl_print `len=` ) ( nurl_print ( nurl_str_int ( lru_len [i] c ) ) ) ( nurl_print `\n` )

    // touch `a` so `b` becomes the LRU victim
    ( getshow `touch_a` c `a` )

    // insert `d` → evicts `b` (the least-recently-used), returns 2
    : ?i ev ( lru_put [i] c `d` 4 )
    ( nurl_print `evicted=` )
    ?? ev { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `none` ) } ( nurl_print `\n` )
    ( nurl_print `has_b=` ) ( nurl_print ? ( lru_contains [i] c `b` ) `T` `F` )
    ( nurl_print ` has_a=` ) ( nurl_print ? ( lru_contains [i] c `a` ) `T` `F` )
    ( nurl_print ` has_d=` ) ( nurl_print ? ( lru_contains [i] c `d` ) `T` `F` ) ( nurl_print `\n` )

    // peek `c` (LRU now) must NOT reorder, so inserting `e` evicts `c`
    ( nurl_print `peek_c=` )
    ?? ( lru_peek [i] c `c` ) { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `MISS` ) } ( nurl_print `\n` )
    : ?i ev2 ( lru_put [i] c `e` 5 )
    ( nurl_print `evicted2=` )
    ?? ev2 { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `none` ) } ( nurl_print `\n` )

    // replace existing key returns old value, no eviction
    : ?i old ( lru_put [i] c `d` 40 )
    ( nurl_print `replace_d_old=` )
    ?? old { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `none` ) } ( nurl_print `\n` )
    ( getshow `d_now` c `d` )
    ( nurl_print `len=` ) ( nurl_print ( nurl_str_int ( lru_len [i] c ) ) ) ( nurl_print `\n` )

    // remove
    : ?i rm ( lru_remove [i] c `a` )
    ( nurl_print `remove_a=` )
    ?? rm { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `none` ) }
    ( nurl_print ` has_a=` ) ( nurl_print ? ( lru_contains [i] c `a` ) `T` `F` )
    ( nurl_print ` len=` ) ( nurl_print ( nurl_str_int ( lru_len [i] c ) ) ) ( nurl_print `\n` )
    : ?i rm2 ( lru_remove [i] c `zzz` )
    ( nurl_print `remove_missing=` )
    ?? rm2 { T _ → ( nurl_print `FOUND(bug)` ) F _ → ( nurl_print `none` ) } ( nurl_print `\n` )

    // each MRU→LRU
    ( nurl_print `order=` )
    : ( @ v s i ) pr \ s k i v → v { ( nurl_print k ) ( nurl_print `:` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print ` ` ) }
    ( lru_each [i] c pr )
    ( nurl_print `\n` )
    ( lru_free [i] c )

    // ── owned-value path: lru_free_with must drop every String ──
    : ( LruCache String ) sc ( lru_new [String] 2 )
    : ?String s1 ( lru_put [String] sc `x` ( mkstr `xv` ) )
    ?? s1 { T sv → ( string_free sv ) F _ → {} }
    : ?String s2 ( lru_put [String] sc `y` ( mkstr `yv` ) )
    ?? s2 { T sv → ( string_free sv ) F _ → {} }
    // a 3rd insert evicts `x`; its value String comes back owned → free it
    : ?String s3 ( lru_put [String] sc `z` ( mkstr `zv` ) )
    ?? s3 { T sv → { ( nurl_print `evicted_val=` ) ( nurl_print ( string_data sv ) ) ( nurl_print `\n` ) ( string_free sv ) } F _ → {} }
    : ( @ v String ) dropf \ String s → v { ( string_free s ) }
    ( lru_free_with [String] sc dropf )
    ^ 0
}
