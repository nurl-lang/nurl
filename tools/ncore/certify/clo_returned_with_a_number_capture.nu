// A function hands back a closure over its number parameter, copied into the environment; the caller binds it and calls it.
@ mk_add i c → ( @ i i ) { ^ \ i x → i { ^ + x c } }

@ main → i {
    : ( @ i i ) f ( mk_add 3 )
    ( nurl_println_int ( f 1 ) )
    ( nurl_println_int ( f 2 ) )
    ^ 0
}
