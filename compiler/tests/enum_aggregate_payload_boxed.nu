// enum_aggregate_payload_boxed.nu — an enum variant's payload that is an
// anonymous aggregate (an option, a result, a closure) lives in a heap box
// the enum owns (agora #155). It outlives the frame that built it, and it is
// dropped, copied (one with no closure payload) and replaced with the
// enum. Runs clean under the
// sanitizers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E {
    Opt ? String
    Res ! String i
    Cb ( @ i )
    Pair ? i ( @ i )
    NoVal
}

: | O {
    Some ? String
    NoO
}

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

// Built a few frames down, read after they are gone.
@ deep i d i v → E {
    ? > d 0 { ^ ( deep - d 1 v ) } {}
    ^ @ E { Pair @ ?i { T v } \ → i { ^ + v 1 } }
}

@ opt_of i n → O { ^ @ O { Some @ ?String { T ( mk ) } } }

@ show_o O o → i { ^ ?? o { Some s → ?? s { T t → ( string_len t ) F → 0 } NoO → -1 } }

@ cb_of String s → E { ^ @ E { Cb \ → i { ^ ( string_len s ) } } }

@ show E e → i {
    ^ ?? e {
        Opt o → ?? o { T s → ( string_len s ) F → 0 }
        Res r → ?? r { T s → ( string_len s ) F x → x }
        Cb f → ( f )
        Pair p f → + ?? p { T x → x F → 0 } ( f )
        NoVal → -1
    }
}

@ main → i {
    : E a ( deep 3 41 )
    ( nurl_println_int ( show a ) )
    : O b ( opt_of 1 )
    : O c ( mem_dup b )
    ( nurl_println_int + ( show_o b ) ( show_o c ) )
    : E e @ E { Opt @ ?String { T ( mk ) } }
    ( nurl_println_int ( show e ) )
    : String s ( mk )
    : E d ( cb_of s )
    ( nurl_println_int ( show d ) )
    : ( Vec E ) v ( vec_new [E] )
    ( vec_push [E] v @ E { Res @ !String i { T ( mk ) } } )
    ( vec_push [E] v @ E { Res @ !String i { F 7 } } )
    ( vec_push [E] v @ E { NoVal } )
    : ~ i n 0
    : ~ i acc 0
    ~ < n ( vec_len [E] v ) {
        ?? ( vec_get [E] v n ) { T e → { = acc + acc ( show e ) } F → {} }
        = n + n 1
    }
    ( nurl_println_int acc )
    : ~ E r @ E { Opt @ ?String { T ( mk ) } }
    = n 0
    ~ < n 5 {
        = r @ E { Cb \ → i { ^ 2 } }
        = n + n 1
    }
    ( nurl_println_int ( show r ) )
    ^ 0
}
