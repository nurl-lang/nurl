// Destructor corners: a disposer — the `sink` function a `% Drop` impl
// hands its receiver to — releases the impl's fields by its drop glue,
// whether the value reached it from the impl or straight from its owner;
// a field the impl replaces releases what it held; a closure defined in
// an impl is its own function; and an impl that panics is not run again
// by the unwind, which still releases its receiver's fields.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Res { String name i id }

@ res_close sink Res r → v { ( nurl_print `close ` ) ( nurl_println ( string_data . r name ) ) }

% Drop Res { @ drop sink Res r → v {
        ( nurl_print `impl ` ) ( nurl_println ( string_data . r name ) )
        : ( @ v i ) f \ i k → v { ( nurl_print `closure ` ) ( nurl_print_int k ) ( nurl_println `` ) }
        ( f . r id )
        ( res_close r )
    } }

: Note { String text i n }

% Drop Note { @ drop sink Note h → v {
        = . h text ( string_from `replaced` )
        ( nurl_print `note ` ) ( nurl_println ( string_data . h text ) )
        ? == . h n 1 { ( panic `in hook` ) } {}
    } }

@ boom → v { : Note x @ Note { ( string_from `orig` ) 1 } }

@ main → i {
    : Res a @ Res { ( string_from `a-scope-exit` ) 1 }
    : Res b @ Res { ( string_from `b-direct` ) 2 }
    ( res_close b )
    : Note n @ Note { ( string_from `quiet` ) 0 }
    : !v PanicInfo pr ( recover \ → v { ( boom ) } )
    ?? pr { T _ → { ( nurl_println `no panic` ) } F p → { ( nurl_print `recovered: ` ) ( nurl_println ( string_data . p msg ) ) } }
    ( nurl_println `end` )
    ^ 0
}
