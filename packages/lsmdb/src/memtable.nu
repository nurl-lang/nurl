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
//   ( mt_new seed )                       → MemTable   a handle: every copy
//                                                    is the same table, the
//                                                    last owner releases it
//   ( mt_put m key val seq kind )         → v      kind: MT_PUT / MT_DEL
//   ( mt_find m key snap )                → i      node index, 0 = miss
//   ( mt_seek m key snap )                → i      first node >= key
//   ( mt_first m ) / ( mt_next m n )      → i      ordered walk, 0 = end
//   ( mt_key m n ) / ( mt_val m n )       → ( Vec u )   owned copies
//   ( mt_seq m n ) / ( mt_kind m n )      → i
//   ( mt_count m ) / ( mt_bytes m )       → i
//   ( mt_free m )                         → v      early release (optional)

$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`

: i MT_MAXLVL 12
: i MT_PUT 1
: i MT_DEL 0

: MemTableImpl {
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

// A MemTable is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: MemTable { s ctl }

unsafe

@ MemTable_share MemTable h → MemTable { ^ @ MemTable { # s ( rcbox_share # i . h ctl ) } }

@ MemTable_drop sink MemTable h → v {
    ( mem_forget h )
    ( rcbox_release [MemTableImpl] # i . h ctl )
}

unsafe

@ __MemTable_ptr MemTable h → *MemTableImpl { ^ ( rcbox_ptr [MemTableImpl] # i . h ctl ) }

// ── raw byte compare ────────────────────────────────────────────────
//
// Bytewise, unsigned, shorter-is-smaller — the total order the whole
// package agrees on: memtable, SSTable, merge, scan.

unsafe

@ lsm_bytes_cmp_raw * u ap i aoff i alen * u bp i boff i blen → i {
    : i lim ? < alen blen alen blen
    : ~ i k 0
    ~ < k lim {
        : i ca # i . ap + aoff k
        : i cb # i . bp + boff k
        ? != ca cb { ^ ? < ca cb -1 1 } {}
        = k + k 1
    }
    ? == alen blen { ^ 0 } {}
    ^ ? < alen blen -1 1
}

// Compare two whole byte vectors.
@ lsm_bytes_cmp ( Vec u ) a ( Vec u ) b → i {
    ^ ( lsm_bytes_cmp_raw ( vec_data [u] a ) 0 ( vec_len [u] a )
    ( vec_data [u] b ) 0 ( vec_len [u] b ) )
}

// ── construction ────────────────────────────────────────────────────

unsafe

@ mt_new i seed → MemTable {
    : i m__box ( rcbox_zero [MemTableImpl] )
    : *MemTableImpl m ( rcbox_ptr [MemTableImpl] m__box )
    = . m arena ( vec_new [u] )
    = . m koff ( vec_new [i] )
    = . m klen ( vec_new [i] )
    = . m voff ( vec_new [i] )
    = . m vlen ( vec_new [i] )
    = . m nseq ( vec_new [i] )
    = . m nkind ( vec_new [i] )
    = . m nlvl ( vec_new [i] )
    = . m links ( vec_new [i] )
    = . m level 1
    = . m count 0
    = . m rng ? == seed 0 88172645463325252 seed
    // Node 0 is the head sentinel, so index 0 doubles as "nil" — a link
    // can never legitimately point back at the head.
    : i _head ( __mt_alloc_node m 0 0 0 0 0 MT_PUT MT_MAXLVL )
    ^ @ MemTable { # s m__box }
}

// Let go of `m` now rather than at the end of its owner's scope.
@ mt_free sink MemTable m → v {}

unsafe

@ __mt_alloc_node * MemTableImpl m i ko i kl i vo i vl i seq i kind i lvl → i {
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

unsafe

@ __mt_link * MemTableImpl m i node i lvl → i {
    ^ ( _mt_iat . m links + * node MT_MAXLVL lvl )
}

unsafe

@ __mt_set_link * MemTableImpl m i node i lvl i to → v {
    : b _ok ( vec_set [i] . m links + * node MT_MAXLVL lvl to )
}

unsafe

@ mt_seq MemTable m__h i node → i {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    ^ ( _mt_iat . m nseq node )
}

unsafe

@ mt_kind MemTable m__h i node → i {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    ^ ( _mt_iat . m nkind node )
}

unsafe

@ mt_count MemTable m__h → i {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    ^ . m count
}

// Bytes held: the arena plus the per-node integer rows. The store
// compares this against its memtable budget, so it has to count the
// index too — a million tiny keys is mostly index.
unsafe

@ mt_bytes MemTable m__h → i {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    : i nodes ( vec_len [i] . m koff )
    ^ + ( vec_len [u] . m arena ) * nodes * 8 + 7 MT_MAXLVL
}

@ _mt_slice ( Vec u ) src i off i n → ( Vec u ) {
    : i cap ? > n 0 n 1
    : ( Vec u ) out ( vec_with_cap [u] cap )
    ? > n 0 { ( vec_extend_range [u] out src off n ) } {}
    ^ out
}

unsafe

@ mt_key MemTable m__h i node → ( Vec u ) {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    ^ ( _mt_slice . m arena ( _mt_iat . m koff node ) ( _mt_iat . m klen node ) )
}

unsafe

@ mt_val MemTable m__h i node → ( Vec u ) {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    ^ ( _mt_slice . m arena ( _mt_iat . m voff node ) ( _mt_iat . m vlen node ) )
}

// ── ordering ────────────────────────────────────────────────────────

// Compare node `node` against the probe (key, seq) in memtable order:
// key ascending, sequence descending. <0 means the node sorts first.
unsafe

@ __mt_cmp_node * MemTableImpl m i node * u pp i poff i plen i pseq → i {
    : *u ap ( vec_data [u] . m arena )
    : i c ( lsm_bytes_cmp_raw ap ( _mt_iat . m koff node ) ( _mt_iat . m klen node )
    pp poff plen )
    ? != c 0 { ^ c } {}
    : i ns ( _mt_iat . m nseq node )
    ? == ns pseq { ^ 0 } {}
    ^ ? > ns pseq -1 1
}

// xorshift64 — deterministic level draws, so a given write sequence
// always builds the same structure and tests can rely on it.
unsafe

@ __mt_rand * MemTableImpl m → i {
    : ~ i x . m rng
    = x ^^ x << x 13
    = x ^^ x >> x 7
    = x ^^ x << x 17
    = . m rng x
    ^ & x 9223372036854775807
}

@ __mt_pick_level * MemTableImpl m → i {
    : ~ i lvl 1
    : ~ b climb T
    ~ climb {
        ? & < lvl MT_MAXLVL == 0 & ( __mt_rand m ) 3 { = lvl + lvl 1 } { = climb F }
    }
    ^ lvl
}

// Walk down the levels to the last node that sorts BEFORE the probe,
// recording the path in `prev` when it is non-empty.
unsafe

@ __mt_descend * MemTableImpl m * u pp i poff i plen i pseq ( Vec i ) prev → i {
    : ~ i x 0
    : ~ i lv - . m level 1
    ~ >= lv 0 {
        : ~ b more T
        ~ more {
            : i nx ( __mt_link m x lv )
            ? == nx 0 { = more F } {
                ? < ( __mt_cmp_node m nx pp poff plen pseq ) 0 { = x nx } { = more F }
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
unsafe

@ mt_put MemTable m__h ( Vec u ) key ( Vec u ) val i seq i kind → v {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    : i kl ( vec_len [u] key )
    : i vl ? == kind MT_PUT ( vec_len [u] val ) 0
    : i ko ( vec_len [u] . m arena )
    ( vec_extend [u] . m arena key )
    : i vo ( vec_len [u] . m arena )
    ? > vl 0 { ( vec_extend [u] . m arena val ) } {}

    : ( Vec i ) prev ( vec_with_cap [i] MT_MAXLVL )
    : ~ i l 0
    ~ < l MT_MAXLVL { ( vec_push [i] prev 0 ) = l + l 1 }

    // The probe is the key we just copied in — take the arena pointer
    // AFTER the extends above, which may have moved the buffer.
    : *u ap ( vec_data [u] . m arena )
    : i _x ( __mt_descend m ap ko kl seq prev )

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
@ mt_seek MemTable m__h ( Vec u ) key i snap → i {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    ^ ( __mt_seek m key snap )
}

@ __mt_seek * MemTableImpl m ( Vec u ) key i snap → i {
    : ( Vec i ) none ( vec_new [i] )
    : i x ( __mt_descend m ( vec_data [u] key ) 0 ( vec_len [u] key ) snap none )
    ^ ( __mt_link m x 0 )
}

// The node holding `key` as of `snap`, or 0. The caller still has to ask
// mt_kind: a tombstone is a hit that means "deleted", not "not found".
unsafe

@ mt_find MemTable m__h ( Vec u ) key i snap → i {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    : i cand ( __mt_seek m key snap )
    ? == cand 0 { ^ 0 } {}
    : i c ( lsm_bytes_cmp_raw ( vec_data [u] . m arena )
    ( _mt_iat . m koff cand ) ( _mt_iat . m klen cand )
    ( vec_data [u] key ) 0 ( vec_len [u] key ) )
    ^ ? == c 0 cand 0
}

@ mt_first MemTable m__h → i {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    ^ ( __mt_link m 0 0 )
}

@ mt_next MemTable m__h i node → i {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    ^ ( __mt_link m node 0 )
}

// Borrowed view of a node's key, for merge comparisons that must not
// allocate. Valid until the next mt_put (which may move the arena).
unsafe

@ mt_kptr MemTable m__h → *u {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    ^ ( vec_data [u] . m arena )
}

unsafe

@ mt_koff MemTable m__h i node → i {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    ^ ( _mt_iat . m koff node )
}

unsafe

@ mt_klen MemTable m__h i node → i {
    : *MemTableImpl m ( __MemTable_ptr m__h )
    ^ ( _mt_iat . m klen node )
}
