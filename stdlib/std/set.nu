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
//   set_new / set_with_cap → owned Set; caller MUST set_free when done.
//   The set borrows keys (stores them by value/copy). For Set[s] (raw
//   string keys) the caller keeps the strings alive until removed.
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
// `hash_int`/`eq_int` from stdlib/std/hashmap.nu).

$ `stdlib/core/mem.nu`
$ `stdlib/std/hashmap.nu`

: Set [E] { s ctl }

// ── Internal helpers ────────────────────────────────────────────────

@ __set_keys_raw   s ctl → s { ^ #s ( nurl_peek ctl 0 ) }
@ __set_states_raw s ctl → s { ^ #s ( nurl_peek ctl 1 ) }
@ __set_len_raw    s ctl → i { ^ ( nurl_peek ctl 2 ) }
@ __set_cap_raw    s ctl → i { ^ ( nurl_peek ctl 3 ) }
@ __set_tomb_raw   s ctl → i { ^ ( nurl_peek ctl 4 ) }

@ __set_alloc_buffers [E] s ctl i cap → v {
  : s keys ( nurl_zalloc * Z E cap )
  : s states ( nurl_zalloc * 8 cap )
  ( nurl_poke ctl 0 # i keys )
  ( nurl_poke ctl 1 # i states )
  ( nurl_poke ctl 3 cap )
}

// __set_probe_for: linear-probe scan starting at hash & mask.
//   On match → returns slot index (≥0).
//   On miss  → returns -(insert_idx + 1)  (always < 0)
//   Caller decodes via insert_idx = -slot - 1.
//   Pre-condition: cap > 0 (callers resize proactively before probing).
@ __set_probe_for [E] s ctl E key (@ i E) hash_fn (@ b E E) eq_fn → i {
  : i cap ( __set_cap_raw ctl )
  : i mask - cap 1
  : i h ( hash_fn key )
  : i start & h mask
  : *E keys #*E ( nurl_peek ctl 0 )
  : *i states #*i ( nurl_peek ctl 1 )
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
// power of two ≥ 8 ≥ target). Tombstones drop during rehash.
@ __set_grow [E] s ctl i target_cap (@ i E) hash_fn → v {
  : i old_cap ( __set_cap_raw ctl )
  : ~ i new_cap ? > old_cap 0 old_cap 8
  ~ < new_cap target_cap { = new_cap * new_cap 2 }
  : s old_keys_raw ( __set_keys_raw ctl )
  : s old_states_raw ( __set_states_raw ctl )
  : *E old_keys #*E old_keys_raw
  : *i old_states #*i old_states_raw
  ( __set_alloc_buffers [E] ctl new_cap )
  ( nurl_poke ctl 2 0 )
  ( nurl_poke ctl 4 0 )
  : i mask - new_cap 1
  : *E new_keys #*E ( nurl_peek ctl 0 )
  : *i new_states #*i ( nurl_peek ctl 1 )
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
  ( nurl_poke ctl 2 new_len )
  ? != 0 # i old_keys_raw   { ( nurl_free old_keys_raw   ) } {}
  ? != 0 # i old_states_raw { ( nurl_free old_states_raw ) } {}
}

// ── Constructors ────────────────────────────────────────────────────

@ set_new [E] → ( Set E ) {
  : s ctl ( nurl_zalloc 40 )
  ^ @ ( Set E ) { ctl }
}

@ set_with_cap [E] i n (@ i E) hash_fn → ( Set E ) {
  : s ctl ( nurl_zalloc 40 )
  : i want ? > n 0 n 0
  ? > want 0 { ( __set_grow [E] ctl want hash_fn ) } {}
  ^ @ ( Set E ) { ctl }
}

// ── Inspectors ──────────────────────────────────────────────────────

@ set_len [E] ( Set E ) st → i {
  ^ ( __set_len_raw . st ctl )
}

@ set_cap [E] ( Set E ) st → i {
  ^ ( __set_cap_raw . st ctl )
}

@ set_is_empty [E] ( Set E ) st → b {
  ^ == ( __set_len_raw . st ctl ) 0
}

// ── Mutation ────────────────────────────────────────────────────────

// Returns T if newly inserted, F if `x` was already present.
@ set_add [E] ( Set E ) st E key (@ i E) hash_fn (@ b E E) eq_fn → b {
  : s ctl . st ctl
  ? == ( __set_cap_raw ctl ) 0
    { ( __set_grow [E] ctl 8 hash_fn ) }
    {}
  : i len0 ( __set_len_raw ctl )
  : i tomb0 ( __set_tomb_raw ctl )
  : i cap0 ( __set_cap_raw ctl )
  ? >= * + + len0 tomb0 1 4 * cap0 3
    { ( __set_grow [E] ctl * cap0 2 hash_fn ) }
    {}

  : i slot ( __set_probe_for [E] ctl key hash_fn eq_fn )
  : *E keys #*E ( nurl_peek ctl 0 )
  : *i states #*i ( nurl_peek ctl 1 )
  ? >= slot 0
    { ^ F }
    { : i ins - -1 slot
      : i st_old . states ins
      = . keys ins key
      = . states ins 1
      ( nurl_poke ctl 2 + ( __set_len_raw ctl ) 1 )
      ? == st_old 2
        { ( nurl_poke ctl 4 - ( __set_tomb_raw ctl ) 1 ) }
        {}
      ^ T
    }
}

// Returns T if removed, F if `x` was absent.
@ set_remove [E] ( Set E ) st E key (@ i E) hash_fn (@ b E E) eq_fn → b {
  : s ctl . st ctl
  ? == ( __set_cap_raw ctl ) 0 { ^ F } {}
  : i slot ( __set_probe_for [E] ctl key hash_fn eq_fn )
  ? < slot 0 { ^ F } {}
  : *i states #*i ( nurl_peek ctl 1 )
  = . states slot 2
  ( nurl_poke ctl 2 - ( __set_len_raw ctl ) 1 )
  ( nurl_poke ctl 4 + ( __set_tomb_raw ctl ) 1 )
  ^ T
}

@ set_contains [E] ( Set E ) st E key (@ i E) hash_fn (@ b E E) eq_fn → b {
  : s ctl . st ctl
  ? == ( __set_cap_raw ctl ) 0 { ^ F } {}
  : i slot ( __set_probe_for [E] ctl key hash_fn eq_fn )
  ^ >= slot 0
}

// ── Higher-order ────────────────────────────────────────────────────

@ set_each [E] ( Set E ) st (@ v E) f → v {
  : s ctl . st ctl
  : i cap ( __set_cap_raw ctl )
  ? > cap 0 {
    : *E keys #*E ( nurl_peek ctl 0 )
    : *i states #*i ( nurl_peek ctl 1 )
    : ~ i i 0
    ~ < i cap {
      ? == . states i 1 { ( f . keys i ) } {}
      = i + i 1
    }
  } {}
}

@ set_fold [E B] ( Set E ) st B init (@ B B E) f → B {
  : s ctl . st ctl
  : i cap ( __set_cap_raw ctl )
  : ~ B acc init
  ? > cap 0 {
    : *E keys #*E ( nurl_peek ctl 0 )
    : *i states #*i ( nurl_peek ctl 1 )
    : ~ i i 0
    ~ < i cap {
      ? == . states i 1 { = acc ( f acc . keys i ) } {}
      = i + i 1
    }
  } {}
  ^ acc
}

// ── Cleanup ─────────────────────────────────────────────────────────

@ set_free [E] ( Set E ) st → v {
  : s ctl . st ctl
  : s keys ( __set_keys_raw ctl )
  : s states ( __set_states_raw ctl )
  ? != 0 # i keys   { ( nurl_free keys ) } {}
  ? != 0 # i states { ( nurl_free states ) } {}
  ( nurl_free ctl )
}

// Drop-aware free: invoke `drop` for every live element before
// releasing the buffers. Use for Set[String] etc.
@ set_free_with [E] ( Set E ) st (@ v E) drop → v {
  ( set_each [E] st drop )
  ( set_free [E] st )
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
@ set_union [E] ( Set E ) a ( Set E ) b (@ i E) hash_fn (@ b E E) eq_fn → ( Set E ) {
  : ( Set E ) out ( set_new [E] )
  : (@ v E) add_each \ E x → v { ( set_add [E] out x hash_fn eq_fn ) }
  ( set_each [E] a add_each )
  ( set_each [E] b add_each )
  ^ out
}

// out = a ∩ b
@ set_intersect [E] ( Set E ) a ( Set E ) b (@ i E) hash_fn (@ b E E) eq_fn → ( Set E ) {
  : ( Set E ) out ( set_new [E] )
  : (@ v E) keep_in_b \ E x → v {
    ? ( set_contains [E] b x hash_fn eq_fn )
      { ( set_add [E] out x hash_fn eq_fn ) }
      {}
  }
  ( set_each [E] a keep_in_b )
  ^ out
}

// out = a \ b   (elements in a but not b)
@ set_diff [E] ( Set E ) a ( Set E ) b (@ i E) hash_fn (@ b E E) eq_fn → ( Set E ) {
  : ( Set E ) out ( set_new [E] )
  : (@ v E) keep_not_in_b \ E x → v {
    ? ( set_contains [E] b x hash_fn eq_fn ) {} {
      ( set_add [E] out x hash_fn eq_fn )
    }
  }
  ( set_each [E] a keep_not_in_b )
  ^ out
}
