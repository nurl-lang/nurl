// cookies_basic.nu — ext/cookies.nu (HTTP client cookie jar) acceptance.
//
// Deterministic: `now` is passed explicitly so Max-Age / Expires resolve
// the same everywhere. Covers host-only vs Domain matching, path
// matching + longest-path-first ordering, Secure gating, Max-Age and
// Expires expiry, replacement, and Max-Age=0 deletion.

$ `stdlib/core/string.nu`
$ `stdlib/ext/cookies.nu`

@ show s label CookieJar j s host s path b secure i now → v {
    : String h ( cookie_jar_header j host path secure now )
    ( nurl_print label ) ( nurl_print `=[` ) ( nurl_print ( string_data h ) ) ( nurl_print `]\n` )
    ( string_free h )
}

@ setok s label CookieJar j s sc s host s path i now → v {
    ( nurl_print label ) ( nurl_print `=` )
    ( nurl_print ? ( cookie_jar_set j sc host path now ) `ok` `bad` ) ( nurl_print `\n` )
}

@ main → i {
    // ── host-only vs Domain ──
    : CookieJar j1 ( cookie_jar_new )
    ( setok `set_sid` j1 `sid=abc123` `example.com` `/` 1000 )
    ( setok `set_dom` j1 `pref=dark; Domain=example.com` `www.example.com` `/` 1000 )
    ( show `exact` j1 `example.com` `/` F 1000 )           // sid (host-only) + pref (domain)
    ( show `www_sub` j1 `www.example.com` `/` F 1000 )     // only pref (sid is host-only to example.com)
    ( show `other` j1 `evil.com` `/` F 1000 )              // none
    ( nurl_print `count1=` ) ( nurl_print ( nurl_str_int ( cookie_jar_count j1 ) ) ) ( nurl_print `\n` )
    ( cookie_jar_free j1 )

    // ── path matching + longest-path-first ──
    : CookieJar j2 ( cookie_jar_new )
    ( setok `set_root` j2 `p=root; Path=/` `ex.com` `/` 1000 )
    ( setok `set_deep` j2 `q=deep; Path=/a/b` `ex.com` `/a/b` 1000 )
    ( show `at_deep` j2 `ex.com` `/a/b` F 1000 )           // q then p (longer path first)
    ( show `at_root` j2 `ex.com` `/` F 1000 )              // only p
    ( show `at_a` j2 `ex.com` `/a` F 1000 )                // only p (/a/b doesn't match /a)
    ( cookie_jar_free j2 )

    // ── Secure gating ──
    : CookieJar j3 ( cookie_jar_new )
    ( setok `set_sec` j3 `t=tok; Secure` `ex.com` `/` 1000 )
    ( show `insecure` j3 `ex.com` `/` F 1000 )             // empty
    ( show `secure` j3 `ex.com` `/` T 1000 )               // t=tok
    ( cookie_jar_free j3 )

    // ── Max-Age expiry + deletion ──
    : CookieJar j4 ( cookie_jar_new )
    ( setok `set_ma` j4 `e=5; Max-Age=100` `ex.com` `/` 1000 )
    ( show `before_exp` j4 `ex.com` `/` F 1050 )           // e=5
    ( show `after_exp` j4 `ex.com` `/` F 1200 )            // empty (expired)
    ( setok `set_again` j4 `e=5; Max-Age=100` `ex.com` `/` 1000 )
    ( setok `delete_e` j4 `e=; Max-Age=0` `ex.com` `/` 1000 )
    ( nurl_print `count4=` ) ( nurl_print ( nurl_str_int ( cookie_jar_count j4 ) ) ) ( nurl_print `\n` )  // 0
    ( cookie_jar_free j4 )

    // ── replacement keeps one entry ──
    : CookieJar j5 ( cookie_jar_new )
    ( setok `set_v1` j5 `s=v1` `ex.com` `/` 1000 )
    ( setok `set_v2` j5 `s=v2` `ex.com` `/` 1000 )
    ( show `replaced` j5 `ex.com` `/` F 1000 )             // s=v2
    ( nurl_print `count5=` ) ( nurl_print ( nurl_str_int ( cookie_jar_count j5 ) ) ) ( nurl_print `\n` )  // 1
    ( cookie_jar_free j5 )

    // ── Expires (HTTP-date) ──
    : CookieJar j6 ( cookie_jar_new )
    ( setok `set_exp` j6 `g=6; Expires=Wed, 09 Jun 2021 10:18:14 GMT` `ex.com` `/` 0 )
    ( show `pre2021` j6 `ex.com` `/` F 0 )                 // g=6 (now=0 is before 2021)
    ( show `post2021` j6 `ex.com` `/` F 2000000000 )       // empty (now in 2033)
    ( cookie_jar_free j6 )

    // ── malformed → bad, nothing stored ──
    : CookieJar j7 ( cookie_jar_new )
    ( setok `set_bad` j7 `=novalue` `ex.com` `/` 1000 )
    ( nurl_print `count7=` ) ( nurl_print ( nurl_str_int ( cookie_jar_count j7 ) ) ) ( nurl_print `\n` )  // 0
    ( cookie_jar_free j7 )
    ^ 0
}
