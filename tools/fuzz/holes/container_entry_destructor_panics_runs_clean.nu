// container_entry_destructor_panics_runs_clean: a HashMap, a Set, a wrapped Deque and a BTree dropped under `recover` with an entry whose destructor panics part-way; `map_remove` whose stored key's destructor panics; `btree_set` / `map_set` over an existing entry whose passed key's destructor panics.
// Guard for agora #659: an entry leaves its container before its destructor runs, and the release in progress is a record in the panic journal (MapRelease, SetRelease, DqRelease, BtRelease; mem_release_rest), so the entries after the panicking one are still dropped, once each; a key that goes is dropped while the value handed back is still a binding. Before, each release was a loop the panic left, and the value beside a panicking key sat in a result literal nobody owned.
// main 0dcd56f: accepted, LeakSanitizer: the entries after the panicking one never dropped (their Strings), and the value map_remove / btree_set was about to hand back.
// map: §7.2 | A2 | runs-clean | - | agora #659 guard: a HashMap, Set, Deque or BTree whose entry's destructor panics still drops every other entry once; map_remove / map_set / btree_set whose key's destructor panics release the value they were handing back
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/set.nu`
$ `stdlib/std/deque.nu`
$ `stdlib/std/btree.nu`

: Bomb { String tag i id i boom }

% Drop Bomb {
    @ drop Bomb b → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) )
        ? == . b boom 1 { ( panic ( nurl_str_cat `panic in drop ` ( string_data . b tag ) ) ) } {}
    }
}

@ bomb s tag i id → Bomb { ^ @ Bomb { ( string_from tag ) id ? == % id 3 1 1 0 } }

@ calm s tag i id → Bomb { ^ @ Bomb { ( string_from tag ) id 0 } }

@ bhash Bomb b → i { ^ ( hash_int . b id ) }

@ beq Bomb a Bomb b → b { ^ == . a id . b id }

@ bcmp Bomb a Bomb b → i { ^ - . a id . b id }

@ long → String { ^ ( string_from `a value long enough for the heap` ) }

@ maps → v {
    : ( HashMap i Bomb ) byval ( map_new [i Bomb] )
    : ( HashMap Bomb String ) bykey ( map_new [Bomb String] )
    : ~ i k 0
    ~ < k 12 {
        : ?Bomb _p ( map_set [i Bomb] byval k ( bomb `v` k ) \ i x → i { ^ ( hash_int x ) } \ i x i y → b { ^ == x y } )
        : ?String _q ( map_set [Bomb String] bykey ( bomb `k` k ) ( long ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
        = k + k 1
    }
}

@ sets → v {
    : ( Set Bomb ) st ( set_new [Bomb] )
    : ~ i k 0
    ~ < k 12 {
        : b _p ( set_add [Bomb] st ( bomb `e` k ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
        = k + k 1
    }
}

// Eight slots, six live, the ring wrapped: bombs in both runs.
@ deques → v {
    : ( Deque Bomb ) d ( deque_new [Bomb] )
    : ~ i k 0
    ~ < k 7 {
        ( deque_push_back [Bomb] d ( calm `early` k ) )
        = k + k 1
    }
    = k 0
    ~ < k 5 {
        : ?Bomb _p ( deque_pop_front [Bomb] d )
        = k + k 1
    }
    = k 0
    ~ < k 4 {
        ( deque_push_back [Bomb] d ( bomb `d` k ) )
        = k + k 1
    }
}

@ trees → v {
    : ( BTree Bomb Bomb ) m ( btree_new [Bomb Bomb] )
    : ~ i k 0
    ~ < k 40 {
        : ?Bomb _p ( btree_set [Bomb Bomb] m ( bomb `k` k ) ( bomb `v` + k 1 ) \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
        = k + k 1
    }
}

// The stored key (id 4: it panics) goes; the value was on its way out.
@ removes → v {
    : ( HashMap Bomb String ) m ( map_new [Bomb String] )
    : ?String _p ( map_set [Bomb String] m ( bomb `stored` 4 ) ( long ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    : Bomb probe ( calm `probe` 4 )
    : ?String got ( map_remove [Bomb String] m probe \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    ( nurl_println `not reached` )
}

// The passed key (id 4: it panics) goes; the old value was on its way out.
@ replaces → v {
    : ( HashMap Bomb String ) m ( map_new [Bomb String] )
    : ( BTree Bomb String ) t ( btree_new [Bomb String] )
    : ?String _p ( map_set [Bomb String] m ( calm `stored` 4 ) ( long ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    : ?String _q ( btree_set [Bomb String] t ( calm `stored` 4 ) ( long ) \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
    : !v PanicInfo r ( recover \ → v {
        : ?String old ( map_set [Bomb String] m ( bomb `passed` 4 ) ( long ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
        ( nurl_println `not reached` )
    } )
    : ?String old ( btree_set [Bomb String] t ( bomb `passed` 4 ) ( long ) \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
    ( nurl_println `not reached` )
}

@ run ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println `no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run \ → v { ( maps ) } )
    ( run \ → v { ( sets ) } )
    ( run \ → v { ( deques ) } )
    ( run \ → v { ( trees ) } )
    ( run \ → v { ( removes ) } )
    ( run \ → v { ( replaces ) } )
    ^ 0
}
