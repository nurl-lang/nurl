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
//   PNCounter : u16 ninc, i64*ninc, u16 ndec, i64*ndec
//   LwwReg    : i64 value, i64 ts, i64 replica
//   OrSet     : tags(adds) ++ tags(tombs);  tags = u16 n, (i64 elem,
//               i64 replica, i64 seq)*n

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/dist/crdt.nu`

: RcCur { ( Vec u ) buf  i off }
@ __rc_u16 *RcCur c → i { : i v ?? ( bytes_read_u16_be . c buf . c off ) { T x → # i x F → 0 } = . c off + . c off 2 ^ v }
@ __rc_u64 *RcCur c → i { : i v ?? ( bytes_read_u64_be . c buf . c off ) { T x → # i x F → 0 } = . c off + . c off 8 ^ v }

// ── PNCounter ────────────────────────────────────────────────────
@ __pn_put ( Vec u ) b ( Vec i ) v → v {
    : i n ( vec_len [i] v )
    ( bytes_push_u16_be b # u16 n )
    : ~ i k 0
    ~ < k n {
        : i x ?? ( vec_get [i] v k ) { T t → t F → 0 }
        ( bytes_push_u64_be b # u64 x )
        = k + k 1
    }
}
@ pncounter_encode *PNCounter c → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( __pn_put b . c inc )
    ( __pn_put b . c dec )
    ^ b
}
@ __pn_get *RcCur cur ( Vec i ) into → v {
    : i n ( __rc_u16 cur )
    : ~ i k 0
    ~ < k n { ( vec_push [i] into ( __rc_u64 cur ) ) = k + k 1 }
}
@ pncounter_decode ( Vec u ) buf → *PNCounter {
    : *PNCounter c ( pncounter_new )
    : *RcCur cur # *RcCur ( nurl_alloc Z RcCur )
    = . cur buf buf
    = . cur off 0
    ( __pn_get cur . c inc )
    ( __pn_get cur . c dec )
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
