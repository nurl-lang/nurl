// stdlib/std/hashmap.nu — owned generic HashMap[K V]
//
// Open addressing + linear probing. The handle ( HashMap K V ) wraps an
// opaque heap-allocated control block; mutations go through the heap
// pointer so the caller's handle stays valid across resizes (mirroring
// Vec[A] and String).
//
// NURL has no type-class dispatch, so hash and equality are passed as
// closure arguments to every operation that needs them. The standard
// hash + eq functions for `s` (raw string) and `i` keys live below.
//
// Control block layout (heap, 48 bytes = 6 × i64), addressed via
// nurl_peek/poke as raw i64 words:
//   word 0: keys ptr   (raw i8*; bitcast to *K when accessing)
//   word 1: vals ptr   (raw i8*; bitcast to *V)
//   word 2: states ptr (raw i8*; bitcast to *i; per-slot 0=empty/1=occupied/2=tombstone)
//   word 3: len        (occupied count, NOT counting tombstones)
//   word 4: cap        (always power-of-two; 0 means no buffer yet)
//   word 5: tombstones (count of slots in tombstone state)
//
// Resize policy:
//   First insert allocates cap=8.
//   Resize when (len + tombstones + 1) * 4 ≥ cap * 3   (≈75% load factor).
//   Resize doubles cap and rehashes only OCCUPIED slots — tombstones evaporate.
//
// Ownership:
//   map_new / map_with_cap → owned HashMap; caller MUST map_free when done.
//   The map borrows keys and values (it stores them by value/copy).
//   For HashMap[s V] (raw-string keys) the caller is responsible for
//   keeping the key strings alive until removed; the map does NOT strdup.
//   Same convention as Vec[A].
//
// API:
//   ( map_new        [K V] )                                     → ( HashMap K V )
//   ( map_with_cap   [K V] n hash_fn )                           → ( HashMap K V )
//   ( map_len        [K V] m )                                   → i
//   ( map_cap        [K V] m )                                   → i
//   ( map_is_empty   [K V] m )                                   → b
//   ( map_get        [K V] m k hash_fn eq_fn )                   → ? V
//   ( map_set        [K V] m k v hash_fn eq_fn )                 → ? V    (Some(prev) on replace)
//   ( map_remove     [K V] m k hash_fn eq_fn )                   → ? V
//   ( map_contains   [K V] m k hash_fn eq_fn )                   → b
//   ( map_each       [K V] m f )           f : (@ v K V)         → v
//   ( map_fold       [K V B] m init f )    f : (@ B B K V)       → B
//   ( map_keys       [K V] m )                                   → ( Vec K )
//   ( map_values     [K V] m )                                   → ( Vec V )
//   ( map_iter       [K V] m )                                   → ( Iter ( Pair K V ) )
//   ( map_free       [K V] m )                                   → v
//   ( map_clone      [K V] m )                  → ( HashMap K V )  bitwise — trivial K/V
//   ( map_clone_with [K V] m clone_k clone_v )  → ( HashMap K V )  deep copy
//
// map_keys / map_values walk occupied slots and bitwise-copy keys/values
// into a fresh Vec. Trivial element types only — for owned keys/values
// (e.g. HashMap[String i]) the result aliases the map's storage; iterate
// with map_each and clone each key explicitly instead. To duplicate a
// whole owned-key/value map use `map_clone_with` with per-key/value
// clone closures.
//
// Stock hash + eq:
//   ( hash_string s )      → i        djb2-style hash over bytes
//   ( eq_string a b )      → b        content equality (nurl_str_eq)
//   ( hash_int x )         → i        Knuth multiplicative hash
//   ( eq_int a b )         → b        ==

$ `stdlib/core/mem.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/pair.nu`
$ `stdlib/core/string.nu`

: HashMap [K V] { s ctl }

// ── Stock hash + eq for common key types ────────────────────────────

@ hash_string s str → i {
    : i n ( nurl_str_len str )
    : ~ i h 5381
    : ~ i i 0
    ~ < i n {
        = h + * h 33 ( nurl_str_get str i )
        = i + i 1
    }
    ^ h
}

@ eq_string s a s b → b {
    ^ ? != 0 ( nurl_str_eq a b ) T F
}

@ hash_int i x → i {
    ^ * x 2654435761
}

@ eq_int i a i b → b {
    ^ == a b
}

// ── Internal helpers ────────────────────────────────────────────────

@ __map_keys_raw s ctl → s { ^ # s ( nurl_peek ctl 0 ) }

@ __map_vals_raw s ctl → s { ^ # s ( nurl_peek ctl 1 ) }

@ __map_states_raw s ctl → s { ^ # s ( nurl_peek ctl 2 ) }

@ __map_len_raw s ctl → i { ^ ( nurl_peek ctl 3 ) }

@ __map_cap_raw s ctl → i { ^ ( nurl_peek ctl 4 ) }

@ __map_tomb_raw s ctl → i { ^ ( nurl_peek ctl 5 ) }

// __map_alloc_buffers: allocate keys/vals/states arrays for `cap` slots
// and store the raw i8* pointers into ctl[0..2]. States are zalloc'd so
// every slot starts empty (state == 0). Also writes cap into word 4.
@ __map_alloc_buffers [K V] s ctl i cap → v {
    : s keys ( nurl_zalloc * Z K cap )
    : s vals ( nurl_zalloc * Z V cap )
    : s states ( nurl_zalloc * 8 cap )
    ( nurl_poke ctl 0 # i keys )
    ( nurl_poke ctl 1 # i vals )
    ( nurl_poke ctl 2 # i states )
    ( nurl_poke ctl 4 cap )
}

// __map_probe_for: linear-probe scan starting at hash & mask.
//   On match    → returns slot index (>= 0).
//   On miss     → returns -(insert_idx + 1)   (always < 0)
//                 Caller decodes via   insert_idx = - slot - 1.
//   Pre-condition: cap > 0 (caller must check / lazily allocate).
//   The map_set caller resizes proactively before probing, so this loop
//   always finds either a match, an empty slot, or a tombstone within
//   cap iterations; the "table full" case never occurs in practice.
@ __map_probe_for [K V] s ctl K key ( @ i K ) hash_fn ( @ b K K ) eq_fn → i {
    : i cap ( __map_cap_raw ctl )
    : i mask - cap 1
    : i h ( hash_fn key )
    : i start & h mask
    : *K keys # *K ( nurl_peek ctl 0 )
    : *i states # *i ( nurl_peek ctl 2 )
    : ~ i first_free -1
    : ~ i probe 0
    : ~ i result -1
    : ~ b done F
    ~ & ! done < probe cap {
        : i idx & + start probe mask
        : i st . states idx
        ? == st 0
        { ? < first_free 0 { = first_free idx } {}
            = done T
        }
        { ? == st 1
            { : K k . keys idx
                ? ( eq_fn k key )
                { = result idx
                    = done T
                }
                {}
            }
            { ? < first_free 0 { = first_free idx } {} }
        }
        = probe + probe 1
    }
    ? >= result 0
    { ^ result }
    { ? >= first_free 0
        { ^ - -1 first_free }
        { ^ -1 }
    }
}

// __map_grow: rehash into a buffer with `target_cap` (rounded up to a
// power of two ≥ 8 ≥ target). Tombstones are dropped during rehash.
@ __map_grow [K V] s ctl i target_cap ( @ i K ) hash_fn → v {
    : i old_cap ( __map_cap_raw ctl )
    : ~ i new_cap ? > old_cap 0 old_cap 8
    ~ < new_cap target_cap { = new_cap * new_cap 2 }
    // Snapshot old buffers (raw i8* + typed views).
    : s old_keys_raw ( __map_keys_raw ctl )
    : s old_vals_raw ( __map_vals_raw ctl )
    : s old_states_raw ( __map_states_raw ctl )
    : *K old_keys # *K old_keys_raw
    : *V old_vals # *V old_vals_raw
    : *i old_states # *i old_states_raw
    // Allocate fresh buffers; reset len + tombstones.
    ( __map_alloc_buffers [K V] ctl new_cap )
    ( nurl_poke ctl 3 0 )
    ( nurl_poke ctl 5 0 )
    : i mask - new_cap 1
    : *K new_keys # *K ( nurl_peek ctl 0 )
    : *V new_vals # *V ( nurl_peek ctl 1 )
    : *i new_states # *i ( nurl_peek ctl 2 )
    : ~ i new_len 0
    : ~ i i 0
    ~ < i old_cap {
        ? == . old_states i 1 {
            : K k . old_keys i
            : V v . old_vals i
            : i h ( hash_fn k )
            : ~ i idx & h mask
            ~ != . new_states idx 0 { = idx & + idx 1 mask }
            = . new_keys idx k
            = . new_vals idx v
            = . new_states idx 1
            = new_len + new_len 1
        } {}
        = i + i 1
    }
    ( nurl_poke ctl 3 new_len )
    // Free old buffers if any existed.
    ? != 0 # i old_keys_raw { ( nurl_free old_keys_raw ) } {}
    ? != 0 # i old_vals_raw { ( nurl_free old_vals_raw ) } {}
    ? != 0 # i old_states_raw { ( nurl_free old_states_raw ) } {}
}

// ── Constructors ────────────────────────────────────────────────────

@ map_new [K V] → ( HashMap K V ) {
    : s ctl ( nurl_zalloc 48 )
    ^ @ ( HashMap K V ) { ctl }
}

@ map_with_cap [K V] i n ( @ i K ) hash_fn → ( HashMap K V ) {
    : s ctl ( nurl_zalloc 48 )
    : i want ? > n 0 n 0
    ? > want 0 { ( __map_grow [K V] ctl want hash_fn ) } {}
    ^ @ ( HashMap K V ) { ctl }
}

// ── Inspectors ──────────────────────────────────────────────────────

@ map_len [K V] ( HashMap K V ) m → i {
    ^ ( __map_len_raw . m ctl )
}

@ map_cap [K V] ( HashMap K V ) m → i {
    ^ ( __map_cap_raw . m ctl )
}

@ map_is_empty [K V] ( HashMap K V ) m → b {
    ^ == ( __map_len_raw . m ctl ) 0
}

// ── Lookup ──────────────────────────────────────────────────────────

@ map_get [K V] ( HashMap K V ) m K key ( @ i K ) hash_fn ( @ b K K ) eq_fn → ?V {
    : s ctl . m ctl
    ? == ( __map_cap_raw ctl ) 0
    { ^ @ ?V { F # V 0 } }
    {}
    : i slot ( __map_probe_for [K V] ctl key hash_fn eq_fn )
    ? < slot 0
    { ^ @ ?V { F # V 0 } }
    {}
    : *V vals # *V ( nurl_peek ctl 1 )
    ^ @ ?V { T . vals slot }
}

@ map_contains [K V] ( HashMap K V ) m K key ( @ i K ) hash_fn ( @ b K K ) eq_fn → b {
    : s ctl . m ctl
    ? == ( __map_cap_raw ctl ) 0
    { ^ F }
    {}
    : i slot ( __map_probe_for [K V] ctl key hash_fn eq_fn )
    ^ >= slot 0
}

// ── Mutation ────────────────────────────────────────────────────────

@ map_set [K V] ( HashMap K V ) m K key V val ( @ i K ) hash_fn ( @ b K K ) eq_fn → ?V {
    : s ctl . m ctl
    // Lazy first allocation.
    ? == ( __map_cap_raw ctl ) 0
    { ( __map_grow [K V] ctl 8 hash_fn ) }
    {}
    // Resize if (len + tomb + 1) * 4 ≥ cap * 3 (≈75% load factor).
    : i len0 ( __map_len_raw ctl )
    : i tomb0 ( __map_tomb_raw ctl )
    : i cap0 ( __map_cap_raw ctl )
    ? >= * + + len0 tomb0 1 4 * cap0 3
    { ( __map_grow [K V] ctl * cap0 2 hash_fn ) }
    {}

    // Probe in (possibly resized) table.
    : i slot ( __map_probe_for [K V] ctl key hash_fn eq_fn )
    : *K keys # *K ( nurl_peek ctl 0 )
    : *V vals # *V ( nurl_peek ctl 1 )
    : *i states # *i ( nurl_peek ctl 2 )
    ? >= slot 0
    { : V prev . vals slot
        = . vals slot val
        ^ @ ?V { T prev }
    }
    { : i ins - -1 slot
        : i st_old . states ins
        = . keys ins key
        = . vals ins val
        = . states ins 1
        ( nurl_poke ctl 3 + ( __map_len_raw ctl ) 1 )
        ? == st_old 2
        { ( nurl_poke ctl 5 - ( __map_tomb_raw ctl ) 1 ) }
        {}
        ^ @ ?V { F # V 0 }
    }
}

@ map_remove [K V] ( HashMap K V ) m K key ( @ i K ) hash_fn ( @ b K K ) eq_fn → ?V {
    : s ctl . m ctl
    ? == ( __map_cap_raw ctl ) 0
    { ^ @ ?V { F # V 0 } }
    {}
    : i slot ( __map_probe_for [K V] ctl key hash_fn eq_fn )
    ? < slot 0
    { ^ @ ?V { F # V 0 } }
    {}
    : *V vals # *V ( nurl_peek ctl 1 )
    : *i states # *i ( nurl_peek ctl 2 )
    : V prev . vals slot
    = . states slot 2
    ( nurl_poke ctl 3 - ( __map_len_raw ctl ) 1 )
    ( nurl_poke ctl 5 + ( __map_tomb_raw ctl ) 1 )
    ^ @ ?V { T prev }
}

// ── Cleanup ─────────────────────────────────────────────────────────

@ map_free [K V] ( HashMap K V ) m → v {
    : s ctl . m ctl
    : s keys ( __map_keys_raw ctl )
    : s vals ( __map_vals_raw ctl )
    : s states ( __map_states_raw ctl )
    ? != 0 # i keys { ( nurl_free keys ) } {}
    ? != 0 # i vals { ( nurl_free vals ) } {}
    ? != 0 # i states { ( nurl_free states ) } {}
    ( nurl_free ctl )
}

// ── Higher-order ────────────────────────────────────────────────────

@ map_each [K V] ( HashMap K V ) m ( @ v K V ) f → v {
    : s ctl . m ctl
    : i cap ( __map_cap_raw ctl )
    ? > cap 0 {
        : *K keys # *K ( nurl_peek ctl 0 )
        : *V vals # *V ( nurl_peek ctl 1 )
        : *i states # *i ( nurl_peek ctl 2 )
        : ~ i i 0
        ~ < i cap {
            ? == . states i 1
            { ( f . keys i . vals i ) }
            {}
            = i + i 1
        }
    } {}
}

@ map_fold [K V B] ( HashMap K V ) m B init ( @ B B K V ) f → B {
    : s ctl . m ctl
    : i cap ( __map_cap_raw ctl )
    : ~ B acc init
    ? > cap 0 {
        : *K keys # *K ( nurl_peek ctl 0 )
        : *V vals # *V ( nurl_peek ctl 1 )
        : *i states # *i ( nurl_peek ctl 2 )
        : ~ i i 0
        ~ < i cap {
            ? == . states i 1
            { = acc ( f acc . keys i . vals i ) }
            {}
            = i + i 1
        }
    } {}
    ^ acc
}

// Bitwise-copy occupied keys into a fresh Vec[K]. Order is host-defined
// (depends on probe layout). Trivial K only — for owned-key maps the
// result aliases the map; clone keys yourself via map_each.
@ map_keys [K V] ( HashMap K V ) m → ( Vec K ) {
    : s ctl . m ctl
    : i cap ( __map_cap_raw ctl )
    : i len ( __map_len_raw ctl )
    : ( Vec K ) out ( vec_with_cap [K] len )
    ? > cap 0 {
        : *K keys # *K ( nurl_peek ctl 0 )
        : *i states # *i ( nurl_peek ctl 2 )
        : ~ i i 0
        ~ < i cap {
            ? == . states i 1
            { ( vec_push [K] out . keys i ) }
            {}
            = i + i 1
        }
    } {}
    ^ out
}

// Lazy iterator over occupied (key, value) pairs. The iterator BORROWS
// the map — do not mutate the map while iterating, and do NOT free the
// map until iteration is finished. cmd=1 only releases the iterator's
// own state; the caller still owns the map.
//
// Element type is ( Pair K V ). The Pair fields are bitwise-copies of
// the slot contents, so the same trivial-only caveat as map_keys /
// map_values applies: for owned-key / owned-value maps the resulting
// Pair fields alias the map's storage. Use map_each + a manual Vec
// build with explicit clones if you need owned copies.
//
// State layout: [walk_idx] (8 bytes; current slot index 0..cap).
@ map_iter [K V] ( HashMap K V ) m → ( @ ?( Pair K V ) i ) {
    : s st ( nurl_zalloc 8 )
    ( nurl_poke st 0 0 )
    : s ctl . m ctl
    : i cap ( __map_cap_raw ctl )
    ^ \ i cmd → ?( Pair K V ) {
        ? == cmd 1 {
            ( nurl_free st )
            ^ @ ?( Pair K V ) { F # ( Pair K V ) 0 }
        } {}
        ? == cap 0 { ^ @ ?( Pair K V ) { F # ( Pair K V ) 0 } } {}
        : *K keys # *K ( nurl_peek ctl 0 )
        : *V vals # *V ( nurl_peek ctl 1 )
        : *i states # *i ( nurl_peek ctl 2 )
        : ~ i idx ( nurl_peek st 0 )
        : ~ b found F
        : ~ ? ( Pair K V ) out @ ?( Pair K V ) { F # ( Pair K V ) 0 }
        ~ & ! found < idx cap {
            ? == . states idx 1 {
                : K k . keys idx
                : V v . vals idx
                = out @ ?( Pair K V ) { T ( pair_new [K V] k v ) }
                = found T
            } {}
            = idx + idx 1
        }
        ( nurl_poke st 0 idx )
        ^ out
    }
}

// Bitwise-copy occupied values into a fresh Vec[V]. Same caveat as map_keys.
@ map_values [K V] ( HashMap K V ) m → ( Vec V ) {
    : s ctl . m ctl
    : i cap ( __map_cap_raw ctl )
    : i len ( __map_len_raw ctl )
    : ( Vec V ) out ( vec_with_cap [V] len )
    ? > cap 0 {
        : *V vals # *V ( nurl_peek ctl 1 )
        : *i states # *i ( nurl_peek ctl 2 )
        : ~ i i 0
        ~ < i cap {
            ? == . states i 1
            { ( vec_push [V] out . vals i ) }
            {}
            = i + i 1
        }
    } {}
    ^ out
}

// ── Clone ───────────────────────────────────────────────────────────

// Bitwise shallow copy of the whole map. The clone keeps the source's
// slot layout verbatim (same cap, same probe positions, tombstones and
// all), so no rehash is needed and lookups behave identically. Safe ONLY
// for trivial K and V (i, f, b, raw s, slice) — for owned keys/values
// this aliases every heap pointer and double-frees on cleanup; use
// `map_clone_with` then. Mirrors the vec_clone / vec_clone_with split.
@ map_clone [K V] ( HashMap K V ) m → ( HashMap K V ) {
    : s sctl . m ctl
    : ( HashMap K V ) out ( map_new [K V] )
    : s dctl . out ctl
    : i cap ( __map_cap_raw sctl )
    ? > cap 0 {
        ( __map_alloc_buffers [K V] dctl cap )
        : *K skeys # *K ( nurl_peek sctl 0 )
        : *V svals # *V ( nurl_peek sctl 1 )
        : *i sstates # *i ( nurl_peek sctl 2 )
        : *K dkeys # *K ( nurl_peek dctl 0 )
        : *V dvals # *V ( nurl_peek dctl 1 )
        : *i dstates # *i ( nurl_peek dctl 2 )
        : ~ i i 0
        ~ < i cap {
            = . dstates i . sstates i
            ? == . sstates i 1 {
                = . dkeys i . skeys i
                = . dvals i . svals i
            } {}
            = i + i 1
        }
        ( nurl_poke dctl 3 ( __map_len_raw sctl ) )
        ( nurl_poke dctl 5 ( __map_tomb_raw sctl ) )
    } {}
    ^ out
}

// Deep copy of the whole map: every occupied key is run through
// `clone_k` and every value through `clone_v`, and the results are
// stored at the SAME slot index as the source. The slot layout is
// preserved verbatim, so no rehash is needed — the clone closures only
// have to produce independently-owned keys/values (for String keys pass
// `\ String s → String { ^ ( string_clone s ) }`, etc.). The source map
// is left untouched; the caller owns both maps.
@ map_clone_with [K V] ( HashMap K V ) m ( @ K K ) clone_k ( @ V V ) clone_v → ( HashMap K V ) {
    : s sctl . m ctl
    : ( HashMap K V ) out ( map_new [K V] )
    : s dctl . out ctl
    : i cap ( __map_cap_raw sctl )
    ? > cap 0 {
        ( __map_alloc_buffers [K V] dctl cap )
        : *K skeys # *K ( nurl_peek sctl 0 )
        : *V svals # *V ( nurl_peek sctl 1 )
        : *i sstates # *i ( nurl_peek sctl 2 )
        : *K dkeys # *K ( nurl_peek dctl 0 )
        : *V dvals # *V ( nurl_peek dctl 1 )
        : *i dstates # *i ( nurl_peek dctl 2 )
        : ~ i i 0
        ~ < i cap {
            = . dstates i . sstates i
            ? == . sstates i 1 {
                : K k . skeys i
                : V v . svals i
                = . dkeys i ( clone_k k )
                = . dvals i ( clone_v v )
            } {}
            = i + i 1
        }
        ( nurl_poke dctl 3 ( __map_len_raw sctl ) )
        ( nurl_poke dctl 5 ( __map_tomb_raw sctl ) )
    } {}
    ^ out
}
