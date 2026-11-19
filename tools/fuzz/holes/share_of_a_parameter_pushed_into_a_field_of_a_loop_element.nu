// map: §2.10 | A2 | rejected | - | AGORA-793: a share of a parameter pushed into `. x hs` of a `~` loop element `x`, then replaced through the owner
// AGORA-793 (this shape): refused on main 4db4cf5b by both nurlc and tools/ncore - closed by earlier work; moved out of the open probes
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

: P { ( Vec ( Rc ( Vec u ) ) ) hs }

@ ch ( Rc ( Vec u ) ) h → v {
    : ( Vec P ) ps ( vec_new [P] )
    ( vec_push [P] ps @ P { ( vec_new [( Rc ( Vec u ) )] ) } )
    ~ x ps { ( vec_push [( Rc ( Vec u ) )] . x hs ( rc_clone [( Vec u )] h ) ) }
    ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] . ( vec_at [P] ps 0 ) hs 0 ) ( vec_new [u] ) )
}

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
