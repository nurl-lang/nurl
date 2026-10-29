// wrap_join_returned_ok.nu — an option or a result literal handed back
// straight away whose payload is a `?` / `??` over this function's own
// values (agora #184): the lent paths are copied, as `^ ?` copies them,
// so the caller owns what it gets. Runs clean under the sanitizers.

$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ opt_local b c → ?String {
    : String x ( mk )
    ^ @ ?String { T ? c x ( mk ) }
}

@ opt_field b c → ?String {
    : P q @ P { ( mk ) 1 }
    ^ @ ?String { T ? c . q s ( mk ) }
}

@ res_local b c → !String i {
    : String x ( mk )
    ^ @ !String i { T ? c x ( mk ) }
}

@ opt_fall_off b c → ?String {
    : String x ( mk )
    @ ?String { T ? c x ( mk ) }
}

@ opt_match i n → ?String {
    : ?String o ? > n 2 @ ?String { T ( mk ) } @ ?String { F }
    ^ @ ?String { T ?? o { T s → s F → ( mk ) } }
}

@ main → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        = acc + acc ?? ( opt_local > k 4 ) { T s → ( string_len s ) F → 0 }
        = acc + acc ?? ( opt_field > k 3 ) { T s → ( string_len s ) F → 0 }
        = acc + acc ?? ( res_local > k 2 ) { T s → ( string_len s ) F e → e }
        = acc + acc ?? ( opt_fall_off > k 1 ) { T s → ( string_len s ) F → 0 }
        = acc + acc ?? ( opt_match k ) { T s → ( string_len s ) F → 0 }
        = k + k 1
    }
    ( nurl_println_int acc )
    ^ 0
}
