// url_parse_edges.nu — url.nu's byte-range edges, the cases a component
// copy or a decoder cursor would get wrong: a '%' escape cut short at a
// component's end, '+' in each decoder, '=' and '&' inside a query,
// empty parts, bracketed IPv6, the scheme's case and illegal characters.
// The golden was produced by the per-byte implementation this replaced.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/url.nu`

@ show s label s url → v {
    ( nurl_print label )
    ?? ( url_parse url ) {
        T u → {
            ( nurl_print `[` ) ( nurl_print ( string_data . u scheme ) )
            ( nurl_print `|` ) ( nurl_print ( string_data . u userinfo ) )
            ( nurl_print `|` ) ( nurl_print ( string_data . u host ) )
            ( nurl_print `|` ) ( nurl_print_int . u port )
            ( nurl_print `|` ) ( nurl_print ( string_data . u path ) )
            ( nurl_print `|` ) ( nurl_print ( string_data . u query ) )
            ( nurl_print `|` ) ( nurl_print ( string_data . u fragment ) )
            ( nurl_print `]\n` )
        }
        F _ → { ( nurl_print `none\n` ) }
    }
}

@ dec s label s in → v {
    : String d ( url_percent_decode in )
    ( nurl_print label ) ( nurl_print `[` ) ( nurl_print ( string_data d ) )
    ( nurl_print `] len ` ) ( nurl_print_int ( string_len d ) ) ( nurl_print `\n` )
}

@ qd s label s q → v {
    : ( Vec UrlParam ) ps ( url_query_decode q )
    ( nurl_print label ) ( nurl_print_int ( vec_len [UrlParam] ps ) )
    : ~ i k 0
    ~ < k ( vec_len [UrlParam] ps ) {
        ?? ( vec_get [UrlParam] ps k ) {
            T p → {
                ( nurl_print ` <` ) ( nurl_print ( string_data . p key ) )
                ( nurl_print `>=<` ) ( nurl_print ( string_data . p val ) ) ( nurl_print `>` )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( nurl_print `\n` )
}

@ main → i {
    ( show `case      ` `HTTP://Example.COM/A` )
    ( show `user      ` `http://u:p@h/x` )
    ( show `empty user` `http://@h/x` )
    ( show `two at    ` `http://a@b@h:81/` )
    ( show `ipv6      ` `http://[::1]` )
    ( show `ipv6 port ` `wss://[2001:db8::1]:9000/s?a#b` )
    ( show `bare colon` `http://h:/p` )
    ( show `big port  ` `http://h:99999/` )
    ( show `no path   ` `http://h?q=1#f` )
    ( show `frag ?    ` `http://h#f?x` )
    ( show `no host   ` `http:///p` )
    ( show `bad scheme` `ht tp://x` )
    ( show `digit sch ` `1x://h` )
    ( show `no sep    ` `http:/h` )
    ( dec `trail %   ` `100%` )
    ( dec `short %4  ` `a%4` )
    ( dec `bad hex   ` `%zz%41` )
    ( dec `plus      ` `a+b` )
    ( dec `%%41      ` `%%41` )
    ( dec `nul       ` `a%00b` )
    ( qd `edges     ` `k%=v%2&%3D=%26&a=b=c&=v&&x=1&` )
    ( qd `plus      ` `a+b=c+d%2B` )
    ( qd `empty     ` `` )
    ^ 0
}
