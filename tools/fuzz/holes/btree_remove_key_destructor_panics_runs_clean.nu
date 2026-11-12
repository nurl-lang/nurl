// btree_remove_key_destructor_panics_runs_clean: `btree_remove` of an entry whose stored key's destructor panics, under `recover`; then the tree is used again and dropped.
// Guard for agora #658: the removed key is handed up out of the recursion and dropped by btree_remove last, once the leaf, the ancestors' sizes, the tree's count and the root are final and while the value handed back is still a binding. The panic leaves a tree without the entry. Before, the key was dropped inside the recursion with its node still counting the (emptied) slot, and the tree's own drop ran the destructor again on it.
// main 0dcd56f: accepted, SEGV in drop__Bomb (a null read of the emptied slot) under __bt_drop_rec in nurl__jrnl_drain.
// map: §7.2 | A2 | runs-clean | - | agora #658 guard: btree_remove whose removed key's destructor panics leaves a tree without the entry, usable, and each remaining entry is dropped once
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/btree.nu`

: Bomb { String tag i id i boom }

% Drop Bomb {
    @ drop Bomb b → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) )
        ? == . b boom 1 { ( panic ( nurl_str_cat `panic in drop ` ( string_data . b tag ) ) ) } {}
    }
}

@ bomb s tag i id i boom → Bomb { ^ @ Bomb { ( string_from tag ) id boom } }

@ bcmp Bomb a Bomb b → i { ^ - . a id . b id }

@ put ( BTree Bomb String ) m s tag i id i boom → v {
    : ?String _p ( btree_set [Bomb String] m ( bomb tag id boom ) ( string_from `a value long enough for the heap` ) \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
}

@ take ( BTree Bomb String ) m i id → v {
    : Bomb probe ( bomb `probe` id 0 )
    : ?String got ( btree_remove [Bomb String] m probe \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
    ( nurl_println `removed without a panic` )
}

@ body → v {
    : ( BTree Bomb String ) m ( btree_new [Bomb String] )
    : ~ i k 0
    // Forty entries: an inner root, so removals take the leaf, the
    // predecessor, the successor and the merge paths; every fifth key's
    // destructor panics.
    ~ < k 40 {
        ( put m `k` k ? == % k 5 0 1 0 )
        = k + k 1
    }
    : ~ i caught 0
    = k 0
    ~ < k 40 {
        : !v PanicInfo r ( recover \ → v { ( take m k ) } )
        ?? r { T _ → {} F _ → { = caught + caught 1 } }
        = k + k 3
    }
    ( nurl_println ( nurl_str_cat `caught ` ( nurl_str_int caught ) ) )
    ( nurl_println ( nurl_str_cat `len ` ( nurl_str_int ( btree_len [Bomb String] m ) ) ) )
    ( put m `late` 100 0 )
    // The tree's own drop follows, with panicking keys still in it.
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { ( body ) } )
    ?? r {
        T _ → { ( nurl_println `no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `recovered: ` ( string_data . e msg ) ) ) }
    }
    ^ 0
}
