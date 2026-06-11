// rc_basic.nu — Rc[T] shared-ownership semantics.

$ `stdlib/std/rc.nu`

@ main → i {
    // rc_new starts the count at 1.
    : ( Rc i ) r ( rc_new [i] 1000 )
    ( nurl_print `count=` ) ( nurl_print ( nurl_str_int ( rc_strong [i] r ) ) )
    ( nurl_print ` value=` ) ( nurl_print ( nurl_str_int ( rc_get [i] r ) ) )
    ( nurl_print ` unique=` ) ( nurl_print ? ( rc_is_unique [i] r ) `T` `F` )
    ( nurl_print `\n` )

    // rc_clone shares the storage and bumps the count.
    : ( Rc i ) r2 ( rc_clone [i] r )
    : ( Rc i ) r3 ( rc_clone [i] r )
    ( nurl_print `after 2 clones count=` ) ( nurl_print ( nurl_str_int ( rc_strong [i] r ) ) )
    ( nurl_print ` unique=` ) ( nurl_print ? ( rc_is_unique [i] r ) `T` `F` )
    ( nurl_print `\n` )

    // Mutating via one handle is observable through the others —
    // all three point at the same storage.
    ( rc_set [i] r2 4242 )
    ( nurl_print `r=` ) ( nurl_print ( nurl_str_int ( rc_get [i] r ) ) )
    ( nurl_print ` r2=` ) ( nurl_print ( nurl_str_int ( rc_get [i] r2 ) ) )
    ( nurl_print ` r3=` ) ( nurl_print ( nurl_str_int ( rc_get [i] r3 ) ) )
    ( nurl_print `\n` )

    // rc_ptr returns a borrowed *i that aliases the value field.
    : *i p ( rc_ptr [i] r )
    = . p 0 - 0 1
    ( nurl_print `via ptr r=` ) ( nurl_print ( nurl_str_int ( rc_get [i] r ) ) )
    ( nurl_print ` r2=` ) ( nurl_print ( nurl_str_int ( rc_get [i] r2 ) ) )
    ( nurl_print `\n` )

    // rc_replace returns the old value.
    : i old ( rc_replace [i] r3 7 )
    ( nurl_print `replace old=` ) ( nurl_print ( nurl_str_int old ) )
    ( nurl_print ` new=` ) ( nurl_print ( nurl_str_int ( rc_get [i] r ) ) )
    ( nurl_print `\n` )

    // Drop two clones, the storage stays alive (count > 0).
    ( rc_free [i] r2 )
    ( rc_free [i] r3 )
    ( nurl_print `after 2 frees count=` ) ( nurl_print ( nurl_str_int ( rc_strong [i] r ) ) )
    ( nurl_print ` value=` ) ( nurl_print ( nurl_str_int ( rc_get [i] r ) ) )
    ( nurl_print `\n` )

    // Last free releases the allocation.
    ( rc_free [i] r )
    ( nurl_print `done\n` )
    ^ 0
}
