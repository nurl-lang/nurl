// elems_changed_value_borrows.nu — agora #118. When only the elements
// behind a handle change (a push, a clear through a borrow of it), a
// borrow whose bytes are not among those elements still reads what it did:
// its handles stay where they are. Each of these was refused before
// ("'b' borrows from 'g', which ended …"):
//   * the value a write guard lends, beside a field viewer of its buffer
//     that the pushes go through (packages/nurldb's log append);
//   * a copy of an owner that an identity call hands back, beside another
//     such copy the clear goes through;
//   * a whole struct copy, beside a field viewer of the same owner.
// What was read out of the elements still ends with them:
// borrow_element_viewer_after_clear.nu, and the hole probes
// tools/fuzz/holes/field_viewer_of_an_element_after_clear*.nu.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rwlock.nu`

: LogBuf { ( Vec u ) buf i start }
: N { ( Vec N ) kids i v }

@ guard_value_beside_its_buffer → i {
    : ( RwLocked LogBuf ) l ( rw_new [LogBuf] @ LogBuf { ( vec_new [u] ) 7 } )
    : ( WGuard LogBuf ) g ( rw_write [LogBuf] l )
    : LogBuf b ( wguard_get [LogBuf] g )
    : ( Vec u ) buf . b buf
    ( vec_push_word_u8 buf 4 4 F )
    ( vec_clear [u] buf )
    ( vec_push_word_u8 buf 9 4 F )
    ^ + * 100 . b start ( vec_len [u] . b buf )
}

@ id ( Vec String ) x → ( Vec String ) { ^ x }

@ identity_copies → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element long enough for the heap` ) )
    : ( Vec String ) h ( id vs )
    : ( Vec String ) w ( id vs )
    ( vec_clear [String] w )
    ( vec_push [String] w ( string_from `x` ) )
    ^ ( vec_len [String] h )
}

@ idn N x → N { ^ x }

@ whole_copy_beside_a_field_viewer → i {
    : ( Vec N ) ks ( vec_new [N] )
    ( vec_push [N] ks @ N { ( vec_new [N] ) 1 } )
    : N o @ N { ks 2 }
    : N x ( idn o )
    : ( Vec N ) kk . o kids
    ( vec_clear [N] kk )
    ^ + * 10 . x v ( vec_len [N] . x kids )
}

@ main → i {
    ( nurl_println_int ( guard_value_beside_its_buffer ) )
    ( nurl_println_int ( identity_copies ) )
    ( nurl_println_int ( whole_copy_beside_a_field_viewer ) )
    ^ 0
}
