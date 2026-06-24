// tlsget — fetch an HTTPS URL over the pure-NURL TLS client and print the
// response. The installable binary for the `tls` package.
//
//   tlsget https://example.com/          (verify-full, the default)
//   tlsget example.com 443 /             (host / port / path form)
//   tlsget --insecure https://self-signed.example/   (skip cert check)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `tls.nu`

// Split "https://host[:port]/path" → (host, port, path). Bare "host"
// works too. Defaults: scheme https, port 443, path "/".
@ __parse_url s url String host String path → i {
    : ~ i p 0
    : i n ( nurl_str_len url )
    // skip scheme
    ? ( nurl_str_starts url `https://` ) { = p 8 } {}
    ? ( nurl_str_starts url `http://` ) { = p 7 } {}
    : ~ i port 443
    : ~ i hostend p
    ~ & < hostend n & != ( nurl_str_get url hostend ) 47 != ( nurl_str_get url hostend ) 58 { = hostend + hostend 1 }
    : ~ i k p
    ~ < k hostend { ( string_push_char host ( nurl_str_get url k ) ) = k + k 1 }
    // optional :port
    : ~ i q hostend
    ? & < q n == ( nurl_str_get url q ) 58 {
        = q + q 1
        : ~ i pv 0
        ~ & < q n != ( nurl_str_get url q ) 47 { = pv + * pv 10 - ( nurl_str_get url q ) 48 = q + q 1 }
        = port pv
    } {}
    // path (rest), default "/"
    ? < q n { : ~ i r q ~ < r n { ( string_push_char path ( nurl_str_get url r ) ) = r + r 1 } } { ( string_push_str path `/` ) }
    ? == 0 ( string_len path ) { ( string_push_str path `/` ) } {}
    ^ port
}

@ __fetch s host i port s path b insecure → i {
    : !*TlsConn TlsErr r ? insecure ( tls_connect_insecure host port host ) ( tls_connect host port host )
    ?? r {
        F e → {
            ( nurl_eprint `tlsget: ` ) ( nurl_eprint ( tls_err_name e ) ) ( nurl_eprint `\n` )
            ^ 1
        }
        T c → {
            : String req ( string_new )
            ( string_push_str req `GET ` )
            ( string_push_str req path )
            ( string_push_str req ` HTTP/1.0\r\nHost: ` )
            ( string_push_str req host )
            ( string_push_str req `\r\nConnection: close\r\nUser-Agent: tlsget/0.1\r\n\r\n` )
            : ( Vec u ) reqb ( bytes_from_str ( string_data req ) )
            : !v TlsErr w ( tls_write c reqb )
            ( vec_free [u] reqb )
            ( string_free req )
            ?? w { T _ → {} F _ → { ( tls_close c ) ^ 1 } }
            : ~ i run 1
            ~ == run 1 {
                ?? ( tls_read c 8192 ) {
                    F re → { ( nurl_eprint `tlsget: read ` ) ( nurl_eprint ( tls_err_name re ) ) ( nurl_eprint `\n` ) = run 0 }
                    T chunk → {
                        ? == 0 ( vec_len [u] chunk ) { = run 0 } {
                            : String s ( bytes_to_str chunk )
                            ( nurl_print ( string_data s ) )
                            ( string_free s )
                        }
                        ( vec_free [u] chunk )
                    }
                }
            }
            ( tls_close c )
            ^ 0
        }
    }
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    : i argc ( vec_len [String] args )
    : ~ b insecure F
    : ~ i ai 1
    ?? ( vec_get [String] args 1 ) {
        T a0 → { ? ( nurl_str_eq ( string_data a0 ) `--insecure` ) { = insecure T = ai 2 } {} }
        F _ → {}
    }
    ? >= ai argc {
        ( nurl_eprint `usage: tlsget [--insecure] <url|host> [port] [path]\n` )
        ^ 2
    } {}
    : String host ( string_new )
    : String path ( string_new )
    : ~ i port 443
    ?? ( vec_get [String] args ai ) {
        T uv → {
            : s u ( string_data uv )
            ? | ( nurl_str_starts u `http` ) ? < + ai 1 argc 0 1 {
                = port ( __parse_url u host path )
            } {
                ( string_push_str host u )
                ?? ( vec_get [String] args + ai 1 ) { T pv → = port ( nurl_str_to_int ( string_data pv ) ) F _ → {} }
                ?? ( vec_get [String] args + ai 2 ) { T pp → ( string_push_str path ( string_data pp ) ) F _ → ( string_push_str path `/` ) }
            }
        }
        F _ → {}
    }
    ? == 0 ( string_len path ) { ( string_push_str path `/` ) } {}
    ^ ( __fetch ( string_data host ) port ( string_data path ) insecure )
}
