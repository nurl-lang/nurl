// map: §2.10 | A2 | rejected | - | AGORA-479: a closure body hands a sink a payload read through its Vec capture's element, called twice
// AGORA-479 (this shape): refused on main 4db4cf5b by both nurlc and tools/ncore - closed by earlier work (AGORA-842's payload-cursor owners, AGORA-580, AGORA-428's copies); moved out of the open probes
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ( Vec ? String ) v ( vec_new [? String] )
    ( vec_push [? String] v @ ?String { T ( string_from `an element payload long enough for the heap buffer, surely` ) } )
    : ( @ i ) c \ → i { ?? ( vec_at [? String] v 0 ) { T s → { ^ ( eat s ) } F → { ^ 0 } } }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
