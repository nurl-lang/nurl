// enum_libh_payload.nu — an enum payload that is a one-pointer library
// handle (Rc, Box) is stored in the slot itself, and dropped and copied that
// way: dropping it used to treat the handle as a box and free the handle's
// own block.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ show s label i n → v { ( nurl_print label ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` ) }

: | Held { Shared ( Rc String ) Owned ( Box String ) Nothing }

@ work → i {
    : ( Rc String ) shared ( rc_new [String] ( string_from `x` ) )
    : Held h1 @ Held { Shared ( rc_clone [String] shared ) }
    : Held h2 @ Held { Owned ( box_new [String] ( string_from `boxed` ) ) }
    : Held h3 @ Held { Nothing }
    ^ ( rc_strong [String] shared )
}

@ main → i {
    : i b0 ( live )
    ( show `strong-while-held` ( work ) )
    ( show `left` - ( live ) b0 )
    ^ 0
}
