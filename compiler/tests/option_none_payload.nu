// option_none_payload.nu — the payload of a None literal is released
// where it is built.
//
// Dropping an option releases the payload only when it is present, so a
// None built with a payload that owns something — `@ ?S { F @ S {
// ( string_new ) … } }`, as parse_basic_auth's early exits did — leaked
// it: no owner could ever release it except by reading a None's payload
// and freeing that by hand. The compiler now drops such a payload at the
// literal and leaves the slot zero. Each round must leave the live
// allocation count where it found it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Creds { String user String pass }

@ parse_creds s text → ?Creds {
    : i n ( nurl_str_len text )
    ? == n 0 { ^ @ ?Creds { F @ Creds { ( string_new ) ( string_new ) } } } {}
    ^ @ ?Creds { T @ Creds { ( string_from text ) ( string_from `secret` ) } }
}

@ first_word s text → ?String {
    ? == 0 ( nurl_str_len text ) { ^ @ ?String { F ( string_from `unused` ) } } {}
    ^ @ ?String { T ( string_from text ) }
}

@ list_or_none b ok → ?( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ? ok { ^ @ ?( Vec i ) { T v } } {}
    ^ @ ?( Vec i ) { F v }
}

@ round → i {
    : ~ i n 0
    ?? ( parse_creds `alice` ) { T c → { = n + n ( string_len . c user ) } F → {} }
    ?? ( parse_creds `` ) { T c → { = n + n 100 } F → {} }
    : ?Creds bound ( parse_creds `` )
    ?? ( first_word `` ) { T w → { = n + n 100 } F → {} }
    : ?String w2 ( first_word `hi` )
    ?? w2 { T w → { = n + n ( string_len w ) } F → {} }
    ?? ( list_or_none F ) { T v → { = n + n 100 } F → {} }
    ?? ( list_or_none T ) { T v → { = n + n ( vec_len [i] v ) } F → {} }
    ^ n
}

@ main → i {
    : i first ( round )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 30 { ( round ) = k + k 1 }
    : i l1 ( live )
    // alice (5) + hi (2) + one element (1)
    ( nurl_println ( nurl_str_cat `sum ` ( nurl_str_int first ) ) )
    ( nurl_println ? == l0 l1 `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l1 l0 ) ) )
    ^ 0
}
