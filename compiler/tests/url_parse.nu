// url_parse.nu — std/url.nu acceptance: RFC 3986 component split,
// scheme defaults, request-target reconstruction, percent + query
// codecs, IPv6 and userinfo edge cases.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/url.nu`

@ show s url → v {
    ( nurl_print url ) ( nurl_print ` => ` )
    : ?Url p ( url_parse url )
    ?? p {
        T u → {
            ( nurl_print `scheme=` ) ( nurl_print ( string_data . u scheme ) )
            ( nurl_print ` user=` ) ( nurl_print ( string_data . u userinfo ) )
            ( nurl_print ` host=` ) ( nurl_print ( string_data . u host ) )
            ( nurl_print ` port=` ) ( nurl_print ( nurl_str_int . u port ) )
            ( nurl_print ` eff=` ) ( nurl_print ( nurl_str_int ( url_port_or_default u ) ) )
            ( nurl_print ` path=` ) ( nurl_print ( string_data . u path ) )
            ( nurl_print ` query=` ) ( nurl_print ( string_data . u query ) )
            ( nurl_print ` frag=` ) ( nurl_print ( string_data . u fragment ) )
            : String tgt ( url_request_target u )
            ( nurl_print ` target=` ) ( nurl_print ( string_data tgt ) )
            ( string_free tgt )
            ( nurl_print `\n` )
            ( url_free u )
        }
        F _ → ( nurl_print `NONE\n` )
    }
}

@ main → i {
    ( show `https://example.com/path/to/page?a=1&b=2#section` )
    ( show `http://example.com` )
    ( show `https://user:pass@host.example.org:8443/secure?token=abc` )
    ( show `ws://localhost:9001/chat` )
    ( show `wss://stream.example.com/feed` )
    ( show `https://[2001:db8::1]:8080/v6` )
    ( show `http://[::1]/loopback` )
    ( show `postgres://db.internal/mydb` )
    ( show `not-a-url` )
    ( show `ftp://files.example.com/pub/` )

    // percent codec
    : String enc ( url_percent_encode `a b/c?d=e&f` )
    ( nurl_print `encode='a b/c?d=e&f' => ` ) ( nurl_print ( string_data enc ) ) ( nurl_print `\n` )
    : String dec ( url_percent_decode ( string_data enc ) )
    ( nurl_print `decode roundtrip => ` ) ( nurl_print ( string_data dec ) ) ( nurl_print `\n` )
    ( string_free enc ) ( string_free dec )

    // query decode (form-urlencoded '+' → space, %xx)
    : ( Vec UrlParam ) ps ( url_query_decode `name=John+Doe&q=a%20b&flag&x=1` )
    ( nurl_print `query pairs:` )
    : i np ( vec_len [UrlParam] ps )
    : ~ i k 0
    ~ < k np {
        : ?UrlParam pp ( vec_get [UrlParam] ps k )
        ?? pp {
            T p → {
                ( nurl_print ` [` ) ( nurl_print ( string_data . p key ) )
                ( nurl_print `=` ) ( nurl_print ( string_data . p val ) ) ( nurl_print `]` )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( nurl_print `\n` )
    ( url_params_free ps )
    ^ 0
}
