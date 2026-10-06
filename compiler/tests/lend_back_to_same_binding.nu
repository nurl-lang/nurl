// lend_back_to_same_binding.nu — a value that comes back to the binding it
// came from stays owned by it, and a field taken out of a table's slot goes
// to the caller.
//
// `= c ( prune c )`, prune handing back a cursor over its parameter: the
// call lends, and a lent value assigned to a binding made the binding a
// borrower — of its own value, which then had no owner at all (h2's
// `_h2_prune_closed`). The same assignment through a function that hands
// its parameter back as is already worked.
//
// `take_body` reads a slot by value, takes its body, puts a fresh one in
// and writes the slot back (http2_client's take_data): the body it returns
// is the caller's. Treated as a lend of the slot copy, it leaked.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Conn { ( Vec i ) xs String name }

@ mk → Conn { ^ @ Conn { ( vec_new [i] ) ( string_from `conn` ) } }

@ prune Conn c → Conn {
    : ~ Conn cur c
    : b _sl ( vec_set_len [i] . cur xs 1 )
    ^ cur
}

@ prune_round → i {
    : ~ Conn c ( mk )
    ( vec_push [i] . c xs 1 ) ( vec_push [i] . c xs 2 )
    = c ( prune c )
    ^ ( vec_len [i] . c xs )
}

: Slot { i id ( Vec u ) body }

unsafe @ get_slot ( Vec Slot ) t i k → Slot {
    : *Slot sp ( vec_data [Slot] t )
    ^ . sp k
}

unsafe @ put_slot ( Vec Slot ) t i k Slot s → v {
    : *Slot sp ( vec_data [Slot] t )
    ( mem_put_back s )
    = . sp k s
}

@ take_body ( Vec Slot ) t i k → !( Vec u ) i {
    ? >= k ( vec_len [Slot] t ) { ^ @ !( Vec u ) i { F 1 } } {}
    : Slot s ( get_slot t k )
    : ( Vec u ) out . s body
    = . s body ( vec_new [u] )
    ( put_slot t k s )
    ^ @ !( Vec u ) i { T out }
}

@ take_round → i {
    : ( Vec Slot ) t ( vec_new [Slot] )
    : ( Vec u ) b ( vec_new [u] ) ( vec_push [u] b # u 7 ) ( vec_push [u] b # u 8 )
    ( vec_push [Slot] t @ Slot { 1 b } )
    : ~ i got 0
    ?? ( take_body t 0 ) { T bytes → { = got ( vec_len [u] bytes ) } F _ → {} }
    ^ got
}

@ main → i {
    : i a ( prune_round )
    : i b ( take_round )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 20 { : i x ( prune_round ) : i y ( take_round ) = k + k 1 }
    ( nurl_println ( nurl_str_cat `pruned to ` ( nurl_str_int a ) ) )
    ( nurl_println ( nurl_str_cat `took ` ( nurl_str_int b ) ) )
    ( nurl_println ? == l0 ( live ) `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - ( live ) l0 ) ) )
    ^ 0
}
