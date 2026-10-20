// packages/nurldb/src/btree.nu — B+tree indexes, shared by every thread.
//
// A node is a page (PT_LEAF or PT_INNER). After the common header:
//
//   32  u16 n        entries
//   34  u16 hi       the start of the entry area (0: the page's end)
//   36  u16 level    0 for a leaf
//   38  u16 flags    BTF_ROOT on the root
//   40  slots: u16 offset per entry, in key order
//
// An entry is u16 length, the key (keys.nu: the columns' bytes and the
// row version's TID, so every key is unique), and in an inner node the
// u32 number of its child. An inner node's keys separate its children:
// keys from entry k's up to entry k+1's live under child k, and keys
// below entry 0's under the leftmost child (PG_AUX). A leaf links to its
// right neighbour (PG_NEXT); a scan walks the leaves along it.
//
// Concurrency is latch crabbing over the buffer pool's page latches:
//
//   * A reader descends with read latches hand over hand — it latches a
//     child before it lets the parent go — so no split can move what it is
//     looking for between the two.
//   * An insert first does the same, taking only its leaf's latch for
//     writing (optimistic: most inserts fit). When the leaf is full it
//     starts again pessimistically: write latches from the root down, and
//     every time a node with room for one more entry is latched, the
//     latches above it are let go — a split below cannot reach past a
//     node that has room. The nodes still latched are exactly the ones a
//     split may change, and they split bottom-up.
//   * Latches are taken top-down, and along a level left to right, so two
//     threads never wait on each other in a circle.
//
// The root may split: a new root is made above it, its number goes into
// the index's anchor page (PG_AUX: what survives a restart) and into the
// shared atomic every descent starts from. A descent that latches a page
// that is no longer the root (it split meanwhile) lets go and starts
// again.
//
// Entries are never deleted while a transaction may see them; the vacuum
// removes those of row versions nobody can see (bt_delete), leaving a
// node with less in it: nodes are not merged.
//
// Every change is logged first: an insert as R_BT_INSERT, a delete as
// R_BT_DELETE (redone by bt_redo), a split or a compaction as the images
// of the pages it rewrote (R_PAGE_IMAGE).

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`
$ `page.nu`
$ `wal.nu`
$ `bufpool.nu`
$ `logrec.nu`
$ `heap.nu`
$ `keys.nu`

: i BT_N 32
: i BT_HI 34
: i BT_LEVEL 36
: i BT_FLAGS 38
: i BT_SLOTS 40
: i BTF_ROOT 1

// The longest key an index takes (columns and TID): a node holds at least
// seven, so a split always leaves room in both halves.
: i BT_MAX_KEY 1032
// The room one entry needs at most (slot, length, key, child).
: i BT_MAX_ENTRY 1040

: IndexImpl {
    i id
    i table
    i anchor  // the page that names the root (PG_AUX)
    Atomic root
    ( Vec i ) cols  // the table's columns it is on, in key order
    ( Vec i ) types
    b unique
}

: Index { ( Arc IndexImpl ) a }

@ Index_share Index t → Index { ^ @ Index { ( arc_clone [IndexImpl] . t a ) } }

@ Index_drop sink Index t → v {}

@ index_new i id i table i anchor i root ( Vec i ) cols ( Vec i ) types b unique → Index {
    ^ @ Index { ( arc_new [IndexImpl] @ IndexImpl { id table anchor ( atomic_new root ) cols types unique } ) }
}

@ index_id Index t → i { ^ . ( arc_get [IndexImpl] . t a ) id }

@ index_root Index t → i { ^ ( atomic_load . ( arc_get [IndexImpl] . t a ) root ) }

@ index_anchor Index t → i { ^ . ( arc_get [IndexImpl] . t a ) anchor }

@ index_unique Index t → b { ^ . ( arc_get [IndexImpl] . t a ) unique }

// The key of `row` (stored at `tid`) in this index.
@ index_key Index t ( Vec Value ) row i tid → ( Vec u ) {
    : IndexImpl x ( arc_get [IndexImpl] . t a )
    ^ ( key_of_row row . x cols . x types tid )
}

// ── node operations (pure: no log, no latch) ──────────────────────────

@ bt_init ( Slice u ) p i level b root → v {
    ( slice_put_u16_le p BT_N 0 )
    ( slice_put_u16_le p BT_HI 0 )
    ( slice_put_u16_le p BT_LEVEL level )
    ( slice_put_u16_le p BT_FLAGS ? root BTF_ROOT 0 )
}

@ bt_n ( Slice u ) p → i { ^ ( slice_u16_le p BT_N ) }

@ bt_level ( Slice u ) p → i { ^ ( slice_u16_le p BT_LEVEL ) }

@ bt_is_root ( Slice u ) p → b { ^ != 0 & ( slice_u16_le p BT_FLAGS ) BTF_ROOT }

@ bt_set_root ( Slice u ) p b r → v { ( slice_put_u16_le p BT_FLAGS ? r BTF_ROOT 0 ) }

@ __bt_hi ( Slice u ) p → i { : i h ( slice_u16_le p BT_HI ) ^ ? == h 0 PAGE_SIZE h }

@ __bt_off ( Slice u ) p i k → i { ^ ( slice_u16_le p + BT_SLOTS * 2 k ) }

@ bt_key ( Slice u ) p i k → ( Slice u ) {
    : i off ( __bt_off p k )
    ^ ( slice_window [u] p + off 2 ( slice_u16_le p off ) )
}

@ bt_child ( Slice u ) p i k → i {
    : i off ( __bt_off p k )
    ^ ( slice_u32_le p + + off 2 ( slice_u16_le p off ) )
}

// Bytes free between the slots and the entries.
@ bt_free ( Slice u ) p → i { ^ - ( __bt_hi p ) + BT_SLOTS * 2 ( bt_n p ) }

// The room an entry with a key of `klen` bytes takes, its slot included.
@ bt_need i klen b inner → i { ^ + + 4 klen ? inner 4 0 }

// The room the entries take, packed (what a compaction leaves used).
@ __bt_used ( Slice u ) p → i {
    : b inner > ( bt_level p ) 0
    : ~ i used 0
    : ~ i k 0
    ~ < k ( bt_n p ) {
        = used + used ( bt_need ( slice_len [u] ( bt_key p k ) ) inner )
        = k + k 1
    }
    ^ used
}

// The first entry whose key is not below `key`.
@ bt_lower ( Slice u ) p ( Slice u ) key → i {
    : ~ i lo 0
    : ~ i hi ( bt_n p )
    ~ < lo hi {
        : i mid / + lo hi 2
        ? < ( slice_bytes_cmp ( bt_key p mid ) key ) 0 { = lo + mid 1 } { = hi mid }
    }
    ^ lo
}

// The first entry whose key is above `key`.
@ bt_upper ( Slice u ) p ( Slice u ) key → i {
    : ~ i lo 0
    : ~ i hi ( bt_n p )
    ~ < lo hi {
        : i mid / + lo hi 2
        ? <= ( slice_bytes_cmp ( bt_key p mid ) key ) 0 { = lo + mid 1 } { = hi mid }
    }
    ^ lo
}

// The child of inner node `p` that `key` belongs under.
@ bt_descend ( Slice u ) p ( Slice u ) key → i {
    : i pos ( bt_upper p key )
    ^ ? == pos 0 ( pg_aux p ) ( bt_child p - pos 1 )
}

// Put an entry at position `pos` (the caller checked it fits).
@ bt_put_at ( Slice u ) p i pos ( Slice u ) key i child b inner → v {
    : i klen ( slice_len [u] key )
    : i off - ( __bt_hi p ) + + 2 klen ? inner 4 0
    ( slice_put_u16_le p off klen )
    ( slice_copy [u] ( slice_window [u] p + off 2 klen ) key )
    ? inner { ( slice_put_u32_le p + + off 2 klen child ) } {}
    ( slice_put_u16_le p BT_HI off )
    : i n ( bt_n p )
    ? < pos n { ( slice_move [u] p + BT_SLOTS * 2 pos + BT_SLOTS * 2 + pos 1 * 2 - n pos ) } {}
    ( slice_put_u16_le p + BT_SLOTS * 2 pos off )
    ( slice_put_u16_le p BT_N + n 1 )
}

// Take entry `pos` out (its bytes stay until a compaction).
@ bt_remove_at ( Slice u ) p i pos → v {
    : i n ( bt_n p )
    ? < + pos 1 n { ( slice_move [u] p + BT_SLOTS * 2 + pos 1 + BT_SLOTS * 2 pos * 2 - - n pos 1 ) } {}
    ( slice_put_u16_le p BT_N - n 1 )
}

// Rewrite `p` to hold entries [from, to) of `src` — a copy of a node of
// the same level — packed, in order.
@ __bt_refill ( Slice u ) p ( Slice u ) src i from i to b inner → v {
    ( slice_put_u16_le p BT_N 0 )
    ( slice_put_u16_le p BT_HI 0 )
    : ~ i k from
    ~ < k to {
        ( bt_put_at p - k from ( bt_key src k ) ? inner ( bt_child src k ) 0 inner )
        = k + k 1
    }
}

// ── logging ────────────────────────────────────────────────────────────

@ __bt_image Store st PageWrite pw → v { : i _l ( log_page_image st pw ) }

// Insert an entry into the node under `pw` at `pos`, logged.
@ __bt_put_logged Store st PageWrite pw i pos ( Slice u ) key i child b inner → v {
    : ( Vec u ) r ( rec_new R_BT_INSERT + 13 ( slice_len [u] key ) )
    ( rec_u32 r ( page_write_pid pw ) )
    ( rec_u16 r pos )
    ( rec_u32 r child )
    ( rec_u16 r ( slice_len [u] key ) )
    ( rec_bytes r key )
    ( bt_put_at ( page_bytes_mut pw ) pos key child inner )
    : i _l ( log_page st pw r )
}

// Make room by packing the entries, if packing makes enough: T when it did.
@ __bt_compact Store st PageWrite pw i need → b {
    : ( Slice u ) p ( page_bytes_mut pw )
    ? < - - PAGE_SIZE BT_SLOTS ( __bt_used p ) need { ^ F } {}
    : ( Vec u ) snap ( slice_to_vec [u] p )
    ( __bt_refill p ( slice_from_vec [u] snap ) 0 ( bt_n p ) > ( bt_level p ) 0 )
    ( __bt_image st pw )
    ^ T
}

// ── a new tree ─────────────────────────────────────────────────────────

// An empty index: its anchor page and a root leaf. The anchor's number.
@ bt_create Store st → i {
    : PageWrite anchor ( pool_new_page . st pool PT_META )
    : PageWrite root ( pool_new_page . st pool PT_LEAF )
    ( bt_init ( page_bytes_mut root ) 0 T )
    ( pg_set_aux ( page_bytes_mut anchor ) ( page_write_pid root ) )
    ( __bt_image st root )
    ( __bt_image st anchor )
    ^ ( page_write_pid anchor )
}

// The root an anchor page names.
@ bt_anchor_root Store st i anchor → i {
    : PageRead r ( pool_read . st pool anchor )
    ^ ( pg_aux ( page_bytes r ) )
}

// ── descent ────────────────────────────────────────────────────────────

// The level of the root `pid`, or -1 when it is no longer the root.
@ __bt_root_level Store st i pid → i {
    : PageRead r ( pool_read . st pool pid )
    : ( Slice u ) p ( page_bytes r )
    ? ! ( bt_is_root p ) { ^ -1 } {}
    ^ ( bt_level p )
}

// The leaf `key` belongs in, read-latched; none when the root moved under
// the descent (the caller starts again).
@ __bt_leaf_r Store st IndexImpl x ( Slice u ) key → ?PageRead {
    : ~ PageRead cur ( pool_read . st pool ( atomic_load . x root ) )
    ? ! ( bt_is_root ( page_bytes cur ) ) { ^ @ ?PageRead { F } } {}
    ~ T {
        : ~ i child 0
        {
            : ( Slice u ) p ( page_bytes cur )
            ? == ( bt_level p ) 0 { break } {}
            = child ( bt_descend p key )
        }
        : PageRead nxt ( pool_read . st pool child )
        = cur nxt
    }
    ^ @ ?PageRead { T cur }
}

// The leaf `key` belongs in, write-latched, found under read latches;
// none when the root moved (start again).
@ __bt_leaf_w Store st IndexImpl x ( Slice u ) key → ?PageWrite {
    : i root ( atomic_load . x root )
    : i lvl ( __bt_root_level st root )
    ? < lvl 0 { ^ @ ?PageWrite { F } } {}
    ? == lvl 0 {
        : PageWrite w ( pool_write . st pool root )
        : b still & ( bt_is_root ( page_bytes_mut w ) ) == ( bt_level ( page_bytes_mut w ) ) 0
        ? ! still { ^ @ ?PageWrite { F } } {}
        ^ @ ?PageWrite { T w }
    } {}
    : ~ PageRead cur ( pool_read . st pool root )
    ? ! ( bt_is_root ( page_bytes cur ) ) { ^ @ ?PageWrite { F } } {}
    ~ T {
        : ~ i child 0
        : ~ i level 0
        {
            : ( Slice u ) p ( page_bytes cur )
            = level ( bt_level p )
            = child ( bt_descend p key )
        }
        ? == level 1 {
            : PageWrite w ( pool_write . st pool child )
            ^ @ ?PageWrite { T w }
        } {}
        : PageRead nxt ( pool_read . st pool child )
        = cur nxt
    }
}

// ── insert ─────────────────────────────────────────────────────────────

// Insert `key` (a full entry key: keys.nu) into the index.
@ bt_insert Store st Index ix ( Slice u ) key → v {
    ? > ( slice_len [u] key ) BT_MAX_KEY { ( panic `nurldb: an index key longer than 1024 bytes` ) } {}
    : IndexImpl x ( arc_get [IndexImpl] . ix a )
    ~ T {
        : i r ( __bt_insert_fast st x key )
        ? == r 1 { ^ } {}
        ? == r 0 { ? ( __bt_insert_slow st x key ) { ^ } {} } {}
    }
}

// The optimistic insert: 1 done, 0 the leaf is full, -1 the root moved.
@ __bt_insert_fast Store st IndexImpl x ( Slice u ) key → i {
    ^ ?? ( __bt_leaf_w st x key ) {
        T w → ( __bt_put_leaf st w key )
        F → -1
    }
}

@ __bt_put_leaf Store st PageWrite w ( Slice u ) key → i {
    : i need ( bt_need ( slice_len [u] key ) F )
    ? < ( bt_free ( page_bytes_mut w ) ) need {
        ? ! ( __bt_compact st w need ) { ^ 0 } {}
    } {}
    ( __bt_put_logged st w ( bt_lower ( page_bytes_mut w ) key ) key 0 F )
    ^ 1
}

// What the bottom of a pessimistic descent knows about the node it latched.
: Peek { i level i child b safe }

@ __bt_peek PageWrite w ( Slice u ) key → Peek {
    : ( Slice u ) p ( page_bytes_mut w )
    : i level ( bt_level p )
    ^ @ Peek { level ? == level 0 0 ( bt_descend p key ) >= ( bt_free p ) BT_MAX_ENTRY }
}

// The entry an insert still has to put in, at the level it belongs to
// (a split passes its separator up: `inout`, changed in place).
: Pending {
    ( Vec u ) key
    i child  // the node the entry points at, in an inner node
    i level
}

// The pessimistic insert: write latches from the root down, those above a
// node with room let go; then the entry goes in, splitting bottom-up. F
// when the root moved before it was latched (start again).
@ __bt_insert_slow Store st IndexImpl x ( Slice u ) key → b {
    : ( Vec PageWrite ) path ( vec_new [PageWrite] )
    {
        : PageWrite r ( pool_write . st pool ( atomic_load . x root ) )
        ? ! ( bt_is_root ( page_bytes_mut r ) ) { ^ F } {}
        ( vec_push [PageWrite] path r )
    }
    ~ T {
        : Peek pk ( __bt_peek ( vec_at [PageWrite] path - ( vec_len [PageWrite] path ) 1 ) key )
        ? == . pk level 0 { break } {}
        : PageWrite c ( pool_write . st pool . pk child )
        : Peek cpk ( __bt_peek c key )
        ? . cpk safe { ( vec_clear [PageWrite] path ) } {}
        ( vec_push [PageWrite] path c )
    }
    : ~ Pending pend @ Pending { ( slice_to_vec [u] key ) 0 0 }
    ~ T {
        : i top - ( vec_len [PageWrite] path ) 1
        : b inner > . pend level 0
        ? ( __bt_room st ( vec_at [PageWrite] path top ) ( bt_need ( vec_len [u] . pend key ) inner ) ) {
            ( __bt_put_sorted st ( vec_at [PageWrite] path top ) ( slice_from_vec [u] . pend key ) . pend child inner )
            ^ T
        } {}
        ? ( __bt_split st x ( vec_at [PageWrite] path top ) pend ) { ^ T } {}
        // The parent is next; this node is done with.
        : ?PageWrite _done ( vec_pop [PageWrite] path )
    }
}

@ __bt_put_sorted Store st PageWrite w ( Slice u ) key i child b inner → v {
    ( __bt_put_logged st w ( bt_lower ( page_bytes_mut w ) key ) key child inner )
}

// Room for `need` bytes in the node under `w`, packing it if that makes it.
@ __bt_room Store st PageWrite w i need → b {
    ? >= ( bt_free ( page_bytes_mut w ) ) need { ^ T } {}
    ^ ( __bt_compact st w need )
}

// Split the full node under `w` into itself and a new right sibling, with
// the pending entry put in the half it belongs to. The entry the parent
// needs then — the separator, pointing at the new node — replaces the
// pending one. T when the node was the root: a new root now holds both
// halves, and nothing is left to do.
@ __bt_split Store st IndexImpl x PageWrite w inout Pending pend → b {
    : i level . pend level
    : b inner > level 0
    : ( Vec u ) ins ( vec_clone [u] . pend key )
    : ( Slice u ) iv ( slice_from_vec [u] ins )
    : PageWrite nw ( pool_new_page . st pool ? inner PT_INNER PT_LEAF )
    : i npid ( page_write_pid nw )
    : ( Slice u ) lp ( page_bytes_mut w )
    : ( Slice u ) rp ( page_bytes_mut nw )
    : ( Vec u ) snap ( slice_to_vec [u] lp )
    : ( Slice u ) sv ( slice_from_vec [u] snap )
    : i n ( bt_n sv )
    : i mid / n 2
    : ( Vec u ) sep ( slice_to_vec [u] ( bt_key sv mid ) )
    : b was_root ( bt_is_root sv )
    ( bt_init rp level F )
    ? inner {
        ( pg_set_aux rp ( bt_child sv mid ) )
        ( __bt_refill rp sv + mid 1 n T )
    } {
        ( __bt_refill rp sv mid n F )
        ( pg_set_next rp ( pg_next lp ) )
        ( pg_set_next lp npid )
    }
    ( __bt_refill lp sv 0 mid inner )
    ( bt_set_root lp F )
    ? >= ( slice_bytes_cmp iv ( slice_from_vec [u] sep ) ) 0 {
        ( bt_put_at rp ( bt_lower rp iv ) iv . pend child inner )
    } {
        ( bt_put_at lp ( bt_lower lp iv ) iv . pend child inner )
    }
    ( __bt_image st nw )
    ( __bt_image st w )
    ? was_root {
        // A new root over the two halves.
        : PageWrite nr ( pool_new_page . st pool PT_INNER )
        : ( Slice u ) np ( page_bytes_mut nr )
        ( bt_init np + level 1 T )
        ( pg_set_aux np ( page_write_pid w ) )
        ( bt_put_at np 0 ( slice_from_vec [u] sep ) npid T )
        ( __bt_image st nr )
        {
            : PageWrite an ( pool_write . st pool . x anchor )
            ( pg_set_aux ( page_bytes_mut an ) ( page_write_pid nr ) )
            ( __bt_image st an )
        }
        ( atomic_store . x root ( page_write_pid nr ) )
        ^ T
    } {}
    ( vec_clear [u] . pend key )
    ( vec_extend [u] . pend key sep )
    = . pend child npid
    = . pend level + level 1
    ^ F
}

// ── scans ──────────────────────────────────────────────────────────────

// Call `f` with each entry key from `lo` to `hi` (both inclusive), in
// order; F from `f` stops. A leaf is copied out and let go before `f`
// sees its keys: `f` may read the table, or change it. Entries a split
// moves right while the scan is between leaves are met on the leaf they
// moved to; ones inserted meanwhile belong to row versions the scan's
// snapshot does not see either way.
@ bt_scan Store st Index ix ( Slice u ) lo ( Slice u ) hi ( @ b ( Slice u ) ) f → v {
    : IndexImpl x ( arc_get [IndexImpl] . ix a )
    : ( Vec u ) buf ( vec_zeroed [u] PAGE_SIZE )
    : ( Slice u ) bv ( slice_from_vec [u] buf )
    : ~ i next NO_PAGE
    ~ T {
        ?? ( __bt_leaf_r st x lo ) {
            T r → {
                ( slice_copy [u] bv ( page_bytes r ) )
                = next ( pg_next bv )
                break
            }
            F → {}
        }
    }
    : ~ i k ( bt_lower bv lo )
    ~ T {
        : i n ( bt_n bv )
        ~ < k n {
            : ( Slice u ) key ( bt_key bv k )
            ? > ( slice_bytes_cmp key hi ) 0 { ^ } {}
            ? ! ( f key ) { ^ } {}
            = k + k 1
        }
        ? == next NO_PAGE { ^ } {}
        {
            : PageRead r ( pool_read . st pool next )
            ( slice_copy [u] bv ( page_bytes r ) )
        }
        = next ( pg_next bv )
        = k ( bt_lower bv lo )
    }
}

// A scan one entry at a time (a query's index scan): the leaf it is on,
// copied out, and where in it.
: BtCursor {
    ( Vec u ) page
    i k
    i next
    b started
    b done
}

@ bt_cursor → BtCursor { ^ @ BtCursor { ( vec_zeroed [u] PAGE_SIZE ) 0 NO_PAGE F F } }

// The next entry key from `lo` up to `hi` (inclusive) into `out`: F at the
// end of the range.
@ bt_cursor_next Store st Index ix inout BtCursor c ( Slice u ) lo ( Slice u ) hi inout ( Vec u ) out → b {
    ? . c done { ^ F } {}
    : ( Slice u ) bv ( slice_from_vec [u] . c page )
    ? ! . c started {
        : IndexImpl x ( arc_get [IndexImpl] . ix a )
        ~ T {
            ?? ( __bt_leaf_r st x lo ) {
                T r → {
                    ( slice_copy [u] bv ( page_bytes r ) )
                    break
                }
                F → {}
            }
        }
        = . c next ( pg_next bv )
        = . c k ( bt_lower bv lo )
        = . c started T
    } {}
    ~ T {
        ? < . c k ( bt_n bv ) {
            : ( Slice u ) key ( bt_key bv . c k )
            ? > ( slice_bytes_cmp key hi ) 0 { = . c done T ^ F } {}
            = . c k + . c k 1
            ( vec_clear [u] out )
            : ~ i j 0
            ~ < j ( slice_len [u] key ) { ( vec_push [u] out # u ( slice_byte key j ) ) = j + j 1 }
            ^ T
        } {}
        ? == . c next NO_PAGE { = . c done T ^ F } {}
        {
            : PageRead r ( pool_read . st pool . c next )
            ( slice_copy [u] bv ( page_bytes r ) )
        }
        = . c next ( pg_next bv )
        = . c k ( bt_lower bv lo )
    }
}

// ── delete ─────────────────────────────────────────────────────────────

// Take the entry `key` out of the index (the vacuum: no snapshot can see
// the row version it points at). F when it was not there.
@ bt_delete Store st Index ix ( Slice u ) key → b {
    : IndexImpl x ( arc_get [IndexImpl] . ix a )
    ~ T {
        ?? ( __bt_leaf_w st x key ) {
            T w → {
                : ~ PageWrite cur w
                // The key may have moved right with a split since.
                ~ T {
                    : ( Slice u ) p ( page_bytes_mut cur )
                    : i pos ( bt_lower p key )
                    ? & < pos ( bt_n p ) == ( slice_bytes_cmp ( bt_key p pos ) key ) 0 {
                        : ( Vec u ) r ( rec_new R_BT_DELETE 7 )
                        ( rec_u32 r ( page_write_pid cur ) )
                        ( rec_u16 r pos )
                        ( bt_remove_at p pos )
                        : i _l ( log_page st cur r )
                        ^ T
                    } {}
                    : i nx ( pg_next p )
                    ? | < pos ( bt_n p ) == nx NO_PAGE { ^ F } {}
                    : PageWrite nw ( pool_write . st pool nx )
                    = cur nw
                }
            }
            F → {}
        }
    }
}

// ── redo ───────────────────────────────────────────────────────────────

// Apply an R_BT_INSERT / R_BT_DELETE record `r` to the node `p` it names.
@ bt_redo ( Slice u ) p ( Slice u ) r → v {
    : i kind ( rec_kind r )
    ? == kind R_BT_INSERT {
        : i klen ( slice_u16_le r 11 )
        ( bt_put_at p ( slice_u16_le r 5 ) ( slice_window [u] r 13 klen ) ( slice_u32_le r 7 ) > ( bt_level p ) 0 )
    } {}
    ? == kind R_BT_DELETE { ( bt_remove_at p ( slice_u16_le r 5 ) ) } {}
}
