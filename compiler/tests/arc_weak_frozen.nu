// arc_weak_frozen.nu — Arc's cycles are ruled out, not collected
// (docs/MEMORY.md §7.7). An Arc whose payload can hold a handle back to it
// is frozen once made: arc_get hands out a copy, so nothing done to the
// copy reaches the shared value, and a tree is built from its leaves up.
// ArcWeak points back without owning.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ show s label i n → v { ( nurl_print label ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` ) }

: TNode { i id ( Vec ( Arc TNode ) ) kids }

@ tree → i {
    : ( Arc TNode ) leaf ( arc_new [TNode] @ TNode { 2 ( vec_new [( Arc TNode )] ) } )
    : ( Vec ( Arc TNode ) ) ks ( vec_new [( Arc TNode )] )
    ( vec_push [( Arc TNode )] ks ( arc_clone [TNode] leaf ) )
    : ( Arc TNode ) root ( arc_new [TNode] @ TNode { 1 ks } )
    : TNode r ( arc_get [TNode] root )
    // The copy takes the push; the shared root keeps its one child.
    ( vec_push [( Arc TNode )] . r kids ( arc_clone [TNode] root ) )
    : TNode r2 ( arc_get [TNode] root )
    ^ + * 10 ( vec_len [( Arc TNode )] . r kids ) ( vec_len [( Arc TNode )] . r2 kids )
}

@ weak → i {
    : ( Arc String ) a ( arc_new [String] ( string_from `shared` ) )
    : ( ArcWeak String ) w ( arc_downgrade [String] a )
    : i up1 ?? ( arc_weak_upgrade [String] w ) { T s → ( arc_strong [String] s ) F → -1 }
    ( arc_free [String] a )
    : i up2 ?? ( arc_weak_upgrade [String] w ) { T s → 1 F → 0 }
    ^ + * up1 10 up2
}

// A payload of plain values is shared as before: arc_get lends it.
@ plain → i {
    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] ( vec_new [i] ) )
    : ( Vec i ) v ( arc_get [( Vec i )] a )
    ( vec_push [i] v 7 )
    : ( Vec i ) v2 ( arc_get [( Vec i )] a )
    ^ ( vec_len [i] v2 )
}

@ main → i {
    : i b0 ( live )
    ( show `tree` ( tree ) )
    ( show `weak` ( weak ) )
    ( show `plain-shared` ( plain ) )
    ( show `left` - ( live ) b0 )
    ^ 0
}
