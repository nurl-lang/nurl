// examples/login.nu — log in with a browser, and print who logged in.
//
// The complete OpenID Connect authorization-code flow with PKCE, as a
// command-line program:
//
//   1. discover the provider,
//   2. mint a PKCE verifier, a state and a nonce,
//   3. print the authorization URL (open it in a browser),
//   4. listen on 127.0.0.1:<port> for the redirect back,
//   5. exchange the code for tokens,
//   6. VERIFY the ID token against the provider's published keys, and
//   7. print the identity and the full claim set.
//
//   login --issuer https://accounts.example.com \
//         --client-id <id> [--client-secret <secret>] \
//         [--scope "openid profile email"] [--port 8765]
//
// The redirect URI is http://127.0.0.1:<port>/callback — register that
// with the provider. A loopback redirect plus PKCE is the OAuth 2.1
// shape for a native/CLI client: no secret is required, and a code that
// leaks is useless without the verifier that never left this process.

$ `stdlib/std/args.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `../src/oauth.nu`

// The request target of the first line: "GET <target> HTTP/1.1".
@ request_target ( Vec u ) buf → String {
    : String head ( bytes_to_str buf )
    : i n ( string_len head )
    : ~ i start 0
    ~ & < start n != ( string_get head start ) 32 { = start + start 1 }
    = start + start 1
    : ~ i end start
    ~ & < end n != ( string_get head end ) 32 { = end + end 1 }
    : String out ( string_substr head start - end start )
    ( string_free head )
    ^ out
}

// The query part of "/callback?code=…", or "".
@ target_query String target → String {
    ?? ( string_index_of target `?` ) {
        T q → { ^ ( string_substr target + q 1 - ( string_len target ) + q 1 ) }
        F _ → { ^ ( string_new ) }
    }
}

// Accept one browser request, answer it, and hand back its query string.
// Requests for anything but the callback path (a browser's favicon
// probe, say) are answered 404 and waited past.
@ await_redirect TcpListener l → String {
    : ~ ( Vec u ) head ( vec_new [u] )
    : ~ String out ( string_new )
    : ~ b waiting T
    ~ waiting {
        ?? ( tcp_accept l ) {
            F _ → { = waiting F }
            T c → {
                ( vec_free [u] head )
                = head ( vec_new [u] )
                : ~ b reading T
                ~ reading {
                    ?? ( tcp_read_chunk c 4096 ) {
                        T chunk → {
                            ? == 0 ( vec_len [u] chunk ) { = reading F } {}
                            ( bytes_extend_bytes head chunk )
                            ( vec_free [u] chunk )
                            : ( Vec u ) mark ( bytes_from_str `\r\n\r\n` )
                            ?? ( bytes_index_of head mark ) {
                                T _ → { = reading F }
                                F _ → {}
                            }
                            ( vec_free [u] mark )
                            ? > ( vec_len [u] head ) 65536 { = reading F } {}
                        }
                        F _ → { = reading F }
                    }
                }
                : String target ( request_target head )
                : String q ( target_query target )
                ? > ( string_len q ) 0 {
                    : !v NetErr _w ( tcp_write_str c `HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\nContent-Length: 62\r\n\r\n<html><body><h3>Signed in. You can close this tab.</h3></body>` )
                    ( string_free out )
                    = out q
                    = waiting F
                } {
                    : !v NetErr _w ( tcp_write_str c `HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n` )
                    ( string_free q )
                }
                ( string_free target )
                ( tcp_close_conn c )
            }
        }
    }
    ( vec_free [u] head )
    ^ out
}

@ say s label String value → v {
    : String m ( string_from label )
    ( string_push_str m ( string_data value ) )
    ( nurl_println ( string_data m ) )
    ( string_free m )
}

@ main → i {
    : ArgParser ap ( args_new `login` `OpenID Connect login, on the command line` )
    ( args_opt ap `issuer` 105 `URL` `the provider's issuer URL` )
    ( args_opt ap `client-id` 99 `ID` `the OAuth client id` )
    ( args_opt ap `client-secret` 115 `SECRET` `client secret (omit for a public client)` )
    ( args_opt ap `scope` 111 `SCOPE` `requested scope (default: openid profile email)` )
    ( args_opt ap `port` 112 `N` `loopback redirect port (default 8765)` )
    ? ( args_parse_argv ap ) {} { ( args_free ap ) ^ 2 }

    : String issuer ( args_value_or ap `issuer` `` )
    : String client_id ( args_value_or ap `client-id` `` )
    : String secret ( args_value_or ap `client-secret` `` )
    : String scope ( args_value_or ap `scope` `openid profile email` )
    : String port_s ( args_value_or ap `port` `8765` )
    ( args_free ap )
    : ~ i port 8765
    ?? ( string_to_int port_s ) { T x → { = port x } F _ → {} }
    ( string_free port_s )

    ? | == 0 ( string_len issuer ) == 0 ( string_len client_id ) {
        ( nurl_eprintln `login: --issuer and --client-id are required` )
        ^ 2
    } {}

    : String redirect ( string_from `http://127.0.0.1:` )
    ( string_push_int redirect port )
    ( string_push_str redirect `/callback` )

    // 1. Who is the provider?
    : ~ i rc 1
    ?? ( oidc_provider_discover ( string_data issuer ) ) {
        F e → { ( nurl_eprintln ( oauth_err_name e ) ) }
        T p → {
            : *OauthConfig cfg ( oauth_config_new ( string_data client_id ) ( string_data redirect ) ( string_data scope ) )
            ? > ( string_len secret ) 0 { ( oauth_config_set_secret cfg ( string_data secret ) ) } {}

            // 2. The three one-use secrets.
            : Pkce pk ( pkce_new )
            : String state ( oauth_state_new )
            : String nonce ( oauth_nonce_new )

            // 3. Send the user.
            : String url ( oauth_authorize_url p cfg ( string_data state ) ( string_data nonce ) pk )
            ( nurl_println `Open this URL in a browser to sign in:` )
            ( nurl_println `` )
            ( nurl_println ( string_data url ) )
            ( nurl_println `` )
            ( string_free url )

            // 4. Wait for the redirect back.
            ?? ( tcp_listen `127.0.0.1` port ) {
                F _ → { ( nurl_eprintln `login: cannot bind the redirect port` ) }
                T l → {
                    ( say `Listening on ` redirect )
                    : String query ( await_redirect l )
                    ( tcp_close_listener l )

                    // 5. The code — but only if it answers OUR request.
                    ?? ( oauth_callback_code ( string_data query ) ( string_data state ) ) {
                        F e → { ( nurl_eprintln ( oauth_err_name e ) ) }
                        T code → {
                            ?? ( oauth_exchange_code p cfg ( string_data code ) ( string_data . pk verifier ) ) {
                                F e → {
                                    ( nurl_eprintln ( oauth_err_name e ) )
                                    ( nurl_eprintln ( oidc_provider_last_error p ) )
                                }
                                T ts → {
                                    // 6. Verify — this is the step that
                                    // turns bytes into an identity.
                                    : *OidcPolicy pol ( oidc_policy_new ( string_data issuer ) ( string_data client_id ) )
                                    ( oidc_policy_set_nonce pol ( string_data nonce ) )
                                    ?? ( oidc_verify_id_token p pol ( token_set_id_token ts ) ) {
                                        F e → {
                                            ( nurl_eprintln ( oauth_err_name e ) )
                                            ( nurl_eprintln ( oidc_provider_last_error p ) )
                                        }
                                        T id → {
                                            // 7. Who logged in.
                                            : String desc ( oidc_identity_describe id )
                                            ( nurl_println `` )
                                            ( say `Signed in: ` desc )
                                            ( string_free desc )
                                            : String key ( oidc_identity_key id )
                                            ( say `Identity:  ` key )
                                            ( string_free key )
                                            ( nurl_println `` )
                                            ( nurl_println `Claims:` )
                                            : String pretty ( json_pretty . id claims )
                                            ( nurl_println ( string_data pretty ) )
                                            ( string_free pretty )
                                            ( oidc_identity_free id )
                                            = rc 0
                                        }
                                    }
                                    ( oidc_policy_free pol )
                                    ( token_set_free ts )
                                }
                            }
                            ( string_free code )
                        }
                    }
                    ( string_free query )
                }
            }
            ( string_free state )
            ( string_free nonce )
            ( pkce_free pk )
            ( oauth_config_free cfg )
            ( oidc_provider_free p )
        }
    }
    ( string_free issuer ) ( string_free client_id ) ( string_free secret )
    ( string_free scope ) ( string_free redirect )
    ^ rc
}
