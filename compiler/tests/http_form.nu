// http_form.nu — acceptance test for parse_form_urlencoded +
// request_form_pairs (Phase 7 form-parsing close-out, see ROADMAP.md
// "Form parsing"). Pure offline: no socket, no filesystem reads.
//
// Coverage:
//   * parse_form_urlencoded — empty, single, multi, bare-key,
//     plus-substitution, percent-decode, empty value/key, multi-`=`,
//     trailing `&`, NUL-byte transparency.
//   * request_form_pairs — match, mismatch, missing header, mixed
//     case, Content-Type with charset parameter.

$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ println_str s prefix s value → v {
    ( nurl_print prefix )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ buf_from_str s src → ( Vec u ) {
    : i n ( nurl_str_len src )
    : ( Vec u ) buf ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n {
        : i c & 255 ( nurl_str_get src k )
        : u byte # u c
        ( vec_push [u] buf byte )
        = k + k 1
    }
    ^ buf
}

@ dump_pairs s prefix ( Vec QueryPair ) pairs → v {
    : i n ( vec_len [QueryPair] pairs )
    ( nurl_print prefix )
    ( nurl_print ` n=` )
    ( nurl_print_int n )
    : *QueryPair data ( vec_data [QueryPair] pairs )
    : ~ i k 0
    ~ < k n {
        : QueryPair p . data k
        ( nurl_print `    [` )
        ( nurl_print ( string_data . p key ) )
        ( nurl_print `]=[` )
        ( nurl_print ( string_data . p value ) )
        ( nurl_print `]\n` )
        = k + k 1
    }
}

@ make_req_form s ct s body → HttpRequest {
    : HttpRequest req ( request_new )
    ( string_push_str . req method `POST` )
    ( string_push_str . req path `/` )
    ( vec_push [Header] . req headers ( header_new `Content-Type` ct ) )
    : ( Vec u ) bb ( buf_from_str body )
    : i bn ( vec_len [u] bb )
    : ~ i k 0
    ~ < k bn {
        : i b ( __bbyte bb k )
        : u byte # u b
        ( vec_push [u] . req body byte )
        = k + k 1
    }
    ( vec_free [u] bb )
    ^ req
}

@ run_parse → v {
    ( nurl_print `── parse_form_urlencoded ──\n` )

    // 1. Empty buffer.
    : ( Vec u ) b1 ( buf_from_str `` )
    : ( Vec QueryPair ) p1 ( parse_form_urlencoded b1 )
    ( dump_pairs `  empty    ` p1 )
    ( query_pairs_free p1 )
    ( vec_free [u] b1 )

    // 2. Single pair.
    : ( Vec u ) b2 ( buf_from_str `name=alice` )
    : ( Vec QueryPair ) p2 ( parse_form_urlencoded b2 )
    ( dump_pairs `  single   ` p2 )
    ( query_pairs_free p2 )
    ( vec_free [u] b2 )

    // 3. Multiple pairs.
    : ( Vec u ) b3 ( buf_from_str `a=1&b=2&c=3` )
    : ( Vec QueryPair ) p3 ( parse_form_urlencoded b3 )
    ( dump_pairs `  multi    ` p3 )
    ( query_pairs_free p3 )
    ( vec_free [u] b3 )

    // 4. Bare key (no '=').
    : ( Vec u ) b4 ( buf_from_str `foo&bar=1` )
    : ( Vec QueryPair ) p4 ( parse_form_urlencoded b4 )
    ( dump_pairs `  bare     ` p4 )
    ( query_pairs_free p4 )
    ( vec_free [u] b4 )

    // 5. Plus -> space substitution.
    : ( Vec u ) b5 ( buf_from_str `q=hello+world&lang=fi+FI` )
    : ( Vec QueryPair ) p5 ( parse_form_urlencoded b5 )
    ( dump_pairs `  plus     ` p5 )
    ( query_pairs_free p5 )
    ( vec_free [u] b5 )

    // 6. Percent-decoded values (spaces, ampersands).
    : ( Vec u ) b6 ( buf_from_str `msg=a%20b%26c&u%C3%A4=v` )
    : ( Vec QueryPair ) p6 ( parse_form_urlencoded b6 )
    ( dump_pairs `  pct      ` p6 )
    ( query_pairs_free p6 )
    ( vec_free [u] b6 )

    // 7. Empty value.
    : ( Vec u ) b7 ( buf_from_str `k=&j=v` )
    : ( Vec QueryPair ) p7 ( parse_form_urlencoded b7 )
    ( dump_pairs `  empty_v  ` p7 )
    ( query_pairs_free p7 )
    ( vec_free [u] b7 )

    // 8. Empty key.
    : ( Vec u ) b8 ( buf_from_str `=v&k=2` )
    : ( Vec QueryPair ) p8 ( parse_form_urlencoded b8 )
    ( dump_pairs `  empty_k  ` p8 )
    ( query_pairs_free p8 )
    ( vec_free [u] b8 )

    // 9. Multiple '=' inside one segment — only the first splits.
    : ( Vec u ) b9 ( buf_from_str `expr=a=b=c&z=1` )
    : ( Vec QueryPair ) p9 ( parse_form_urlencoded b9 )
    ( dump_pairs `  multi_eq ` p9 )
    ( query_pairs_free p9 )
    ( vec_free [u] b9 )

    // 10. Trailing '&' — should not introduce a phantom empty pair.
    : ( Vec u ) bA ( buf_from_str `a=1&b=2&` )
    : ( Vec QueryPair ) pA ( parse_form_urlencoded bA )
    ( dump_pairs `  trailing ` pA )
    ( query_pairs_free pA )
    ( vec_free [u] bA )
}

@ try_request_form s ct s body s label → v {
    : HttpRequest req ( make_req_form ct body )
    : ?( Vec QueryPair ) opt ( request_form_pairs req )
    ?? opt {
        T pairs → {
            ( dump_pairs label pairs )
            ( query_pairs_free pairs )
        }
        F empty → {
            ( nurl_print label )
            ( nurl_print ` = None\n` )
            ( query_pairs_free empty )
        }
    }
    ( request_free req )
}

@ run_request_form → v {
    ( nurl_print `── request_form_pairs ──\n` )

    ( try_request_form `application/x-www-form-urlencoded`
    `name=alice&age=30`
    `  match    ` )

    ( try_request_form `application/json`
    `{"name":"alice"}`
    `  json     ` )

    ( try_request_form `Application/X-WWW-Form-UrlEncoded`
    `mixed=case`
    `  case     ` )

    ( try_request_form `application/x-www-form-urlencoded; charset=utf-8`
    `q=foo`
    `  charset  ` )

    // Missing Content-Type → None.
    : HttpRequest req ( request_new )
    ( string_push_str . req method `POST` )
    ( string_push_str . req path `/` )
    : ?( Vec QueryPair ) opt ( request_form_pairs req )
    ?? opt {
        T pairs → {
            ( nurl_print `  missing UNEXPECTED Some\n` )
            ( query_pairs_free pairs )
        }
        F empty → {
            ( nurl_print `  missing  = None\n` )
            ( query_pairs_free empty )
        }
    }
    ( request_free req )
}

@ main → i {
    ( run_parse )
    ( run_request_form )
    ^ 0
}
