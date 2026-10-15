// arc_get lends an Arc's payload even when the payload has a `% Drop` of
// its own and no clone: the copying branch is for a payload that can reach
// its own Arc, and an instance whose payload cannot leaves it dead.
$ `stdlib/core/string.nu`
$ `stdlib/std/arc.nu`

: Res { String name i fd }

% Drop Res { @ drop Res r → v { ( nurl_println `released` ) } }

: H { ( Arc Res ) a }

@ H_share H h → H { ^ @ H { ( arc_clone [Res] . h a ) } }

@ H_drop sink H h → v {}

@ h_name H h → s { ^ ( string_data . ( arc_get [Res] . h a ) name ) }

@ main → i {
    : H h @ H { ( arc_new [Res] @ Res { ( string_from `the resource` ) 3 } ) }
    : H h2 ( H_share h )
    ( nurl_println ( h_name h2 ) )
    ( nurl_println_int . ( arc_get [Res] . h a ) fd )
    ^ 0
}
