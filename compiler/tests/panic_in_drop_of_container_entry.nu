// panic_in_drop_of_container_entry.nu — an entry's destructor panics while
// a HashMap, a Set, a Deque or a BTree releases its entries, or hands one
// out (Agora #659, #658; stdlib/core/mem.nu, "A release a panic can go on
// with").
//
// The panic does not end the release: every entry after the panicking one
// still runs its destructor, once, the container's buffers are freed, and
// only then does the panic go on to its `recover`. Before, each of these
// releases was a loop the panic simply left: the entries after it ran no
// destructor and what they owned leaked (LeakSanitizer, run_san_tests.sh).
//
// `*_two`: a LATER entry's destructor panics too, inside the first panic's
// drain; the release goes on again and the first panic — the cause — keeps
// its message. `every_one`: all twenty thousand do, in each container; each
// is caught where the release goes on, so the stack is no deeper than for
// one.
//
// A container that hands an entry out drops what goes with it LAST, with
// the container already without the entry and the value handed back still
// the frame's own: `btree_remove` (the stored key — before, dropped while
// its node still counted the slot, and the tree's own drop ran it again on
// a slot given up: a crash, #658), `map_remove` (the stored key),
// `btree_set` / `map_set` replacing an entry (the passed key). The
// container lives on, without that entry and usable.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
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

@ bomb s tag i id i boom → Bomb { ^ @ Bomb { ( string_from tag ) id boom } }

@ bhash Bomb b → i { ^ ( hash_int . b id ) }

@ beq Bomb a Bomb b → b { ^ == . a id . b id }

@ bcmp Bomb a Bomb b → i { ^ - . a id . b id }

@ icmp i a i b → i { ^ - a b }

// ── HashMap ─────────────────────────────────────────────────────────

@ vmap i boom2 i boom3 → ( HashMap i Bomb ) {
    : ( HashMap i Bomb ) m ( map_new [i Bomb] )
    : ?Bomb _a ( map_set [i Bomb] m 1 ( bomb `a` 1 0 ) \ i x → i { ^ ( hash_int x ) } \ i x i y → b { ^ == x y } )
    : ?Bomb _b ( map_set [i Bomb] m 2 ( bomb `b` 2 boom2 ) \ i x → i { ^ ( hash_int x ) } \ i x i y → b { ^ == x y } )
    : ?Bomb _c ( map_set [i Bomb] m 3 ( bomb `c` 3 boom3 ) \ i x → i { ^ ( hash_int x ) } \ i x i y → b { ^ == x y } )
    : ?Bomb _d ( map_set [i Bomb] m 4 ( bomb `d` 4 0 ) \ i x → i { ^ ( hash_int x ) } \ i x i y → b { ^ == x y } )
    ^ m
}

@ kmap i boom2 → ( HashMap Bomb String ) {
    : ( HashMap Bomb String ) m ( map_new [Bomb String] )
    : ?String _a ( map_set [Bomb String] m ( bomb `a` 1 0 ) ( string_from `value of a, on the heap` ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    : ?String _b ( map_set [Bomb String] m ( bomb `b` 2 boom2 ) ( string_from `value of b, on the heap` ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    : ?String _c ( map_set [Bomb String] m ( bomb `c` 3 0 ) ( string_from `value of c, on the heap` ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    : ?String _d ( map_set [Bomb String] m ( bomb `d` 4 0 ) ( string_from `value of d, on the heap` ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    ^ m
}

// A value's destructor, at the map binding's end.
@ map_values → v {
    : ( HashMap i Bomb ) m ( vmap 1 0 )
    ( nurl_println `map_values: built` )
}

@ map_two → v {
    : ( HashMap i Bomb ) m ( vmap 1 1 )
    ( nurl_println `map_two: built` )
}

// A key's destructor: the value beside it goes too.
@ map_keys → v {
    : ( HashMap Bomb String ) m ( kmap 1 )
    ( nurl_println `map_keys: built` )
}

// map_remove: the stored key's destructor panics. The map is without the
// entry, the value it was about to hand back is released by the unwind.
@ map_removes → v {
    : ( HashMap Bomb String ) m ( kmap 1 )
    : !v PanicInfo r ( recover \ → v {
        : Bomb which ( bomb `which` 2 0 )
        : ?String got ( map_remove [Bomb String] m which \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
        ( nurl_println `map_removes: not reached` )
    } )
    ?? r {
        T _ → { ( nurl_println `map_removes: no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `map_removes: recovered: ` ( string_data . e msg ) ) ) }
    }
    ( nurl_println ( nurl_str_cat `map_removes: len ` ( nurl_str_int ( map_len [Bomb String] m ) ) ) )
    : Bomb probe ( bomb `probe` 2 0 )
    ( nurl_println ( nurl_str_cat `map_removes: still has b: ` ? ( map_contains [Bomb String] m probe \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } ) `yes` `no` ) )
}

// map_set over an existing entry: the stored key stays, the passed one is
// dropped — and panics. The new value is in, the old one is released.
@ map_replaces → v {
    : ( HashMap Bomb String ) m ( kmap 0 )
    : !v PanicInfo r ( recover \ → v {
        : ?String old ( map_set [Bomb String] m ( bomb `b2` 2 1 ) ( string_from `the new value of b, on the heap` ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
        ( nurl_println `map_replaces: not reached` )
    } )
    ?? r {
        T _ → { ( nurl_println `map_replaces: no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `map_replaces: recovered: ` ( string_data . e msg ) ) ) }
    }
    : Bomb probe ( bomb `probe` 2 0 )
    : ?String now ( map_get [Bomb String] m probe \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    ?? now {
        T x → { ( nurl_println ( nurl_str_cat `map_replaces: b is ` ( string_data x ) ) ) }
        F → { ( nurl_println `map_replaces: b is gone` ) }
    }
}

// ── Set ─────────────────────────────────────────────────────────────

@ set_elements i boom3 → v {
    : ( Set Bomb ) st ( set_new [Bomb] )
    : b _a ( set_add [Bomb] st ( bomb `a` 1 0 ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    : b _b ( set_add [Bomb] st ( bomb `b` 2 1 ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    : b _c ( set_add [Bomb] st ( bomb `c` 3 boom3 ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    : b _d ( set_add [Bomb] st ( bomb `d` 4 0 ) \ Bomb x → i { ^ ( bhash x ) } \ Bomb x Bomb y → b { ^ ( beq x y ) } )
    ( nurl_println `set: built` )
}

// ── Deque ───────────────────────────────────────────────────────────

// Four slots, the ring wrapped: y z in slots 2 3, then a b in slots 0 1.
@ ring i boomz i booma → ( Deque Bomb ) {
    : ( Deque Bomb ) d ( deque_new [Bomb] )
    ( deque_push_back [Bomb] d ( bomb `p` 0 0 ) )
    ( deque_push_back [Bomb] d ( bomb `q` 0 0 ) )
    ( deque_push_back [Bomb] d ( bomb `y` 0 0 ) )
    ( deque_push_back [Bomb] d ( bomb `z` 0 boomz ) )
    : ?Bomb _p ( deque_pop_front [Bomb] d )
    : ?Bomb _q ( deque_pop_front [Bomb] d )
    ( deque_push_back [Bomb] d ( bomb `a` 0 booma ) )
    ( deque_push_back [Bomb] d ( bomb `b` 0 0 ) )
    ^ d
}

// The run before the wrap panics: the run after it is still dropped.
@ deque_first_run → v {
    : ( Deque Bomb ) d ( ring 1 0 )
    ( nurl_println `deque_first_run: built` )
}

// …and one in each run.
@ deque_both_runs → v {
    : ( Deque Bomb ) d ( ring 1 1 )
    ( nurl_println `deque_both_runs: built` )
}

// deque_clear inside a `recover` of its own: the deque lives on, empty.
@ deque_clears → v {
    : ( Deque Bomb ) d ( ring 0 1 )
    : !v PanicInfo r ( recover \ → v { ( deque_clear [Bomb] d ) } )
    ?? r {
        T _ → { ( nurl_println `deque_clears: no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `deque_clears: recovered: ` ( string_data . e msg ) ) ) }
    }
    ( nurl_println ( nurl_str_cat `deque_clears: len ` ( nurl_str_int ( deque_len [Bomb] d ) ) ) )
    ( deque_push_back [Bomb] d ( bomb `late` 0 0 ) )
}

// ── BTree ───────────────────────────────────────────────────────────

@ ktree i boom2 → ( BTree Bomb String ) {
    : ( BTree Bomb String ) m ( btree_new [Bomb String] )
    : ?String _a ( btree_set [Bomb String] m ( bomb `a` 1 0 ) ( string_from `value of a, on the heap` ) \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
    : ?String _b ( btree_set [Bomb String] m ( bomb `b` 2 boom2 ) ( string_from `value of b, on the heap` ) \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
    : ?String _c ( btree_set [Bomb String] m ( bomb `c` 3 0 ) ( string_from `value of c, on the heap` ) \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
    : ?String _d ( btree_set [Bomb String] m ( bomb `d` 4 0 ) ( string_from `value of d, on the heap` ) \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
    ^ m
}

@ tree_values → v {
    : ( BTree i Bomb ) m ( btree_new [i Bomb] )
    : ?Bomb _a ( btree_set [i Bomb] m 1 ( bomb `a` 1 0 ) \ i x i y → i { ^ ( icmp x y ) } )
    : ?Bomb _b ( btree_set [i Bomb] m 2 ( bomb `b` 2 1 ) \ i x i y → i { ^ ( icmp x y ) } )
    : ?Bomb _c ( btree_set [i Bomb] m 3 ( bomb `c` 3 0 ) \ i x i y → i { ^ ( icmp x y ) } )
    : ?Bomb _d ( btree_set [i Bomb] m 4 ( bomb `d` 4 0 ) \ i x i y → i { ^ ( icmp x y ) } )
    ( nurl_println `tree_values: built` )
}

@ tree_keys → v {
    : ( BTree Bomb String ) m ( ktree 1 )
    ( nurl_println `tree_keys: built` )
}

@ tree_show ( BTree Bomb String ) m s name → v {
    : ~ String line ( string_from name )
    ( string_push_str line `: holds` )
    ( btree_each [Bomb String] m \ Bomb k String x → v { ( string_push_str line ` ` ) ( string_push_str line ( string_data . k tag ) ) } )
    ( string_push_str line `, len ` )
    ( string_push_str line ( nurl_str_int ( btree_len [Bomb String] m ) ) )
    ( nurl_println ( string_data line ) )
}

// The #658 shape: btree_remove drops the stored key, and it panics. The
// tree holds exactly the other keys and goes on being used.
@ tree_removes → v {
    : ( BTree Bomb String ) m ( ktree 1 )
    : !v PanicInfo r ( recover \ → v {
        : Bomb which ( bomb `which` 2 0 )
        : ?String got ( btree_remove [Bomb String] m which \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
        ( nurl_println `tree_removes: not reached` )
    } )
    ?? r {
        T _ → { ( nurl_println `tree_removes: no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `tree_removes: recovered: ` ( string_data . e msg ) ) ) }
    }
    ( tree_show m `tree_removes` )
    : ?String _e ( btree_set [Bomb String] m ( bomb `e` 5 0 ) ( string_from `value of e, on the heap` ) \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
    ( tree_show m `tree_removes` )
}

// The same with no `recover` of its own: the panic unwinds the tree's
// binding, which drops what the remove left — each entry once.
@ tree_removes_unwound → v {
    : ( BTree Bomb String ) m ( ktree 1 )
    : Bomb probe ( bomb `probe` 2 0 )
    : ?String got ( btree_remove [Bomb String] m probe \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
    ( nurl_println `tree_removes_unwound: not reached` )
}

// btree_set over an existing entry: the passed key is dropped, and panics.
@ tree_replaces → v {
    : ( BTree Bomb String ) m ( ktree 0 )
    : !v PanicInfo r ( recover \ → v {
        : ?String old ( btree_set [Bomb String] m ( bomb `b2` 2 1 ) ( string_from `the new value of b, on the heap` ) \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
        ( nurl_println `tree_replaces: not reached` )
    } )
    ?? r {
        T _ → { ( nurl_println `tree_replaces: no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `tree_replaces: recovered: ` ( string_data . e msg ) ) ) }
    }
    : Bomb probe ( bomb `probe` 2 0 )
    : ?String now ( btree_get [Bomb String] m probe \ Bomb x Bomb y → i { ^ ( bcmp x y ) } )
    ?? now {
        T x → { ( nurl_println ( nurl_str_cat `tree_replaces: b is ` ( string_data x ) ) ) }
        F → { ( nurl_println `tree_replaces: b is gone` ) }
    }
}

// ── Many entries: counted, not printed ──────────────────────────────

: ~ i g_ticks 0

: ~ i g_live 0

// Panics when its id is a multiple of `every` (0: never).
: Tick { i id i every String pad }

% Drop Tick {
    @ drop Tick t → v {
        = g_ticks + g_ticks 1
        = g_live - g_live 1
        ? & > . t every 0 == % . t id . t every 0 { ( panic `tick` ) } {}
    }
}

@ tick i id i every → Tick {
    = g_live + g_live 1
    ^ @ Tick { id every ( string_from `sixteen bytes+one` ) }
}

@ thash Tick t → i { ^ ( hash_int . t id ) }

@ teq Tick a Tick b → b { ^ == . a id . b id }

@ tcmp Tick a Tick b → i { ^ - . a id . b id }

@ many_map i n i every → v {
    : ( HashMap i Tick ) m ( map_new [i Tick] )
    : ~ i k 0
    ~ < k n {
        : ?Tick _p ( map_set [i Tick] m k ( tick k every ) \ i x → i { ^ ( hash_int x ) } \ i x i y → b { ^ == x y } )
        = k + k 1
    }
}

@ many_set i n i every → v {
    : ( Set Tick ) st ( set_new [Tick] )
    : ~ i k 0
    ~ < k n {
        : b _p ( set_add [Tick] st ( tick k every ) \ Tick x → i { ^ ( thash x ) } \ Tick x Tick y → b { ^ ( teq x y ) } )
        = k + k 1
    }
}

@ many_deque i n i every → v {
    : ( Deque Tick ) d ( deque_new [Tick] )
    : ~ i k 0
    ~ < k n {
        ? == % k 3 0 { ( deque_push_front [Tick] d ( tick k every ) ) } { ( deque_push_back [Tick] d ( tick k every ) ) }
        = k + k 1
    }
}

// Keys and values both: three levels of nodes at twenty thousand.
@ many_tree i n i every → v {
    : ( BTree Tick Tick ) m ( btree_new [Tick Tick] )
    : ~ i k 0
    ~ < k n {
        : ?Tick _p ( btree_set [Tick Tick] m ( tick k every ) ( tick + k 1 every ) \ Tick x Tick y → i { ^ ( tcmp x y ) } )
        = k + k 1
    }
}

// Removals out of a three-level tree, a panicking key every seventh: each
// inside a recover of its own; the tree stays ordered and counted.
@ tree_churn → v {
    : ( BTree Tick i ) m ( btree_new [Tick i] )
    : ~ i k 0
    ~ < k 3000 {
        : ?i _p ( btree_set [Tick i] m ( tick k 7 ) k \ Tick x Tick y → i { ^ ( tcmp x y ) } )
        = k + k 1
    }
    : ~ i caught 0
    : ~ i removed 0
    = k 0
    ~ < k 3000 {
        : !v PanicInfo r ( recover \ → v {
            : Tick probe ( tick k 0 )
            : ?i got ( btree_remove [Tick i] m probe \ Tick x Tick y → i { ^ ( tcmp x y ) } )
            ?? got { T _ → { = removed + removed 1 } F → {} }
        } )
        ?? r { T _ → {} F _ → { = caught + caught 1 } }
        = k + k 2
    }
    : ~ i seen 0
    : ~ i last -1
    : ~ b ordered T
    ( btree_each [Tick i] m \ Tick t i x → v {
        ? <= . t id last { = ordered F } {}
        = last . t id
        = seen + seen 1
    } )
    ( nurl_println ( nurl_str_cat `tree_churn: panics caught ` ( nurl_str_int caught ) ) )
    ( nurl_println ( nurl_str_cat `tree_churn: removed without a panic ` ( nurl_str_int removed ) ) )
    ( nurl_println ( nurl_str_cat `tree_churn: len ` ( nurl_str_int ( btree_len [Tick i] m ) ) ) )
    ( nurl_println ( nurl_str_cat `tree_churn: walked ` ( nurl_str_int seen ) ) )
    ( nurl_println ( nurl_str_cat `tree_churn: ordered ` ? ordered `yes` `no` ) )
}

// A container in a container: the inner release is left by the panic,
// then the outer.
@ nested → v {
    : ~ ( Vec ( HashMap i Bomb ) ) vm ( vec_new [( HashMap i Bomb )] )
    ( vec_push [( HashMap i Bomb )] vm ( vmap 1 0 ) )
    ( vec_push [( HashMap i Bomb )] vm ( vmap 0 0 ) )
    ( nurl_println `nested: built` )
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ counted s name ( @ v ) f → v {
    = g_ticks 0
    ( run name f )
    ( nurl_println ( nurl_str_cat4 name `: destructors run ` ( nurl_str_int g_ticks ) ( nurl_str_cat `, values left ` ( nurl_str_int g_live ) ) ) )
}

@ main → i {
    ( run `map_values` \ → v { ( map_values ) } )
    ( run `map_two` \ → v { ( map_two ) } )
    ( run `map_keys` \ → v { ( map_keys ) } )
    ( map_removes )
    ( map_replaces )
    ( run `set` \ → v { ( set_elements 0 ) } )
    ( run `set_two` \ → v { ( set_elements 1 ) } )
    ( run `deque_first_run` \ → v { ( deque_first_run ) } )
    ( run `deque_both_runs` \ → v { ( deque_both_runs ) } )
    ( deque_clears )
    ( run `tree_values` \ → v { ( tree_values ) } )
    ( run `tree_keys` \ → v { ( tree_keys ) } )
    ( tree_removes )
    ( run `tree_removes_unwound` \ → v { ( tree_removes_unwound ) } )
    ( tree_replaces )
    ( run `nested` \ → v { ( nested ) } )
    ( counted `some_map` \ → v { ( many_map 20000 97 ) } )
    ( counted `every_map` \ → v { ( many_map 20000 1 ) } )
    ( counted `some_set` \ → v { ( many_set 20000 97 ) } )
    ( counted `every_set` \ → v { ( many_set 20000 1 ) } )
    ( counted `some_deque` \ → v { ( many_deque 20000 97 ) } )
    ( counted `every_deque` \ → v { ( many_deque 20000 1 ) } )
    ( counted `some_tree` \ → v { ( many_tree 20000 97 ) } )
    ( counted `every_tree` \ → v { ( many_tree 20000 1 ) } )
    ( counted `tree_churn` \ → v { ( tree_churn ) } )
    // The thread's frees are ordinary again after all of that.
    : ~ i k 0
    : ~ i n 0
    ~ < k 100000 {
        : String s ( string_from `abcdefghijklmnop` )
        = n + n ( string_len s )
        = k + k 1
    }
    ( nurl_println ( nurl_str_cat `bytes: ` ( nurl_str_int n ) ) )
    ^ 0
}
