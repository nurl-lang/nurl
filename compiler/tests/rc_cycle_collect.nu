// rc_cycle_collect.nu — reference-count cycles are collected (docs/MEMORY.md §7.7).
//
// A value that holds, through its own contents, an Rc to itself keeps every
// count in the cycle above zero. The context's cycle collector finds them:
// self-loops, pairs, cycles through Vec / HashMap / Deque / BTree / Box /
// an enum payload / a closure stored in the value it captured — while a
// live structure that a cycle points INTO survives with its count intact.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`
$ `stdlib/std/btree.nu`
$ `stdlib/std/rc.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ show s label i n → v { ( nurl_print label ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` ) }

: Node { i id ( Vec ( Rc Node ) ) kids }
: | Link { To ( Rc Lnk ) Nil }
: Lnk { i id Link next }
: Holder { i id ? ( @ i ) cb }
: Bag { i id ( HashMap i ( Rc Bag ) ) m ( Deque ( Rc Bag ) ) d ( BTree i ( Rc Bag ) ) t ? ( Box ( Rc Bag ) ) b }

@ link ( Rc Node ) a ( Rc Node ) b → v {
    : Node na ( rc_get [Node] a )
    ( vec_push [( Rc Node )] . na kids ( rc_clone [Node] b ) )
}

@ node i k → ( Rc Node ) { ^ ( rc_new [Node] @ Node { k ( vec_new [( Rc Node )] ) } ) }

@ self_loop → v { : ( Rc Node ) a ( node 1 ) ( link a a ) }

@ pair → v { : ( Rc Node ) a ( node 1 ) : ( Rc Node ) b ( node 2 ) ( link a b ) ( link b a ) }

@ enum_pair → v {
    : ( Rc Lnk ) a ( rc_new [Lnk] @ Lnk { 1 @ Link { Nil } } )
    : ( Rc Lnk ) b ( rc_new [Lnk] @ Lnk { 2 @ Link { To ( rc_clone [Lnk] a ) } } )
    ( rc_set [Lnk] a @ Lnk { 1 @ Link { To ( rc_clone [Lnk] b ) } } )
}

@ closure_loop → v {
    : ( Rc Holder ) h ( rc_new [Holder] @ Holder { 7 @ ?( @ i ) { F } } )
    : ( Rc Holder ) cap ( rc_clone [Holder] h )
    : ( @ i ) f \ → i { ^ ( rc_strong [Holder] cap ) }
    ( rc_set [Holder] h @ Holder { 7 @ ?( @ i ) { T f } } )
}

@ bag i k → ( Rc Bag ) {
    ^ ( rc_new [Bag] @ Bag { k ( map_new [i ( Rc Bag )] ) ( deque_new [( Rc Bag )] ) ( btree_new [i ( Rc Bag )] ) @ ?( Box ( Rc Bag ) ) { F } } )
}

@ cmp_i i a i b → i { ^ - a b }

@ containers → v {
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i a i b → b { ^ == a b }
    : ( @ i i i ) ci \ i a i b → i { ^ ( cmp_i a b ) }
    : ( Rc Bag ) a ( bag 1 )
    : ( Rc Bag ) b ( bag 2 )
    : ( Rc Bag ) c ( bag 3 )
    : ( Rc Bag ) e ( bag 4 )
    : Bag na ( rc_get [Bag] a )
    ( map_set [i ( Rc Bag )] . na m 2 ( rc_clone [Bag] b ) hi ei )
    : Bag nb ( rc_get [Bag] b )
    ( deque_push_back [( Rc Bag )] . nb d ( rc_clone [Bag] c ) )
    : Bag nc ( rc_get [Bag] c )
    ( btree_set [i ( Rc Bag )] . nc t 1 ( rc_clone [Bag] e ) ci )
    : Bag ne ( rc_get [Bag] e )
    ( rc_set [Bag] e @ Bag { 4 . ne m . ne d . ne t @ ?( Box ( Rc Bag ) ) { T ( box_new [( Rc Bag )] ( rc_clone [Bag] a ) ) } } )
}

@ into_live ( Rc Node ) keep → v {
    : ( Rc Node ) x ( node 2 )
    : ( Rc Node ) y ( node 3 )
    ( link keep x ) ( link x y ) ( link y x )
    : ( Rc Node ) z ( node 4 )
    ( link z z ) ( link z keep )
}

@ kid_id ( Rc Node ) keep → i {
    : Node nk ( rc_get [Node] keep )
    ^ ?? ( vec_get [( Rc Node )] . nk kids 0 ) { T r → { : Node nx ( rc_get [Node] r ) . nx id } F → 0 }
}

@ many → v {
    : ~ i k 0
    ~ < k 20000 { ( self_loop ) = k + k 1 }
}

@ main → i {
    : i b0 ( live )
    ( self_loop ) ( pair ) ( enum_pair ) ( closure_loop ) ( containers )
    ( rc_collect )
    ( show `garbage-left` - ( live ) b0 )
    // A cycle that points INTO a live structure: the cycle goes, the
    // structure (keep → x ⇄ y) stays, and keep's count is back to 1.
    : ( Rc Node ) keep ( node 1 )
    ( into_live keep )
    ( rc_collect )
    ( show `kid-of-keep` ( kid_id keep ) )
    ( show `keep-strong` ( rc_strong [Node] keep ) )
    // Twenty thousand cycles: collected as they pile up, not at the end.
    : i b1 ( live )
    ( many )
    ( show `bounded` ? < - ( live ) b1 20000 1 0 )
    ^ 0
}
