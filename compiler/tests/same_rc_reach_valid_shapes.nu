// What the same-Rc rule keeps (agora #712): a loop over a Vec of shares
// that clears each payload (the loop reads the Vec's own buffer), a share
// pushed into a Vec of shares beside a view through another share (the
// Vec's own buffer moves, no payload), a payload holding shares cleared by
// a helper and reused (a borrow's Rcs are its source's), a view of a
// struct's inline field kept past clearing another struct's shared
// payload, and a view through one Rc type kept past a wipe of a struct
// holding another, and a Vec of shares cleared or an element of it replaced
// beside a view through another share (a handle going, which the view's own
// handle outlives).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Ctx { ( Rc ( Vec String ) ) log String name }
: Box2 { ( Rc ( Vec String ) ) log i n }

@ wipe_rc ( Rc ( Vec i ) ) r → v { ( vec_clear [i] ( rc_get [( Vec i )] r ) ) }

@ wipe_ctx Ctx c → v { ( vec_clear [String] ( rc_get [( Vec String )] . c log ) ) }

@ wipe_box Box2 c → v { ( vec_clear [String] ( rc_get [( Vec String )] . c log ) ) }

@ wipe_shares ( Vec ( Rc String ) ) p → v { ( vec_clear [( Rc String )] p ) }

@ loop_clears → i {
    : ( Vec ( Rc ( Vec i ) ) ) hs ( vec_new [( Rc ( Vec i ) )] )
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 1 )
    ( vec_push [( Rc ( Vec i ) )] hs ( rc_new [( Vec i )] a ) )
    ~ h hs { ( wipe_rc h ) }
    ^ ( vec_len [( Rc ( Vec i ) )] hs )
}

@ push_beside_view → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( vec_push [( Rc ( Vec u ) )] hs r )
    ( vec_reserve [( Rc ( Vec u ) )] hs 64 )
    ^ # i ( slice_at [u] sl 0 )
}

@ shares_cleared_and_reused → i {
    : ( Vec ( Rc String ) ) v ( vec_new [( Rc String )] )
    ( vec_push [( Rc String )] v ( rc_new [String] ( string_from `an element string long enough for a heap buffer` ) ) )
    : ( Rc ( Vec ( Rc String ) ) ) r ( rc_new [( Vec ( Rc String ) )] v )
    : ( Vec ( Rc String ) ) p ( rc_get [( Vec ( Rc String ) )] r )
    ( wipe_shares p )
    ( vec_push [( Rc String )] p ( rc_new [String] ( string_from `another element string long enough for a heap buffer` ) ) )
    ^ ( vec_len [( Rc String )] p )
}

@ inline_field_kept → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v )
    : Ctx ctx @ Ctx { ( rc_clone [( Vec String )] r ) ( string_from `a name long enough to live on the heap` ) }
    : Ctx other @ Ctx { r ( string_from `another name long enough to live on the heap` ) }
    : ( Slice u ) nm ( string_bytes . ctx name )
    ( wipe_ctx other )
    ^ # i ( slice_at [u] nm 0 )
}

@ other_rc_type_kept → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : Box2 c @ Box2 { ( rc_new [( Vec String )] v ) 1 }
    : ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] w )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( wipe_box c )
    ^ # i ( slice_at [u] sl 0 )
}

@ shares_dropped_beside_view → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs r )
    ( vec_push [( Rc ( Vec u ) )] hs ( rc_clone [( Vec u )] r2 ) )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( vec_put [( Rc ( Vec u ) )] hs 0 ( rc_new [( Vec u )] ( vec_new [u] ) ) )
    ( vec_clear [( Rc ( Vec u ) )] hs )
    ^ # i ( slice_at [u] sl 0 )
}

@ main → i {
    ( nurl_println_int ( loop_clears ) )
    ( nurl_println_int ( push_beside_view ) )
    ( nurl_println_int ( shares_cleared_and_reused ) )
    ( nurl_println_int ( inline_field_kept ) )
    ( nurl_println_int ( other_rc_type_kept ) )
    ( nurl_println_int ( shares_dropped_beside_view ) )
    ^ 0
}
