// box_basic.nu — Box[T] round-trip, mutation, replace, clone, into,
// raw-pointer borrow. Covers the integer payload — the simplest case
// where the read-by-value path is safe.

$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`

@ main → i {
    // box_new + box_get round-trip.
    : ( Box i ) b1 ( box_new [i] 42 )
    ( nurl_print `b1 get=` ) ( nurl_print ( nurl_str_int ( box_get [i] b1 ) ) )
    ( nurl_print `\n` )

    // box_set rewrites the slot; box_get sees the new value.
    ( box_set [i] b1 100 )
    ( nurl_print `b1 after set=` ) ( nurl_print ( nurl_str_int ( box_get [i] b1 ) ) )
    ( nurl_print `\n` )

    // box_replace returns the old, stores the new.
    : i old ( box_replace [i] b1 7 )
    ( nurl_print `b1 replace old=` ) ( nurl_print ( nurl_str_int old ) )
    ( nurl_print ` new=` ) ( nurl_print ( nurl_str_int ( box_get [i] b1 ) ) )
    ( nurl_print `\n` )

    // box_ptr returns a borrowed *i; writing through it must show up
    // in box_get.
    : *i p ( box_ptr [i] b1 )
    = . p 0 999
    ( nurl_print `b1 via ptr=` ) ( nurl_print ( nurl_str_int ( box_get [i] b1 ) ) )
    ( nurl_print `\n` )

    // box_clone copies the value into a fresh allocation.
    : ( Box i ) b2 ( box_clone [i] b1 )
    ( nurl_print `b2 clone=` ) ( nurl_print ( nurl_str_int ( box_get [i] b2 ) ) )
    ( nurl_print `\n` )

    // Mutating b1 does NOT affect b2 (they are independent allocs).
    ( box_set [i] b1 -1 )
    ( nurl_print `b1=` ) ( nurl_print ( nurl_str_int ( box_get [i] b1 ) ) )
    ( nurl_print ` b2=` ) ( nurl_print ( nurl_str_int ( box_get [i] b2 ) ) )
    ( nurl_print `\n` )

    // box_zero: count starts at the zero value.
    : ( Box i ) b3 ( box_zero [i] )
    ( nurl_print `b3 zero=` ) ( nurl_print ( nurl_str_int ( box_get [i] b3 ) ) )
    ( nurl_print `\n` )

    // box_into consumes b2, returns its value.
    : i taken ( box_into [i] b2 )
    ( nurl_print `b2 into=` ) ( nurl_print ( nurl_str_int taken ) )
    ( nurl_print `\n` )

    // Cleanup.
    ( box_free [i] b1 )
    ( box_free [i] b3 )
    ( nurl_print `done\n` )
    ^ 0
}
