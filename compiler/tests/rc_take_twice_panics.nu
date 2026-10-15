// An Rc's value checked out (rc_take) and not restored: every other use
// of it, through any handle, panics instead of reading a value that is
// not there; restoring a value that was not taken panics too.
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/panic.nu`

: P { String name i n }

@ main → i {
    : ( Rc P ) r ( rc_new [P] @ P { ( string_from `a name long enough to own a heap buffer` ) 1 } )
    : ( Rc P ) r2 ( rc_clone [P] r )
    : ~ P p ( rc_take [P] r )
    ( nurl_println ( string_data . p name ) )
    : !v PanicInfo t2 ( recover \ → v { : P q ( rc_take [P] r2 ) ( nurl_println_int . q n ) } )
    ?? t2 { T _ → { ( nurl_println `no panic` ) } F e → { ( nurl_println ( string_data . e msg ) ) } }
    : !v PanicInfo g ( recover \ → v { ( nurl_println_int . ( rc_get [P] r2 ) n ) } )
    ?? g { T _ → { ( nurl_println `no panic` ) } F e → { ( nurl_println ( string_data . e msg ) ) } }
    ( rc_restore [P] r p )
    ( nurl_println_int . ( rc_get [P] r2 ) n )
    : !v PanicInfo d ( recover \ → v { ( rc_restore [P] r2 @ P { ( string_from `x` ) 2 } ) } )
    ?? d { T _ → { ( nurl_println `no panic` ) } F e → { ( nurl_println ( string_data . e msg ) ) } }
    ^ 0
}
