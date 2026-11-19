// map: §2.10 | A2 | rejected | - | AGORA-479: a closure body hands a sink a payload read through `vec_get` of its Vec capture, called twice
// AGORA-479 (this shape, closed): refused - a closure body may not hand a sink a copy or a part of its capture, which the environment still releases (main b215deb5: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ( Vec ? String ) v ( vec_new [? String] )
    ( vec_push [? String] v @ ?String { T ( string_from `an element payload long enough for the heap buffer, surely` ) } )
    : ( @ i ) c \ → i { ?? ( vec_get [? String] v 0 ) { T e → { ?? e { T s → { ^ ( eat s ) } F → { ^ 1 } } } F → { ^ 0 } } }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
