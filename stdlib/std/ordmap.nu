// stdlib/std/ordmap.nu — owned generic ordered map (sorted-array backed)
//
// A key→value map that keeps its keys in sorted order, so iteration is
// ordered and range/min/max queries are cheap. Backed by two parallel
// ( Vec K ) / ( Vec V ) arrays kept in lock-step; lookup is O(log n)
// binary search, insert/remove are O(n) (the shift), and ordered
// iteration is O(1) per step. This is the "flat map" shape — simpler
// and more cache-friendly than a B-tree for small/medium maps; swap the
// backing for a B-tree later if O(log n) writes become the bottleneck.
//
// Ordering is decided by a key comparator `cmp : (@ i K K)` passed to
// every keyed call (same convention as sort_by / hashmap's hash_fn):
// `cmp a b` returns < 0 / 0 / > 0. Use the SAME comparator for a map's
// whole lifetime.
//
//   ( ordmap_new       [K V] )              → ( OrdMap K V )
//   ( ordmap_len       [K V] m )            → i
//   ( ordmap_is_empty  [K V] m )            → b
//   ( ordmap_get       [K V] m k cmp )      → ? V
//   ( ordmap_set       [K V] m k v cmp )    → ? V   Some(prev) on replace
//   ( ordmap_remove    [K V] m k cmp )      → ? V   Some(val) if removed
//   ( ordmap_contains  [K V] m k cmp )      → b
//   ( ordmap_key_at    [K V] m i )          → ? K   i-th smallest key
//   ( ordmap_val_at    [K V] m i )          → ? V   its value
//   ( ordmap_min_key   [K V] m )            → ? K
//   ( ordmap_max_key   [K V] m )            → ? K
//   ( ordmap_free      [K V] m )            → v     trivial K/V
//   ( ordmap_free_with [K V] m dk dv )      → v     dk:(@ v K) dv:(@ v V)
//
// Ownership: mirrors Vec/HashMap. On ordmap_set REPLACE, the existing
// equal key is kept and the passed-in `k` is NOT stored — for owned
// keys the caller still owns that `k`. ordmap_remove returns the value;
// for owned-key maps prefer bulk teardown via ordmap_free_with.

$ `stdlib/core/vec.nu`

: OrdMap [K V] { ( Vec K ) keys ( Vec V ) vals }

// Smallest index `i` with keys[i] >= k (lower bound). Equals len when
// k is greater than every key. The insertion point for k.
@ __om_lb [K V] ( Vec K ) keys K k ( @ i K K ) cmp → i {
    : i n ( vec_len [K] keys )
    : ~ i lo 0
    : ~ i hi n
    ~ < lo hi {
        : i mid / + lo hi 2
        : ?K kmo ( vec_get [K] keys mid )
        : K km ?? kmo { T x → x F → k }
        ? < ( cmp km k ) 0 { = lo + mid 1 } { = hi mid }
    }
    ^ lo
}

@ ordmap_new [K V] → ( OrdMap K V ) {
    ^ @ ( OrdMap K V ) { ( vec_new [K] ) ( vec_new [V] ) }
}

@ ordmap_len [K V] ( OrdMap K V ) m → i {
    ^ ( vec_len [K] . m keys )
}

@ ordmap_is_empty [K V] ( OrdMap K V ) m → b {
    ^ == ( vec_len [K] . m keys ) 0
}

@ ordmap_get [K V] ( OrdMap K V ) m K k ( @ i K K ) cmp → ?V {
    : i idx ( __om_lb [K V] . m keys k cmp )
    : i n ( vec_len [K] . m keys )
    ? >= idx n { ^ @ ?V { F # V 0 } } {}
    : ?K kmo ( vec_get [K] . m keys idx )
    : K km ?? kmo { T x → x F → k }
    ? == ( cmp km k ) 0 { ^ ( vec_get [V] . m vals idx ) } {}
    ^ @ ?V { F # V 0 }
}

@ ordmap_contains [K V] ( OrdMap K V ) m K k ( @ i K K ) cmp → b {
    ^ ?? ( ordmap_get [K V] m k cmp ) { T _ → T F → F }
}

@ ordmap_set [K V] ( OrdMap K V ) m K k V val ( @ i K K ) cmp → ?V {
    : i idx ( __om_lb [K V] . m keys k cmp )
    : i n ( vec_len [K] . m keys )
    ? < idx n {
        : ?K kmo ( vec_get [K] . m keys idx )
        : K km ?? kmo { T x → x F → k }
        ? == ( cmp km k ) 0 {
            : ?V oldo ( vec_get [V] . m vals idx )
            ( vec_set [V] . m vals idx val )
            ^ oldo
        } {}
    } {}
    ( vec_insert [K] . m keys idx k )
    ( vec_insert [V] . m vals idx val )
    ^ @ ?V { F # V 0 }
}

@ ordmap_remove [K V] ( OrdMap K V ) m K k ( @ i K K ) cmp → ?V {
    : i idx ( __om_lb [K V] . m keys k cmp )
    : i n ( vec_len [K] . m keys )
    ? >= idx n { ^ @ ?V { F # V 0 } } {}
    : ?K kmo ( vec_get [K] . m keys idx )
    : K km ?? kmo { T x → x F → k }
    ? == ( cmp km k ) 0 {
        ( vec_remove [K] . m keys idx )
        ^ ( vec_remove [V] . m vals idx )
    } {}
    ^ @ ?V { F # V 0 }
}

@ ordmap_key_at [K V] ( OrdMap K V ) m i idx → ?K {
    ^ ( vec_get [K] . m keys idx )
}

@ ordmap_val_at [K V] ( OrdMap K V ) m i idx → ?V {
    ^ ( vec_get [V] . m vals idx )
}

@ ordmap_min_key [K V] ( OrdMap K V ) m → ?K {
    ^ ( vec_get [K] . m keys 0 )
}

@ ordmap_max_key [K V] ( OrdMap K V ) m → ?K {
    : i n ( vec_len [K] . m keys )
    ? == n 0 { ^ @ ?K { F # K 0 } } {}
    ^ ( vec_get [K] . m keys - n 1 )
}

@ ordmap_free [K V] ( OrdMap K V ) m → v {
    ( vec_free [K] . m keys )
    ( vec_free [V] . m vals )
}

@ ordmap_free_with [K V] ( OrdMap K V ) m ( @ v K ) dk ( @ v V ) dv → v {
    ( vec_free_with [K] . m keys dk )
    ( vec_free_with [V] . m vals dv )
}
