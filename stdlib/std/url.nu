// stdlib/std/url.nu — one RFC 3986 URL parser.
//
// websocket.nu, http2_client.nu (and the http client stack) each
// hand-rolled scheme/host/port/path splitting. This is the single
// parser they delegate to. Lives in std/ with core-only dependencies,
// so ext/ modules can layer on it without a cycle.
//
// Grammar (RFC 3986, the subset URLs in the wild actually use):
//
//   scheme "://" [ userinfo "@" ] host [ ":" port ] path [ "?" query ] [ "#" fragment ]
//
// The "//" authority form is what every network scheme uses; this
// parser requires it (a bare `mailto:` style opaque URI is out of
// scope — the callers are all network clients). Host may be a name,
// IPv4, or a `[...]`-bracketed IPv6 literal.
//
//   ( url_parse s in )                 → ?Url      None on malformed / no scheme
//   ( url_free Url u )                 → v
//   ( url_default_port s scheme )      → i         80/443/21/… or -1 if unknown
//   ( url_port_or_default Url u )      → i         u.port if given, else scheme default
//   ( url_request_target Url u )       → String    "path[?query]" for the request line
//   ( url_percent_decode s in )        → String    %xx → byte; '+' kept literal
//   ( url_percent_encode s in )        → String    non-unreserved → %XX (upper)
//   ( url_query_decode s query )       → ( Vec UrlParam )  '&'/'='-split, %-decoded, '+'→' '
//   ( url_params_free ( Vec UrlParam ) ps ) → v
//
// Field conventions on the returned Url (all String fields OWNED):
//   scheme    lowercased; "" only when parse fails (then None anyway)
//   userinfo  "" when absent
//   host      "" only on parse failure; bracketed IPv6 keeps no brackets
//   port      explicit port, or -1 when absent (use url_port_or_default)
//   path      "" when absent (callers default to "/")
//   query     raw, without '?'; "" when absent
//   fragment  raw, without '#'; "" when absent

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Url {
    String scheme
    String userinfo
    String host
    i port
    String path
    String query
    String fragment
}

: UrlParam { String key String val }

@ url_free Url u → v {
    ( string_free . u scheme )
    ( string_free . u userinfo )
    ( string_free . u host )
    ( string_free . u path )
    ( string_free . u query )
    ( string_free . u fragment )
}

@ url_params_free ( Vec UrlParam ) ps → v {
    : i n ( vec_len [UrlParam] ps )
    : ~ i k 0
    ~ < k n {
        : ?UrlParam p ( vec_get [UrlParam] ps k )
        ?? p {
            T pp → { ( string_free . pp key ) ( string_free . pp val ) }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [UrlParam] ps )
}

// ── ASCII helpers ──────────────────────────────────────────────────

@ __url_lower i c → i { ? & >= c 65 <= c 90 { ^ + c 32 } { ^ c } }

@ __url_hex_val i c → i {
    ? & >= c 48 <= c 57 { ^ - c 48 } {}
    ? & >= c 97 <= c 102 { ^ + 10 - c 97 } {}
    ? & >= c 65 <= c 70 { ^ + 10 - c 65 } {}
    ^ -1
}

@ __url_hex_digit i n → i { ? < n 10 { ^ + 48 n } { ^ + 55 n } }  // 0-9, A-F

@ __url_is_unreserved i c → b {
    ? & >= c 65 <= c 90 { ^ T } {}
    ? & >= c 97 <= c 122 { ^ T } {}
    ? & >= c 48 <= c 57 { ^ T } {}
    ? | | == c 45 == c 95 == c 46 { ^ T } {}  // - _ .
    ? == c 126 { ^ T } {}  // ~
    ^ F
}

// ── Percent codec ──────────────────────────────────────────────────
//
// Decode treats '+' literally (RFC 3986 — '+' is not a space in the
// path/generic component). url_query_decode handles the
// form-urlencoded '+'→space rule for query strings.

// Reads the input through a raw pointer with the length hoisted once.
// `nurl_str_get` re-runs strlen per call, and the `string_push_char`
// in this loop stores, so LLVM cannot hoist that strlen out — the byte
// walk was O(n²) in the length of every decoded URL / query value.
@ url_percent_decode s in → String {
    : i n ( nurl_str_len in )
    : *u p # *u in
    : String out ( string_with_cap + n 1 )
    : ~ i k 0
    ~ < k n {
        : i c & # i . p k 255
        ? & == c 37 <= + k 2 - n 1 {
            : i hi ( __url_hex_val & # i . p + k 1 255 )
            : i lo ( __url_hex_val & # i . p + k 2 255 )
            ? & >= hi 0 >= lo 0 {
                ( string_push_char out + * hi 16 lo )
                = k + k 3
            } {
                ( string_push_char out c )
                = k + k 1
            }
        } {
            ( string_push_char out c )
            = k + k 1
        }
    }
    ^ out
}

// Same hoisted-length / raw-pointer walk as url_percent_decode.
@ url_percent_encode s in → String {
    : i n ( nurl_str_len in )
    : *u p # *u in
    : String out ( string_with_cap + n 1 )
    : ~ i k 0
    ~ < k n {
        : i c & # i . p k 255
        ? ( __url_is_unreserved c ) {
            ( string_push_char out c )
        } {
            ( string_push_char out 37 )  // '%'
            ( string_push_char out ( __url_hex_digit / c 16 ) )
            ( string_push_char out ( __url_hex_digit % c 16 ) )
        }
        = k + k 1
    }
    ^ out
}

// ── Scheme defaults ────────────────────────────────────────────────

@ url_default_port s scheme → i {
    ? == 1 ( nurl_str_eq scheme `http` ) { ^ 80 } {}
    ? == 1 ( nurl_str_eq scheme `https` ) { ^ 443 } {}
    ? == 1 ( nurl_str_eq scheme `ws` ) { ^ 80 } {}
    ? == 1 ( nurl_str_eq scheme `wss` ) { ^ 443 } {}
    ? == 1 ( nurl_str_eq scheme `ftp` ) { ^ 21 } {}
    ? == 1 ( nurl_str_eq scheme `redis` ) { ^ 6379 } {}
    ? == 1 ( nurl_str_eq scheme `postgres` ) { ^ 5432 } {}
    ? == 1 ( nurl_str_eq scheme `postgresql` ) { ^ 5432 } {}
    ^ -1
}

@ url_port_or_default Url u → i {
    ? >= . u port 0 { ^ . u port } { ^ ( url_default_port ( string_data . u scheme ) ) }
}

// ── Parser ─────────────────────────────────────────────────────────

@ url_parse s in → ?Url {
    : i n ( nurl_str_len in )
    // scheme: letters/digits/+/-/. up to "://"
    : ~ i pos 0
    : String scheme ( string_with_cap 8 )
    : ~ b ok_scheme F
    ~ & < pos n != ( nurl_str_get in pos ) 58 {
        : i c ( nurl_str_get in pos )
        // scheme char = ALPHA / DIGIT / '+' / '-' / '.'  (RFC 3986 §3.1)
        : b sc | ( __url_is_alpha c ) | ( __url_is_digit c ) | == c 43 | == c 45 == c 46
        ? sc {
            ( string_push_char scheme ( __url_lower c ) )
            = pos + pos 1
        } {
            // illegal scheme char before ':' → not a scheme-prefixed URL
            ( string_free scheme )
            ^ @ ?Url { F # Url 0 }
        }
    }
    // require "://"
    ? & & < + pos 2 n == ( nurl_str_get in pos ) 58
    & == ( nurl_str_get in + pos 1 ) 47 == ( nurl_str_get in + pos 2 ) 47
    { = pos + pos 3 = ok_scheme T } {}
    ? ! ok_scheme { ( string_free scheme ) ^ @ ?Url { F # Url 0 } } {}
    ? == 0 ( string_len scheme ) { ( string_free scheme ) ^ @ ?Url { F # Url 0 } } {}

    // authority = [userinfo "@"] host [":" port], up to '/' '?' '#'
    : i auth_start pos
    : ~ i auth_end pos
    ~ & < auth_end n & != ( nurl_str_get in auth_end ) 47
    & != ( nurl_str_get in auth_end ) 63 != ( nurl_str_get in auth_end ) 35 {
        = auth_end + auth_end 1
    }
    // userinfo: split on the LAST '@' within the authority
    : ~ i at -1
    : ~ i scan auth_start
    ~ < scan auth_end {
        ? == ( nurl_str_get in scan ) 64 { = at scan } {}
        = scan + scan 1
    }
    : String userinfo ( string_with_cap 1 )
    : ~ i host_start auth_start
    ? >= at 0 {
        : ~ i ui auth_start
        ~ < ui at { ( string_push_char userinfo ( nurl_str_get in ui ) ) = ui + ui 1 }
        = host_start + at 1
    } {}
    // host: bracketed IPv6 [..]  OR  up to ':' (port) / authority end
    : String host ( string_with_cap 16 )
    : ~ i hp host_start
    ? & < hp auth_end == ( nurl_str_get in hp ) 91 {
        // [IPv6] — copy inside the brackets, skip past ']'
        = hp + hp 1
        ~ & < hp auth_end != ( nurl_str_get in hp ) 93 {
            ( string_push_char host ( nurl_str_get in hp ) )
            = hp + hp 1
        }
        ? & < hp auth_end == ( nurl_str_get in hp ) 93 { = hp + hp 1 } {}
    } {
        ~ & < hp auth_end != ( nurl_str_get in hp ) 58 {
            ( string_push_char host ( nurl_str_get in hp ) )
            = hp + hp 1
        }
    }
    ? == 0 ( string_len host ) {
        ( string_free scheme ) ( string_free userinfo ) ( string_free host )
        ^ @ ?Url { F # Url 0 }
    } {}
    // optional :port. A port is 0..65535 (RFC 3986 allows *DIGIT, but a
    // TCP/UDP port that doesn't fit 16 bits is meaningless); a bad or
    // overflowing port rejects the whole URL rather than wrapping into a
    // plausible-looking small number.
    : ~ i port -1
    ? & < hp auth_end == ( nurl_str_get in hp ) 58 {
        = hp + hp 1
        : ~ i pv 0
        : ~ b anyd F
        : ~ b over F
        ~ & < hp auth_end ( __url_is_digit ( nurl_str_get in hp ) ) {
            = pv + * pv 10 - ( nurl_str_get in hp ) 48
            ? > pv 65535 { = over T } {}
            = anyd T
            = hp + hp 1
        }
        // An out-of-range port → invalid URL (rather than a 16-bit-wrapped
        // small number). A bare ':' with no digits stays lenient (no port),
        // matching the prior behaviour.
        ? over {
            ( string_free scheme ) ( string_free userinfo ) ( string_free host )
            ^ @ ?Url { F # Url 0 }
        } {}
        ? anyd { = port pv } {}
    } {}
    = pos auth_end

    // path: up to '?' or '#'
    : String path ( string_with_cap 16 )
    ~ & < pos n & != ( nurl_str_get in pos ) 63 != ( nurl_str_get in pos ) 35 {
        ( string_push_char path ( nurl_str_get in pos ) )
        = pos + pos 1
    }
    // query: '?' up to '#'
    : String query ( string_with_cap 8 )
    ? & < pos n == ( nurl_str_get in pos ) 63 {
        = pos + pos 1
        ~ & < pos n != ( nurl_str_get in pos ) 35 {
            ( string_push_char query ( nurl_str_get in pos ) )
            = pos + pos 1
        }
    } {}
    // fragment: '#' to end
    : String fragment ( string_with_cap 8 )
    ? & < pos n == ( nurl_str_get in pos ) 35 {
        = pos + pos 1
        ~ < pos n { ( string_push_char fragment ( nurl_str_get in pos ) ) = pos + pos 1 }
    } {}

    ^ @ ?Url { T @ Url { scheme userinfo host port path query fragment } }
}

@ __url_is_alpha i c → b { ^ | & >= c 65 <= c 90 & >= c 97 <= c 122 }

@ __url_is_digit i c → b { ^ & >= c 48 <= c 57 }

// "path[?query]" for the HTTP request line. Path defaults to "/" when
// empty; the fragment is client-only and never sent.
@ url_request_target Url u → String {
    : String out ( string_with_cap + + ( string_len . u path ) ( string_len . u query ) 2 )
    ? == 0 ( string_len . u path ) { ( string_push_char out 47 ) }
    { ( string_push_str out ( string_data . u path ) ) }
    ? > ( string_len . u query ) 0 {
        ( string_push_char out 63 )
        ( string_push_str out ( string_data . u query ) )
    } {}
    ^ out
}

// ── Query string codec ─────────────────────────────────────────────
//
// Split `query` on '&', each item on the first '='. Both halves are
// percent-decoded with the form-urlencoded '+'→space rule. A bare key
// (`a&b=1`) yields an empty value. Returns an OWNED Vec[UrlParam];
// free with url_params_free.

@ __url_form_decode s in → String {
    // like url_percent_decode but '+' → space (form-urlencoded)
    : i n ( nurl_str_len in )
    : *u p # *u in
    : String out ( string_with_cap + n 1 )
    : ~ i k 0
    ~ < k n {
        : i c & # i . p k 255
        ? == c 43 { ( string_push_char out 32 ) = k + k 1 } {
            ? & == c 37 <= + k 2 - n 1 {
                : i hi ( __url_hex_val & # i . p + k 1 255 )
                : i lo ( __url_hex_val & # i . p + k 2 255 )
                ? & >= hi 0 >= lo 0 { ( string_push_char out + * hi 16 lo ) = k + k 3 }
                { ( string_push_char out c ) = k + k 1 }
            } { ( string_push_char out c ) = k + k 1 }
        }
    }
    ^ out
}

@ url_query_decode s query → ( Vec UrlParam ) {
    : ( Vec UrlParam ) out ( vec_new [UrlParam] )
    : i n ( nurl_str_len query )
    : ~ i start 0
    ~ <= start n {
        // find next '&' or end
        : ~ i e start
        ~ & < e n != ( nurl_str_get query e ) 38 { = e + e 1 }
        ? > - e start 0 {
            // split [start,e) on first '='
            : ~ i eq start
            : ~ b has_eq F
            ~ & < eq e ! has_eq {
                ? == ( nurl_str_get query eq ) 61 { = has_eq T } { = eq + eq 1 }
            }
            : String kraw ( string_with_cap + - eq start 1 )
            : ~ i ki start
            ~ < ki eq { ( string_push_char kraw ( nurl_str_get query ki ) ) = ki + ki 1 }
            : String vraw ( string_with_cap 8 )
            ? has_eq {
                : ~ i vi + eq 1
                ~ < vi e { ( string_push_char vraw ( nurl_str_get query vi ) ) = vi + vi 1 }
            } {}
            : String key ( __url_form_decode ( string_data kraw ) )
            : String val ( __url_form_decode ( string_data vraw ) )
            ( string_free kraw ) ( string_free vraw )
            ( vec_push [UrlParam] out @ UrlParam { key val } )
        } {}
        = start + e 1
    }
    ^ out
}
