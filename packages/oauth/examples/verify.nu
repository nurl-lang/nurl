// examples/verify.nu — is this token real, and who does it name?
//
// The verifying half of the package on its own: give it an issuer and a
// token, and it fetches that issuer's metadata and keys, checks the
// signature and every claim, and prints the identity — or says exactly
// what was wrong.
//
//   verify --issuer https://accounts.example.com \
//          --audience <client-id-or-api> \
//          --token <jwt>            (or --token-file <path>)
//          [--scope <required-scope>] [--algs "RS256 ES256"]
//
// This is what a resource server does on every request; the same call is
// wrapped for HTTP routes by `with_oidc_bearer` (see protected_api.nu).
// Exit status is 0 for a token that verifies, 1 for one that does not —
// so it composes into a shell pipeline as a check.

$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`
$ `../src/oauth.nu`

@ main → i {
    : ArgParser ap ( args_new `verify` `verify an OIDC token and print its claims` )
    ( args_opt ap `issuer` 105 `URL` `the issuer that minted the token` )
    ( args_opt ap `audience` 97 `AUD` `the audience the token must name (this client / API)` )
    ( args_opt ap `token` 116 `JWT` `the token itself` )
    ( args_opt ap `token-file` 102 `PATH` `read the token from a file instead` )
    ( args_opt ap `scope` 111 `SCOPE` `also require this scope` )
    ( args_opt ap `algs` 108 `LIST` `restrict the accepted algorithms` )
    ? ( args_parse_argv ap ) {} { ( args_free ap ) ^ 2 }

    : String issuer ( args_value_or ap `issuer` `` )
    : String audience ( args_value_or ap `audience` `` )
    : ~ String token ( args_value_or ap `token` `` )
    : String token_file ( args_value_or ap `token-file` `` )
    : String want_scope ( args_value_or ap `scope` `` )
    : String algs ( args_value_or ap `algs` `` )
    ( args_free ap )

    ? > ( string_len token_file ) 0 {
        ?? ( read_file ( string_data token_file ) ) {
            T contents → {
                ( string_free token )
                = token ( string_trim contents )
                ( string_free contents )
            }
            F _ → { ( nurl_eprintln `verify: cannot read the token file` ) }
        }
    } {}

    ? | == 0 ( string_len issuer ) == 0 ( string_len token ) {
        ( nurl_eprintln `verify: --issuer and --token (or --token-file) are required` )
        ^ 2
    } {}

    : ~ i rc 1
    ?? ( oidc_provider_discover ( string_data issuer ) ) {
        F e → {
            ( nurl_eprintln ( oauth_err_name e ) )
        }
        T p → {
            : *OidcPolicy pol ( oidc_policy_new ( string_data issuer ) ( string_data audience ) )
            ? > ( string_len algs ) 0 { ( oidc_policy_set_algs pol ( string_data algs ) ) } {}
            ?? ( oidc_verify_token p pol ( string_data token ) ) {
                F e → {
                    : String m ( string_from `INVALID (` )
                    ( string_push_str m ( oauth_err_name e ) )
                    ( string_push_str m `): ` )
                    ( string_push_str m ( oidc_provider_last_error p ) )
                    ( nurl_println ( string_data m ) )
                    ( string_free m )
                }
                T id → {
                    : ~ b allowed T
                    ? > ( string_len want_scope ) 0 {
                        = allowed ( oidc_identity_has_scope id ( string_data want_scope ) )
                    } {}
                    ? allowed {
                        : String desc ( oidc_identity_describe id )
                        : String m ( string_from `VALID — ` )
                        ( string_push_str m ( string_data desc ) )
                        ( nurl_println ( string_data m ) )
                        ( string_free m ) ( string_free desc )
                        : String pretty ( json_pretty . id claims )
                        ( nurl_println ( string_data pretty ) )
                        ( string_free pretty )
                        = rc 0
                    } {
                        : String m ( string_from `VALID, but without the scope ` )
                        ( string_push_str m ( string_data want_scope ) )
                        ( nurl_println ( string_data m ) )
                        ( string_free m )
                    }
                    ( oidc_identity_free id )
                }
            }
            ( oidc_policy_free pol )
            ( oidc_provider_free p )
        }
    }
    ( string_free issuer ) ( string_free audience ) ( string_free token )
    ( string_free token_file ) ( string_free want_scope ) ( string_free algs )
    ^ rc
}
