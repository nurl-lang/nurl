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

// Let go of `u` now rather than at the end of its owner's scope.
@ url_free sink Url u → v {}

// Let go of `ps` now rather than at the end of its owner's scope.
@ url_params_free sink ( Vec UrlParam ) ps → v {}

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

// Bytes [from, to) of `in` percent-decoded into a new String, '+' read
// as a space when `plus` (the form-urlencoded rule). The input is read
// through a raw pointer with the length hoisted (`nurl_str_get` re-runs
// strlen per call, which made the walk O(n²)), and the output goes
// through a reserved cursor: decoding never lengthens, so `to − from`
// bytes are reserved once and the true length committed. A component
// costs one allocation and no per-byte push.
@ __url_decode_range s in i from i to b plus → String {
    : i n - to from
    : String out ( string_with_cap + n 1 )
    ? > n 0 {
        : *u p # *u in
        : *u w ( string_reserve_at out n )
        : ~ i k from
        : ~ i o 0
        ~ < k to {
            : i c & # i . p k 255
            : ~ i v c
            : ~ i step 1
            ? & plus == c 43 { = v 32 } {
                ? & == c 37 <= + k 2 - to 1 {
                    : i hi ( __url_hex_val & # i . p + k 1 255 )
                    : i lo ( __url_hex_val & # i . p + k 2 255 )
                    ? & >= hi 0 >= lo 0 { = v + * hi 16 lo = step 3 } {}
                } {}
            }
            = . w o # u v
            = o + o 1
            = k + k step
        }
        ( string_commit out o )
    } {}
    ^ out
}

// Bytes [from, to) of `in`, copied once into a new String.
@ __url_span s in i from i to → String {
    : i n - to from
    : String out ( string_with_cap + n 1 )
    ? > n 0 { ( string_push_bytes out # *u + # i in from n ) } {}
    ^ out
}

@ url_percent_decode s in → String { ^ ( __url_decode_range in 0 ( nurl_str_len in ) F ) }

// Same hoisted-length / raw-pointer walk as url_percent_decode, and the
// output goes through a reserved cursor: each input byte yields either
// 1 byte or a 3-byte `%XX`, so 3n is a hard upper bound. We reserve that
// once and commit the actual length — `string_push_char` per emitted
// byte was ~12x the cost of a cursor store.
@ __url_encode s in b path → String {
    : i n ( nurl_str_len in )
    : *u p # *u in
    : String out ( string_with_cap + n 1 )
    ? > n 0 {
        : *u w ( string_reserve_at out * n 3 )
        : ~ i k 0
        : ~ i o 0
        ~ < k n {
            : i c & # i . p k 255
            ? | ( __url_is_unreserved c ) & path | == c 47 == c 58 {
                = . w o # u c
                = o + o 1
            } {
                = . w o # u 37  // '%'
                = . w + o 1 # u ( __url_hex_digit / c 16 )
                = . w + o 2 # u ( __url_hex_digit % c 16 )
                = o + o 3
            }
            = k + k 1
        }
        ( string_commit out o )
    } {}
    ^ out
}

// Encode a component, including its path separators.
@ url_percent_encode s in → String { ( __url_encode in F ) }

// Encode a URI path while preserving slash separators and drive colons.
// Spaces, percent signs, query/fragment delimiters and UTF-8 bytes escape.
@ url_path_encode s in → String { ( __url_encode in T ) }

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
    : *u ip # *u in
    : ~ i pos 0
    : ~ b ok_scheme F
    ~ & < pos n != ( nurl_str_at in n pos ) 58 {
        : i c ( nurl_str_at in n pos )
        // scheme char = ALPHA / DIGIT / '+' / '-' / '.'  (RFC 3986 §3.1)
        : b sc | ( __url_is_alpha c ) | ( __url_is_digit c ) | == c 43 | == c 45 == c 46
        ? sc { = pos + pos 1 } {
            // illegal scheme char before ':' → not a scheme-prefixed URL
            ^ @ ?Url { F # Url 0 }
        }
    }
    // the scheme, lowercased, in one reserved write
    : String scheme ( string_with_cap + pos 1 )
    ? > pos 0 {
        : *u sw ( string_reserve_at scheme pos )
        : ~ i si 0
        ~ < si pos { = . sw si # u ( __url_lower & # i . ip si 255 ) = si + si 1 }
        ( string_commit scheme pos )
    } {}
    // require "://"
    ? & & < + pos 2 n == ( nurl_str_at in n pos ) 58
    & == ( nurl_str_at in n + pos 1 ) 47 == ( nurl_str_at in n + pos 2 ) 47
    { = pos + pos 3 = ok_scheme T } {}
    ? ! ok_scheme { ^ @ ?Url { F # Url 0 } } {}
    ? == 0 ( string_len scheme ) { ^ @ ?Url { F # Url 0 } } {}

    // authority = [userinfo "@"] host [":" port], up to '/' '?' '#'
    : i auth_start pos
    : ~ i auth_end pos
    ~ & < auth_end n & != ( nurl_str_at in n auth_end ) 47
    & != ( nurl_str_at in n auth_end ) 63 != ( nurl_str_at in n auth_end ) 35 {
        = auth_end + auth_end 1
    }
    // userinfo: split on the LAST '@' within the authority
    : ~ i at -1
    : ~ i scan auth_start
    ~ < scan auth_end {
        ? == ( nurl_str_at in n scan ) 64 { = at scan } {}
        = scan + scan 1
    }
    : String userinfo ( __url_span in auth_start ? >= at 0 at auth_start )
    : i host_start ? >= at 0 + at 1 auth_start
    // host: bracketed IPv6 [..]  OR  up to ':' (port) / authority end
    : ~ i hp host_start
    : ~ i h0 host_start
    : ~ i h1 host_start
    ? & < hp auth_end == ( nurl_str_at in n hp ) 91 {
        // [IPv6] — the bytes inside the brackets, then past ']'
        = hp + hp 1
        = h0 hp
        ~ & < hp auth_end != ( nurl_str_at in n hp ) 93 { = hp + hp 1 }
        = h1 hp
        ? & < hp auth_end == ( nurl_str_at in n hp ) 93 { = hp + hp 1 } {}
    } {
        ~ & < hp auth_end != ( nurl_str_at in n hp ) 58 { = hp + hp 1 }
        = h1 hp
    }
    : String host ( __url_span in h0 h1 )
    ? == 0 ( string_len host ) {
        ^ @ ?Url { F # Url 0 }
    } {}
    // optional :port. A port is 0..65535 (RFC 3986 allows *DIGIT, but a
    // TCP/UDP port that doesn't fit 16 bits is meaningless); a bad or
    // overflowing port rejects the whole URL rather than wrapping into a
    // plausible-looking small number.
    : ~ i port -1
    ? & < hp auth_end == ( nurl_str_at in n hp ) 58 {
        = hp + hp 1
        : ~ i pv 0
        : ~ b anyd F
        : ~ b over F
        ~ & < hp auth_end ( __url_is_digit ( nurl_str_at in n hp ) ) {
            = pv + * pv 10 - ( nurl_str_at in n hp ) 48
            ? > pv 65535 { = over T } {}
            = anyd T
            = hp + hp 1
        }
        // An out-of-range port → invalid URL (rather than a 16-bit-wrapped
        // small number). A bare ':' with no digits stays lenient (no port),
        // matching the prior behaviour.
        ? over {
            ^ @ ?Url { F # Url 0 }
        } {}
        ? anyd { = port pv } {}
    } {}
    = pos auth_end

    // path: up to '?' or '#'
    : i p0 pos
    ~ & < pos n & != ( nurl_str_at in n pos ) 63 != ( nurl_str_at in n pos ) 35 { = pos + pos 1 }
    : String path ( __url_span in p0 pos )
    // query: '?' up to '#'
    : ~ i q0 pos
    ? & < pos n == ( nurl_str_at in n pos ) 63 {
        = pos + pos 1
        = q0 pos
        ~ & < pos n != ( nurl_str_at in n pos ) 35 { = pos + pos 1 }
    } {}
    : String query ( __url_span in q0 pos )
    // fragment: '#' to end
    : ~ i f0 pos
    ? & < pos n == ( nurl_str_at in n pos ) 35 { = f0 + pos 1 = pos n } {}
    : String fragment ( __url_span in f0 pos )

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

@ url_query_decode s query → ( Vec UrlParam ) {
    : ( Vec UrlParam ) out ( vec_new [UrlParam] )
    : i n ( nurl_str_len query )
    : ~ i start 0
    ~ <= start n {
        // find next '&' or end
        : ~ i e start
        ~ & < e n != ( nurl_str_at query n e ) 38 { = e + e 1 }
        ? > - e start 0 {
            // split [start,e) on first '='
            : ~ i eq start
            : ~ b has_eq F
            ~ & < eq e ! has_eq {
                ? == ( nurl_str_at query n eq ) 61 { = has_eq T } { = eq + eq 1 }
            }
            // each half decoded straight from its bytes of `query`
            : String key ( __url_decode_range query start eq T )
            : String val ( __url_decode_range query ? has_eq + eq 1 e e T )
            ( vec_push [UrlParam] out @ UrlParam { key val } )
        } {}
        = start + e 1
    }
    ^ out
}
