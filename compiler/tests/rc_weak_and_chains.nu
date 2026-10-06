// rc_weak_and_chains.nu — Weak handles, and a long chain of Rc released
// without recursion (docs/MEMORY.md §7.7).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`
$ `stdlib/std/btree.nu`
$ `stdlib/std/rc.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ show s label i n → v { ( nurl_print label ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` ) }

: Node { i id ? ( Weak Node ) parent ( Vec ( Rc Node ) ) kids }
: Chain { i id ? ( Rc Chain ) next }

@ tree → i {
    : ( Rc Node ) root ( rc_new [Node] @ Node { 1 @ ?( Weak Node ) { F } ( vec_new [( Rc Node )] ) } )
    : ( Rc Node ) kid ( rc_new [Node] @ Node { 2 @ ?( Weak Node ) { T ( rc_downgrade [Node] root ) } ( vec_new [( Rc Node )] ) } )
    : Node nr ( rc_get [Node] root )
    ( vec_push [( Rc Node )] . nr kids ( rc_clone [Node] kid ) )
    : Node nk ( rc_get [Node] kid )
    ^ ?? . nk parent { T w → ?? ( weak_upgrade [Node] w ) { T p → { : Node np ( rc_get [Node] p ) . np id } F → -1 } F → -2 }
}

@ dangling → i {
    : ~ ? ( Weak Node ) w @ ?( Weak Node ) { F }
    {
        : ( Rc Node ) gone ( rc_new [Node] @ Node { 9 @ ?( Weak Node ) { F } ( vec_new [( Rc Node )] ) } )
        = w @ ?( Weak Node ) { T ( rc_downgrade [Node] gone ) }
        ( rc_free [Node] gone )
    }
    ^ ?? w { T x → ?? ( weak_upgrade [Node] x ) { T p → 1 F → 0 } F → -1 }
}

@ chain i n → i {
    : ( Rc Chain ) head ( rc_new [Chain] @ Chain { 0 @ ?( Rc Chain ) { F } } )
    : ~ ( Rc Chain ) cur ( rc_clone [Chain] head )
    : ~ i k 1
    ~ < k n {
        : ( Rc Chain ) nn ( rc_new [Chain] @ Chain { k @ ?( Rc Chain ) { F } } )
        ( rc_set [Chain] cur @ Chain { - k 1 @ ?( Rc Chain ) { T ( rc_clone [Chain] nn ) } } )
        = cur nn
        = k + k 1
    }
    ^ n
}

@ main → i {
    : i b0 ( live )
    ( show `parent-via-weak` ( tree ) )
    ( show `upgrade-after-free` ( dangling ) )
    ( show `chain` ( chain 300000 ) )
    ( show `left` - ( live ) b0 )
    ^ 0
}
