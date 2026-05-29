// http_options.nu — offline acceptance test for the HttpOptions struct
// in stdlib/ext/http.nu (ROADMAP §2 "HttpOptions struct").
//
// Pure-struct exercise: builds default + custom HttpOptions values,
// reads every field back, and runs the same timeout-defaulting and
// user-agent-fallback logic the libcurl orchestrator applies — all
// without touching the network or any HTTP backend, so it runs
// unconditionally (added to the http_* gate exemption in run_tests.sh).
//
// Determinism: no clock, no socket, no env. ASan-clean.

$ `stdlib/ext/http.nu`
$ `stdlib/core/string.nu`

@ yn i v → s { ^ ? != v 0 `T` `F` }

@ show_opts s label HttpOptions opt → v {
    : i tmo . opt timeout_ms
    : i cto . opt connect_timeout_ms
    : i follow . opt follow_redirects
    : i maxr . opt max_redirects
    : i verify . opt verify_tls
    : s ua . opt user_agent
    ( nurl_print label )
    ( nurl_print ` tmo=` )    ( nurl_print_int tmo )
    ( nurl_print ` cto=` )    ( nurl_print_int cto )
    ( nurl_print ` follow=` ) ( nurl_print ( yn follow ) )
    ( nurl_print ` maxr=` )   ( nurl_print_int maxr )
    ( nurl_print ` verify=` ) ( nurl_print ( yn verify ) )
    ( nurl_print ` ua=[` )    ( nurl_print ua )
    ( nurl_print `]\n` )
}

// Mirror the orchestrator's effective-value derivation so the test
// pins the exact defaulting rules (<=0 timeout → runtime default; empty
// user_agent → stock UA). Pass-by-value of the struct is exercised here.
@ effective_tmo HttpOptions opt → i {
    : i t . opt timeout_ms
    ^ ? <= t 0 30000 t
}
@ effective_cto HttpOptions opt → i {
    : i c . opt connect_timeout_ms
    ^ ? <= c 0 10000 c
}
@ effective_ua HttpOptions opt → s {
    : s u . opt user_agent
    : i has && != # i u 0 != ( nurl_str_len u ) 0
    ^ ? != has 0 u `nurl-http/0.1`
}

@ main → i {
    : HttpOptions d ( http_options_default )
    ( show_opts `default ` d )

    : HttpOptions c @ HttpOptions { 5000 2000 0 3 0 `my-agent/1.0` }
    ( show_opts `custom  ` c )

    ( nurl_print `eff(default) tmo=` ) ( nurl_print_int ( effective_tmo d ) )
    ( nurl_print ` cto=` )             ( nurl_print_int ( effective_cto d ) )
    ( nurl_print ` ua=` )              ( nurl_print ( effective_ua d ) )
    ( nurl_print `\n` )

    ( nurl_print `eff(custom)  tmo=` ) ( nurl_print_int ( effective_tmo c ) )
    ( nurl_print ` cto=` )             ( nurl_print_int ( effective_cto c ) )
    ( nurl_print ` ua=` )              ( nurl_print ( effective_ua c ) )
    ( nurl_print `\n` )

    ^ 0
}
