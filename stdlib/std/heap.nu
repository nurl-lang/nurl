// stdlib/std/heap.nu — owned generic binary heap / priority queue
//
// An array-backed binary heap over a ( Vec A ). The ordering is decided
// by a comparator `cmp : (@ i A A)` passed to every mutating call (the
// same convention as sort_by / binary_search): `cmp a b` returns < 0
// when `a` should leave the heap before `b`. So a comparator that
// orders ascending yields a MIN-heap (smallest pops first); pass a
// reversed comparator for a max-heap / highest-priority-first queue.
//
// The same comparator must be used across a heap's lifetime — mixing
// orderings corrupts the heap invariant.
//
//   ( heap_new       [A] )            → ( Heap A )   empty
//   ( heap_len       [A] h )          → i
//   ( heap_is_empty  [A] h )          → b
//   ( heap_push      [A] h x cmp )    → v            O(log n)
//   ( heap_pop       [A] h cmp )      → ? A          remove + return top, O(log n)
//   ( heap_peek      [A] h )          → ? A          inspect top, no remove
//   ( heap_free      [A] h )          → v            trivial element types
//   ( heap_free_with [A] h drop )     → v   drop : (@ v A)

$ `stdlib/core/vec.nu`

: Heap [A] { ( Vec A ) data }

// ── Internal sift helpers (operate on the raw element buffer) ─────────

@ __heap_swap [A] * A data i i i j → v {
    : A t . data i
    = . data i . data j
    = . data j t
}

@ __heap_sift_up [A] * A data i start ( @ i A A ) cmp → v {
    : ~ i i start
    : ~ b go ? > i 0 T F
    ~ go {
        : i parent / - i 1 2
        ? < ( cmp . data i . data parent ) 0 {
            ( __heap_swap [A] data i parent )
            = i parent
            = go ? > i 0 T F
        } {
            = go F
        }
    }
}

@ __heap_sift_down [A] * A data i start i n ( @ i A A ) cmp → v {
    : ~ i i start
    : ~ b go T
    ~ go {
        : i l + * 2 i 1
        : i r + * 2 i 2
        : ~ i small i
        ? & < l n < ( cmp . data l . data small ) 0 { = small l } {}
        ? & < r n < ( cmp . data r . data small ) 0 { = small r } {}
        ? == small i {
            = go F
        } {
            ( __heap_swap [A] data i small )
            = i small
        }
    }
}

// ── API ───────────────────────────────────────────────────────────────

@ heap_new [A] → ( Heap A ) {
    ^ @ ( Heap A ) { ( vec_new [A] ) }
}

@ heap_len [A] ( Heap A ) h → i {
    ^ ( vec_len [A] . h data )
}

@ heap_is_empty [A] ( Heap A ) h → b {
    ^ == ( vec_len [A] . h data ) 0
}

@ heap_push [A] ( Heap A ) h A x ( @ i A A ) cmp → v {
    ( vec_push [A] . h data x )
    : i n ( vec_len [A] . h data )
    : *A d ( vec_data [A] . h data )
    ( __heap_sift_up [A] d - n 1 cmp )
}

@ heap_peek [A] ( Heap A ) h → ?A {
    ^ ( vec_get [A] . h data 0 )
}

@ heap_pop [A] ( Heap A ) h ( @ i A A ) cmp → ?A {
    : i n ( vec_len [A] . h data )
    ? == n 0 { ^ @ ?A { F # A 0 } } {}
    : *A d ( vec_data [A] . h data )
    : A root . d 0
    // Move the last element to the root, drop the (now duplicated) tail
    // slot, then sift the new root down over the shrunken length.
    = . d 0 . d - n 1
    ( vec_pop [A] . h data )
    : i m - n 1
    ? > m 1 { ( __heap_sift_down [A] d 0 m cmp ) } {}
    ^ @ ?A { T root }
}

@ heap_free [A] ( Heap A ) h → v {
    ( vec_free [A] . h data )
}

@ heap_free_with [A] ( Heap A ) h ( @ v A ) drop → v {
    ( vec_free_with [A] . h data drop )
}
