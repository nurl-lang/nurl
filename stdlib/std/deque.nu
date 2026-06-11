// stdlib/std/deque.nu — owned generic double-ended queue (ring buffer)
//
// A growable circular buffer with O(1) amortized push/pop at BOTH ends
// and O(1) indexed access. Backed by a single contiguous allocation; on
// overflow the buffer doubles and the live elements are unwrapped into
// logical order (head reset to 0).
//
// The handle ( Deque A ) wraps a heap control block of four slots:
//   slot 0 = element buffer pointer   slot 2 = head index
//   slot 1 = capacity (in elements)   slot 3 = length (live elements)
//
// Ownership mirrors Vec: deque_new returns an owned Deque the caller
// must release. For trivial element types (i, f, b, raw pointers) use
// deque_free; for owned element types (String, nested Vec, …) use
// deque_free_with with a per-element drop closure.
//
//   ( deque_new        [A] )              → ( Deque A )   empty, no alloc
//   ( deque_len        [A] d )            → i
//   ( deque_is_empty   [A] d )            → b
//   ( deque_push_back  [A] d x )          → v
//   ( deque_push_front [A] d x )          → v
//   ( deque_pop_front  [A] d )            → ? A           None when empty
//   ( deque_pop_back   [A] d )            → ? A           None when empty
//   ( deque_front      [A] d )            → ? A           peek, no remove
//   ( deque_back       [A] d )            → ? A           peek, no remove
//   ( deque_get        [A] d i )          → ? A           0 = front
//   ( deque_clear      [A] d )            → v             keeps the buffer
//   ( deque_free       [A] d )            → v
//   ( deque_free_with  [A] d drop )       → v   drop : (@ v A)


: Deque [A] { s ctl }

// ── Internal ──────────────────────────────────────────────────────────

// Ensure at least one free slot; double + unwrap when full. Safe at
// cap 0 (the copy loop is empty and `% … cap` never runs).
@ __dq_ensure [A] s ctl → v {
    : i cap ( nurl_peek ctl 1 )
    : i len ( nurl_peek ctl 3 )
    ? >= len cap {
        : i newcap ? == cap 0 4 * cap 2
        : i head ( nurl_peek ctl 2 )
        : s oldbuf # s ( nurl_peek ctl 0 )
        : s newbuf ( nurl_alloc * Z A newcap )
        : *A nd # *A newbuf
        : *A od # *A oldbuf
        : ~ i i 0
        ~ < i len {
            : i src % + head i cap
            = . nd i . od src
            = i + i 1
        }
        ? != 0 # i oldbuf { ( nurl_free oldbuf ) } {}
        ( nurl_poke ctl 0 # i newbuf )
        ( nurl_poke ctl 1 newcap )
        ( nurl_poke ctl 2 0 )
    } {}
}

// ── Constructor / inspectors ──────────────────────────────────────────

@ deque_new [A] → ( Deque A ) {
    : s ctl ( nurl_zalloc 32 )
    ^ @ ( Deque A ) { ctl }
}

@ deque_len [A] ( Deque A ) d → i {
    ^ ( nurl_peek . d ctl 3 )
}

@ deque_is_empty [A] ( Deque A ) d → b {
    ^ == ( nurl_peek . d ctl 3 ) 0
}

// ── Push ──────────────────────────────────────────────────────────────

@ deque_push_back [A] ( Deque A ) d A x → v {
    : s ctl . d ctl
    ( __dq_ensure [A] ctl )
    : i cap ( nurl_peek ctl 1 )
    : i head ( nurl_peek ctl 2 )
    : i len ( nurl_peek ctl 3 )
    : *A data # *A ( nurl_peek ctl 0 )
    : i pos % + head len cap
    = . data pos x
    ( nurl_poke ctl 3 + len 1 )
}

@ deque_push_front [A] ( Deque A ) d A x → v {
    : s ctl . d ctl
    ( __dq_ensure [A] ctl )
    : i cap ( nurl_peek ctl 1 )
    : i head ( nurl_peek ctl 2 )
    : i len ( nurl_peek ctl 3 )
    : i nh % + - head 1 cap cap
    : *A data # *A ( nurl_peek ctl 0 )
    = . data nh x
    ( nurl_poke ctl 2 nh )
    ( nurl_poke ctl 3 + len 1 )
}

// ── Pop ───────────────────────────────────────────────────────────────

@ deque_pop_front [A] ( Deque A ) d → ?A {
    : s ctl . d ctl
    : i len ( nurl_peek ctl 3 )
    ? == len 0 { ^ @ ?A { F # A 0 } } {}
    : i cap ( nurl_peek ctl 1 )
    : i head ( nurl_peek ctl 2 )
    : *A data # *A ( nurl_peek ctl 0 )
    : A x . data head
    ( nurl_poke ctl 2 % + head 1 cap )
    ( nurl_poke ctl 3 - len 1 )
    ^ @ ?A { T x }
}

@ deque_pop_back [A] ( Deque A ) d → ?A {
    : s ctl . d ctl
    : i len ( nurl_peek ctl 3 )
    ? == len 0 { ^ @ ?A { F # A 0 } } {}
    : i cap ( nurl_peek ctl 1 )
    : i head ( nurl_peek ctl 2 )
    : *A data # *A ( nurl_peek ctl 0 )
    : i idx % + head - len 1 cap
    : A x . data idx
    ( nurl_poke ctl 3 - len 1 )
    ^ @ ?A { T x }
}

// ── Peek / index (0 = front) ──────────────────────────────────────────

@ deque_get [A] ( Deque A ) d i idx → ?A {
    : s ctl . d ctl
    : i len ( nurl_peek ctl 3 )
    ? | < idx 0 >= idx len { ^ @ ?A { F # A 0 } } {}
    : i cap ( nurl_peek ctl 1 )
    : i head ( nurl_peek ctl 2 )
    : *A data # *A ( nurl_peek ctl 0 )
    : i pos % + head idx cap
    : A x . data pos
    ^ @ ?A { T x }
}

@ deque_front [A] ( Deque A ) d → ?A {
    ^ ( deque_get [A] d 0 )
}

@ deque_back [A] ( Deque A ) d → ?A {
    : i len ( nurl_peek . d ctl 3 )
    ? == len 0 { ^ @ ?A { F # A 0 } } {}
    ^ ( deque_get [A] d - len 1 )
}

// ── Clear / free ──────────────────────────────────────────────────────

@ deque_clear [A] ( Deque A ) d → v {
    ( nurl_poke . d ctl 2 0 )
    ( nurl_poke . d ctl 3 0 )
}

@ deque_free [A] ( Deque A ) d → v {
    : s ctl . d ctl
    : s buf # s ( nurl_peek ctl 0 )
    ? != 0 # i buf { ( nurl_free buf ) } {}
    ( nurl_free ctl )
}

@ deque_free_with [A] ( Deque A ) d ( @ v A ) drop → v {
    : s ctl . d ctl
    : i len ( nurl_peek ctl 3 )
    : i cap ( nurl_peek ctl 1 )
    : i head ( nurl_peek ctl 2 )
    : *A data # *A ( nurl_peek ctl 0 )
    : ~ i i 0
    ~ < i len {
        : i pos % + head i cap
        ( drop . data pos )
        = i + i 1
    }
    : s buf # s ( nurl_peek ctl 0 )
    ? != 0 # i buf { ( nurl_free buf ) } {}
    ( nurl_free ctl )
}
