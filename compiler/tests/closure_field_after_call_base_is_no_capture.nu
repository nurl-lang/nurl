// agora #710: in a closure body, the name after a parenthesised base —
// `. ( arc_get [P] a ) r` — is a field of the struct the call hands back,
// not a capture of an outer binding `r`. Taken for one, an outer Rc named
// like the field made the closure "not Send", and an outer Vec named like
// it was moved into the closure. Over a call that hands back a POINTER,
// `. ( p ) k` indexes by the value `k`, which is still captured.
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: P { i r }
: Q { i v }
: W [T] { T r i k }
: XY { i x i y }

@ mk i k → XY { ^ @ XY { k + k 1 } }

// The outer name is a parameter of the enclosing function.
@ spawn_reader ( Rc i ) r ( Arc P ) a → i {
    ?? ( thread_spawn \ → v { : i n . ( arc_get [P] a ) r } ) { T t → { ( thread_join t ) } F _ → {} }
    ^ ( rc_strong [i] r )
}

unsafe @ at * i p → *i { ^ p }

unsafe @ main → i {
    // An outer Rc named like the field: the thread's closure reaches no Rc.
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Arc P ) a ( arc_new [P] @ P { 3 } )
    ?? ( thread_spawn \ → v { : i n . ( arc_get [P] a ) r } ) { T t → { ( thread_join t ) } F _ → {} }
    ( nurl_println ( nurl_str_int ( rc_strong [i] r ) ) )
    ( nurl_println ( nurl_str_int ( spawn_reader r a ) ) )
    // An outer Vec named like the field is not moved into the closure.
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 4 )
    : ( Arc Q ) b ( arc_new [Q] @ Q { 7 } )
    ?? ( thread_spawn \ → v { : i n . ( arc_get [Q] b ) v } ) { T t → { ( thread_join t ) } F _ → {} }
    ( nurl_println ( nurl_str_int ( vec_len [i] v ) ) )
    // A generic instance as the struct.
    : ( Arc ( W i ) ) c ( arc_new [( W i )] @ ( W i ) { 3 4 } )
    ?? ( thread_spawn \ → v { : i n . ( arc_get [( W i )] c ) r } ) { T t → { ( thread_join t ) } F _ → {} }
    ( nurl_println ( nurl_str_int ( rc_strong [i] r ) ) )
    // A plain closure: the field `y`, then the captured binding `y`.
    : i y 40
    : ( @ i i ) f \ i k → i { ^ + . ( mk k ) y y }
    ( nurl_println ( nurl_str_int ( f 1 ) ) )
    // A pointer result is indexed by the value `k`: captured.
    : *i arr # *i ( nurl_alloc * 4 Z i )
    ( nurl_poke arr 0 10 ) ( nurl_poke arr 1 11 ) ( nurl_poke arr 2 12 )
    : i k 2
    : ( @ i i ) g \ i j → i { ^ + j . ( at arr ) k }
    ( nurl_println ( nurl_str_int ( g 30 ) ) )
    ( nurl_free # s arr )
    ^ 0
}
