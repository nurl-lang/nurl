// examples/h2_client.nu — native HTTP/2 CLIENT over TLS (ALPN "h2").
//
// Dials a real HTTPS/2 server, negotiates h2 via ALPN, and issues TWO
// concurrent requests multiplexed over the SAME connection — printing
// each status line + the first bytes of each body.
//
//   ./nurl.sh examples/h2_client.nu
//
// Requires the runtime built with OpenSSL (build.sh auto-detects it).
// Default target is cloudflare's HTTP/2 endpoint; override with argv[1].

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/net.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http2_client.nu`

@ print_resp s label HttpResponse r → v {
    ( nurl_print label )
    ( nurl_print ` status=` )
    : String s ( string_new )
    ( string_push_int s . r status )
    ( nurl_print ( string_data s ) )
    ( string_free s )
    ( nurl_print ` bytes=` )
    : String n ( string_new )
    ( string_push_int n ( vec_len [u] . r body ) )
    ( nurl_print ( string_data n ) )
    ( string_free n )
    ( nurl_print `\n` )
}

@ main → i {
    ( runtime_init 0 )
    : s host `www.cloudflare.com`
    : i port 443

    : !H2Client H2ClientErr cr ( h2_client_connect_tls host port T )
    ?? cr {
        T client → {
            // Two concurrent streams over one h2 connection.
            : ( Vec Header ) h1 ( vec_new [Header] )
            : ( Vec u ) b1 ( vec_new [u] )
            : !i H2ClientErr s1 ( h2_client_submit client `GET` `https`
            host `/` h1 b1 )
            ( vec_free_with [Header] h1 \ Header hh → v { ( header_free hh ) } )

            : ( Vec Header ) h2 ( vec_new [Header] )
            : ( Vec u ) b2 ( vec_new [u] )
            : !i H2ClientErr s2 ( h2_client_submit client `GET` `https`
            host `/robots.txt` h2 b2 )
            ( vec_free_with [Header] h2 \ Header hh → v { ( header_free hh ) } )

            : !v H2ClientErr rr ( h2_client_run_until_complete client )
            ?? rr {
                T _ → {
                    ?? s1 {
                        T sid1 → {
                            : !HttpResponse H2ClientErr t1 ( h2_client_take_response client sid1 )
                            ?? t1 {
                                T resp → { ( print_resp `GET /` resp ) ( http_response_free resp ) }
                                F e → { ( nurl_print `take1 err: ` ) ( nurl_print ( h2_client_err_name e ) ) ( nurl_print `\n` ) }
                            }
                        }
                        F _ → {}
                    }
                    ?? s2 {
                        T sid2 → {
                            : !HttpResponse H2ClientErr t2 ( h2_client_take_response client sid2 )
                            ?? t2 {
                                T resp → { ( print_resp `GET /robots.txt` resp ) ( http_response_free resp ) }
                                F e → { ( nurl_print `take2 err: ` ) ( nurl_print ( h2_client_err_name e ) ) ( nurl_print `\n` ) }
                            }
                        }
                        F _ → {}
                    }
                }
                F e → {
                    ( nurl_print `run err: ` ) ( nurl_print ( h2_client_err_name e ) ) ( nurl_print `\n` )
                }
            }
            ( h2_client_disconnect client )
        }
        F e → {
            ( nurl_print `connect err: ` )
            ( nurl_print ( h2_client_err_name e ) )
            ( nurl_print `\n` )
            ^ 1
        }
    }
    ^ 0
}
