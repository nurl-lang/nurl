// try_call_lend_ok.nu — a try `\ ( g w )` over a call that lends the local
// `w` hands on that call's provenance (agora #194): as a returned result's
// payload, and as a `sink` argument, what it lends of `w` is copied; over
// a parameter it stays a lend.

$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw s t → W { ^ @ W { ( string_from t ) } }

@ keep sink String x → i { ^ ( string_len x ) }

@ payload → !String E {
    : W w ( mkw `a try's payload lent out of a local` )
    ^ @ !String E { T \ ( getr w ) }
}

@ sinked → !i E {
    : W w ( mkw `a try handed to a sink` )
    : i n ( keep \ ( getr w ) )
    ^ @ !i E { T + n ( string_len . w s ) }
}

@ param W p → !String E { ^ @ !String E { T \ ( getr p ) } }

@ main → i {
    ?? ( payload ) { T x → ( nurl_println ( string_data x ) ) F _ → ( nurl_println `bad` ) }
    ?? ( sinked ) { T n → ( nurl_println_int n ) F _ → ( nurl_println `bad` ) }
    : W p ( mkw `a parameter's field, lent back` )
    ?? ( param p ) { T x → ( nurl_println ( string_data x ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
