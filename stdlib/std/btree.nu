// stdlib/std/btree.nu — owned generic ordered map, B-tree backed.
//
// The write-optimized sibling of std/ordmap.nu: same comparator
// convention and API shape, but O(log n) insert/remove instead of the
// flat map's O(n) shifts. Use OrdMap for small/medium maps (simpler,
// cache-friendly); switch here when write volume on a large map is the
// bottleneck. Per-node subtree sizes give O(log n) `key_at`/`val_at`
// (order statistics), so ordered indexed iteration works exactly like
// OrdMap's.
//
// Classic B-tree of minimum degree t = 8: every node holds 7..15 keys
// (root 1..15) and leaf nodes sit at one depth. Insert splits full
// nodes on the way down; remove borrows/merges under-full nodes on the
// way down (CLRS shape), so neither ever backtracks.
//
// Ordering is decided by a key comparator `cmp : (@ i K K)` passed to
// every keyed call (sort_by convention): `cmp a b` < 0 / 0 / > 0. Use
// the SAME comparator for a map's whole lifetime.
//
//   ( btree_new       [K V] )              → ( BTree K V )
//   ( btree_len       [K V] m )            → i
//   ( btree_is_empty  [K V] m )            → b
//   ( btree_get       [K V] m k cmp )      → ? V
//   ( btree_set       [K V] m k v cmp )    → ? V   Some(prev) on replace
//   ( btree_remove    [K V] m k cmp )      → ? V   Some(val) if removed
//   ( btree_contains  [K V] m k cmp )      → b
//   ( btree_key_at    [K V] m i )          → ? K   i-th smallest key
//   ( btree_val_at    [K V] m i )          → ? V   its value
//   ( btree_min_key   [K V] m )            → ? K
//   ( btree_max_key   [K V] m )            → ? K
//   ( btree_each      [K V] m f )          → v     f:(@ v K V), in order
//   ( btree_free      [K V] m )            → v     trivial K/V
//   ( btree_free_with [K V] m dk dv )      → v     dk:(@ v K) dv:(@ v V)
//
// Ownership: mirrors OrdMap. On btree_set REPLACE the existing equal
// key is kept and the passed-in `k` is NOT stored — for owned keys the
// caller still owns that `k`. btree_remove returns the value (caller
// frees an owned V); the removed key's storage is bitwise-dropped, so
// owned-key maps should prefer bulk teardown via btree_free_with.
//
// Node layout (heap block, 6 × i64 slots via nurl_peek/poke):
//   slot 0: keys ptr   (*K, capacity 15)
//   slot 1: vals ptr   (*V, capacity 15)
//   slot 2: kids ptr   (*i, capacity 16 node pointers; leaf → unused)
//   slot 3: nkeys
//   slot 4: leaf flag  (1 = leaf)
//   slot 5: size       (total entries in this subtree)
// Tree control block (2 × i64): slot 0 root ptr (0 = empty), slot 1 len.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: BTree [K V] { s ctl }

: i BT_MAXK 15   // 2t-1 keys
: i BT_MINK 7    // t-1
: i BT_DEG 8     // t

// ── node primitives ─────────────────────────────────────────────────

@ __bt_node_new [K V] i leaf → s {
    : s n ( nurl_zalloc 48 )
    ( nurl_poke n 0 # i ( nurl_zalloc * Z K BT_MAXK ) )
    ( nurl_poke n 1 # i ( nurl_zalloc * Z V BT_MAXK ) )
    ? == leaf 1 {} { ( nurl_poke n 2 # i ( nurl_zalloc * 8 16 ) ) }
    ( nurl_poke n 4 leaf )
    ^ n
}

@ __bt_nkeys s n → i { ^ ( nurl_peek n 3 ) }
@ __bt_leaf s n → b { ^ == ( nurl_peek n 4 ) 1 }
@ __bt_size s n → i { ^ ( nurl_peek n 5 ) }
@ __bt_kid s n i idx → s {
    : *i kp # *i ( nurl_peek n 2 )
    ^ # s . kp idx
}
@ __bt_set_kid s n i idx s child → v {
    : *i kp # *i ( nurl_peek n 2 )
    = . kp idx # i child
}

// Recompute slot 5 from nkeys + child sizes (used after split/merge).
@ __bt_recount s n → v {
    : ~ i total ( __bt_nkeys n )
    ? ( __bt_leaf n ) {} {
        : i nk ( __bt_nkeys n )
        : ~ i c 0
        ~ <= c nk { = total + total ( __bt_size ( __bt_kid n c ) ) = c + c 1 }
    }
    ( nurl_poke n 5 total )
}

// Free a node block (arrays + block). Entries must already be handled.
@ __bt_node_free s n → v {
    ( nurl_free # s ( nurl_peek n 0 ) )
    ( nurl_free # s ( nurl_peek n 1 ) )
    ? ( __bt_leaf n ) {} { ( nurl_free # s ( nurl_peek n 2 ) ) }
    ( nurl_free n )
}

// ── construction / size ─────────────────────────────────────────────

@ btree_new [K V] → ( BTree K V ) {
    : s ctl ( nurl_zalloc 16 )
    ^ @ ( BTree K V ) { ctl }
}

@ btree_len [K V] ( BTree K V ) m → i { ^ ( nurl_peek . m ctl 1 ) }
@ btree_is_empty [K V] ( BTree K V ) m → b { ^ == ( btree_len [K V] m ) 0 }

// ── search ──────────────────────────────────────────────────────────

// Index of the first key in `n` that is >= k (0..nkeys).
@ __bt_lower [K V] s n K k ( @ i K K ) cmp → i {
    : *K kp # *K ( nurl_peek n 0 )
    : i nk ( __bt_nkeys n )
    : ~ i lo 0
    : ~ i hi nk
    ~ < lo hi {
        : i mid / + lo hi 2
        ? < ( cmp . kp mid k ) 0 { = lo + mid 1 } { = hi mid }
    }
    ^ lo
}

@ btree_get [K V] ( BTree K V ) m K k ( @ i K K ) cmp → ?V {
    : ~ s n # s ( nurl_peek . m ctl 0 )
    ~ != 0 # i n {
        : i pos ( __bt_lower [K V] n k cmp )
        : *K kp # *K ( nurl_peek n 0 )
        ? & < pos ( __bt_nkeys n ) == ( cmp . kp pos k ) 0 {
            : *V vp # *V ( nurl_peek n 1 )
            ^ @ ?V { T . vp pos }
        } {}
        ? ( __bt_leaf n ) { ^ @ ?V { F } } {}
        = n ( __bt_kid n pos )
    }
    ^ @ ?V { F }
}

@ btree_contains [K V] ( BTree K V ) m K k ( @ i K K ) cmp → b {
    : ?V r ( btree_get [K V] m k cmp )
    ^ ?? r { T _ → T F → F }
}

// ── insert ──────────────────────────────────────────────────────────

// Split the full child `c` (at child index ci of parent `p`): median key
// moves up into p, right half moves into a fresh sibling.
@ __bt_split_child [K V] s p i ci s c → v {
    : i leaf ? ( __bt_leaf c ) 1 0
    : s right ( __bt_node_new [K V] leaf )
    : *K ck # *K ( nurl_peek c 0 )
    : *V cv # *V ( nurl_peek c 1 )
    : *K rk # *K ( nurl_peek right 0 )
    : *V rv # *V ( nurl_peek right 1 )
    // right gets keys t..2t-2 (7 of them)
    : ~ i j 0
    ~ < j BT_MINK {
        = . rk j . ck + j BT_DEG
        = . rv j . cv + j BT_DEG
        = j + j 1
    }
    ? == leaf 1 {} {
        : ~ i j2 0
        ~ <= j2 BT_MINK {
            ( __bt_set_kid right j2 ( __bt_kid c + j2 BT_DEG ) )
            = j2 + j2 1
        }
    }
    ( nurl_poke right 3 BT_MINK )
    ( nurl_poke c 3 BT_MINK )
    // shift parent kids right of ci, insert `right` at ci+1
    : i pn ( __bt_nkeys p )
    : ~ i kk pn
    ~ > kk ci {
        ( __bt_set_kid p + kk 1 ( __bt_kid p kk ) )
        = kk - kk 1
    }
    ( __bt_set_kid p + ci 1 right )
    // shift parent keys/vals right of ci, lift c's median (index t-1)
    : *K pk # *K ( nurl_peek p 0 )
    : *V pv # *V ( nurl_peek p 1 )
    : ~ i mm pn
    ~ > mm ci {
        = . pk mm . pk - mm 1
        = . pv mm . pv - mm 1
        = mm - mm 1
    }
    = . pk ci . ck BT_MINK
    = . pv ci . cv BT_MINK
    ( nurl_poke p 3 + pn 1 )
    ( __bt_recount c )
    ( __bt_recount right )
}

// Insert into the non-full subtree rooted at `n`. Returns Some(prev) on
// replace, None on fresh insert (caller bumps len + path sizes).
@ __bt_insert_nonfull [K V] s n K k V v ( @ i K K ) cmp → ?V {
    : i pos ( __bt_lower [K V] n k cmp )
    : *K kp # *K ( nurl_peek n 0 )
    : *V vp # *V ( nurl_peek n 1 )
    : i nk ( __bt_nkeys n )
    ? & < pos nk == ( cmp . kp pos k ) 0 {
        : V prev . vp pos
        = . vp pos v
        ^ @ ?V { T prev }
    } {}
    ? ( __bt_leaf n ) {
        : ~ i j nk
        ~ > j pos {
            = . kp j . kp - j 1
            = . vp j . vp - j 1
            = j - j 1
        }
        = . kp pos k
        = . vp pos v
        ( nurl_poke n 3 + nk 1 )
        ( nurl_poke n 5 + ( __bt_size n ) 1 )
        ^ @ ?V { F }
    } {}
    : ~ i ci pos
    : ~ s c ( __bt_kid n ci )
    ? == ( __bt_nkeys c ) BT_MAXK {
        ( __bt_split_child [K V] n ci c )
        // after the lift, re-test against the lifted key
        : *K kp2 # *K ( nurl_peek n 0 )
        : i cr ( cmp . kp2 ci k )
        ? == cr 0 {
            : *V vp2 # *V ( nurl_peek n 1 )
            : V prev . vp2 ci
            = . vp2 ci v
            ^ @ ?V { T prev }
        } {}
        ? < cr 0 { = ci + ci 1 } {}
        = c ( __bt_kid n ci )
    } {}
    : ?V r ( __bt_insert_nonfull [K V] c k v cmp )
    ?? r {
        T prev → { ^ @ ?V { T prev } }
        F _ → {
            ( nurl_poke n 5 + ( __bt_size n ) 1 )
            ^ @ ?V { F }
        }
    }
}

@ btree_set [K V] ( BTree K V ) m K k V v ( @ i K K ) cmp → ?V {
    : s ctl . m ctl
    : ~ s root # s ( nurl_peek ctl 0 )
    ? == 0 # i root {
        = root ( __bt_node_new [K V] 1 )
        ( nurl_poke ctl 0 # i root )
    } {}
    ? == ( __bt_nkeys root ) BT_MAXK {
        : s nr ( __bt_node_new [K V] 0 )
        ( __bt_set_kid nr 0 root )
        ( __bt_recount nr )
        ( __bt_split_child [K V] nr 0 root )
        ( nurl_poke ctl 0 # i nr )
        = root nr
    } {}
    : ?V r ( __bt_insert_nonfull [K V] root k v cmp )
    ?? r {
        T prev → { ^ @ ?V { T prev } }
        F _ → {
            ( nurl_poke ctl 1 + ( nurl_peek ctl 1 ) 1 )
            ^ @ ?V { F }
        }
    }
}

// ── order statistics / min / max ────────────────────────────────────

@ btree_key_at [K V] ( BTree K V ) m i want → ?K {
    ? | < want 0 >= want ( btree_len [K V] m ) { ^ @ ?K { F } } {}
    : ~ s n # s ( nurl_peek . m ctl 0 )
    : ~ i idx want
    : ~ b going T
    ~ going {
        : *K kp # *K ( nurl_peek n 0 )
        : i nk ( __bt_nkeys n )
        ? ( __bt_leaf n ) { ^ @ ?K { T . kp idx } } {}
        : ~ i c 0
        : ~ b stepped F
        ~ & <= c nk ! stepped {
            : i csz ( __bt_size ( __bt_kid n c ) )
            ? < idx csz { = n ( __bt_kid n c ) = stepped T } {
                = idx - idx csz
                ? & == stepped F < c nk {
                    ? == idx 0 { ^ @ ?K { T . kp c } } {}
                    = idx - idx 1
                } {}
                = c + c 1
            }
        }
    }
    ^ @ ?K { F }
}

@ btree_val_at [K V] ( BTree K V ) m i want → ?V {
    ? | < want 0 >= want ( btree_len [K V] m ) { ^ @ ?V { F } } {}
    : ~ s n # s ( nurl_peek . m ctl 0 )
    : ~ i idx want
    : ~ b going T
    ~ going {
        : *V vp # *V ( nurl_peek n 1 )
        : i nk ( __bt_nkeys n )
        ? ( __bt_leaf n ) { ^ @ ?V { T . vp idx } } {}
        : ~ i c 0
        : ~ b stepped F
        ~ & <= c nk ! stepped {
            : i csz ( __bt_size ( __bt_kid n c ) )
            ? < idx csz { = n ( __bt_kid n c ) = stepped T } {
                = idx - idx csz
                ? & == stepped F < c nk {
                    ? == idx 0 { ^ @ ?V { T . vp c } } {}
                    = idx - idx 1
                } {}
                = c + c 1
            }
        }
    }
    ^ @ ?V { F }
}

@ btree_min_key [K V] ( BTree K V ) m → ?K { ^ ( btree_key_at [K V] m 0 ) }
@ btree_max_key [K V] ( BTree K V ) m → ?K { ^ ( btree_key_at [K V] m - ( btree_len [K V] m ) 1 ) }

// ── in-order traversal ──────────────────────────────────────────────

@ __bt_each_node [K V] s n ( @ v K V ) f → v {
    : *K kp # *K ( nurl_peek n 0 )
    : *V vp # *V ( nurl_peek n 1 )
    : i nk ( __bt_nkeys n )
    : ~ i j 0
    ~ < j nk {
        ? ( __bt_leaf n ) {} { ( __bt_each_node [K V] ( __bt_kid n j ) f ) }
        ( f . kp j . vp j )
        = j + j 1
    }
    ? ( __bt_leaf n ) {} { ( __bt_each_node [K V] ( __bt_kid n nk ) f ) }
}

@ btree_each [K V] ( BTree K V ) m ( @ v K V ) f → v {
    : s root # s ( nurl_peek . m ctl 0 )
    ? == 0 # i root { ^ v } {}
    ( __bt_each_node [K V] root f )
}

// ── remove (CLRS, proactive borrow/merge on the way down) ───────────

// Merge kids[ci] + parent key ci + kids[ci+1] into kids[ci]. Both kids
// hold exactly t-1 keys when called.
@ __bt_merge [K V] s n i ci → v {
    : s left ( __bt_kid n ci )
    : s right ( __bt_kid n + ci 1 )
    : *K lk # *K ( nurl_peek left 0 )
    : *V lv # *V ( nurl_peek left 1 )
    : *K rk # *K ( nurl_peek right 0 )
    : *V rv # *V ( nurl_peek right 1 )
    : *K nk2 # *K ( nurl_peek n 0 )
    : *V nv2 # *V ( nurl_peek n 1 )
    // parent separator drops into left[t-1]
    = . lk BT_MINK . nk2 ci
    = . lv BT_MINK . nv2 ci
    : ~ i j 0
    ~ < j BT_MINK {
        = . lk + BT_DEG j . rk j
        = . lv + BT_DEG j . rv j
        = j + j 1
    }
    ? ( __bt_leaf left ) {} {
        : ~ i j2 0
        ~ <= j2 BT_MINK {
            ( __bt_set_kid left + BT_DEG j2 ( __bt_kid right j2 ) )
            = j2 + j2 1
        }
    }
    ( nurl_poke left 3 BT_MAXK )
    // close the gap in n
    : i pn ( __bt_nkeys n )
    : ~ i m ci
    ~ < m - pn 1 {
        = . nk2 m . nk2 + m 1
        = . nv2 m . nv2 + m 1
        ( __bt_set_kid n + m 1 ( __bt_kid n + m 2 ) )
        = m + m 1
    }
    ( nurl_poke n 3 - pn 1 )
    ( __bt_node_free right )
    ( __bt_recount left )
}

// Ensure kids[ci] of `n` has at least t keys before descending: borrow
// from a sibling with spare keys, else merge. Returns the (possibly
// changed) child index to descend into.
@ __bt_fixup [K V] s n i ci → i {
    : s c ( __bt_kid n ci )
    ? >= ( __bt_nkeys c ) BT_DEG { ^ ci } {}
    : *K nk2 # *K ( nurl_peek n 0 )
    : *V nv2 # *V ( nurl_peek n 1 )
    : *K ck # *K ( nurl_peek c 0 )
    : *V cv # *V ( nurl_peek c 1 )
    : i cn ( __bt_nkeys c )
    // borrow from left sibling
    ? > ci 0 {
        : s ls ( __bt_kid n - ci 1 )
        ? > ( __bt_nkeys ls ) BT_MINK {
            : *K lk # *K ( nurl_peek ls 0 )
            : *V lv # *V ( nurl_peek ls 1 )
            : i ln ( __bt_nkeys ls )
            // shift c right one
            : ~ i j cn
            ~ > j 0 {
                = . ck j . ck - j 1
                = . cv j . cv - j 1
                = j - j 1
            }
            ? ( __bt_leaf c ) {} {
                : ~ i j2 + cn 1
                ~ > j2 0 {
                    ( __bt_set_kid c j2 ( __bt_kid c - j2 1 ) )
                    = j2 - j2 1
                }
                ( __bt_set_kid c 0 ( __bt_kid ls ln ) )
            }
            = . ck 0 . nk2 - ci 1
            = . cv 0 . nv2 - ci 1
            = . nk2 - ci 1 . lk - ln 1
            = . nv2 - ci 1 . lv - ln 1
            ( nurl_poke c 3 + cn 1 )
            ( nurl_poke ls 3 - ln 1 )
            ( __bt_recount ls )
            ( __bt_recount c )
            ^ ci
        } {}
    } {}
    // borrow from right sibling
    ? < ci ( __bt_nkeys n ) {
        : s rs ( __bt_kid n + ci 1 )
        ? > ( __bt_nkeys rs ) BT_MINK {
            : *K rk # *K ( nurl_peek rs 0 )
            : *V rv # *V ( nurl_peek rs 1 )
            : i rn ( __bt_nkeys rs )
            = . ck cn . nk2 ci
            = . cv cn . nv2 ci
            ? ( __bt_leaf c ) {} {
                ( __bt_set_kid c + cn 1 ( __bt_kid rs 0 ) )
            }
            = . nk2 ci . rk 0
            = . nv2 ci . rv 0
            // shift rs left one
            : ~ i j 0
            ~ < j - rn 1 {
                = . rk j . rk + j 1
                = . rv j . rv + j 1
                = j + j 1
            }
            ? ( __bt_leaf rs ) {} {
                : ~ i j2 0
                ~ < j2 rn {
                    ( __bt_set_kid rs j2 ( __bt_kid rs + j2 1 ) )
                    = j2 + j2 1
                }
            }
            ( nurl_poke c 3 + cn 1 )
            ( nurl_poke rs 3 - rn 1 )
            ( __bt_recount rs )
            ( __bt_recount c )
            ^ ci
        } {}
    } {}
    // merge with a sibling
    ? > ci 0 {
        ( __bt_merge [K V] n - ci 1 )
        ^ - ci 1
    } {}
    ( __bt_merge [K V] n ci )
    ^ ci
}

// Remove k from the subtree at `n` (which has ≥ t keys unless root).
// Returns Some(removed value).
@ __bt_remove_rec [K V] s n K k ( @ i K K ) cmp → ?V {
    : i pos ( __bt_lower [K V] n k cmp )
    : *K kp # *K ( nurl_peek n 0 )
    : *V vp # *V ( nurl_peek n 1 )
    : i nk ( __bt_nkeys n )
    : b here & < pos nk == ( cmp . kp pos k ) 0
    ? ( __bt_leaf n ) {
        ? here {} { ^ @ ?V { F } }
        : V out . vp pos
        : ~ i j pos
        ~ < j - nk 1 {
            = . kp j . kp + j 1
            = . vp j . vp + j 1
            = j + j 1
        }
        ( nurl_poke n 3 - nk 1 )
        ( nurl_poke n 5 - ( __bt_size n ) 1 )
        ^ @ ?V { T out }
    } {}
    ? here {
        : V out . vp pos
        : s lc ( __bt_kid n pos )
        ? >= ( __bt_nkeys lc ) BT_DEG {
            // replace with predecessor (max of left subtree), recurse
            : ~ s pn lc
            ~ ! ( __bt_leaf pn ) { = pn ( __bt_kid pn ( __bt_nkeys pn ) ) }
            : *K pk # *K ( nurl_peek pn 0 )
            : *V pv # *V ( nurl_peek pn 1 )
            : K predk . pk - ( __bt_nkeys pn ) 1
            : V predv . pv - ( __bt_nkeys pn ) 1
            = . kp pos predk
            = . vp pos predv
            : ?V sub ( __bt_remove_rec [K V] lc predk cmp )
            ?? sub { T _ → {} F _ → {} }
            ( nurl_poke n 5 - ( __bt_size n ) 1 )
            ^ @ ?V { T out }
        } {}
        : s rc ( __bt_kid n + pos 1 )
        ? >= ( __bt_nkeys rc ) BT_DEG {
            // replace with successor (min of right subtree)
            : ~ s sn rc
            ~ ! ( __bt_leaf sn ) { = sn ( __bt_kid sn 0 ) }
            : *K sk # *K ( nurl_peek sn 0 )
            : *V sv # *V ( nurl_peek sn 1 )
            : K succk . sk 0
            : V succv . sv 0
            = . kp pos succk
            = . vp pos succv
            : ?V sub ( __bt_remove_rec [K V] rc succk cmp )
            ?? sub { T _ → {} F _ → {} }
            ( nurl_poke n 5 - ( __bt_size n ) 1 )
            ^ @ ?V { T out }
        } {}
        // both kids minimal: merge them around the key, recurse into merge
        ( __bt_merge [K V] n pos )
        : ?V sub ( __bt_remove_rec [K V] ( __bt_kid n pos ) k cmp )
        ?? sub {
            T got → {
                ( nurl_poke n 5 - ( __bt_size n ) 1 )
                ^ @ ?V { T got }
            }
            F _ → { ^ @ ?V { F } }
        }
    } {}
    // not in this node: descend (fix the child up first)
    : i ci ( __bt_fixup [K V] n pos )
    : ?V sub ( __bt_remove_rec [K V] ( __bt_kid n ci ) k cmp )
    ?? sub {
        T got → {
            ( nurl_poke n 5 - ( __bt_size n ) 1 )
            ^ @ ?V { T got }
        }
        F _ → { ^ @ ?V { F } }
    }
}

@ btree_remove [K V] ( BTree K V ) m K k ( @ i K K ) cmp → ?V {
    : s ctl . m ctl
    : s root # s ( nurl_peek ctl 0 )
    ? == 0 # i root { ^ @ ?V { F } } {}
    : ?V r ( __bt_remove_rec [K V] root k cmp )
    ?? r {
        T got → {
            ( nurl_poke ctl 1 - ( nurl_peek ctl 1 ) 1 )
            // shrink the root: empty internal root → its sole child
            : s root2 # s ( nurl_peek ctl 0 )
            ? & == ( __bt_nkeys root2 ) 0 ! ( __bt_leaf root2 ) {
                : s only ( __bt_kid root2 0 )
                ( __bt_node_free root2 )
                ( nurl_poke ctl 0 # i only )
            } {
                ? & == ( __bt_nkeys root2 ) 0 ( __bt_leaf root2 ) {
                    ( __bt_node_free root2 )
                    ( nurl_poke ctl 0 0 )
                } {}
            }
            ^ @ ?V { T got }
        }
        F _ → { ^ @ ?V { F } }
    }
}

// ── teardown ────────────────────────────────────────────────────────

@ __bt_free_rec [K V] s n → v {
    ? ( __bt_leaf n ) {} {
        : i nk ( __bt_nkeys n )
        : ~ i c 0
        ~ <= c nk { ( __bt_free_rec [K V] ( __bt_kid n c ) ) = c + c 1 }
    }
    ( __bt_node_free n )
}

@ btree_free [K V] ( BTree K V ) m → v {
    : s root # s ( nurl_peek . m ctl 0 )
    ? == 0 # i root {} { ( __bt_free_rec [K V] root ) }
    ( nurl_free . m ctl )
}

@ __bt_free_with_rec [K V] s n ( @ v K ) dk ( @ v V ) dv → v {
    : *K kp # *K ( nurl_peek n 0 )
    : *V vp # *V ( nurl_peek n 1 )
    : i nk ( __bt_nkeys n )
    : ~ i j 0
    ~ < j nk {
        ( dk . kp j )
        ( dv . vp j )
        = j + j 1
    }
    ? ( __bt_leaf n ) {} {
        : ~ i c 0
        ~ <= c nk { ( __bt_free_with_rec [K V] ( __bt_kid n c ) dk dv ) = c + c 1 }
    }
    ( __bt_node_free n )
}

@ btree_free_with [K V] ( BTree K V ) m ( @ v K ) dk ( @ v V ) dv → v {
    : s root # s ( nurl_peek . m ctl 0 )
    ? == 0 # i root {} { ( __bt_free_with_rec [K V] root dk dv ) }
    ( nurl_free . m ctl )
}
