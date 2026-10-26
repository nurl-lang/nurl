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
//   word 2: states ptr (raw i8*; one byte per slot: 0 = empty, 1 = tombstone,
//           128..255 = occupied, the low 7 bits a fragment of the key's hash)
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
//   map_new / map_with_cap → owned HashMap, dropped (with its keys and
//   values) by its owner at scope exit like a Vec (docs/MEMORY.md §7.6);
//   map_free releases early. A key / value handed to map_set moves in;
//   map_set / map_remove hand the displaced value back owned, and a removed
//   key is dropped. For HashMap[s V] (raw-string keys) the caller keeps the
//   key strings alive until removed; the map does NOT strdup.
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
//   ( map_clone      [K V] m )                  → ( HashMap K V )  owns copies of every entry
//   ( map_clone_with [K V] m clone_k clone_v )  → ( HashMap K V )  deep copy
//
// map_keys / map_values / map_iter hand out copies the caller owns: a key
// or value that owns memory (a String) is copied deep (docs/MEMORY.md
// §7.6), so the result and the map are dropped independently. map_iter's
// iterator borrows the map itself: the map must outlive it (the checker
// rejects anything else). To duplicate a
// whole map use `map_clone`, or `map_clone_with` for custom copies.
//
// Stock hash + eq:
//   ( hash_string s )      → i        djb2-style hash over bytes
//   ( eq_string a b )      → b        content equality (nurl_str_eq)
//   ( hash_int x )         → i        Knuth multiplicative hash
//   ( eq_int a b )         → b        ==

$ `stdlib/core/vec.nu`
$ `stdlib/core/pair.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/core/box.nu`

: MapCtl {
    RawBlock keys
    RawBlock vals
    RawBlock states
    i len
    i cap
    i tomb
}

: HashMap [K V] { ( Box MapCtl ) ctl }

// ── Stock hash + eq for common key types ────────────────────────────

// djb2 hash — direct byte access via *u pointer walk. The original
// version called `nurl_str_get` per byte, which calls `strlen` per
// call, making the whole hash O(n²). Now O(n) — one `strlen` at the
// start, then byte-by-byte through the pointer.
//
// Returns 5381 (the djb2 seed) for a NULL or empty string so the
// caller's downstream code doesn't need to branch.
// FNV-1a (64-bit) with a murmur-style avalanche finisher. The map masks
// the hash with a power of two, so only the LOW bits pick the slot — and
// the previous djb2's low bits carried so little of the key that 250 k
// real multilingual tokenizer pieces probed ~7× slower than well-spread
// synthetic keys. FNV-1a plus two xorshift-multiply rounds pushes every
// input byte into the low bits. (The finisher masks to 63 bits first so
// the arithmetic `>>` behaves like a logical shift.)
@ hash_string s str → i {
    ? == # i str 0 { ^ 5381 } {}
    : i n ( strlen str )
    : *u p # *u str
    : ~ i h -3750763034362895579  // FNV-1a 64-bit offset basis
    : ~ i i 0
    ~ < i n {
        = h ^^ h & # i . p i 255
        = h * h 1099511628211  // FNV-1a 64-bit prime
        = i + i 1
    }
    = h & h 9223372036854775807
    = h ^^ h >> h 31
    = h * h -49064778989728563  // 0xff51afd7ed558ccd
    = h & h 9223372036854775807
    = h ^^ h >> h 29
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

// The state byte of an occupied slot: 128 | seven bits of the key's hash
// (its mixed high bits — the slot index already spends the low ones). A
// probe compares keys only where the byte matches, so a collision chain is
// walked in the one-byte-per-slot states array, not in the keys.
@ __map_frag i h → i { ^ | 128 & >> * h -7046029254386353131 57 127 }

@ __map_occupied i st → b { ^ >= st 128 }

// __map_alloc_buffers: fresh zeroed keys/vals/states buffers for `cap`
// slots (every slot starts empty, state == 0) and the capacity. The old
// buffers are released as they are replaced; whatever they held must
// have moved out first.
@ __map_alloc_buffers [K V] * MapCtl c i cap → v {
    = . c keys ( raw_block_zero ( alloc_size Z K cap ) )
    = . c vals ( raw_block_zero ( alloc_size Z V cap ) )
    = . c states ( raw_block_zero cap )
    = . c cap cap
}

// __map_probe_for: linear-probe scan starting at hash & mask.
//   On match    → returns slot index (>= 0).
//   On miss     → returns -(insert_idx + 1)   (always < 0)
//                 Caller decodes via   insert_idx = - slot - 1.
//   Pre-condition: cap > 0 (caller must check / lazily allocate).
//   The map_set caller resizes proactively before probing, so this loop
//   always finds either a match, an empty slot, or a tombstone within
//   cap iterations; the "table full" case never occurs in practice.
@ __map_probe_for [K V] * MapCtl c K key i h ( @ b K K ) eq_fn → i {
    : i cap . c cap
    : i mask - cap 1
    : i start & h mask
    : i frag ( __map_frag h )
    : *K keys # *K ( raw_block_ptr . c keys )
    : *u states # *u ( raw_block_ptr . c states )
    : ~ i first_free -1
    : ~ i probe 0
    : ~ i result -1
    : ~ b done F
    ~ & ! done < probe cap {
        : i idx & + start probe mask
        : i st # i . states idx
        ? == st 0
        { ? < first_free 0 { = first_free idx } {}
            = done T
        }
        { ? == st frag
            { : K k . keys idx
                ? ( eq_fn k key )
                { = result idx
                    = done T
                }
                {}
            }
            { ? & == st 1 < first_free 0 { = first_free idx } {} }
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

// __map_probe_with: __map_probe_for for a query `q` of another type than
// the keys — found, or -1 (never an insert slot: map_get_with only reads).
@ __map_probe_with [K V Q] * MapCtl c Q q i h ( @ b K Q ) eq_kq → i {
    : i cap . c cap
    : i mask - cap 1
    : i start & h mask
    : i frag ( __map_frag h )
    : *K keys # *K ( raw_block_ptr . c keys )
    : *u states # *u ( raw_block_ptr . c states )
    : ~ i probe 0
    ~ < probe cap {
        : i idx & + start probe mask
        : i st # i . states idx
        ? == st 0 { ^ -1 } {}
        ? == st frag {
            : K k . keys idx
            ? ( eq_kq k q ) { ^ idx } {}
        } {}
        = probe + probe 1
    }
    ^ -1
}

// __map_grow: rehash into a buffer with `target_cap` (rounded up to a
// power of two ≥ 8 ≥ target). Tombstones are dropped during rehash. The
// entries move bitwise into the new buffers; the old ones are released
// after, holding nothing they own any more.
@ __map_grow [K V] * MapCtl c i target_cap ( @ i K ) hash_fn → v {
    : i old_cap . c cap
    : i new_cap ( alloc_grow_pow2 old_cap target_cap 8 )
    : RawBlock okb ( mem_replace [RawBlock] . c keys ( raw_block_zero ( alloc_size Z K new_cap ) ) )
    : RawBlock ovb ( mem_replace [RawBlock] . c vals ( raw_block_zero ( alloc_size Z V new_cap ) ) )
    : RawBlock osb ( mem_replace [RawBlock] . c states ( raw_block_zero new_cap ) )
    = . c cap new_cap
    = . c len 0
    = . c tomb 0
    : *K old_keys # *K ( raw_block_ptr okb )
    : *V old_vals # *V ( raw_block_ptr ovb )
    : *u old_states # *u ( raw_block_ptr osb )
    : i mask - new_cap 1
    : *K new_keys # *K ( raw_block_ptr . c keys )
    : *V new_vals # *V ( raw_block_ptr . c vals )
    : *u new_states # *u ( raw_block_ptr . c states )
    : ~ i new_len 0
    : ~ i i 0
    ~ < i old_cap {
        ? ( __map_occupied # i . old_states i ) {
            : K k . old_keys i
            : V v . old_vals i
            : i h ( hash_fn k )
            : ~ i idx & h mask
            ~ != # i . new_states idx 0 { = idx & + idx 1 mask }
            = . new_keys idx k
            = . new_vals idx v
            = . new_states idx # u ( __map_frag h )
            = new_len + new_len 1
        } {}
        = i + i 1
    }
    = . c len new_len
}

@ __map_ctl_new → ( Box MapCtl ) {
    ^ ( box_new [MapCtl] @ MapCtl { ( raw_block 0 ) ( raw_block 0 ) ( raw_block 0 ) 0 0 0 } )
}

// ── Constructors ────────────────────────────────────────────────────

@ map_new [K V] → ( HashMap K V ) {
    ^ @ ( HashMap K V ) { ( __map_ctl_new ) }
}

@ map_with_cap [K V] i n ( @ i K ) hash_fn → ( HashMap K V ) {
    : ( HashMap K V ) m @ ( HashMap K V ) { ( __map_ctl_new ) }
    ? > n 0 { ( __map_grow [K V] ( box_ptr [MapCtl] . m ctl ) n hash_fn ) } {}
    ^ m
}

// ── Inspectors ──────────────────────────────────────────────────────

@ map_len [K V] ( HashMap K V ) m → i {
    ^ . ( box_ptr [MapCtl] . m ctl ) len
}

@ map_cap [K V] ( HashMap K V ) m → i {
    ^ . ( box_ptr [MapCtl] . m ctl ) cap
}

@ map_is_empty [K V] ( HashMap K V ) m → b {
    ^ == . ( box_ptr [MapCtl] . m ctl ) len 0
}

// ── Lookup ──────────────────────────────────────────────────────────

@ map_get [K V] ( HashMap K V ) m K key ( @ i K ) hash_fn ( @ b K K ) eq_fn → ?V {
    : *MapCtl c ( box_ptr [MapCtl] . m ctl )
    ? == . c cap 0
    { ^ @ ?V { F # V 0 } }
    {}
    : i slot ( __map_probe_for [K V] c key ( hash_fn key ) eq_fn )
    ? < slot 0
    { ^ @ ?V { F # V 0 } }
    {}
    : *V vals # *V ( raw_block_ptr . c vals )
    ^ @ ?V { T . vals slot }
}

// A lookup by a query of another type: `hash_q` hashes `q` as the key it
// stands for hashes, and `eq_kq` says whether a stored key is it — a map
// that owns its String keys, found by a borrowed `s` with nothing
// allocated:
//   ( map_get_with [String i s] m `the` \ s x → i { ^ ( hash_string x ) }
//     \ String k s x → b { ^ ( eq_string ( string_data k ) x ) } )
@ map_get_with [K V Q] ( HashMap K V ) m Q q ( @ i Q ) hash_q ( @ b K Q ) eq_kq → ?V {
    : *MapCtl c ( box_ptr [MapCtl] . m ctl )
    ? == . c cap 0 { ^ @ ?V { F # V 0 } } {}
    : i slot ( __map_probe_with [K V Q] c q ( hash_q q ) eq_kq )
    ? < slot 0 { ^ @ ?V { F # V 0 } } {}
    : *V vals # *V ( raw_block_ptr . c vals )
    ^ @ ?V { T . vals slot }
}

@ map_contains [K V] ( HashMap K V ) m K key ( @ i K ) hash_fn ( @ b K K ) eq_fn → b {
    : *MapCtl c ( box_ptr [MapCtl] . m ctl )
    ? == . c cap 0
    { ^ F }
    {}
    : i slot ( __map_probe_for [K V] c key ( hash_fn key ) eq_fn )
    ^ >= slot 0
}

// ── Mutation ────────────────────────────────────────────────────────

@ map_set [K V] ( HashMap K V ) m K key V val ( @ i K ) hash_fn ( @ b K K ) eq_fn → ?V {
    : *MapCtl c ( box_ptr [MapCtl] . m ctl )
    // Lazy first allocation.
    ? == . c cap 0
    { ( __map_grow [K V] c 8 hash_fn ) }
    {}
    // Resize if (len + tomb + 1) * 4 ≥ cap * 3 (≈75% load factor).
    : i len0 . c len
    : i tomb0 . c tomb
    : i cap0 . c cap
    ? >= * + + len0 tomb0 1 4 * cap0 3
    { ( __map_grow [K V] c * cap0 2 hash_fn ) }
    {}

    // Probe in (possibly resized) table.
    : i h ( hash_fn key )
    : i slot ( __map_probe_for [K V] c key h eq_fn )
    : *K keys # *K ( raw_block_ptr . c keys )
    : *V vals # *V ( raw_block_ptr . c vals )
    : *u states # *u ( raw_block_ptr . c states )
    ? >= slot 0
    { : V prev . vals slot
        // The old value leaves the map: the caller owns it.
        ( mem_take prev )
        = . vals slot val
        ^ @ ?V { T prev }
    }
    { : i ins - -1 slot
        : i st_old # i . states ins
        = . keys ins key
        = . vals ins val
        = . states ins # u ( __map_frag h )
        = . c len + . c len 1
        ? == st_old 1
        { = . c tomb - . c tomb 1 }
        {}
        ^ @ ?V { F # V 0 }
    }
}

@ map_remove [K V] ( HashMap K V ) m K key ( @ i K ) hash_fn ( @ b K K ) eq_fn → ?V {
    : *MapCtl c ( box_ptr [MapCtl] . m ctl )
    ? == . c cap 0
    { ^ @ ?V { F # V 0 } }
    {}
    : i slot ( __map_probe_for [K V] c key ( hash_fn key ) eq_fn )
    ? < slot 0
    { ^ @ ?V { F # V 0 } }
    {}
    : *V vals # *V ( raw_block_ptr . c vals )
    : *u states # *u ( raw_block_ptr . c states )
    : *K keys # *K ( raw_block_ptr . c keys )
    // The stored key leaves with its entry (dropped here); the value is
    // handed to the caller.
    : K gone . keys slot
    ( mem_take gone )
    : V prev . vals slot
    ( mem_take prev )
    = . states slot # u 1
    = . c len - . c len 1
    = . c tomb + . c tomb 1
    ^ @ ?V { T prev }
}

// ── Cleanup ─────────────────────────────────────────────────────────

// What dropping a map does (its owner does it at scope exit — docs/
// MEMORY.md §7.6): every entry's key and value are dropped (no work, and
// no loop, for ones that own nothing); the record and its buffers go with
// the handle's field.
@ HashMap_drop [K V] sink ( HashMap K V ) m → v {
    ? ( box_is_null [MapCtl] . m ctl ) { ^ } {}
    : *MapCtl c ( box_ptr [MapCtl] . m ctl )
    : i cap . c cap
    ? > cap 0 {
        : *K keys # *K ( raw_block_ptr . c keys )
        : *V vals # *V ( raw_block_ptr . c vals )
        : *u states # *u ( raw_block_ptr . c states )
        : ~ i i 0
        ~ < i cap {
            ? ( __map_occupied # i . states i ) {
                : K k . keys i
                ( mem_take k )
                : V v . vals i
                ( mem_take v )
            } {}
            = i + i 1
        }
    } {}
}

// What the reference-count cycle collector sees in a map (docs/MEMORY.md
// §7.7): every live entry's key and value.
@ HashMap_trace [K V] ( HashMap K V ) m s vis → v {
    ( map_each [K V] m \ K k V x → v { ( mem_trace [K] k vis ) ( mem_trace [V] x vis ) } )
}

// The thread crossing's check (docs/MEMORY.md §6.5): every live entry's key
// and value carries every owner of a handle whose copies are one state. (A
// loop, not map_each: a closure the check panics through would leak its
// environment, agora #131.)
@ HashMap_sendck [K V] ( HashMap K V ) m s what → v {
    : *MapCtl c ( box_ptr [MapCtl] . m ctl )
    : i cap . c cap
    ? > cap 0 {
        : *K keys # *K ( raw_block_ptr . c keys )
        : *V vals # *V ( raw_block_ptr . c vals )
        : *u states # *u ( raw_block_ptr . c states )
        : ~ i i 0
        ~ < i cap {
            ? ( __map_occupied # i . states i ) {
                ( mem_send_check [K] . keys i what )
                ( mem_send_check [V] . vals i what )
            } {}
            = i + i 1
        }
    } {}
}

// A copy of the map that owns its own entries (each key and value copied
// — a String deep, an integer as is), at the same slot layout: no rehash.
// What a borrowed map stored into an owner becomes (docs/MEMORY.md §7.6).
@ HashMap_clone [K V] ( HashMap K V ) m → ( HashMap K V ) {
    : *MapCtl sc ( box_ptr [MapCtl] . m ctl )
    : ( HashMap K V ) out @ ( HashMap K V ) { ( __map_ctl_new ) }
    : *MapCtl dc ( box_ptr [MapCtl] . out ctl )
    : i cap . sc cap
    ? > cap 0 {
        ( __map_alloc_buffers [K V] dc cap )
        : *K skeys # *K ( raw_block_ptr . sc keys )
        : *V svals # *V ( raw_block_ptr . sc vals )
        : *u sstates # *u ( raw_block_ptr . sc states )
        : *K dkeys # *K ( raw_block_ptr . dc keys )
        : *V dvals # *V ( raw_block_ptr . dc vals )
        : *u dstates # *u ( raw_block_ptr . dc states )
        : ~ i i 0
        ~ < i cap {
            = . dstates i . sstates i
            ? ( __map_occupied # i . sstates i ) {
                : K k . skeys i
                = . dkeys i ( mem_dup k )
                : V v . svals i
                = . dvals i ( mem_dup v )
            } {}
            = i + i 1
        }
        = . dc len . sc len
        = . dc tomb . sc tomb
    } {}
    ^ out
}

// Early release: exactly what dropping `m` does (HashMap_drop).
@ map_free [K V] sink ( HashMap K V ) m → v {}

// ── Higher-order ────────────────────────────────────────────────────

@ map_each [K V] ( HashMap K V ) m ( @ v K V ) f → v {
    : *MapCtl c ( box_ptr [MapCtl] . m ctl )
    : i cap . c cap
    ? > cap 0 {
        : *K keys # *K ( raw_block_ptr . c keys )
        : *V vals # *V ( raw_block_ptr . c vals )
        : *u states # *u ( raw_block_ptr . c states )
        : ~ i i 0
        ~ < i cap {
            ? ( __map_occupied # i . states i )
            { ( f . keys i . vals i ) }
            {}
            = i + i 1
        }
    } {}
}

@ map_fold [K V B] ( HashMap K V ) m B init ( @ B B K V ) f → B {
    : *MapCtl c ( box_ptr [MapCtl] . m ctl )
    : i cap . c cap
    : ~ B acc init
    ? > cap 0 {
        : *K keys # *K ( raw_block_ptr . c keys )
        : *V vals # *V ( raw_block_ptr . c vals )
        : *u states # *u ( raw_block_ptr . c states )
        : ~ i i 0
        ~ < i cap {
            ? ( __map_occupied # i . states i )
            { = acc ( f acc . keys i . vals i ) }
            {}
            = i + i 1
        }
    } {}
    ^ acc
}

// The occupied keys, copied into a fresh Vec[K] (an owned key deep, §7.6).
// Order is host-defined (depends on probe layout).
@ map_keys [K V] ( HashMap K V ) m → ( Vec K ) {
    : *MapCtl c ( box_ptr [MapCtl] . m ctl )
    : i cap . c cap
    : i len . c len
    : ( Vec K ) out ( vec_with_cap [K] len )
    ? > cap 0 {
        : *K keys # *K ( raw_block_ptr . c keys )
        : *u states # *u ( raw_block_ptr . c states )
        : ~ i i 0
        ~ < i cap {
            ? ( __map_occupied # i . states i )
            { ( vec_push [K] out . keys i ) }
            {}
            = i + i 1
        }
    } {}
    ^ out
}

// Lazy iterator over occupied (key, value) pairs. The iterator borrows
// the map: it holds a copy of the handle and reads the slots through it
// when called, so releasing the map or giving it a new value while the
// iterator is still used, or returning the iterator past the map, is
// rejected (h301). A map changed between calls (map_set, map_remove) is
// walked on its current slots: after a resize an entry may be skipped or
// met twice. cmd=1 only releases the iterator's own state (the closure
// releases it anyway); the caller still owns the map.
//
// Element type is ( Pair K V ), each Pair its own: a key or value that
// owns memory is copied into it (docs/MEMORY.md §7.6), so dropping or
// keeping a Pair leaves the map as it was.
//
// State: the slot index the walk has reached, in a Box the closure owns
// (released with it).
@ map_iter [K V] ( HashMap K V ) m → ( @ ?( Pair K V ) i ) {
    : ( Box i ) st ( box_new [i] 0 )
    ^ \ i cmd → ?( Pair K V ) {
        ? == cmd 1 { ^ @ ?( Pair K V ) { F # ( Pair K V ) 0 } } {}
        : *MapCtl c ( box_ptr [MapCtl] . m ctl )
        : i cap . c cap
        ? == cap 0 { ^ @ ?( Pair K V ) { F # ( Pair K V ) 0 } } {}
        : *K keys # *K ( raw_block_ptr . c keys )
        : *V vals # *V ( raw_block_ptr . c vals )
        : *u states # *u ( raw_block_ptr . c states )
        : ~ i idx ( box_get [i] st )
        : ~ b found F
        : ~ ? ( Pair K V ) out @ ?( Pair K V ) { F # ( Pair K V ) 0 }
        ~ & ! found < idx cap {
            ? ( __map_occupied # i . states idx ) {
                : K k . keys idx
                : V v . vals idx
                = out @ ?( Pair K V ) { T ( pair_new [K V] k v ) }
                = found T
            } {}
            = idx + idx 1
        }
        ( box_set [i] st idx )
        ^ out
    }
}

// The occupied values, copied into a fresh Vec[V] (as map_keys).
@ map_values [K V] ( HashMap K V ) m → ( Vec V ) {
    : *MapCtl c ( box_ptr [MapCtl] . m ctl )
    : i cap . c cap
    : i len . c len
    : ( Vec V ) out ( vec_with_cap [V] len )
    ? > cap 0 {
        : *V vals # *V ( raw_block_ptr . c vals )
        : *u states # *u ( raw_block_ptr . c states )
        : ~ i i 0
        ~ < i cap {
            ? ( __map_occupied # i . states i )
            { ( vec_push [V] out . vals i ) }
            {}
            = i + i 1
        }
    } {}
    ^ out
}

// ── Clone ───────────────────────────────────────────────────────────

// A copy of the whole map that owns its entries: keys and values that own
// memory are copied deep (HashMap_clone), at the same slot layout.
@ map_clone [K V] ( HashMap K V ) m → ( HashMap K V ) {
    ^ ( HashMap_clone [K V] m )
}

// Deep copy of the whole map: every occupied key is run through
// `clone_k` and every value through `clone_v`, and the results are
// stored at the SAME slot index as the source. The slot layout is
// preserved verbatim, so no rehash is needed — the clone closures only
// have to produce independently-owned keys/values (for String keys pass
// `\ String s → String { ^ ( string_clone s ) }`, etc.). The source map
// is left untouched; the caller owns both maps.
@ map_clone_with [K V] ( HashMap K V ) m ( @ K K ) clone_k ( @ V V ) clone_v → ( HashMap K V ) {
    : *MapCtl sc ( box_ptr [MapCtl] . m ctl )
    : ( HashMap K V ) out ( map_new [K V] )
    : *MapCtl dc ( box_ptr [MapCtl] . out ctl )
    : i cap . sc cap
    ? > cap 0 {
        ( __map_alloc_buffers [K V] dc cap )
        : *K skeys # *K ( raw_block_ptr . sc keys )
        : *V svals # *V ( raw_block_ptr . sc vals )
        : *u sstates # *u ( raw_block_ptr . sc states )
        : *K dkeys # *K ( raw_block_ptr . dc keys )
        : *V dvals # *V ( raw_block_ptr . dc vals )
        : *u dstates # *u ( raw_block_ptr . dc states )
        : ~ i i 0
        ~ < i cap {
            = . dstates i . sstates i
            ? ( __map_occupied # i . sstates i ) {
                : K k . skeys i
                : V v . svals i
                = . dkeys i ( clone_k k )
                = . dvals i ( clone_v v )
            } {}
            = i + i 1
        }
        = . dc len . sc len
        = . dc tomb . sc tomb
    } {}
    ^ out
}
