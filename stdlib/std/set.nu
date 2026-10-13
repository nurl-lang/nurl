// stdlib/std/set.nu — owned generic Set[E]
//
// Open addressing + linear probing, mirroring HashMap[K V] but specialised
// for sets: no values array, smaller per-slot state. Same hash/eq closure-
// per-call convention as HashMap (NURL has no type-class dispatch).
//
// Direct implementation rather than a HashMap[T b] wrapper because the
// compiler's text-level pre-scan does not propagate struct instantiations
// through generic function bodies — Set[s] would need %HashMap__str__i1
// emitted from a literal `( HashMap s b )` in source, which we don't have.
//
// Control block layout (heap, 40 bytes = 5 × i64), accessed via
// nurl_peek/poke as raw i64 words:
//   word 0: keys ptr   (raw i8*; bitcast to *T when accessing)
//   word 1: states ptr (raw i8*; bitcast to *i; per-slot 0=empty/1=occupied/2=tombstone)
//   word 2: len        (occupied count, NOT counting tombstones)
//   word 3: cap        (always power-of-two; 0 means no buffer yet)
//   word 4: tombstones (count of slots in tombstone state)
//
// Resize policy: lazy first allocation at cap=8; double when
// (len + tombstones + 1) * 4 ≥ cap * 3 (≈75% load factor). Rehash drops
// tombstones.
//
// Ownership:
//   set_new / set_with_cap → owned Set, dropped (with its elements) by its
//   owner at scope exit like a Vec (docs/MEMORY.md §7.6); set_free releases
//   early. An added element moves in; a removed one is dropped. For Set[s]
//   (raw string keys) the caller keeps the strings alive until removed.
//
// API:
//   ( set_new      [E] )                                   → ( Set E )
//   ( set_with_cap [E] n hash_fn )                         → ( Set E )
//   ( set_len      [E] s )                                 → i
//   ( set_cap      [E] s )                                 → i
//   ( set_is_empty [E] s )                                 → b
//   ( set_add      [E] s x hash_fn eq_fn )                 → b   (T = newly inserted, F = already there)
//   ( set_remove   [E] s x hash_fn eq_fn )                 → b   (T = removed, F = was absent)
//   ( set_contains [E] s x hash_fn eq_fn )                 → b
//   ( set_each     [E] s f )    f : (@ v E)                → v
//   ( set_fold     [E B] s init f )  f : (@ B B E)         → B
//   ( set_free     [E] s )                                 → v
//   ( set_free_with [E] s drop ) drop : (@ v E)            → v   (drop each element first)
//
// Use the same stock hash/eq as HashMap (`hash_string`/`eq_string`,
// `hash_int`/`eq_int`) — import `stdlib/std/hashmap.nu` alongside this
// file to get them; set.nu itself does not depend on it.

$ `stdlib/core/vec.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/core/box.nu`

// The handle owns a boxed control record: the key and state buffers
// (RawBlocks, which release themselves), the live count, the capacity and
// the tombstone count. Dropping the set drops its live keys; the record
// and the buffers go with the handle's field.
: SetCtl { RawBlock keys RawBlock states i len i cap i tomb }

: Set [E] { ( Box SetCtl ) ctl }

// ── Internal helpers ────────────────────────────────────────────────

// Fresh zeroed buffers for `cap` slots (the old ones are released as
// they are replaced; whatever they held must have moved out first).
@ __set_alloc_buffers [E] * SetCtl c i cap → v {
    = . c keys ( raw_block_zero ( alloc_size Z E cap ) )
    = . c states ( raw_block_zero ( alloc_size 8 cap ) )
    = . c cap cap
}

// __set_probe_for: linear-probe scan starting at hash & mask.
//   On match → returns slot index (≥0).
//   On miss  → returns -(insert_idx + 1)  (always < 0)
//   Caller decodes via insert_idx = -slot - 1.
//   Pre-condition: cap > 0 (callers resize proactively before probing).
@ __set_probe_for [E] * SetCtl c E key ( @ i E ) hash_fn ( @ b E E ) eq_fn → i {
    : i cap . c cap
    : i mask - cap 1
    : i h ( hash_fn key )
    : i start & h mask
    : *E keys # *E ( raw_block_ptr . c keys )
    : *i states # *i ( raw_block_ptr . c states )
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
            { : E k . keys idx
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

// __set_grow: rehash into a buffer with `target_cap` (rounded up to a
// power of two ≥ 8 ≥ target). Tombstones drop during rehash. The keys
// move bitwise into the new buffer; the old ones are released after.
@ __set_grow [E] * SetCtl c i target_cap ( @ i E ) hash_fn → v {
    : i old_cap . c cap
    : i new_cap ( alloc_grow_pow2 old_cap target_cap 8 )
    : RawBlock okb ( mem_replace [RawBlock] . c keys ( raw_block_zero ( alloc_size Z E new_cap ) ) )
    : RawBlock osb ( mem_replace [RawBlock] . c states ( raw_block_zero ( alloc_size 8 new_cap ) ) )
    = . c cap new_cap
    = . c len 0
    = . c tomb 0
    : *E old_keys # *E ( raw_block_ptr okb )
    : *i old_states # *i ( raw_block_ptr osb )
    : i mask - new_cap 1
    : *E new_keys # *E ( raw_block_ptr . c keys )
    : *i new_states # *i ( raw_block_ptr . c states )
    : ~ i new_len 0
    : ~ i i 0
    ~ < i old_cap {
        ? == . old_states i 1 {
            : E k . old_keys i
            : i h ( hash_fn k )
            : ~ i idx & h mask
            ~ != . new_states idx 0 { = idx & + idx 1 mask }
            = . new_keys idx k
            = . new_states idx 1
            = new_len + new_len 1
        } {}
        = i + i 1
    }
    = . c len new_len
}

@ __set_ctl_new → ( Box SetCtl ) {
    ^ ( box_new [SetCtl] @ SetCtl { ( raw_block 0 ) ( raw_block 0 ) 0 0 0 } )
}

// ── Constructors ────────────────────────────────────────────────────

@ set_new [E] → ( Set E ) {
    ^ @ ( Set E ) { ( __set_ctl_new ) }
}

@ set_with_cap [E] i n ( @ i E ) hash_fn → ( Set E ) {
    : ( Set E ) st @ ( Set E ) { ( __set_ctl_new ) }
    ? > n 0 { ( __set_grow [E] ( box_ptr [SetCtl] . st ctl ) n hash_fn ) } {}
    ^ st
}

// ── Inspectors ──────────────────────────────────────────────────────

@ set_len [E] ( Set E ) st → i {
    ^ . ( box_ptr [SetCtl] . st ctl ) len
}

@ set_cap [E] ( Set E ) st → i {
    ^ . ( box_ptr [SetCtl] . st ctl ) cap
}

@ set_is_empty [E] ( Set E ) st → b {
    ^ == . ( box_ptr [SetCtl] . st ctl ) len 0
}

// ── Mutation ────────────────────────────────────────────────────────

// Returns T if newly inserted, F if `x` was already present.
@ set_add [E] ( Set E ) st E key ( @ i E ) hash_fn ( @ b E E ) eq_fn → b {
    : *SetCtl c ( box_ptr [SetCtl] . st ctl )
    ? == . c cap 0 { ( __set_grow [E] c 8 hash_fn ) } {}
    ? >= * + + . c len . c tomb 1 4 * . c cap 3 { ( __set_grow [E] c * . c cap 2 hash_fn ) } {}
    : i slot ( __set_probe_for [E] c key hash_fn eq_fn )
    : *E keys # *E ( raw_block_ptr . c keys )
    : *i states # *i ( raw_block_ptr . c states )
    ? >= slot 0
    { ^ F }
    { : i ins - -1 slot
        : i st_old . states ins
        = . keys ins key
        = . states ins 1
        = . c len + . c len 1
        ? == st_old 2 { = . c tomb - . c tomb 1 } {}
        ^ T
    }
}

// Returns T if removed, F if `x` was absent.
@ set_remove [E] ( Set E ) st E key ( @ i E ) hash_fn ( @ b E E ) eq_fn → b {
    : *SetCtl c ( box_ptr [SetCtl] . st ctl )
    ? == . c cap 0 { ^ F } {}
    : i slot ( __set_probe_for [E] c key hash_fn eq_fn )
    ? < slot 0 { ^ F } {}
    : *E keys # *E ( raw_block_ptr . c keys )
    // The stored element leaves with its slot.
    : E gone . keys slot
    ( mem_take gone )
    : *i states # *i ( raw_block_ptr . c states )
    = . states slot 2
    = . c len - . c len 1
    = . c tomb + . c tomb 1
    ^ T
}

@ set_contains [E] ( Set E ) st E key ( @ i E ) hash_fn ( @ b E E ) eq_fn → b {
    : *SetCtl c ( box_ptr [SetCtl] . st ctl )
    ? == . c cap 0 { ^ F } {}
    ^ >= ( __set_probe_for [E] c key hash_fn eq_fn ) 0
}

// ── Higher-order ────────────────────────────────────────────────────

@ set_each [E] ( Set E ) st ( @ v E ) f → v {
    : *SetCtl c ( box_ptr [SetCtl] . st ctl )
    : i cap . c cap
    ? > cap 0 {
        : *E keys # *E ( raw_block_ptr . c keys )
        : *i states # *i ( raw_block_ptr . c states )
        : ~ i i 0
        ~ < i cap {
            ? == . states i 1 { ( f . keys i ) } {}
            = i + i 1
        }
    } {}
}

@ set_fold [E B] ( Set E ) st B init ( @ B B E ) f → B {
    : *SetCtl c ( box_ptr [SetCtl] . st ctl )
    : i cap . c cap
    : ~ B acc init
    ? > cap 0 {
        : *E keys # *E ( raw_block_ptr . c keys )
        : *i states # *i ( raw_block_ptr . c states )
        : ~ i i 0
        ~ < i cap {
            ? == . states i 1 { = acc ( f acc . keys i ) } {}
            = i + i 1
        }
    } {}
    ^ acc
}

// ── Cleanup ─────────────────────────────────────────────────────────

// What dropping a set does (its owner does it at scope exit — docs/
// MEMORY.md §7.6): every live element is dropped (no work, and no loop,
// for elements that own nothing); the record and its buffers go with the
// handle's field.
@ Set_drop [E] sink ( Set E ) st → v {
    ? ( box_is_null [SetCtl] . st ctl ) { ^ } {}
    : *SetCtl c ( box_ptr [SetCtl] . st ctl )
    : i cap . c cap
    ? > cap 0 {
        : *E keys # *E ( raw_block_ptr . c keys )
        : *i states # *i ( raw_block_ptr . c states )
        : ~ i i 0
        ~ < i cap {
            ? == . states i 1 {
                : E e . keys i
                ( mem_take e )
            } {}
            = i + i 1
        }
    } {}
}

// What the reference-count cycle collector sees in a set (docs/MEMORY.md
// §7.7): every live element.
@ Set_trace [E] ( Set E ) st s vis → v {
    ( set_each [E] st \ E x → v { ( mem_trace [E] x vis ) } )
}

// A copy that owns its own elements, at the same slot layout (no rehash).
@ Set_clone [E] ( Set E ) st → ( Set E ) {
    : *SetCtl sc ( box_ptr [SetCtl] . st ctl )
    : ( Set E ) out @ ( Set E ) { ( __set_ctl_new ) }
    : i cap . sc cap
    ? > cap 0 {
        : *SetCtl dc ( box_ptr [SetCtl] . out ctl )
        ( __set_alloc_buffers [E] dc cap )
        : *E skeys # *E ( raw_block_ptr . sc keys )
        : *i sstates # *i ( raw_block_ptr . sc states )
        : *E dkeys # *E ( raw_block_ptr . dc keys )
        : *i dstates # *i ( raw_block_ptr . dc states )
        : ~ i i 0
        ~ < i cap {
            = . dstates i . sstates i
            ? == . sstates i 1 {
                : E e . skeys i
                = . dkeys i ( mem_dup e )
            } {}
            = i + i 1
        }
        = . dc len . sc len
        = . dc tomb . sc tomb
    } {}
    ^ out
}

// Early release: exactly what dropping `st` does (Set_drop).
@ set_free [E] sink ( Set E ) st → v {}

// Early release with a last look at every live element (see
// vec_free_with); then `st` goes as `set_free` releases it.
@ set_free_with [E] sink ( Set E ) st ( @ v E ) drop → v {
    ( set_each [E] st drop )
}

// ── Set algebra ─────────────────────────────────────────────────────
//
// Closures capture the output Set by value, but the captured ctl
// pointer references the same heap, so set_add through the captured
// handle mutates the same buffer the caller sees.
//
// All three return a fresh owned Set; caller calls set_free.
// Element bytes are bitwise-copied (same caveat as vec_map): safe for
// trivial element types (i, raw s, fat-ptr slices), unsafe for owned
// String / Vec / HashMap unless you also clone them.

// Closures below capture the output Set handle and the hash/eq closures
// — both are aggregate values which the compiler now stores in the env
// struct with their native LLVM type (no ptrtoint shimming).

// out = a ∪ b
@ set_union [E] ( Set E ) a ( Set E ) b ( @ i E ) hash_fn ( @ b E E ) eq_fn → ( Set E ) {
    : ( Set E ) out ( set_new [E] )
    : ( @ v E ) add_each \ E x → v { ( set_add [E] out x hash_fn eq_fn ) }
    ( set_each [E] a add_each )
    ( set_each [E] b add_each )
    ^ out
}

// out = a ∩ b
@ set_intersect [E] ( Set E ) a ( Set E ) b ( @ i E ) hash_fn ( @ b E E ) eq_fn → ( Set E ) {
    : ( Set E ) out ( set_new [E] )
    : ( @ v E ) keep_in_b \ E x → v {
        ? ( set_contains [E] b x hash_fn eq_fn )
        { ( set_add [E] out x hash_fn eq_fn ) }
        {}
    }
    ( set_each [E] a keep_in_b )
    ^ out
}

// out = a \ b   (elements in a but not b)
@ set_diff [E] ( Set E ) a ( Set E ) b ( @ i E ) hash_fn ( @ b E E ) eq_fn → ( Set E ) {
    : ( Set E ) out ( set_new [E] )
    : ( @ v E ) keep_not_in_b \ E x → v {
        ? ( set_contains [E] b x hash_fn eq_fn ) {} {
            ( set_add [E] out x hash_fn eq_fn )
        }
    }
    ( set_each [E] a keep_not_in_b )
    ^ out
}
