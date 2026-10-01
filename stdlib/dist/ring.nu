// stdlib/dist/ring.nu — consistent-hash ring over pubkey-addressed members
// (§7.4 Phase 6). Maps keys to the live member that OWNS them — the basis for
// sharding distributed work/state across the SWIM cluster (net/membership)
// with minimal disruption on churn.
//
// Each member is placed at `vnodes` pseudo-random points on a 64-bit ring
// (virtual nodes → even load + smooth rebalancing). A key hashes onto the
// ring and is owned by the next member clockwise; the n distinct members
// clockwise are its replica set. Removing a member only re-homes the keys it
// owned (the consistent-hashing property), not the whole keyspace.
//
// Hashing is FNV-1a/64 over raw bytes (native `^^` XOR + wrapping `*`),
// deterministic and well-distributed; ring points are kept sorted so lookup
// is a binary search. Pure + offline-testable; the caller rebuilds the ring
// from membership on join/leave (hysteresis to damp churn is a follow-up).
//
// A Ring is a handle: every copy is the same ring, and its last owner
// releases it (ring_free is an early release, optional). The *RingPoint
// pointers ring_owner / ring_owners hand out are the ring's, valid while
// it lives and is not changed.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/core/rcbox.nu`

@ __ring_cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

@ __ring_veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a )
    ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n {
        : i x ?? ( vec_get [u] a k ) { T t → # i t F → -1 }
        : i y ?? ( vec_get [u] b k ) { T t → # i t F → -2 }
        ? != x y { = e F } {}
        = k + k 1
    }
    ^ e
}

// FNV-1a 64-bit over a byte vector (wraps in i64 two's complement).
@ __ring_hash ( Vec u ) data → i {
    : ~ i h 0xcbf29ce484222325
    : i n ( vec_len [u] data )
    : ~ i k 0
    ~ < k n {
        : i bj ?? ( vec_get [u] data k ) { T x → # i x F → 0 }
        = h ^^ h & bj 255
        = h * h 0x100000001b3
        = k + k 1
    }
    ^ h
}

// Distinct ring position for member `pubkey`'s vnode `v`.
@ __ring_point_hash ( Vec u ) pubkey i v → i {
    : ( Vec u ) buf ( vec_with_cap [u] + ( vec_len [u] pubkey ) 4 )
    ( vec_extend [u] buf pubkey )
    ( bytes_push_u32_be buf # u32 v )
    : i h ( __ring_hash buf )
    ^ h
}

: RingPoint {
    i hash
    ( Vec u ) owner
}

: RingImpl {
    ( Vec s ) points  // *RingPoint, sorted ascending by signed hash
}

// A Ring is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: Ring { s ctl }

@ Ring_share Ring h → Ring { ^ @ Ring { # s ( rcbox_share # i . h ctl ) } }

@ Ring_drop sink Ring h → v {
    ( mem_forget h )
    ( rcbox_release [RingImpl] # i . h ctl )
}

@ __Ring_ptr Ring h → *RingImpl { ^ ( rcbox_ptr [RingImpl] # i . h ctl ) }

// The points are raw blocks the Vec only points at: releasing them is the
// ring's own drop, run by its last owner (the Vec goes after it).
% Drop RingImpl {
    @ drop RingImpl r → v {
        : i n ( vec_len [s] . r points )
        : ~ i k 0
        ~ < k n {
            : s pp ?? ( vec_get [s] . r points k ) { T x → x F → # s 0 }
            ? != # i pp 0 { : *RingPoint p # *RingPoint pp ( vec_free [u] . p owner ) ( nurl_free # s p ) } {}
            = k + k 1
        }
    }
}

@ ring_new → Ring {
    : i r__box ( rcbox_zero [RingImpl] )
    : *RingImpl r ( rcbox_ptr [RingImpl] r__box )
    = . r points ( vec_new [s] )
    ^ @ Ring { # s r__box }
}

// Let go of `r` now rather than at the end of its owner's scope.
@ ring_free sink Ring r → v {}

@ ring_point_count Ring r__h → i {
    : *RingImpl r ( __Ring_ptr r__h )
    ^ ( vec_len [s] . r points )
}

@ __ring_sort * RingImpl r → v {
    ( sort_by [s] . r points \ s a s b → i {
        : *RingPoint pa # *RingPoint a
        : *RingPoint pb # *RingPoint b
        : i ha . pa hash
        : i hb . pb hash
        ? < ha hb { ^ - 0 1 } {}
        ? > ha hb { ^ 1 } {}
        ^ 0
    } )
}

// Place a member at `vnodes` points on the ring.
@ ring_add_member Ring r__h ( Vec u ) pubkey i vnodes → v {
    : *RingImpl r ( __Ring_ptr r__h )
    : ~ i v 0
    ~ < v vnodes {
        : *RingPoint p # *RingPoint ( nurl_alloc Z RingPoint )
        = . p hash ( __ring_point_hash pubkey v )
        = . p owner ( __ring_cpy pubkey )
        ( vec_push [s] . r points # s p )
        = v + v 1
    }
    ( __ring_sort r )
}

// Remove all of a member's points (keys it owned re-home clockwise).
@ ring_remove_member Ring r__h ( Vec u ) pubkey → v {
    : *RingImpl r ( __Ring_ptr r__h )
    : ( Vec s ) keep ( vec_new [s] )
    : i n ( vec_len [s] . r points )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . r points k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *RingPoint p # *RingPoint pp
            ? ( __ring_veq . p owner pubkey ) { ( vec_free [u] . p owner ) ( nurl_free # s p ) } { ( vec_push [s] keep pp ) }
        } {}
        = k + k 1
    }
    ( vec_free [s] . r points )
    = . r points keep
}

// First point index with hash >= kh (binary search), wrapping to 0.
@ __ring_first_idx * RingImpl r i kh → i {
    : i n ( vec_len [s] . r points )
    : ~ i lo 0
    : ~ i hi n
    ~ < lo hi {
        : i mid + lo / - hi lo 2
        : s mp ?? ( vec_get [s] . r points mid ) { T x → x F → # s 0 }
        : *RingPoint pm # *RingPoint mp
        ? < . pm hash kh { = lo + mid 1 } { = hi mid }
    }
    ^ ? >= lo n 0 lo
}

// The *RingPoint owning `key` (0 on an empty ring). Borrowed (ring-owned).
@ ring_owner Ring r__h ( Vec u ) key → s {
    : *RingImpl r ( __Ring_ptr r__h )
    : i n ( vec_len [s] . r points )
    ? == n 0 { ^ # s 0 } {}
    : i kh ( __ring_hash key )
    : i idx ( __ring_first_idx r kh )
    ^ ?? ( vec_get [s] . r points idx ) { T x → x F → # s 0 }
}

// Owner pubkey for `key`, copied (caller frees). None on an empty ring.
@ ring_owner_pk Ring r__h ( Vec u ) key → ?( Vec u ) {
    : s pp ( ring_owner r__h key )
    ? == # i pp 0 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : *RingPoint p # *RingPoint pp
    ^ @ ?( Vec u ) { T ( __ring_cpy . p owner ) }
}

@ __owners_has ( Vec s ) acc ( Vec u ) pk → b {
    : i n ( vec_len [s] acc )
    : ~ b found F : ~ i k 0
    ~ & ! found < k n {
        : s pp ?? ( vec_get [s] acc k ) { T x → x F → # s 0 }
        ? != # i pp 0 { : *RingPoint p # *RingPoint pp ? ( __ring_veq . p owner pk ) { = found T } {} } {}
        = k + k 1
    }
    ^ found
}

// The replica set for `key`: up to `nrep` DISTINCT owners clockwise from the
// primary. Returns borrowed *RingPoint pointers (ring-owned); free only the
// container with vec_free [s].
@ ring_owners Ring r__h ( Vec u ) key i nrep → ( Vec s ) {
    : *RingImpl r ( __Ring_ptr r__h )
    : ( Vec s ) out ( vec_new [s] )
    : i n ( vec_len [s] . r points )
    ? == n 0 { ^ out } {}
    : i kh ( __ring_hash key )
    : i start ( __ring_first_idx r kh )
    : ~ i steps 0
    ~ & < steps n < ( vec_len [s] out ) nrep {
        : i idx % + start steps n
        : s pp ?? ( vec_get [s] . r points idx ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *RingPoint p # *RingPoint pp
            ? ! ( __owners_has out . p owner ) { ( vec_push [s] out pp ) } {}
        } {}
        = steps + steps 1
    }
    ^ out
}
