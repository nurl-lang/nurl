// stdlib/ext/http_auth.nu — HTTP server Phase 7 conveniences:
// Authorization-header parsers + cookie helpers. Pure NURL — uses
// `http_request.nu#header_get` + `std/encode.nu#b64_decode` only.
//
// API (this revision):
//
//   ( parse_basic_auth  HttpRequest req ) → ? BasicAuth   OWNED user/pass
//   ( basic_auth_free   BasicAuth ba )    → v
//   ( parse_bearer_auth HttpRequest req ) → ? String      OWNED token
//
//   ( request_cookie HttpRequest req s name )           → ? String
//   ( response_set_cookie HttpResponse r s name s value
//                         CookieOpts opts )             → v
//
//   ( cookie_opts_default )                             → CookieOpts
//
// Memory model:
//
//   * `parse_basic_auth` returns an OWNED `BasicAuth { user, pass }`
//     inside the Some arm. Caller frees with `basic_auth_free`. None
//     means: header absent, not "Basic ...", base64 decode failed,
//     or no ':' separator in the decoded credentials.
//   * `parse_bearer_auth` returns an OWNED String token (everything
//     after `Bearer ` with leading/trailing whitespace stripped). None
//     means: header absent, not "Bearer ...", or the token is empty.
//   * `request_cookie` returns an OWNED String value. The cookie name
//     is matched case-sensitively (RFC 6265 §4.2.1 — names are case-
//     sensitive on the wire). None on missing cookie / missing header.
//   * `response_set_cookie` always appends a fresh `Set-Cookie:` header
//     (HTTP allows multiple — one entry per cookie). Internally this
//     uses `response_add_header`, NOT `response_set_header`, so two
//     `response_set_cookie` calls on the same response produce two
//     `Set-Cookie:` lines on the wire. The CookieOpts struct is
//     BORROWED.

$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`

// ── Basic auth ────────────────────────────────────────────────────────

: BasicAuth {
    String user
    String pass
}

@ basic_auth_free BasicAuth ba → v {
    ( string_free . ba user )
    ( string_free . ba pass )
}

// Lowercase-compare first `n` bytes of `s` against a literal prefix
// (which is itself lowercase). Returns T iff `s[..n]` matches `prefix`
// (case-insensitively for letters A–Z) and `n <= len(s)`.
@ __ascii_lower_eq_prefix String s s prefix → b {
    : i pn ( nurl_str_len prefix )
    : i sn ( string_len s )
    ? < sn pn { ^ F } {}
    : ~ i k 0
    ~ < k pn {
        : ~ i a ( string_get s k )
        ? & >= a 65 <= a 90 { = a + a 32 } {}
        : i b ( nurl_str_get prefix k )
        ? != a b { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ __strip_ows String src → String {
    : i n ( string_len src )
    : ~ i a 0
    : ~ b going T
    ~ & going < a n {
        : i c ( string_get src a )
        ? & != c 32 != c 9 { = going F } {
            = a + a 1
        }
    }
    : ~ i b n
    = going T
    ~ & going > b a {
        : i c ( string_get src - b 1 )
        ? & != c 32 != c 9 { = going F } {
            = b - b 1
        }
    }
    ^ ( string_substr src a - b a )
}

// Extract the credentials substring after a "Basic " or "Bearer "
// prefix. Returns the OWNED trimmed remainder, or an empty owned
// string when the header didn't start with the expected prefix.
@ __after_scheme String header s scheme → String {
    : i pn ( nurl_str_len scheme )
    ? ! ( __ascii_lower_eq_prefix header scheme ) { ^ ( string_new ) } {}
    : i hn ( string_len header )
    ? <= hn pn { ^ ( string_new ) } {}
    // Require a single SP / HTAB after the scheme name.
    : i sep ( string_get header pn )
    ? & != sep 32 != sep 9 { ^ ( string_new ) } {}
    : String tail ( string_substr header + pn 1 - hn + pn 1 )
    : String trimmed ( __strip_ows tail )
    ( string_free tail )
    ^ trimmed
}

@ parse_basic_auth HttpRequest req → ?BasicAuth {
    : ?String got ( header_get . req headers `Authorization` )
    ?? got {
        T h → {
            : String creds64 ( __after_scheme h `basic` )
            ( string_free h )
            : i n ( string_len creds64 )
            ? == n 0 {
                ( string_free creds64 )
                ^ @ ?BasicAuth { F @ BasicAuth { ( string_new ) ( string_new ) } }
            } {}
            : !String ParseErr dec ( b64_decode ( string_data creds64 ) )
            ( string_free creds64 )
            ?? dec {
                T raw → {
                    // Split on the first ':' — RFC 7617 §2 — anything after is
                    // the password (which may itself contain ':').
                    : ?i sep_opt ( string_index_of raw `:` )
                    ?? sep_opt {
                        T idx → {
                            : i rn ( string_len raw )
                            : String user ( string_substr raw 0 idx )
                            : String pass ( string_substr raw + idx 1 - rn + idx 1 )
                            ( string_free raw )
                            ^ @ ?BasicAuth { T @ BasicAuth { user pass } }
                        }
                        F _ → {
                            ( string_free raw )
                            ^ @ ?BasicAuth { F @ BasicAuth { ( string_new ) ( string_new ) } }
                        }
                    }
                }
                F _ → {
                    ^ @ ?BasicAuth { F @ BasicAuth { ( string_new ) ( string_new ) } }
                }
            }
        }
        F empty → {
            ( string_free empty )
            ^ @ ?BasicAuth { F @ BasicAuth { ( string_new ) ( string_new ) } }
        }
    }
}

// ── Bearer auth ───────────────────────────────────────────────────────

@ parse_bearer_auth HttpRequest req → ?String {
    : ?String got ( header_get . req headers `Authorization` )
    ?? got {
        T h → {
            : String token ( __after_scheme h `bearer` )
            ( string_free h )
            : i n ( string_len token )
            ? == n 0 {
                ( string_free token )
                ^ @ ?String { F }
            } {}
            ^ @ ?String { T token }
        }
        F empty → {
            ( string_free empty )
            ^ @ ?String { F }
        }
    }
}

// ── Cookies ───────────────────────────────────────────────────────────
//
// Cookie header format (RFC 6265 §5.4):  "name1=value1; name2=value2"
// We do not URL-decode values — the spec explicitly says cookie values
// may contain percent-encoding but the choice is application-level.
// `request_cookie` returns the raw value bytes. Use `percent_decode`
// from http_request.nu if you need decoding.

@ __skip_cookie_ows String h i k → i {
    : i n ( string_len h )
    : ~ i j k
    ~ < j n {
        : i c ( string_get h j )
        ? & != c 32 != c 9 { ^ j } {}
        = j + j 1
    }
    ^ n
}

@ request_cookie HttpRequest req s name → ?String {
    : ?String got ( header_get . req headers `Cookie` )
    ?? got {
        T h → {
            : i hn ( string_len h )
            : i name_len ( nurl_str_len name )
            : ~ i k 0
            : ~ b done F
            : ~ b have_hit F
            : ~ i hit_v_start 0
            : ~ i hit_v_len 0
            ~ & ! done < k hn {
                = k ( __skip_cookie_ows h k )
                ? >= k hn {
                    = done T
                } {
                    // Scan to next ';' to find the pair end, recording the first '='.
                    : ~ i eq - 0 1
                    : ~ i semi - 0 1
                    : ~ i j k
                    : ~ b scan T
                    ~ & scan < j hn {
                        : i c ( string_get h j )
                        ? == c 59 {
                            = semi j
                            = scan F
                        } {}
                        ? & scan == c 61 {
                            ? < eq 0 { = eq j } {}
                        } {}
                        ? scan { = j + j 1 } {}
                    }
                    : i pair_end ? >= semi 0 semi hn
                    ? & >= eq 0 < eq pair_end {
                        : i this_name_len - eq k
                        ? == this_name_len name_len {
                            : ~ b match T
                            : ~ i m 0
                            ~ & match < m name_len {
                                ? != ( string_get h + k m ) ( nurl_str_get name m ) { = match F } {}
                                = m + m 1
                            }
                            ? match {
                                = have_hit T
                                = hit_v_start + eq 1
                                = hit_v_len - pair_end hit_v_start
                                = done T
                            } {}
                        } {}
                    } {}
                    ? & ! done < semi 0 { = done T } {}
                    ? & ! done >= semi 0 { = k + semi 1 } {}
                }
            }
            ? have_hit {
                : String value ( string_substr h hit_v_start hit_v_len )
                ( string_free h )
                ^ @ ?String { T value }
            } {}
            ( string_free h )
            ^ @ ?String { F }
        }
        F empty → {
            ( string_free empty )
            ^ @ ?String { F }
        }
    }
}

// ── Set-Cookie ────────────────────────────────────────────────────────
//
// A subset of RFC 6265 attributes. Values are written verbatim — caller
// is responsible for ensuring `name`, `value`, `path`, `domain` don't
// contain control bytes / `;` / `,` (Set-Cookie has no escaping
// mechanism — those bytes are simply forbidden).

: | SameSite { SameSiteUnset SameSiteStrict SameSiteLax SameSiteNone }

: CookieOpts {
    s path
    s domain
    i max_age
    b secure
    b http_only
    SameSite same_site
}

@ cookie_opts_default → CookieOpts {
    ^ @ CookieOpts {
        `` `` -1 F F @ SameSite { SameSiteUnset }
    }
}

@ __same_site_name SameSite ss → s {
    ^ ?? ss {
        SameSiteUnset → ``
        SameSiteStrict → `Strict`
        SameSiteLax → `Lax`
        SameSiteNone → `None`
    }
}

@ response_set_cookie HttpResponse r s name s value CookieOpts opts → v {
    : String hv ( string_with_cap 128 )
    ( string_push_str hv name )
    ( string_push_char hv 61 )
    ( string_push_str hv value )

    : s pth . opts path
    ? != 0 ( nurl_str_len pth ) {
        ( string_push_str hv `; Path=` )
        ( string_push_str hv pth )
    } {}

    : s dom . opts domain
    ? != 0 ( nurl_str_len dom ) {
        ( string_push_str hv `; Domain=` )
        ( string_push_str hv dom )
    } {}

    : i ma . opts max_age
    ? >= ma 0 {
        ( string_push_str hv `; Max-Age=` )
        ( string_push_int hv ma )
    } {}

    ? . opts secure {
        ( string_push_str hv `; Secure` )
    } {}

    ? . opts http_only {
        ( string_push_str hv `; HttpOnly` )
    } {}

    : s ssn ( __same_site_name . opts same_site )
    ? != 0 ( nurl_str_len ssn ) {
        ( string_push_str hv `; SameSite=` )
        ( string_push_str hv ssn )
    } {}

    ( response_add_header r `Set-Cookie` ( string_data hv ) )
    ( string_free hv )
}
