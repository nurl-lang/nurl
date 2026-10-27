// arc_weak_frozen.nu — Arc's cycles are ruled out, not collected
// (docs/MEMORY.md §7.7). An Arc whose payload can hold a handle back to it
// is frozen like any other — what arc_get lends no call may change, so
// nothing closes a cycle through it; a reader that wants a changed value
// copies it — and a tree is built from its leaves up.
// ArcWeak points back without owning.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ show s label i n → v { ( nurl_print label ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` ) }

: TNode { i id ( Vec ( Arc TNode ) ) kids }

@ tree → i {
    : ( Arc TNode ) leaf ( arc_new [TNode] @ TNode { 2 ( vec_new [( Arc TNode )] ) } )
    : ( Vec ( Arc TNode ) ) ks ( vec_new [( Arc TNode )] )
    ( vec_push [( Arc TNode )] ks ( arc_clone [TNode] leaf ) )
    : ( Arc TNode ) root ( arc_new [TNode] @ TNode { 1 ks } )
    : TNode r ( mem_dup ( arc_get [TNode] root ) )
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

// A payload of plain values is lent, read-only — every Arc's payload is
// frozen once made (docs/MEMORY.md §6.5); state that changes is a Locked.
@ plain → i {
    : ( Vec i ) d ( vec_new [i] )
    ( vec_push [i] d 7 )
    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )
    : ( Locked ( Vec i ) ) l ( locked_new [( Vec i )] ( vec_new [i] ) )
    ( locked_with [( Vec i )] l \ ( Vec i ) v → v { ( vec_push [i] v 8 ) } )
    ^ ( vec_len [i] ( locked_get [( Vec i )] l ) )
}

@ main → i {
    : i b0 ( live )
    ( show `tree` ( tree ) )
    ( show `weak` ( weak ) )
    ( show `plain-shared` ( plain ) )
    ( show `left` - ( live ) b0 )
    ^ 0
}
