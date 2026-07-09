// stdlib/ext/cookies.nu — an HTTP client cookie jar (RFC 6265).
//
// The server side of the stack writes Set-Cookie (ext/http_auth.nu); the
// client had no way to round-trip a session short of hand-building
// `Cookie:` headers. This is the missing half: feed each Set-Cookie
// response header to the jar, then ask the jar for the `Cookie:` value
// to send on the next request. Pure string in / string out — decoupled
// from the HTTP client types, so it is fully offline-testable and works
// with HTTP/1.1, h2, or anything else that hands you header strings.
//
//   ( cookie_jar_new )                                   → CookieJar
//   ( cookie_jar_set    CookieJar j s setcookie s host s path i now ) → b
//        Parse + store one Set-Cookie value. Defaults Domain/Path from
//        the request host/path; Max-Age (relative to `now`) wins over
//        Expires; a cookie that resolves as already-expired DELETES any
//        stored match. Returns F on a malformed header (nothing stored).
//   ( cookie_jar_header CookieJar j s host s path b secure i now ) → String
//        The `Cookie:` header value for a request — matching cookies
//        (domain + path + Secure + unexpired), longest path first,
//        "a=1; b=2" — or "" when none apply. Caller owns the String.
//   ( cookie_jar_count  CookieJar j )                    → i
//   ( cookie_jar_free   CookieJar j )                    → v
//
// `now` is unix seconds (e.g. from time_now → unix); pass it explicitly
// so expiry is deterministic and testable. Session cookies (no Expires
// / Max-Age) live until cookie_jar_free. Domain matching follows RFC
// 6265 §5.1.3 (host-only vs subdomain) and path matching §5.1.4.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`

// expires: -1 = session (no expiry). host_only T = exact-host only
// (no Domain attribute was sent). Strings are owned by the jar.
: Cookie { String name String value String domain String path i expires b host_only b secure }

: CookieJar { ( Vec Cookie ) cookies }

@ cookie_jar_new → CookieJar {
    ^ @ CookieJar { ( vec_new [Cookie] ) }
}

@ cookie_jar_count CookieJar j → i { ^ ( vec_len [Cookie] . j cookies ) }

@ __cookie_free Cookie c → v {
    ( string_free . c name )
    ( string_free . c value )
    ( string_free . c domain )
    ( string_free . c path )
}

@ cookie_jar_free CookieJar j → v {
    : ~ i k 0
    ~ < k ( vec_len [Cookie] . j cookies ) {
        ?? ( vec_get [Cookie] . j cookies k ) { T c → ( __cookie_free c ) F _ → {} }
        = k + k 1
    }
    ( vec_free [Cookie] . j cookies )
}

@ __cookies_free_str_vec ( Vec String ) v → v {
    : ~ i k 0
    ~ < k ( vec_len [String] v ) {
        ?? ( vec_get [String] v k ) { T s → ( string_free s ) F _ → {} }
        = k + k 1
    }
    ( vec_free [String] v )
}

// ── small string helpers ─────────────────────────────────────────────

// Compare a String against a raw `s` literal (string_eq is String×String;
// attribute keys are matched against bare literals).
@ __keyeq String k s lit → b { ^ == ( strcmp ( string_data k ) lit ) 0 }

// substring before / after the first occurrence of `ch` (a 1-char
// needle). When `ch` is absent: before = whole, after = "".
@ __cut_before String s s ch → String {
    ^ ?? ( string_index_of s ch ) {
        T i → ( string_substr s 0 i )
        F _ → { : String out ( string_with_cap + ( string_len s ) 1 ) ( string_push_str out ( string_data s ) ) out }
    }
}

@ __cut_after String s s ch → String {
    ^ ?? ( string_index_of s ch ) {
        T i → ( string_substr s + i 1 - ( string_len s ) + i 1 )
        F _ → ( string_with_cap 1 )
    }
}

// default-path (RFC 6265 §5.1.4): up to and excluding the last '/';
// "/" when the path is empty, relative, or has a single leading slash.
@ __default_path s reqpath → String {
    : String p ( string_with_cap 8 )
    : i n ( nurl_str_len reqpath )
    ? | == n 0 != ( nurl_str_get reqpath 0 ) 47 {  // empty or not absolute
        ( string_push_char p 47 )
        ^ p
    } {}
    : ~ i last 0
    : ~ i k 0
    ~ < k n { ? == ( nurl_str_get reqpath k ) 47 { = last k } {} = k + k 1 }
    ? == last 0 { ( string_push_char p 47 ) } {
        : ~ i j 0
        ~ < j last { ( string_push_char p ( nurl_str_get reqpath j ) ) = j + j 1 }
    }
    ^ p
}

// ── matching (RFC 6265 §5.1.3 / §5.1.4) ──────────────────────────────

@ __domain_match s host s domain b host_only → b {
    : String h ( string_with_cap 8 ) ( string_push_str h host )
    : String hl ( string_to_lower h ) ( string_free h )
    : String d ( string_with_cap 8 ) ( string_push_str d domain )
    : String dl ( string_to_lower d ) ( string_free d )
    : i hn ( string_len hl )
    : i dn ( string_len dl )
    : ~ b ok F
    ? ( string_eq hl dl ) { = ok T } {
        ? host_only {} {
            // subdomain: host ends with domain AND the char before is '.'
            ? & ( string_ends_with hl ( string_data dl ) ) & > hn dn == ( string_get hl - - hn dn 1 ) 46 { = ok T } {}
        }
    }
    ( string_free hl )
    ( string_free dl )
    ^ ok
}

@ __path_match s reqpath s cookiepath → b {
    : String r ( string_with_cap 8 ) ( string_push_str r reqpath )
    : String cp ( string_with_cap 8 ) ( string_push_str cp cookiepath )
    : i rn ( string_len r )
    : i cn ( string_len cp )
    : ~ b ok F
    ? ( string_eq r cp ) { = ok T } {
        ? ( string_starts_with r cookiepath ) {
            // prefix: ok if cookie-path ends in '/' or the next req char is '/'
            ? > cn 0 {
                ? == ( string_get cp - cn 1 ) 47 { = ok T } {
                    ? & < cn rn == ( string_get r cn ) 47 { = ok T } {}
                }
            } {}
        } {}
    }
    ( string_free r )
    ( string_free cp )
    ^ ok
}

// ── parse one Set-Cookie value ───────────────────────────────────────

// Returns a freshly-owned Cookie (None on a malformed pair). `now` is
// used to resolve Max-Age to an absolute expiry.
@ cookie_parse s setcookie s host s path i now → ?Cookie {
    : String sc ( string_with_cap + ( nurl_str_len setcookie ) 1 )
    ( string_push_str sc setcookie )
    : ( Vec String ) parts ( string_split sc `;` )
    ( string_free sc )
    ? == ( vec_len [String] parts ) 0 { ( vec_free [String] parts ) ^ @ ?Cookie { F } } {}

    // first part: name=value
    : ~ String nm ( string_with_cap 4 )
    : ~ String val ( string_with_cap 4 )
    ?? ( vec_get [String] parts 0 ) {
        T p0 → {
            : String t ( string_trim p0 )
            ( string_free nm ) ( string_free val )
            : String nraw ( __cut_before t `=` )
            = nm ( string_trim nraw ) ( string_free nraw )
            : String vraw ( __cut_after t `=` )
            = val ( string_trim vraw ) ( string_free vraw )
            ( string_free t )
        }
        F _ → {}
    }
    ? == ( string_len nm ) 0 {
        ( string_free nm ) ( string_free val )
        ( __cookies_free_str_vec parts )
        ^ @ ?Cookie { F }
    } {}

    // defaults
    : String hl0 ( string_with_cap 8 ) ( string_push_str hl0 host )
    : ~ String dom ( string_to_lower hl0 ) ( string_free hl0 )
    : ~ String cpath ( __default_path path )
    : ~ i expires -1
    : ~ b host_only T
    : ~ b secure F
    : ~ i seen_maxage 0

    : ~ i pi 1
    ~ < pi ( vec_len [String] parts ) {
        ?? ( vec_get [String] parts pi ) {
            T pp → {
                : String seg ( string_trim pp )
                : String kraw ( __cut_before seg `=` )
                : String ktrim ( string_trim kraw ) ( string_free kraw )
                : String key ( string_to_lower ktrim ) ( string_free ktrim )
                : String vraw ( __cut_after seg `=` )
                : String aval ( string_trim vraw ) ( string_free vraw )

                ? ( __keyeq key `domain` ) {
                    // strip a leading '.', lowercase
                    : i dn0 ( string_len aval )
                    : String stripped ? & > dn0 0 == ( string_get aval 0 ) 46 ( string_substr aval 1 - dn0 1 ) ( __cut_before aval `;` )
                    : String low ( string_to_lower stripped ) ( string_free stripped )
                    ? > ( string_len low ) 0 {
                        ( string_free dom ) = dom low = host_only F
                    } { ( string_free low ) }
                } {
                    ? ( __keyeq key `path` ) {
                        ? & > ( string_len aval ) 0 == ( string_get aval 0 ) 47 {
                            ( string_free cpath )
                            = cpath ( string_with_cap + ( string_len aval ) 1 )
                            ( string_push_str cpath ( string_data aval ) )
                        } {}
                    } {
                        ? ( __keyeq key `max-age` ) {
                            = seen_maxage 1
                            = expires + now ( nurl_str_to_int ( string_data aval ) )
                        } {
                            ? ( __keyeq key `expires` ) {
                                ? == seen_maxage 0 {
                                    ?? ( http_date_parse ( string_data aval ) ) { T t → { = expires t } F _ → {} }
                                } {}
                            } {
                                ? ( __keyeq key `secure` ) { = secure T } {}
                            } } } }

                ( string_free seg ) ( string_free key ) ( string_free aval )
            }
            F _ → {}
        }
        = pi + pi 1
    }
    ( __cookies_free_str_vec parts )

    : Cookie c @ Cookie { nm val dom cpath expires host_only secure }
    ^ @ ?Cookie { T c }
}

// ── jar mutation + query ─────────────────────────────────────────────

@ __vget_i ( Vec i ) v i k → i {
    ^ ?? ( vec_get [i] v k ) { T x → x F _ → 0 }
}

// Drop any stored cookie with the same (name, domain, path) as `c`
// (RFC 6265 identity). The jar holds at most one such, so we stop at
// the first hit; removal is swap-with-last (order is not significant —
// cookie_jar_header sorts on its own).
@ __jar_remove CookieJar j Cookie c → v {
    : ~ i k 0
    ~ < k ( vec_len [Cookie] . j cookies ) {
        : ~ b hit F
        ?? ( vec_get [Cookie] . j cookies k ) {
            T e → {
                ? & & ( string_eq . e name . c name ) ( string_eq . e domain . c domain ) ( string_eq . e path . c path ) {
                    ( __cookie_free e )
                    = hit T
                } {}
            }
            F _ → {}
        }
        ? hit {
            : i last - ( vec_len [Cookie] . j cookies ) 1
            ? > last k {
                ?? ( vec_get [Cookie] . j cookies last ) { T lc → { : b _s ( vec_set [Cookie] . j cookies k lc ) } F _ → {} }
            } {}
            : b _t ( vec_set_len [Cookie] . j cookies last )
            = k ( vec_len [Cookie] . j cookies )  // unique → done
        } { = k + k 1 }
    }
}

@ cookie_jar_set CookieJar j s setcookie s host s path i now → b {
    ^ ?? ( cookie_parse setcookie host path now ) {
        F _ → F
        T c → {
            ( __jar_remove j c )
            ? & != . c expires -1 <= . c expires now {
                ( __cookie_free c )  // already expired → deletion only
            } {
                ( vec_push [Cookie] . j cookies c )
            }
            T
        }
    }
}

@ __cookie_path_len CookieJar j i idx → i {
    ^ ?? ( vec_get [Cookie] . j cookies idx ) { T c → ( string_len . c path ) F _ → 0 }
}

// Insertion sort of `idxs` by cookie path length, longest first
// (RFC 6265 §5.4: more specific paths sort earlier). Stable on ties.
@ __sort_by_path_desc CookieJar j ( Vec i ) idxs → v {
    : i n ( vec_len [i] idxs )
    : ~ i i 1
    ~ < i n {
        : i cur ( __vget_i idxs i )
        : i curlen ( __cookie_path_len j cur )
        : ~ i jx - i 1
        ~ & >= jx 0 < ( __cookie_path_len j ( __vget_i idxs jx ) ) curlen {
            : b _s ( vec_set [i] idxs + jx 1 ( __vget_i idxs jx ) )
            = jx - jx 1
        }
        : b _t ( vec_set [i] idxs + jx 1 cur )
        = i + i 1
    }
}

@ cookie_jar_header CookieJar j s host s path b secure i now → String {
    : ( Vec i ) idxs ( vec_new [i] )
    : ~ i k 0
    ~ < k ( vec_len [Cookie] . j cookies ) {
        ?? ( vec_get [Cookie] . j cookies k ) {
            T c → {
                : ~ b keep T
                ? & != . c expires -1 <= . c expires now { = keep F } {}
                ? & . c secure ! secure { = keep F } {}
                ? keep { ? ( __domain_match host ( string_data . c domain ) . c host_only ) {} { = keep F } } {}
                ? keep { ? ( __path_match path ( string_data . c path ) ) {} { = keep F } } {}
                ? keep { ( vec_push [i] idxs k ) } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( __sort_by_path_desc j idxs )
    : String out ( string_with_cap 64 )
    : ~ i m 0
    ~ < m ( vec_len [i] idxs ) {
        ?? ( vec_get [Cookie] . j cookies ( __vget_i idxs m ) ) {
            T c → {
                ? > m 0 { ( string_push_str out `; ` ) } {}
                ( string_push_str out ( string_data . c name ) )
                ( string_push_char out 61 )  // '='
                ( string_push_str out ( string_data . c value ) )
            }
            F _ → {}
        }
        = m + m 1
    }
    ( vec_free [i] idxs )
    ^ out
}
