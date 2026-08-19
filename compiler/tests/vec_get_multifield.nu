// vec_get / ! T E with MULTI-FIELD payloads — the shapes the HTTP
// stdlib modules worked around by pointer iteration until 2026-05-14,
// when the multi-field Option Some-arm boxing fix shipped. This test
// pins the fix: a Vec element type with several fields (owned Strings,
// a Vec, a closure) must survive the vec_get copy + ?? unwrap, and a
// multi-field struct must ride an ! T E Ok arm. The out-of-range arm
// exercises the None default-construction path the old workaround
// comments blamed.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: MPart {
    String name
    String filename
    String content_type
    ( Vec u ) data
}

: CRoute { String method String pattern ( @ i i ) handler }

: Wide { String a String b i c }

@ mk_part s nm i nbytes → MPart {
    : ( Vec u ) d ( vec_new [u] )
    : ~ i k 0
    ~ < k nbytes { ( vec_push [u] d # u + 65 k ) = k + k 1 }
    ^ @ MPart { ( string_from nm ) ( string_from `f.txt` ) ( string_from `text/plain` ) d }
}

@ free_part MPart p → v {
    ( string_free . p name ) ( string_free . p filename )
    ( string_free . p content_type ) ( vec_free [u] . p data )
}

@ mk_wide s x → !Wide s {
    ^ @ !Wide s { T @ Wide { ( string_from x ) ( string_from `bee` ) 7 } }
}

@ main → i {
    : ( Vec MPart ) v ( vec_new [MPart] )
    ( vec_push [MPart] v ( mk_part `alpha` 4 ) )
    ( vec_push [MPart] v ( mk_part `beta` 2 ) )
    : ?MPart g ( vec_get [MPart] v 1 )
    ?? g { T p → ( printf `owned: %s len=%d\n` ( string_data . p name ) ( vec_len [u] . p data ) ) F _ → ( puts `miss` ) }
    : ?MPart g9 ( vec_get [MPart] v 9 )
    ?? g9 { T _ → ( puts `BUG oob hit` ) F _ → ( puts `owned oob: None` ) }
    ( vec_free_with [MPart] v \ MPart p → v { ( free_part p ) } )

    : ( Vec CRoute ) rs ( vec_new [CRoute] )
    ( vec_push [CRoute] rs @ CRoute { ( string_from `GET` ) ( string_from `/a` ) \ i x → i { + x 1 } } )
    ( vec_push [CRoute] rs @ CRoute { ( string_from `POST` ) ( string_from `/b` ) \ i x → i { * x 10 } } )
    : ?CRoute rg ( vec_get [CRoute] rs 1 )
    ?? rg { T r → { : ( @ i i ) h . r handler ( printf `closure: %s %s h(4)=%d\n` ( string_data . r method ) ( string_data . r pattern ) ( h 4 ) ) } F _ → ( puts `miss` ) }
    : ?CRoute rg9 ( vec_get [CRoute] rs 99 )
    ?? rg9 { T _ → ( puts `BUG oob hit` ) F _ → ( puts `closure oob: None` ) }
    ( vec_free_with [CRoute] rs \ CRoute r → v { ( string_free . r method ) ( string_free . r pattern ) } )

    : !Wide s w ( mk_wide `ayy` )
    ?? w { T ww → { ( printf `ok arm: %s %s %d\n` ( string_data . ww a ) ( string_data . ww b ) . ww c ) ( string_free . ww a ) ( string_free . ww b ) } F e → ( puts e ) }
    ^ 0
}
