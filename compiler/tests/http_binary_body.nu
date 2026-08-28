// http_binary_body.nu — binary-safe HTTP request body round-trip.
//
// Regression for the request-body NUL-truncation bug: the s-body
// http_request_* family recovers the body length via strlen, so a body
// with an embedded NUL byte truncates at the first NUL. The new
// http_post_bytes / http_request_bytes family carries the body as a
// length-tracked ( Vec u ) and ships it via CURLOPT_COPYPOSTFIELDS +
// an explicit POSTFIELDSIZE, so the exact byte count is sent.
//
// Shape: a NURL HTTP server runs one accept on loopback; a separate
// pthread POSTs a 5-byte body `A B \0 C D` with the binary-safe
// client. The handler records the body length it actually parsed.
// PASS  → server_saw_len=5 (full body shipped through the NUL).
// FAIL  → server_saw_len=2 (truncated at the embedded NUL).
//
// Both results funnel through globals and are printed in fixed order
// after the client thread joins, so the two-thread output stays
// deterministic for the baseline diff. Opens a loopback socket, hence
// `requires: live`.
// requires: live

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/core/vec.nu`

: ~ i g_saw_len -1
: ~ i g_client_status -1

@ echo_len_handler HttpRequest r → HttpResponse {
    = g_saw_len ( vec_len [u] . r body )
    ^ ( response_text 200 `ok\n` )
}

@ run_binary_body_test → v {
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18941 )
    ?? lr {
        T listener → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse { ^ ( echo_len_handler req ) }
            : HttpServer srv ( server_new listener h )

            : ( @ v ) client \ → v {
                ( sleep_ms 250 )
                : ( Vec u ) body ( vec_new [u] )
                ( vec_push [u] body # u 65 )  // 'A'
                ( vec_push [u] body # u 66 )  // 'B'
                ( vec_push [u] body # u 0 )  // embedded NUL
                ( vec_push [u] body # u 67 )  // 'C'
                ( vec_push [u] body # u 68 )  // 'D'
                : !Response HttpErr r ( http_post_bytes `http://127.0.0.1:18941/echo` body `application/octet-stream` )
                ?? r {
                    T resp → {
                        = g_client_status ( http_status resp )
                        ( response_free resp )
                    }
                    F e → { = g_client_status -2 }
                }
                ( vec_free [u] body )
            }
            : !Thread ThreadErr ct ( thread_spawn client )

            : !v NetErr rr ( server_run_once srv )
            ?? rr {
                T _ → {}
                F e → {
                    ( nurl_print `server_err=` )
                    ( nurl_print ( net_err_name e ) )
                    ( nurl_print `\n` )
                }
            }
            ?? ct { T t → { ( thread_join t ) } F _ → {} }

            ( nurl_print `server_saw_len=` )
            ( nurl_println_int g_saw_len )
            ( nurl_print `client_status=` )
            ( nurl_println_int g_client_status )
            ( nurl_print `done\n` )
        }
        F e → {
            ( nurl_print `listen_fail=` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
        }
    }
}

@ main → i {
    ( run_binary_body_test )
    ^ 0
}
