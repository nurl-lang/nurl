// drop_v1_shapes.nu — shapes the v1 memory model drops with nothing
// freed by hand (docs/MEMORY.md §7.6), each run for several rounds: the
// live allocation count (nurl_alloc_count − nurl_free_count) must not grow
// from one round to the next. Every shape below leaked before v1.
//
//   - an option-typed call result passed straight to a function that only
//     reads it;
//   - a `?` / `??` arm whose tail call's value is discarded;
//   - vec_set replacing an element (the old one is dropped);
//   - a scalar computed from a local handle (`^ + … ( vec_len v )`);
//   - library handles (HashMap, Set, Deque, BTree, Box, Rc) with String
//     contents, including their replace / remove operations;
//   - String / Vec / HashMap locals of a function a panic unwinds out of
//     (under `recover`), and one that moved its value on first.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/set.nu`
$ `stdlib/std/deque.nu`
$ `stdlib/std/btree.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/panic.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ maybe i k → ?String {
    ? > k 0 { ^ @ ?String { T ( string_from `yes` ) } } {}
    ^ @ ?String { F }
}

@ width ? String o → i {
    ^ ?? o { T s → ( string_len s ) F → 0 }
}

@ sizes i k → i {
    : String s ( string_from `abc` )
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v k )
    ^ + ( string_len s ) ( vec_len [i] v )
}

@ explode i k ( Vec String ) keep → i {
    : String s ( string_from `abc` )
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v k )
    : ( HashMap i i ) m ( map_new [i i] )
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i a i b → b { ^ == a b }
    ( map_set [i i] m k k hi ei )
    : String moved ( string_from `moved` )
    ( vec_push [String] keep moved )
    ? > k 0 { ( panic `boom` ) } {}
    ^ + ( string_len s ) ( vec_len [i] v )
}

@ cmp_s String a String b → i { ^ ( nurl_str_cmp ( string_data a ) ( string_data b ) ) }

@ round i r → i {
    : ~ i acc 0
    // Option temporaries.
    = acc + acc ( width ( maybe 1 ) )
    = acc + acc ( width ( maybe 0 ) )
    // Discarded arm tails.
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a` ) )
    ( vec_push [String] v ( string_from `b` ) )
    ( vec_push [String] v ( string_from `c` ) )
    ?? ( vec_len [String] v ) { 3 → ( vec_remove [String] v 0 ) _ → @ ?String { F } }
    ? > ( vec_len [String] v ) 0 { ( vec_pop [String] v ) } {}
    // vec_set drops what it replaces.
    : b _s ( vec_set [String] v 0 ( string_from `z` ) )
    // A scalar out of local handles.
    = acc + acc ( sizes r )
    // Library handles.
    : ( @ i String ) hs \ String x → i { ^ ( hash_string ( string_data x ) ) }
    : ( @ b String String ) es \ String a String b → b { ^ ( eq_string ( string_data a ) ( string_data b ) ) }
    : ( HashMap String String ) m ( map_new [String String] )
    ( map_set [String String] m ( string_from `k` ) ( string_from `v1` ) hs es )
    ( map_set [String String] m ( string_from `k` ) ( string_from `v2` ) hs es )
    ( map_set [String String] m ( string_from `j` ) ( string_from `v3` ) hs es )
    : String rk ( string_from `j` )
    ( map_remove [String String] m rk hs es )
    : ( HashMap String String ) mc ( map_clone [String String] m )
    = acc + acc ( map_len [String String] mc )
    : ( Set String ) st ( set_new [String] )
    ( set_add [String] st ( string_from `x` ) hs es )
    ( set_add [String] st ( string_from `x` ) hs es )
    : ( Deque String ) dq ( deque_new [String] )
    ( deque_push_back [String] dq ( string_from `d1` ) )
    ( deque_push_front [String] dq ( string_from `d0` ) )
    ( deque_pop_back [String] dq )
    : ( @ i String String ) c \ String a String b → i { ^ ( cmp_s a b ) }
    : ( BTree String String ) t ( btree_new [String String] )
    : ~ i k 0
    ~ < k 40 {
        ( btree_set [String String] t ( string_from ( nurl_str_int k ) ) ( string_from `v` ) c )
        = k + k 1
    }
    = k 0
    ~ < k 30 {
        : String key ( string_from ( nurl_str_int k ) )
        ( btree_remove [String String] t key c )
        = k + k 1
    }
    : ( Box String ) b ( box_new [String] ( string_from `boxed` ) )
    ( box_set [String] b ( string_from `boxed2` ) )
    : ( Rc String ) rc ( rc_new [String] ( string_from `shared` ) )
    : ( Rc String ) rc2 ( rc_clone [String] rc )
    = acc + acc ( rc_strong [String] rc2 )
    // A panic unwinding out of a function with owned locals.
    : ( Vec String ) kept ( vec_new [String] )
    : !v PanicInfo pr ( recover \ → v { : i x ( explode r kept ) } )
    = acc + acc ( vec_len [String] kept )
    ^ acc
}

@ main → i {
    : i r1 ( round 1 )
    : i l1 ( live )
    : i r2 ( round 2 )
    : i r3 ( round 3 )
    : i l3 ( live )
    ( puts ( nurl_str_int r1 ) )
    ( puts ( nurl_str_int + r2 r3 ) )
    ? == l1 l3 { ( puts `live allocations: steady` ) } { ( puts ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l3 l1 ) ) ) }
    ^ 0
}
