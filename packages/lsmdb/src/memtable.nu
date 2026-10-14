// packages/lsmdb/src/memtable.nu — the write buffer of the LSM tree: a
// skip list over a byte arena.
//
// Every write lands here first (after the WAL). The structure has to be
// three things at once: ordered (so a flush emits a sorted SSTable and a
// range scan needs no sorting), versioned (so a snapshot read can see the
// database as it was N writes ago), and cheap to build (a database does
// millions of these).
//
// The layout is index-based, not pointer-based: keys and values are
// appended to ONE growable arena, and a node is a row of integers —
// (key offset, key length, value offset, value length, sequence, kind)
// plus its forward links. Nothing is individually allocated or freed, so
// dropping the whole memtable is a handful of Vec drops, and a node is
// never invalidated by the arena growing under it (offsets, not pointers).
//
// Ordering is LevelDB's: key ascending, and for equal keys sequence
// DESCENDING — the newest version of a key sorts first. That single rule
// gives both "get the current value" (take the first match) and "get the
// value as of sequence S" (take the first match with seq <= S) from the
// same search.
//
//   ( mt_new seed )                       → MemTable   a value: its owner
//                                                    (the store) changes it
//                                                    through `inout`
//   ( mt_put m key val seq kind )         → v      kind: MT_PUT / MT_DEL
//   ( mt_find m key snap )                → i      node index, 0 = miss
//   ( mt_seek m key snap )                → i      first node >= key
//   ( mt_first m ) / ( mt_next m n )      → i      ordered walk, 0 = end
//   ( mt_key m n ) / ( mt_val m n )       → ( Vec u )   owned copies
//   ( mt_seq m n ) / ( mt_kind m n )      → i
//   ( mt_count m ) / ( mt_bytes m )       → i
//   ( mt_key_view m n )                   → ( Slice u )  the key in place
//   ( mt_free m )                         → v      early release (optional)

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: i MT_MAXLVL 12
: i MT_PUT 1
: i MT_DEL 0

: MemTable {
    ( Vec u ) arena
    ( Vec i ) koff
    ( Vec i ) klen
    ( Vec i ) voff
    ( Vec i ) vlen
    ( Vec i ) nseq
    ( Vec i ) nkind
    ( Vec i ) nlvl
    ( Vec i ) links
    i level
    i count
    i rng
}

// ── byte order ──────────────────────────────────────────────────────
//
// Bytewise, unsigned, shorter-is-smaller — the total order the whole
// package agrees on: memtable, SSTable, merge, scan.

@ lsm_bytes_cmp_view ( Slice u ) a ( Slice u ) b → i { ^ ( slice_bytes_cmp a b ) }

// Compare two whole byte vectors.
@ lsm_bytes_cmp ( Vec u ) a ( Vec u ) b → i {
    ^ ( slice_bytes_cmp ( slice_from_vec [u] a ) ( slice_from_vec [u] b ) )
}

// ── construction ────────────────────────────────────────────────────

@ mt_new i seed → MemTable {
    : ~ MemTable m @ MemTable { ( vec_new [u] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) 1 0 ? == seed 0 88172645463325252 seed }
    // Node 0 is the head sentinel, so index 0 doubles as "nil" — a link
    // can never legitimately point back at the head.
    : i _head ( __mt_alloc_node m 0 0 0 0 0 MT_PUT MT_MAXLVL )
    ^ m
}

// Let go of `m` now rather than at the end of its owner's scope.
@ mt_free sink MemTable m → v {}

@ __mt_alloc_node inout MemTable m i ko i kl i vo i vl i seq i kind i lvl → i {
    : i idx ( vec_len [i] . m koff )
    ( vec_push [i] . m koff ko )
    ( vec_push [i] . m klen kl )
    ( vec_push [i] . m voff vo )
    ( vec_push [i] . m vlen vl )
    ( vec_push [i] . m nseq seq )
    ( vec_push [i] . m nkind kind )
    ( vec_push [i] . m nlvl lvl )
    : ~ i l 0
    ~ < l MT_MAXLVL {
        ( vec_push [i] . m links 0 )
        = l + l 1
    }
    ^ idx
}

// ── accessors ───────────────────────────────────────────────────────

@ _mt_iat ( Vec i ) v i idx → i {
    ^ ?? ( vec_get [i] v idx ) { T x → x F _ → 0 }
}

@ __mt_link MemTable m i node i lvl → i {
    ^ ( _mt_iat . m links + * node MT_MAXLVL lvl )
}

@ __mt_set_link inout MemTable m i node i lvl i to → v {
    : b _ok ( vec_set [i] . m links + * node MT_MAXLVL lvl to )
}

@ mt_seq MemTable m i node → i { ^ ( _mt_iat . m nseq node ) }

@ mt_kind MemTable m i node → i { ^ ( _mt_iat . m nkind node ) }

@ mt_count MemTable m → i { ^ . m count }

// Bytes held: the arena plus the per-node integer rows. The store
// compares this against its memtable budget, so it has to count the
// index too — a million tiny keys is mostly index.
@ mt_bytes MemTable m → i {
    : i nodes ( vec_len [i] . m koff )
    ^ + ( vec_len [u] . m arena ) * nodes * 8 + 7 MT_MAXLVL
}

@ _mt_slice ( Vec u ) src i off i n → ( Vec u ) {
    : i cap ? > n 0 n 1
    : ( Vec u ) out ( vec_with_cap [u] cap )
    ? > n 0 { ( vec_extend_range [u] out src off n ) } {}
    ^ out
}

@ mt_key MemTable m i node → ( Vec u ) {
    ^ ( _mt_slice . m arena ( _mt_iat . m koff node ) ( _mt_iat . m klen node ) )
}

@ mt_val MemTable m i node → ( Vec u ) {
    ^ ( _mt_slice . m arena ( _mt_iat . m voff node ) ( _mt_iat . m vlen node ) )
}

// A node's key in place, for merge comparisons that must not allocate:
// a view of the arena, valid while the memtable is not written to.
@ mt_key_view MemTable m i node → ( Slice u ) {
    ^ ( slice_window [u] ( slice_from_vec [u] . m arena ) ( _mt_iat . m koff node ) ( _mt_iat . m klen node ) )
}

// ── ordering ────────────────────────────────────────────────────────

// Compare node `node` against the probe (key, seq) in memtable order:
// key ascending, sequence descending. <0 means the node sorts first.
@ __mt_cmp_node MemTable m i node ( Slice u ) probe i pseq → i {
    : i c ( slice_bytes_cmp ( mt_key_view m node ) probe )
    ? != c 0 { ^ c } {}
    : i ns ( _mt_iat . m nseq node )
    ? == ns pseq { ^ 0 } {}
    ^ ? > ns pseq -1 1
}

// xorshift64 — deterministic level draws, so a given write sequence
// always builds the same structure and tests can rely on it.
@ __mt_rand inout MemTable m → i {
    : ~ i x . m rng
    = x ^^ x << x 13
    = x ^^ x >> x 7
    = x ^^ x << x 17
    = . m rng x
    ^ & x 9223372036854775807
}

@ __mt_pick_level inout MemTable m → i {
    : ~ i lvl 1
    : ~ b climb T
    ~ climb {
        ? & < lvl MT_MAXLVL == 0 & ( __mt_rand m ) 3 { = lvl + lvl 1 } { = climb F }
    }
    ^ lvl
}

// Walk down the levels to the last node that sorts BEFORE the probe,
// recording the path in `prev` when it is non-empty.
@ __mt_descend MemTable m ( Slice u ) probe i pseq ( Vec i ) prev → i {
    : ~ i x 0
    : ~ i lv - . m level 1
    ~ >= lv 0 {
        : ~ b more T
        ~ more {
            : i nx ( __mt_link m x lv )
            ? == nx 0 { = more F } {
                ? < ( __mt_cmp_node m nx probe pseq ) 0 { = x nx } { = more F }
            }
        }
        ? > ( vec_len [i] prev ) lv { : b _ok ( vec_set [i] prev lv x ) } {}
        = lv - lv 1
    }
    ^ x
}

// ── insert ──────────────────────────────────────────────────────────

// Append (key, val) as a new version. Both are COPIED into the arena;
// the caller keeps ownership of the vectors it passed in.
@ mt_put inout MemTable m ( Vec u ) key ( Vec u ) val i seq i kind → v {
    : i kl ( vec_len [u] key )
    : i vl ? == kind MT_PUT ( vec_len [u] val ) 0
    : i ko ( vec_len [u] . m arena )
    ( vec_extend [u] . m arena key )
    : i vo ( vec_len [u] . m arena )
    ? > vl 0 { ( vec_extend [u] . m arena val ) } {}

    : ( Vec i ) prev ( vec_with_cap [i] MT_MAXLVL )
    : ~ i l 0
    ~ < l MT_MAXLVL { ( vec_push [i] prev 0 ) = l + l 1 }

    // (The probe is the caller's key: equal to the bytes just appended,
    // and not a view of the arena the descent reads.)
    : i _x ( __mt_descend m ( slice_from_vec [u] key ) seq prev )

    : i lvl ( __mt_pick_level m )
    ? > lvl . m level {
        : ~ i j . m level
        ~ < j lvl { : b _o ( vec_set [i] prev j 0 ) = j + j 1 }
        = . m level lvl
    } {}

    : i node ( __mt_alloc_node m ko kl vo vl seq kind lvl )
    : ~ i q 0
    ~ < q lvl {
        : i p ( _mt_iat prev q )
        ( __mt_set_link m node q ( __mt_link m p q ) )
        ( __mt_set_link m p q node )
        = q + q 1
    }
    = . m count + . m count 1
}

// ── lookup / iteration ──────────────────────────────────────────────

// First node with (key, seq) >= (probe, snap) — i.e. the newest version
// of `key` no newer than `snap`, or the next key after it. 0 = end.
@ mt_seek MemTable m ( Vec u ) key i snap → i {
    : ( Vec i ) none ( vec_new [i] )
    : i x ( __mt_descend m ( slice_from_vec [u] key ) snap none )
    ^ ( __mt_link m x 0 )
}

// The node holding `key` as of `snap`, or 0. The caller still has to ask
// mt_kind: a tombstone is a hit that means "deleted", not "not found".
@ mt_find MemTable m ( Vec u ) key i snap → i {
    : i cand ( mt_seek m key snap )
    ? == cand 0 { ^ 0 } {}
    : i c ( slice_bytes_cmp ( mt_key_view m cand ) ( slice_from_vec [u] key ) )
    ^ ? == c 0 cand 0
}

@ mt_first MemTable m → i { ^ ( __mt_link m 0 0 ) }

@ mt_next MemTable m i node → i { ^ ( __mt_link m node 0 ) }
