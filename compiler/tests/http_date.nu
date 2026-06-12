// http_date.nu — std/time.nu §12c HTTP-date / RFC 2822 parsing.
//
// RFC 7231 §7.1.1.1 gives the three equivalent spellings of the same
// instant (Sun, 06 Nov 1994 08:49:37 GMT = 784111777). All three must
// parse to that value. RFC 2822 adds a numeric zone. Also checks a
// round-trip against time_format_http and a few rejects.

$ `stdlib/core/string.nu`
$ `stdlib/std/time.nu`

@ show s label s input → v {
    ( nurl_print label ) ( nurl_print `: ` )
    : !i ParseErr r ( http_date_parse input )
    ?? r {
        T secs → ( nurl_print ( nurl_str_int secs ) )
        F _ → ( nurl_print `PARSE_ERR` )
    }
    ( nurl_print `\n` )
}

@ show2822 s label s input → v {
    ( nurl_print label ) ( nurl_print `: ` )
    : !i ParseErr r ( rfc2822_parse input )
    ?? r {
        T secs → ( nurl_print ( nurl_str_int secs ) )
        F _ → ( nurl_print `PARSE_ERR` )
    }
    ( nurl_print `\n` )
}

@ main → i {
    // RFC 7231 §7.1.1.1 — the three forms of 784111777
    ( show `imf` `Sun, 06 Nov 1994 08:49:37 GMT` )
    ( show `rfc850` `Sunday, 06-Nov-94 08:49:37 GMT` )
    ( show `asctime` `Sun Nov  6 08:49:37 1994` )

    // Epoch + a modern date
    ( show `epoch` `Thu, 01 Jan 1970 00:00:00 GMT` )
    ( show `modern` `Wed, 06 May 2026 17:30:45 GMT` )

    // RFC 2822 email Date with numeric zones
    ( show2822 `utc_off` `Mon, 02 Jan 2006 15:04:05 +0000` )
    ( show2822 `neg_off` `Mon, 02 Jan 2006 15:04:05 -0700` )   // == 22:04:05 UTC
    ( show2822 `pos_off` `Mon, 02 Jan 2006 15:04:05 +0530` )
    ( show2822 `no_dow` `2 Jan 2006 15:04:05 GMT` )            // day-of-week optional

    // round-trip: parse → format → must equal input
    : !i ParseErr rt ( http_date_parse `Fri, 31 Dec 1999 23:59:59 GMT` )
    ?? rt {
        T secs → {
            : Time t ( time_from_unix secs )
            : String back ( time_format_http t )
            ( nurl_print `roundtrip: ` ) ( nurl_print ( string_data back ) )
            ( nurl_print ` == ` )
            ( nurl_print ? ( __seq ( string_data back ) `Fri, 31 Dec 1999 23:59:59 GMT` ) `T` `F` )
            ( nurl_print `\n` )
            ( string_free back )
        }
        F _ → ( nurl_print `roundtrip PARSE_ERR\n` )
    }

    // rejects
    ( show `bad_month` `Sun, 06 Xyz 1994 08:49:37 GMT` )       // bad month → ERR
    ( show `garbage` `not a date at all` )
    ( show2822 `missing_zone` `Mon, 02 Jan 2006 15:04:05` )    // RFC 2822 needs a zone

    ^ 0
}

@ __seq s a s b → b {
    : i la ( nurl_str_len a )
    ? != la ( nurl_str_len b ) { ^ F } {}
    : ~ i k 0
    ~ < k la { ? != ( nurl_str_get a k ) ( nurl_str_get b k ) { ^ F } {} = k + k 1 }
    ^ T
}
