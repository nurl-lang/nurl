// http_query_value: a query parameter read in place (stdlib/ext/
// http_request.nu, Agora #43) — query_value's raw view of the first value
// of a key, request_query_int's integer, and core/string.nu's
// slice_to_int under them. Nothing is decoded or allocated; parse_query
// stays the decoding path. Safe code only.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/http_request.nu`

@ show_value s qs s key → v {
    ( nurl_print `  ` )
    ( nurl_print key )
    ( nurl_print ` in "` )
    ( nurl_print qs )
    ( nurl_print `": ` )
    ?? ( query_value ( slice_of_str qs ) key ) {
        T v → {
            ( nurl_print `"` )
            ( write_slice v )
            ( nurl_print `"\n` )
        }
        F → ( nurl_print `none\n` )
    }
}

@ show_int s qs s key → v {
    : HttpRequest req ( request_new )
    = . req query ( string_from qs )
    ( nurl_print `  ` )
    ( nurl_print key )
    ( nurl_print ` in "` )
    ( nurl_print qs )
    ( nurl_print `": ` )
    ?? ( request_query_int req key ) {
        T x → {
            ( nurl_print_int x )
            ( nurl_print `\n` )
        }
        F → ( nurl_print `none\n` )
    }
}

@ show_parse s text i from i n → v {
    ( nurl_print `  "` )
    : ( Slice u ) w ( slice_window [u] ( slice_of_str text ) from n )
    ( write_slice w )
    ( nurl_print `": ` )
    ?? ( slice_to_int w ) {
        T x → {
            ( nurl_print_int x )
            ( nurl_print `\n` )
        }
        F e → {
            ( nurl_print ?? e { Empty → `Empty` BadFormat → `BadFormat` Overflow → `Overflow` _ → `other` } )
            ( nurl_print `\n` )
        }
    }
}

@ main → i {
    ( nurl_print `query_value\n` )
    ( show_value `min=10&max=50&limit=5` `max` )
    ( show_value `min=10&max=50&limit=5` `limit` )
    ( show_value `name=a%20b+c` `name` )
    ( show_value `flag&x=1` `flag` )
    ( show_value `limitx=1&xlimit=2&limit=3` `limit` )
    ( show_value `a=b=c` `a` )
    ( show_value `k=1&k=2` `k` )
    ( show_value `&&k=7&` `k` )
    ( show_value `k=` `k` )
    ( show_value `` `k` )
    ( show_value `kk=1` `k` )

    ( nurl_print `request_query_int\n` )
    ( show_int `queries=20` `queries` )
    ( show_int `x=1&queries=-3` `queries` )
    ( show_int `queries=+7` `queries` )
    ( show_int `queries=foo` `queries` )
    ( show_int `queries=` `queries` )
    ( show_int `queries` `queries` )
    ( show_int `queries=12x` `queries` )
    ( show_int `queries=9223372036854775807` `queries` )
    ( show_int `queries=9223372036854775808` `queries` )
    ( show_int `other=1` `queries` )

    ( nurl_print `slice_to_int\n` )
    ( show_parse `[123]` 1 3 )
    ( show_parse `x-45y` 1 3 )
    ( show_parse `--` 0 0 )
    ( show_parse `+` 0 1 )
    ( show_parse `1 2` 0 3 )
    ( show_parse `-9223372036854775808` 0 20 )
    ( show_parse `-9223372036854775809` 0 20 )
    ^ 0
}
