// Registry identity shared by resolution, locks and installation.
// A registry is an HTTP(S) directory URL, never a query, credential or fragment.
// Canonicalize scheme/host/default port and the directory separator; preserve
// path bytes because servers may distinguish repeated slashes and escapes.

$ `stdlib/core/string.nu`
$ `stdlib/std/url.nu`

@ registry_default → s { ^ `https://reg.nurl-lang.org/` }

@ registry_url s raw → ?String {
    : i n ( nurl_str_len raw )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at raw n k )
        ? | | <= c 32 == c 127 | == c 92 | == c 63 == c 35 { ^ @ ?String { F ( string_new ) } } {}
        = k + k 1
    }
    ?? ( url_parse raw ) {
        F _ → { ^ @ ?String { F ( string_new ) } }
        T url → {
            : s scheme ( string_data . url scheme )
            ? | ! | != 0 ( nurl_str_eq scheme `http` ) != 0 ( nurl_str_eq scheme `https` ) > ( string_len . url userinfo ) 0 {
                ( url_free url )
                ^ @ ?String { F ( string_new ) }
            } {}
            : String out ( string_with_cap + n 2 )
            ( string_push_str out scheme )
            ( string_push_str out `://` )
            : String host ( string_to_lower . url host )
            : b ipv6 >= ( nurl_str_find ( string_data host ) `:` ) 0
            ? ipv6 { ( string_push_char out 91 ) } {}
            ( string_push_str out ( string_data host ) )
            ? ipv6 { ( string_push_char out 93 ) } {}
            ( string_free host )
            ? & >= . url port 0 != . url port ( url_default_port scheme ) {
                ( string_push_char out 58 )
                ( string_push_int out . url port )
            } {}
            ( string_push_str out ( string_data . url path ) )
            : i len ( string_len out )
            ? != ( nurl_str_at ( string_data out ) len - len 1 ) 47 { ( string_push_char out 47 ) } {}
            ( url_free url )
            ^ @ ?String { T out }
        }
    }
}

// Takes a normalized registry URL; the prefix distinguishes registry sources
// from filesystem sources in the lock format.
@ registry_source s registry → String {
    : String out ( string_from `registry+` )
    ( string_push_str out registry )
    ^ out
}

@ registry_from_source s source → ?String {
    ? == 0 ( nurl_str_starts source `registry+` ) { ^ @ ?String { F ( string_new ) } } {}
    : s raw ( nurl_str_slice source 9 - ( nurl_str_len source ) 9 )
    ^ ( registry_url raw )
}

// Same published-name grammar as the registry: [a-z0-9][a-z0-9_-]{0,63}.
// Names are a single URL and filesystem component.
@ registry_name_valid s name → b {
    : i n ( nurl_str_len name )
    ? | == n 0 > n 64 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at name n k )
        : b alnum | & >= c 97 <= c 122 & >= c 48 <= c 57
        ? ! | alnum & > k 0 | == c 45 == c 95 { ^ F } {}
        = k + k 1
    }
    ^ T
}
