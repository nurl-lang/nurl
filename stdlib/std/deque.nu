// stdlib/std/deque.nu — owned generic double-ended queue (ring buffer)
//
// A growable circular buffer with O(1) amortized push/pop at BOTH ends
// and O(1) indexed access. Backed by a single contiguous allocation; on
// overflow the buffer doubles and the live elements are unwrapped into
// logical order (head reset to 0).
//
// The handle ( Deque A ) owns a boxed control record: the element buffer
// (a RawBlock, which releases itself), its capacity, the head index and
// the live length. Dropping the deque drops its live elements; the record
// and the buffer go with the handle's fields — nothing here releases
// memory by hand.
//
// Ownership mirrors Vec: deque_new returns an owned Deque, dropped with its
// elements by its owner at scope exit (docs/MEMORY.md §7.6); deque_free
// releases early, deque_free_with hands each element to a closure first.
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
//   ( deque_clear      [A] d )            → v             drops the elements, keeps the buffer
//   ( deque_free       [A] d )            → v
//   ( deque_free_with  [A] d drop )       → v   drop : (@ v A)

$ `stdlib/core/mem.nu`
$ `stdlib/core/box.nu`

: DqCtl { RawBlock buf i cap i head i len }

: Deque [A] { ( Box DqCtl ) ctl }

// ── Internal ──────────────────────────────────────────────────────────

// Ensure at least one free slot; double + unwrap when full. Safe at
// cap 0 (the copy loop is empty and `% … cap` never runs). The elements
// move bitwise into the new buffer; the old one is released as it is
// replaced, holding nothing it owns any more.
@ __dq_ensure [A] * DqCtl c → v {
    : i cap . c cap
    : i len . c len
    ? >= len cap {
        : i newcap ? == cap 0 4 * cap 2
        : i head . c head
        : RawBlock nb ( raw_block ( alloc_size Z A newcap ) )
        : *A nd # *A ( raw_block_ptr nb )
        : *A od # *A ( raw_block_ptr . c buf )
        : ~ i i 0
        ~ < i len {
            : i src % + head i cap
            = . nd i . od src
            = i + i 1
        }
        = . c buf nb
        = . c cap newcap
        = . c head 0
    } {}
}

// ── Constructor / inspectors ──────────────────────────────────────────

@ deque_new [A] → ( Deque A ) {
    ^ @ ( Deque A ) { ( box_new [DqCtl] @ DqCtl { ( raw_block 0 ) 0 0 0 } ) }
}

@ deque_len [A] ( Deque A ) d → i {
    ^ . ( box_ptr [DqCtl] . d ctl ) len
}

@ deque_is_empty [A] ( Deque A ) d → b {
    ^ == . ( box_ptr [DqCtl] . d ctl ) len 0
}

// ── Push ──────────────────────────────────────────────────────────────

@ deque_push_back [A] ( Deque A ) d A x → v {
    : *DqCtl c ( box_ptr [DqCtl] . d ctl )
    ( __dq_ensure [A] c )
    : *A data # *A ( raw_block_ptr . c buf )
    : i pos % + . c head . c len . c cap
    = . data pos x
    = . c len + . c len 1
}

@ deque_push_front [A] ( Deque A ) d A x → v {
    : *DqCtl c ( box_ptr [DqCtl] . d ctl )
    ( __dq_ensure [A] c )
    : i cap . c cap
    : i nh % + - . c head 1 cap cap
    : *A data # *A ( raw_block_ptr . c buf )
    = . data nh x
    = . c head nh
    = . c len + . c len 1
}

// ── Pop ───────────────────────────────────────────────────────────────

@ deque_pop_front [A] ( Deque A ) d → ?A {
    : *DqCtl c ( box_ptr [DqCtl] . d ctl )
    : i len . c len
    ? == len 0 { ^ @ ?A { F # A 0 } } {}
    : i head . c head
    : *A data # *A ( raw_block_ptr . c buf )
    : A x . data head
    ( mem_take x )  // the element leaves the container
    = . c head % + head 1 . c cap
    = . c len - len 1
    ^ @ ?A { T x }
}

@ deque_pop_back [A] ( Deque A ) d → ?A {
    : *DqCtl c ( box_ptr [DqCtl] . d ctl )
    : i len . c len
    ? == len 0 { ^ @ ?A { F # A 0 } } {}
    : *A data # *A ( raw_block_ptr . c buf )
    : i idx % + . c head - len 1 . c cap
    : A x . data idx
    ( mem_take x )  // the element leaves the container
    = . c len - len 1
    ^ @ ?A { T x }
}

// ── Peek / index (0 = front) ──────────────────────────────────────────

@ deque_get [A] ( Deque A ) d i idx → ?A {
    : *DqCtl c ( box_ptr [DqCtl] . d ctl )
    ? | < idx 0 >= idx . c len { ^ @ ?A { F # A 0 } } {}
    : *A data # *A ( raw_block_ptr . c buf )
    : A x . data % + . c head idx . c cap
    ^ @ ?A { T x }
}

@ deque_front [A] ( Deque A ) d → ?A {
    ^ ( deque_get [A] d 0 )
}

@ deque_back [A] ( Deque A ) d → ?A {
    : i len . ( box_ptr [DqCtl] . d ctl ) len
    ? == len 0 { ^ @ ?A { F # A 0 } } {}
    ^ ( deque_get [A] d - len 1 )
}

// ── Clear / free ──────────────────────────────────────────────────────

// Drop every live element (no work, and no loop, for elements that own
// nothing); the length goes to zero first.
@ __dq_drop_elems [A] * DqCtl c → v {
    : i len . c len
    : i cap . c cap
    : i head . c head
    : *A data # *A ( raw_block_ptr . c buf )
    = . c head 0
    = . c len 0
    : ~ i i 0
    ~ < i len {
        : A e . data % + head i cap
        ( mem_take e )
        = i + i 1
    }
}

// The elements are dropped; the buffer stays for reuse.
@ deque_clear [A] ( Deque A ) d → v {
    ( __dq_drop_elems [A] ( box_ptr [DqCtl] . d ctl ) )
}

// What dropping a deque does (its owner does it at scope exit — docs/
// MEMORY.md §7.6): the live elements; the control record and its buffer
// go with the handle's field.
@ Deque_drop [A] sink ( Deque A ) d → v {
    ? ( box_is_null [DqCtl] . d ctl ) {} { ( __dq_drop_elems [A] ( box_ptr [DqCtl] . d ctl ) ) }
}

// What the reference-count cycle collector sees in a deque (docs/MEMORY.md
// §7.7): every live element.
@ Deque_trace [A] ( Deque A ) d s vis → v {
    ? ( box_is_null [DqCtl] . d ctl ) { ^ } {}
    : *DqCtl c ( box_ptr [DqCtl] . d ctl )
    : *A data # *A ( raw_block_ptr . c buf )
    : ~ i i 0
    ~ < i . c len {
        ( mem_trace [A] . data % + . c head i . c cap vis )
        = i + i 1
    }
}

// The thread crossing's check (docs/MEMORY.md §6.5): every live element.
@ Deque_sendck [A] ( Deque A ) d s what → v {
    ? ( box_is_null [DqCtl] . d ctl ) { ^ } {}
    : *DqCtl c ( box_ptr [DqCtl] . d ctl )
    : *A data # *A ( raw_block_ptr . c buf )
    : ~ i i 0
    ~ < i . c len {
        ( mem_send_check [A] . data % + . c head i . c cap what )
        = i + i 1
    }
}

// A copy that owns its own elements, in logical order (head at 0).
@ Deque_clone [A] ( Deque A ) d → ( Deque A ) {
    : *DqCtl sc ( box_ptr [DqCtl] . d ctl )
    : i len . sc len
    : RawBlock nb ( raw_block ( alloc_size Z A len ) )
    : *A dd # *A ( raw_block_ptr nb )
    : *A sd # *A ( raw_block_ptr . sc buf )
    : ~ i i 0
    ~ < i len {
        : A e . sd % + . sc head i . sc cap
        = . dd i ( mem_dup e )
        = i + i 1
    }
    ^ @ ( Deque A ) { ( box_new [DqCtl] @ DqCtl { nb len 0 len } ) }
}

// Early release: exactly what dropping `d` does (Deque_drop).
@ deque_free [A] sink ( Deque A ) d → v {}

// Early release with a last look at every live element (see
// vec_free_with); then `d` goes as `deque_free` releases it.
@ deque_free_with [A] sink ( Deque A ) d ( @ v A ) drop → v {
    : *DqCtl c ( box_ptr [DqCtl] . d ctl )
    : *A data # *A ( raw_block_ptr . c buf )
    : ~ i i 0
    ~ < i . c len {
        ( drop . data % + . c head i . c cap )
        = i + i 1
    }
}
