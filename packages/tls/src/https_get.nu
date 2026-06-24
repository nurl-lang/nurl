// https_get — minimal HTTPS GET over the pure-NURL TLS 1.3 client.
//   https_get <host> <port> [path]

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `src/tls.nu`

@ arg ( Vec String ) a i idx s dflt → s {
    ?? ( vec_get [String] a idx ) { T v → ^ ( string_data v ) F _ → ^ dflt }
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    : s host ( arg args 1 `127.0.0.1` )
    : s ports ( arg args 2 `4433` )
    : i port ( nurl_str_to_int ports )
    : s path ( arg args 3 `/` )

    : !*TlsConn TlsErr r ( tls_connect host port host )
    ?? r {
        F e → {
            ( nurl_print `handshake failed: ` ) ( nurl_print ( tls_err_name e ) ) ( nurl_print `\n` )
            ^ 1
        }
        T c → {
            : String req ( string_new )
            ( string_push_str req `GET ` )
            ( string_push_str req path )
            ( string_push_str req ` HTTP/1.0\r\nHost: ` )
            ( string_push_str req host )
            ( string_push_str req `\r\nConnection: close\r\n\r\n` )
            : ( Vec u ) reqb ( bytes_from_str ( string_data req ) )
            : !v TlsErr w ( tls_write c reqb )
            ?? w { T _ → {} F we → { ( nurl_print `write failed\n` ) ( tls_close c ) ^ 1 } }
            ( vec_free [u] reqb )
            ( string_free req )

            : ~ i running 1
            : ~ i total 0
            ~ == running 1 {
                : !( Vec u ) TlsErr rd ( tls_read c 8192 )
                ?? rd {
                    F re → { ( nurl_print `\nread error: ` ) ( nurl_print ( tls_err_name re ) ) ( nurl_print `\n` ) = running 0 }
                    T chunk → {
                        : i n ( vec_len [u] chunk )
                        ? == n 0 { = running 0 } {
                            : String s ( bytes_to_str chunk )
                            ( nurl_print ( string_data s ) )
                            ( string_free s )
                            = total + total n
                        }
                        ( vec_free [u] chunk )
                    }
                }
            }
            ( nurl_print `\n--- ` ) ( nurl_print ( nurl_str_int total ) ) ( nurl_print ` bytes ---\n` )
            ( tls_close c )
            ^ 0
        }
    }
}
