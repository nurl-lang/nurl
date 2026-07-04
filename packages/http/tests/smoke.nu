// tests/smoke.nu — a minimal server built with the HttpApp facade. Drives
// routing, path params, a POST body echo, static fallback, CORS and the
// panic→500 recovery. The test harness (http_test.sh) curls it.
//
//   smoke --port N [--webroot DIR]

$ `stdlib/std/args.nu`
$ `src/http.nu`

@ h_hi HttpRequest req Params p → HttpResponse {
    : String out ( string_from `hi ` )
    ?? ( params_get p `name` ) {
        T nm → { ( string_push_str out ( string_data nm ) ) ( string_free nm ) }
        F junk → { ( string_free junk ) }
    }
    : HttpResponse r ( response_text 200 ( string_data out ) )
    ( string_free out )
    ^ r
}

@ h_echo HttpRequest req Params p → HttpResponse {
    : String body ( bytes_to_str . req body )
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( response_set_body_str r ( string_data body ) )
    ( string_free body )
    ^ r
}

@ h_boom HttpRequest req Params p → HttpResponse {
    ( nurl_panic `boom` )
    ^ ( response_text 200 `unreachable` )
}

@ main → i {
    : ArgParser ap ( args_new `smoke` `http facade smoke server` )
    ( args_opt ap `port` 112 `N` `bind port on 127.0.0.1` )
    ( args_opt ap `webroot` 119 `DIR` `static dir` )
    ? ( args_parse_argv ap ) {} { ( args_free ap ) ^ 2 }

    : ~ i port 8099
    : ?String pv ( args_value ap `port` )
    ?? pv {
        T v → { ?? ( string_to_int v ) { T x → { = port x } F _ → {} } ( string_free v ) }
        F junk → { ( string_free junk ) }
    }

    : *HttpApp a ( http_app_new )
    ( http_app_cors a )
    ( http_app_logging a )
    ( http_app_get a `/` \ HttpRequest req Params p → HttpResponse { ^ ( response_text 200 `hello from http` ) } )
    ( http_app_get a `/hi/:name` \ HttpRequest req Params p → HttpResponse { ^ ( h_hi req p ) } )
    ( http_app_post a `/echo` \ HttpRequest req Params p → HttpResponse { ^ ( h_echo req p ) } )
    ( http_app_get a `/boom` \ HttpRequest req Params p → HttpResponse { ^ ( h_boom req p ) } )

    : ?String wv ( args_value ap `webroot` )
    ?? wv {
        T w → { ( http_app_static_dir a ( string_data w ) ) ( string_free w ) }
        F junk → { ( string_free junk ) }
    }

    : i rc ( http_app_listen a `127.0.0.1` port )
    ( http_app_free a )
    ( args_free ap )
    ^ rc
}
