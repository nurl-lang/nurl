// The thread crossing's run-time check (docs/MEMORY.md §6.5, agora #121):
// a handle whose copies are one state (a PNCounter) crosses to another
// thread only with every owner of that state. One that is the only owner
// crosses — alone, in a struct, a Vec, a Locked, on a channel — and so do
// several owners of one state that all go along (a struct holding two, a
// copy inside a Box beside the original: the walk counts them). One with a
// copy left behind — an explicit share, a struct literal storing one, a
// share in a Vec, a HashMap, a BTree, a Deque, a Set or a Box, a closure's
// capture, a trait object's box — panics at the crossing, naming the
// crossing and the handle.
// (The closures that panic crossing are held in a `Job`, whose drop the
// unwind runs: a closure environment the frame holds directly is not in
// the panic journal yet, agora #131.)
$ `stdlib/core/string.nu`
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/btree.nu`
$ `stdlib/std/deque.nu`
$ `stdlib/std/set.nu`
$ `stdlib/std/panic.nu`

: Holder { PNCounter c }

: Job { ( @ v ) run }

: Twin { PNCounter x PNCounter y }

: Boxed { PNCounter c ( Box PNCounter ) bx }

: Plain { i n }

% Bump [T] : Send { @ bump T self i k → i }

% Bump Holder {
    @ bump Holder h i k → i {
        ( pncounter_inc . h c k 1 )
        ^ k
    }
}

% Bump Plain {
    @ bump Plain p i k → i { ^ + . p n k }
}

@ say s what ! v PanicInfo r → v {
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat what `: crossed` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 what `: ` ( string_data . e msg ) ) ) }
    }
}

@ spawn_join ( @ v ) body → v {
    ?? ( thread_spawn body ) { T t → { ( thread_join t ) } F _ → {} }
}

@ only_owner → v {
    : PNCounter a ( pncounter_new )
    ( spawn_join \ → v { ( pncounter_inc a 1 1 ) } )
}

@ share_kept → v {
    : PNCounter a ( pncounter_new )
    : PNCounter b ( PNCounter_share a )
    : Job j @ Job { \ → v { ( pncounter_inc a 1 1 ) } }
    ( spawn_join . j run )
    ( pncounter_inc b 2 1 )
}

@ in_a_struct → v {
    : Holder h @ Holder { ( pncounter_new ) }
    ( spawn_join \ → v { ( pncounter_inc . h c 1 1 ) } )
}

@ literal_kept → v {
    : Holder h @ Holder { ( pncounter_new ) }
    : Holder h2 @ Holder { . h c }
    : Job j @ Job { \ → v { ( pncounter_inc . h c 1 1 ) } }
    ( spawn_join . j run )
    ( pncounter_inc . h2 c 2 1 )
}

@ both_go_along → v {
    : PNCounter a ( pncounter_new )
    : PNCounter b ( PNCounter_share a )
    : Twin p @ Twin { a b }
    ( spawn_join \ → v { ( pncounter_inc . p x 1 1 ) ( pncounter_inc . p y 2 1 ) } )
}

@ box_copy_goes_along → v {
    : PNCounter a ( pncounter_new )
    : ( Box PNCounter ) bx ( box_new [PNCounter] ( PNCounter_share a ) )
    : Boxed k @ Boxed { a bx }
    : ( Locked Boxed ) l ( locked_new [Boxed] k )
    : Boxed got ( locked_take [Boxed] l )
    ( pncounter_inc . got c 1 1 )
    ( locked_restore [Boxed] l got )
}

@ vec_of_only_owners → v {
    : ( Vec PNCounter ) v ( vec_new [PNCounter] )
    ( vec_push [PNCounter] v ( pncounter_new ) )
    ( vec_push [PNCounter] v ( pncounter_new ) )
    ( spawn_join \ → v { ( pncounter_inc ( vec_at [PNCounter] v 1 ) 1 1 ) } )
}

@ vec_share_kept → v {
    : PNCounter a ( pncounter_new )
    : ( Vec PNCounter ) v ( vec_new [PNCounter] )
    ( vec_push [PNCounter] v ( pncounter_new ) )
    ( vec_push [PNCounter] v ( PNCounter_share a ) )
    : Job j @ Job { \ → v { ( pncounter_inc ( vec_at [PNCounter] v 1 ) 1 1 ) } }
    ( spawn_join . j run )
    ( pncounter_inc a 2 1 )
}

@ map_share_kept → v {
    : PNCounter a ( pncounter_new )
    : ( HashMap i PNCounter ) m ( map_new [i PNCounter] )
    : ?PNCounter _old ( map_set [i PNCounter] m 7 ( PNCounter_share a ) \ i k → i { ^ k } \ i x i y → b { ^ == x y } )
    : Job j @ Job { \ → v { ( nurl_println_int ( map_len [i PNCounter] m ) ) } }
    ( spawn_join . j run )
    ( pncounter_inc a 2 1 )
}

@ btree_share_kept → v {
    : PNCounter a ( pncounter_new )
    : ( BTree i PNCounter ) m ( btree_new [i PNCounter] )
    : ?PNCounter _old ( btree_set [i PNCounter] m 3 ( PNCounter_share a ) \ i x i y → i { ^ - x y } )
    : Job j @ Job { \ → v { ( nurl_println_int ( btree_len [i PNCounter] m ) ) } }
    ( spawn_join . j run )
    ( pncounter_inc a 2 1 )
}

@ deque_share_kept → v {
    : PNCounter a ( pncounter_new )
    : ( Deque PNCounter ) d ( deque_new [PNCounter] )
    ( deque_push_back [PNCounter] d ( PNCounter_share a ) )
    : Job j @ Job { \ → v { ( nurl_println_int ( deque_len [PNCounter] d ) ) } }
    ( spawn_join . j run )
    ( pncounter_inc a 2 1 )
}

@ box_share_kept → v {
    : PNCounter a ( pncounter_new )
    : ( Box PNCounter ) bx ( box_new [PNCounter] ( PNCounter_share a ) )
    : Job j @ Job { \ → v { ( pncounter_inc ( box_get [PNCounter] bx ) 1 1 ) } }
    ( spawn_join . j run )
    ( pncounter_inc a 2 1 )
}

@ set_share_kept → v {
    : PNCounter a ( pncounter_new )
    : ( Set PNCounter ) st ( set_new [PNCounter] )
    : b _in ( set_add [PNCounter] st ( PNCounter_share a ) \ PNCounter x → i { ^ 0 } \ PNCounter x PNCounter y → b { ^ F } )
    : Job j @ Job { \ → v { ( nurl_println_int ( set_len [PNCounter] st ) ) } }
    ( spawn_join . j run )
    ( pncounter_inc a 2 1 )
}

@ closure_in_a_closure → v {
    : PNCounter a ( pncounter_new )
    : PNCounter b ( PNCounter_share a )
    : Job inner @ Job { \ → v { ( pncounter_inc a 1 1 ) } }
    : Job j @ Job { \ → v { : ( @ v ) r . inner run ( r ) } }
    ( spawn_join . j run )
    ( pncounter_inc b 2 1 )
}

@ channel_only_owner → v {
    : ( Channel PNCounter ) ch ( chan_new [PNCounter] )
    : b _sent ( chan_send [PNCounter] ch ( pncounter_new ) )
    ?? ( chan_recv [PNCounter] ch ) { T c → { ( pncounter_inc c 1 1 ) } F → {} }
}

@ channel_share_kept → v {
    : ( Channel PNCounter ) ch ( chan_new [PNCounter] )
    : PNCounter a ( pncounter_new )
    : PNCounter b ( PNCounter_share a )
    : b _sent ( chan_send [PNCounter] ch a )
    ( pncounter_inc b 2 1 )
}

@ locked_only_owner → v {
    : ( Locked PNCounter ) l ( locked_new [PNCounter] ( pncounter_new ) )
    : PNCounter c ( locked_take [PNCounter] l )
    ( pncounter_inc c 1 1 )
    ( locked_restore [PNCounter] l c )
}

@ locked_share_kept → v {
    : PNCounter a ( pncounter_new )
    : PNCounter b ( PNCounter_share a )
    : ( Locked PNCounter ) l ( locked_new [PNCounter] a )
    ( pncounter_inc b 2 1 )
}

@ locked_restore_share_kept → v {
    : ( Locked PNCounter ) l ( locked_new [PNCounter] ( pncounter_new ) )
    : PNCounter c ( locked_take [PNCounter] l )
    : PNCounter d ( PNCounter_share c )
    ( locked_restore [PNCounter] l c )
    ( pncounter_inc d 2 1 )
}

@ locked_get_copies → v {
    : ( Locked PNCounter ) l ( locked_new [PNCounter] ( pncounter_new ) )
    : PNCounter c ( locked_get [PNCounter] l )
    ( pncounter_inc c 2 1 )
}

@ dyn_only_owner → v {
    : %Bump d ( dyn Bump @ Holder { ( pncounter_new ) } )
    : %Bump e ( dyn Bump @ Plain { 3 } )
    ( spawn_join \ → v { : i _r ( bump d 1 ) : i _s ( bump e 1 ) } )
}

@ dyn_share_kept → v {
    : PNCounter a ( pncounter_new )
    : PNCounter b ( PNCounter_share a )
    : %Bump d ( dyn Bump @ Holder { a } )
    : Job j @ Job { \ → v { : i _r ( bump d 1 ) } }
    ( spawn_join . j run )
    ( pncounter_inc b 2 1 )
}

@ main → i {
    ( say `only owner` ( recover \ → v { ( only_owner ) } ) )
    ( say `share kept` ( recover \ → v { ( share_kept ) } ) )
    ( say `in a struct` ( recover \ → v { ( in_a_struct ) } ) )
    ( say `literal kept` ( recover \ → v { ( literal_kept ) } ) )
    ( say `both go along` ( recover \ → v { ( both_go_along ) } ) )
    ( say `box copy goes along` ( recover \ → v { ( box_copy_goes_along ) } ) )
    ( say `vec of only owners` ( recover \ → v { ( vec_of_only_owners ) } ) )
    ( say `vec share kept` ( recover \ → v { ( vec_share_kept ) } ) )
    ( say `map share kept` ( recover \ → v { ( map_share_kept ) } ) )
    ( say `btree share kept` ( recover \ → v { ( btree_share_kept ) } ) )
    ( say `deque share kept` ( recover \ → v { ( deque_share_kept ) } ) )
    ( say `box share kept` ( recover \ → v { ( box_share_kept ) } ) )
    ( say `set share kept` ( recover \ → v { ( set_share_kept ) } ) )
    ( say `closure in a closure` ( recover \ → v { ( closure_in_a_closure ) } ) )
    ( say `channel only owner` ( recover \ → v { ( channel_only_owner ) } ) )
    ( say `channel share kept` ( recover \ → v { ( channel_share_kept ) } ) )
    ( say `locked only owner` ( recover \ → v { ( locked_only_owner ) } ) )
    ( say `locked share kept` ( recover \ → v { ( locked_share_kept ) } ) )
    ( say `locked restore share kept` ( recover \ → v { ( locked_restore_share_kept ) } ) )
    ( say `locked get` ( recover \ → v { ( locked_get_copies ) } ) )
    ( say `dyn only owner` ( recover \ → v { ( dyn_only_owner ) } ) )
    ( say `dyn share kept` ( recover \ → v { ( dyn_share_kept ) } ) )
    ^ 0
}
