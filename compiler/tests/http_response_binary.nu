// http_response_binary.nu — binary-safe HTTP response body round-trip.
//
// Companion to http_binary_body.nu (which covers the request side). A
// loopback NURL server replies with a 5-byte body `A B \0 C D`; the NURL
// client reads it with http_body_bytes and confirms the full length and
// the embedded NUL survive (http_body_str would truncate at byte 2).
// Results funnel through globals so the two-thread output is deterministic.
// Opens a loopback socket, hence `requires: live`.
// requires: live

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/core/vec.nu`

: ~ i g_len -1
: ~ i g_nul -1
: ~ i g_status -1

@ bin_handler HttpRequest r → HttpResponse {
    : HttpResponse resp ( response_new 200 )
    : ( Vec u ) body ( vec_new [u] )
    ( vec_push [u] body # u 65 )  // 'A'
    ( vec_push [u] body # u 66 )  // 'B'
    ( vec_push [u] body # u 0 )  // embedded NUL
    ( vec_push [u] body # u 67 )  // 'C'
    ( vec_push [u] body # u 68 )  // 'D'
    ( response_set_body_bytes resp body )  // copies the bytes
    ( vec_free [u] body )
    ^ resp
}

@ run_test → v {
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18942 )
    ?? lr {
        T listener → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse { ^ ( bin_handler req ) }
            : HttpServer srv ( server_new listener h )

            : ( @ v ) client \ → v {
                ( sleep_ms 250 )
                : !Response HttpErr rr ( http_get `http://127.0.0.1:18942/blob` )
                ?? rr {
                    T resp → {
                        = g_status ( http_status resp )
                        : ( Vec u ) body ( http_body_bytes resp )
                        = g_len ( vec_len [u] body )
                        : *u bp ( vec_data [u] body )
                        ? > ( vec_len [u] body ) 2 { = g_nul # i . bp 2 } {}
                        ( vec_free [u] body )
                        ( response_free resp )
                    }
                    F → { = g_status -2 }
                }
            }
            : !Thread ThreadErr ct ( thread_spawn client )

            : !v NetErr sr ( server_run_once srv )
            ?? sr { T _ → {} F e → { ( nurl_print `server_err=` ) ( nurl_print ( net_err_name e ) ) ( nurl_print `\n` ) } }
            ?? ct { T t → ( thread_join t ) F _ → {} }

            ( nurl_print `status=` ) ( nurl_println_int g_status )
            ( nurl_print `body_len=` ) ( nurl_println_int g_len )
            ( nurl_print `nul_at2=` ) ( nurl_println_int g_nul )
            ( nurl_print `done\n` )
        }
        F e → { ( nurl_print `listen_fail=` ) ( nurl_print ( net_err_name e ) ) ( nurl_print `\n` ) }
    }
}

@ main → i {
    ( run_test )
    ^ 0
}
