// stdlib/dist/replicator.nu — CRDT gossip wiring (§7.4 Phase 6). Turns the
// dist/crdt types into something that travels: each CRDT serializes to an
// opaque byte payload that rides net/transport (transport_send to a peer or
// transport_broadcast to the group), and `*_merge_bytes` decodes a received
// payload and merges it into the local replica. Because the merge is a CRDT
// merge, repeated anti-entropy exchanges converge with no coordination.
//
// Pure (no transport import) so the codecs + convergence are deterministically
// testable; the live loop is a thin adapter (gossip local state on a timer,
// merge_bytes on receipt — see examples/replicated_counter.nu).
//
// Wire: integers are 8-byte big-endian (i64 bit pattern via u64), counts are
// 2-byte big-endian.
//   PNCounter : u16 ninc, (i64 id, i64 amt)*ninc, u16 ndec, (i64 id, i64 amt)*ndec
//   LwwReg    : i64 value, i64 ts, i64 replica
//   OrSet     : tags(adds) ++ tags(tombs);  tags = u16 n, (i64 elem,
//               i64 replica, i64 seq)*n
// PNCounter slots carry their replica id on the wire so a receiver merges by
// id, not by position — replicas discovered in different orders still converge.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/dist/crdt.nu`
$ `stdlib/dist/ring.nu`

: RcCur { ( Vec u ) buf  i off }
@ __rc_u16 *RcCur c → i { : i v ?? ( bytes_read_u16_be . c buf . c off ) { T x → # i x F → 0 } = . c off + . c off 2 ^ v }
@ __rc_u64 *RcCur c → i { : i v ?? ( bytes_read_u64_be . c buf . c off ) { T x → # i x F → 0 } = . c off + . c off 8 ^ v }

// ── PNCounter ────────────────────────────────────────────────────
// Emit the sparse (id, amt) slots in ASCENDING id order so the encoding is
// CANONICAL: two replicas holding the same logical state (possibly inserted in
// different orders) produce byte-identical output, which is what makes the
// crdt_digest anti-entropy compare equal when they are in sync.
@ __pn_put ( Vec u ) b ( Vec i ) ids ( Vec i ) amts → v {
    : i n ( vec_len [i] ids )
    ( bytes_push_u16_be b # u16 n )
    : ( Vec i ) used ( vec_new [i] )
    : ~ i u 0
    ~ < u n { ( vec_push [i] used 0 ) = u + u 1 }
    : ~ i out 0
    ~ < out n {
        : ~ i best - 0 1
        : ~ i bid 0
        : ~ i k 0
        ~ < k n {
            ? == ?? ( vec_get [i] used k ) { T x → x F → 1 } 0 {
                : i idk ?? ( vec_get [i] ids k ) { T x → x F → 0 }
                ? | == best - 0 1 < idk bid { = best k = bid idk } {}
            } {}
            = k + k 1
        }
        ( vec_set [i] used best 1 )
        ( bytes_push_u64_be b # u64 ?? ( vec_get [i] ids best ) { T t → t F → 0 } )
        ( bytes_push_u64_be b # u64 ?? ( vec_get [i] amts best ) { T t → t F → 0 } )
        = out + out 1
    }
    ( vec_free [i] used )
}
@ pncounter_encode *PNCounter c → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( __pn_put b . c inc_id . c inc_amt )
    ( __pn_put b . c dec_id . c dec_amt )
    ^ b
}
@ __pn_get *RcCur cur ( Vec i ) ids ( Vec i ) amts → v {
    : i n ( __rc_u16 cur )
    : ~ i k 0
    ~ < k n { ( vec_push [i] ids ( __rc_u64 cur ) ) ( vec_push [i] amts ( __rc_u64 cur ) ) = k + k 1 }
}
@ pncounter_decode ( Vec u ) buf → *PNCounter {
    : *PNCounter c ( pncounter_new )
    : *RcCur cur # *RcCur ( nurl_alloc Z RcCur )
    = . cur buf buf
    = . cur off 0
    ( __pn_get cur . c inc_id . c inc_amt )
    ( __pn_get cur . c dec_id . c dec_amt )
    ( nurl_free # s cur )
    ^ c
}
// Decode a peer's encoded counter and merge it into this one.
@ pncounter_merge_bytes *PNCounter c ( Vec u ) buf → v {
    : *PNCounter o ( pncounter_decode buf )
    ( pncounter_merge c o )
    ( pncounter_free o )
}

// ── LwwReg ───────────────────────────────────────────────────────
@ lww_encode LwwReg r → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( bytes_push_u64_be b # u64 . r value )
    ( bytes_push_u64_be b # u64 . r ts )
    ( bytes_push_u64_be b # u64 . r replica )
    ^ b
}
@ lww_decode ( Vec u ) buf → LwwReg {
    : *RcCur cur # *RcCur ( nurl_alloc Z RcCur )
    = . cur buf buf
    = . cur off 0
    : i v ( __rc_u64 cur )
    : i ts ( __rc_u64 cur )
    : i rep ( __rc_u64 cur )
    ( nurl_free # s cur )
    ^ @ LwwReg { v ts rep }
}
@ lww_merge_bytes LwwReg r ( Vec u ) buf → LwwReg { ^ ( lww_merge r ( lww_decode buf ) ) }

// ── OrSet ────────────────────────────────────────────────────────
@ __ortags_put ( Vec u ) b ( Vec s ) tags → v {
    : i n ( vec_len [s] tags )
    ( bytes_push_u16_be b # u16 n )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] tags k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *OrTag t # *OrTag pp
            ( bytes_push_u64_be b # u64 . t elem )
            ( bytes_push_u64_be b # u64 . t replica )
            ( bytes_push_u64_be b # u64 . t seq )
        } {}
        = k + k 1
    }
}
@ orset_encode *OrSet s → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( __ortags_put b . s adds )
    ( __ortags_put b . s tombs )
    ^ b
}
@ __ortags_get *RcCur cur ( Vec s ) into → v {
    : i n ( __rc_u16 cur )
    : ~ i k 0
    ~ < k n {
        // NB: locals must NOT shadow OrTag field names — on the field-STORE
        // path a local int var of a field's name is (intentionally) read as
        // an array index, not a field (see core/vec.nu's `= . data idx x`).
        : i ev ( __rc_u64 cur )
        : i rv ( __rc_u64 cur )
        : i sv ( __rc_u64 cur )
        : *OrTag t # *OrTag ( nurl_alloc Z OrTag )
        = . t elem ev
        = . t replica rv
        = . t seq sv
        ( vec_push [s] into # s t )
        = k + k 1
    }
}
@ orset_decode ( Vec u ) buf → *OrSet {
    : *OrSet s ( orset_new )
    : *RcCur cur # *RcCur ( nurl_alloc Z RcCur )
    = . cur buf buf
    = . cur off 0
    ( __ortags_get cur . s adds )
    ( __ortags_get cur . s tombs )
    ( nurl_free # s cur )
    ^ s
}
@ orset_merge_bytes *OrSet s ( Vec u ) buf → v {
    : *OrSet o ( orset_decode buf )
    ( orset_merge s o )
    ( orset_free o )
}

// ════════════════════════════════════════════════════════════════
// Ownership-scoped anti-entropy (§7.5 Phase 9.2).
//
// Whole-group CRDT broadcast is O(N) per delta and makes the ring decorative.
// Scope gossip to the ring instead: a key's state lives only on its replica
// set `ring_owners(key, R)`. On a local update the encoded delta is sent only
// to those R replicas (not the whole group); a non-replica never receives — or
// stores — a key's delta. Periodic anti-entropy compares a cheap DIGEST of the
// encoded state between replicas and transfers only on mismatch — so a node
// that newly joins a key's replica set (after a ring change) converges by
// pulling, without flooding. This is the same sharding the Phase 11 work
// dispatch reuses: `ring_owner(key)` runs the task, `ring_owners(key, R)` hold
// its result.
// ════════════════════════════════════════════════════════════════

@ __rep_veq ( Vec u ) a ( Vec u ) b → b {
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

// A compact divergence summary of an encoded CRDT (FNV-1a/64). Two replicas
// with equal digests are in sync and skip the transfer; differing digests
// trigger a pull. Cheap to gossip in an anti-entropy digest round.
@ crdt_digest ( Vec u ) bytes → i {
    : ~ i h 0xcbf29ce484222325
    : i n ( vec_len [u] bytes )
    : ~ i k 0
    ~ < k n {
        : i bj ?? ( vec_get [u] bytes k ) { T x → # i x F → 0 }
        = h ^^ h & bj 255
        = h * h 0x100000001b3
        = k + k 1
    }
    ^ h
}

// Is `self_pk` in the replica set for `key` (the R members clockwise from the
// key's position)? A node uses this to decide whether to store / accept a
// key's state.
@ is_replica *Ring r ( Vec u ) key i nrep ( Vec u ) self_pk → b {
    : ( Vec s ) owners ( ring_owners r key nrep )
    : i n ( vec_len [s] owners )
    : ~ b found F : ~ i k 0
    ~ & ! found < k n {
        : s pp ?? ( vec_get [s] owners k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *RingPoint p # *RingPoint pp
            ? ( __rep_veq . p owner self_pk ) { = found T } {}
        } {}
        = k + k 1
    }
    ( vec_free [s] owners )
    ^ found
}

// How many replicas a key actually has (≤ nrep, ≤ distinct members) — the
// fan-out of a delta. O(R), independent of cluster size N.
@ replica_fanout *Ring r ( Vec u ) key i nrep → i {
    : ( Vec s ) owners ( ring_owners r key nrep )
    : i n ( vec_len [s] owners )
    ( vec_free [s] owners )
    ^ n
}

// Do two encoded states agree? (Anti-entropy: skip the pull when they do.)
@ crdt_in_sync ( Vec u ) a ( Vec u ) b → b { ^ == ( crdt_digest a ) ( crdt_digest b ) }
