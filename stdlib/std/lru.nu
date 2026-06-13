// stdlib/std/lru.nu — a fixed-capacity LRU (least-recently-used) cache.
//
// String keys → generic values `[V]`, backed by a HashMap (key → slot)
// plus an intrusive doubly-linked recency list over preallocated slot
// arrays. get / put / contains / remove are all O(1): the map locates
// the slot, the list moves it to the front (MRU) or drops the tail
// (LRU) on overflow. Slots are recycled through a free list, so a cache
// at capacity does no further allocation.
//
//   ( lru_new      [V] i cap )            → ( LruCache V )   cap >= 1
//   ( lru_len      [V] c )                → i
//   ( lru_cap      [V] c )                → i
//   ( lru_is_empty [V] c )                → b
//   ( lru_contains [V] c s key )          → b        (no reorder)
//   ( lru_peek     [V] c s key )          → ?V       borrow, no reorder
//   ( lru_get      [V] c s key )          → ?V       borrow, moves to MRU
//   ( lru_put      [V] c s key V val )    → ?V       displaced value (replaced
//                                                    or evicted), owned; None
//   ( lru_remove   [V] c s key )          → ?V       owned, or None
//   ( lru_each     [V] c f )              → v        f:(@ v s V), MRU→LRU
//   ( lru_free     [V] c )                → v        POD values
//   ( lru_free_with[V] c drop )           → v        drop:(@ v V) each value
//
// The cache OWNS a private copy of each key (duplicated on insert) and
// each value handed to `lru_put`. `lru_get`/`lru_peek` return a BORROW
// of the stored value — do not free it, and treat it as invalid after a
// later `lru_put` that may evict it. For owned value types use
// `lru_free_with` to drop each value on teardown.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hashmap.nu`   // HashMap, map_*, hash_string, eq_string

// ctl is a 3-word scalar block (boxed so mutations survive the value-
// passed struct): [0]=head slot, [1]=tail slot (both -1 when empty),
// [2]=live count. The collections (keys/vals/prev/nxt) are slot-indexed
// arrays of length `cap`; `freelist` is a stack of unused slot indices.
: LruCache [V] {
    s ctl
    i cap
    ( HashMap s i ) index
    ( Vec String ) keys
    ( Vec V ) vals
    ( Vec i ) prev
    ( Vec i ) nxt
    ( Vec i ) freelist
}

@ __lru_head s ctl → i { ^ ( nurl_peek ctl 0 ) }
@ __lru_tail s ctl → i { ^ ( nurl_peek ctl 1 ) }
@ __lru_count s ctl → i { ^ ( nurl_peek ctl 2 ) }
@ __lru_set_head s ctl i v → v { ( nurl_poke ctl 0 v ) }
@ __lru_set_tail s ctl i v → v { ( nurl_poke ctl 1 v ) }
@ __lru_set_count s ctl i v → v { ( nurl_poke ctl 2 v ) }

@ __lru_gi ( Vec i ) v i idx → i {
    ^ ?? ( vec_get [i] v idx ) { T x → x F _ → -1 }
}

// ── index (HashMap) wrappers: the map key is the slot's owned-key
// bytes; hash/eq closures are non-capturing so creating them per call
// does not allocate. ──────────────────────────────────────────────────

@ __lru_idx_get ( HashMap s i ) index s key → ?i {
    : ( @ i s ) hf \ s str → i { ^ ( hash_string str ) }
    : ( @ b s s ) ef \ s a s b → b { ^ ( eq_string a b ) }
    ^ ( map_get [s i] index key hf ef )
}

@ __lru_idx_set ( HashMap s i ) index s key i slot → v {
    : ( @ i s ) hf \ s str → i { ^ ( hash_string str ) }
    : ( @ b s s ) ef \ s a s b → b { ^ ( eq_string a b ) }
    : ?i _old ( map_set [s i] index key slot hf ef )
    ?? _old { T _ → {} F _ → {} }
}

@ __lru_idx_remove ( HashMap s i ) index s key → v {
    : ( @ i s ) hf \ s str → i { ^ ( hash_string str ) }
    : ( @ b s s ) ef \ s a s b → b { ^ ( eq_string a b ) }
    : ?i _old ( map_remove [s i] index key hf ef )
    ?? _old { T _ → {} F _ → {} }
}

// ── intrusive list ────────────────────────────────────────────────────

@ __lru_detach [V] ( LruCache V ) c i slot → v {
    : s ctl . c ctl
    : i p ( __lru_gi . c prev slot )
    : i n ( __lru_gi . c nxt slot )
    ? >= p 0 { : b _a ( vec_set [i] . c nxt p n ) {} } { ( __lru_set_head ctl n ) }
    ? >= n 0 { : b _b ( vec_set [i] . c prev n p ) {} } { ( __lru_set_tail ctl p ) }
}

@ __lru_push_front [V] ( LruCache V ) c i slot → v {
    : s ctl . c ctl
    : i h ( __lru_head ctl )
    : b _a ( vec_set [i] . c prev slot -1 )
    : b _b ( vec_set [i] . c nxt slot h )
    ? >= h 0 { : b _c ( vec_set [i] . c prev h slot ) {} } {}
    ( __lru_set_head ctl slot )
    ? < ( __lru_tail ctl ) 0 { ( __lru_set_tail ctl slot ) } {}
}

@ __lru_touch [V] ( LruCache V ) c i slot → v {
    ? == ( __lru_head . c ctl ) slot {} {
        ( __lru_detach [V] c slot )
        ( __lru_push_front [V] c slot )
    }
}

// ── construction / inspection ─────────────────────────────────────────

@ lru_new [V] i cap → ( LruCache V ) {
    : i c ? > cap 0 cap 1
    : s ctl ( nurl_zalloc 24 )
    ( nurl_poke ctl 0 -1 )
    ( nurl_poke ctl 1 -1 )
    ( nurl_poke ctl 2 0 )
    : ( Vec String ) keys ( vec_with_cap [String] c )
    : ( Vec V ) vals ( vec_with_cap [V] c )
    : ( Vec i ) prev ( vec_with_cap [i] c )
    : ( Vec i ) nxt ( vec_with_cap [i] c )
    : b _k ( vec_set_len [String] keys c )
    : b _v ( vec_set_len [V] vals c )
    : b _p ( vec_set_len [i] prev c )
    : b _n ( vec_set_len [i] nxt c )
    : ( Vec i ) fl ( vec_with_cap [i] c )
    : ~ i k 0
    ~ < k c { ( vec_push [i] fl k ) = k + k 1 }
    : ( HashMap s i ) index ( map_new [s i] )
    ^ @ ( LruCache V ) { ctl c index keys vals prev nxt fl }
}

@ lru_len [V] ( LruCache V ) c → i { ^ ( __lru_count . c ctl ) }
@ lru_cap [V] ( LruCache V ) c → i { ^ . c cap }
@ lru_is_empty [V] ( LruCache V ) c → b { ^ == ( __lru_count . c ctl ) 0 }

@ lru_contains [V] ( LruCache V ) c s key → b {
    ^ ?? ( __lru_idx_get . c index key ) { T _ → T F _ → F }
}

@ lru_peek [V] ( LruCache V ) c s key → ?V {
    ^ ?? ( __lru_idx_get . c index key ) {
        T slot → ( vec_get [V] . c vals slot )
        F _ → @ ?V { F }
    }
}

@ lru_get [V] ( LruCache V ) c s key → ?V {
    ^ ?? ( __lru_idx_get . c index key ) {
        T slot → {
            ( __lru_touch [V] c slot )
            ( vec_get [V] . c vals slot )
        }
        F _ → @ ?V { F }
    }
}

// Insert a brand-new key: evict the LRU entry first if at capacity,
// then claim a free slot. Returns the evicted value (owned) or None.
@ __lru_insert_new [V] ( LruCache V ) c s key V val → ?V {
    : s ctl . c ctl
    : ~ ?V evicted @ ?V { F }
    ? >= ( __lru_count ctl ) . c cap {
        : i t ( __lru_tail ctl )
        ? >= t 0 {
            ?? ( vec_get [String] . c keys t ) {
                T tkey → { ( __lru_idx_remove . c index ( string_data tkey ) ) ( string_free tkey ) }
                F _ → {}
            }
            ?? ( vec_get [V] . c vals t ) { T tv → { = evicted @ ?V { T tv } } F _ → {} }
            ( __lru_detach [V] c t )
            ( vec_push [i] . c freelist t )
            ( __lru_set_count ctl - ( __lru_count ctl ) 1 )
        } {}
    } {}
    : i sl ?? ( vec_pop [i] . c freelist ) { T fs → fs F _ → -1 }
    ? >= sl 0 {
        : String kc ( string_from key )
        : b _sk ( vec_set [String] . c keys sl kc )
        : b _sv ( vec_set [V] . c vals sl val )
        ( __lru_idx_set . c index ( string_data kc ) sl )
        ( __lru_push_front [V] c sl )
        ( __lru_set_count ctl + ( __lru_count ctl ) 1 )
    } {}
    ^ evicted
}

@ lru_put [V] ( LruCache V ) c s key V val → ?V {
    ^ ?? ( __lru_idx_get . c index key ) {
        T slot → {
            : ?V old ( vec_get [V] . c vals slot )
            : b _s ( vec_set [V] . c vals slot val )
            ( __lru_touch [V] c slot )
            old
        }
        F _ → ( __lru_insert_new [V] c key val )
    }
}

@ lru_remove [V] ( LruCache V ) c s key → ?V {
    : s ctl . c ctl
    ^ ?? ( __lru_idx_get . c index key ) {
        T slot → {
            ?? ( vec_get [String] . c keys slot ) {
                T k → { ( __lru_idx_remove . c index ( string_data k ) ) ( string_free k ) }
                F _ → {}
            }
            : ?V val ( vec_get [V] . c vals slot )
            ( __lru_detach [V] c slot )
            ( vec_push [i] . c freelist slot )
            ( __lru_set_count ctl - ( __lru_count ctl ) 1 )
            val
        }
        F _ → @ ?V { F }
    }
}

// Visit live entries most-recent first.
@ lru_each [V] ( LruCache V ) c ( @ v s V ) f → v {
    : ~ i cur ( __lru_head . c ctl )
    ~ >= cur 0 {
        : i nextc ( __lru_gi . c nxt cur )
        ?? ( vec_get [String] . c keys cur ) {
            T k → {
                ?? ( vec_get [V] . c vals cur ) { T v → ( f ( string_data k ) v ) F _ → {} }
            }
            F _ → {}
        }
        = cur nextc
    }
}

@ __lru_free_keys [V] ( LruCache V ) c → v {
    : ~ i cur ( __lru_head . c ctl )
    ~ >= cur 0 {
        : i nx ( __lru_gi . c nxt cur )
        ?? ( vec_get [String] . c keys cur ) { T k → ( string_free k ) F _ → {} }
        = cur nx
    }
}

@ __lru_free_arrays [V] ( LruCache V ) c → v {
    ( vec_free [String] . c keys )
    ( vec_free [V] . c vals )
    ( vec_free [i] . c prev )
    ( vec_free [i] . c nxt )
    ( vec_free [i] . c freelist )
    ( map_free [s i] . c index )
    ( nurl_free . c ctl )
}

@ lru_free [V] ( LruCache V ) c → v {
    ( __lru_free_keys [V] c )
    ( __lru_free_arrays [V] c )
}

@ lru_free_with [V] ( LruCache V ) c ( @ v V ) drop → v {
    : ~ i cur ( __lru_head . c ctl )
    ~ >= cur 0 {
        : i nx ( __lru_gi . c nxt cur )
        ?? ( vec_get [String] . c keys cur ) { T k → ( string_free k ) F _ → {} }
        ?? ( vec_get [V] . c vals cur ) { T v → ( drop v ) F _ → {} }
        = cur nx
    }
    ( __lru_free_arrays [V] c )
}
