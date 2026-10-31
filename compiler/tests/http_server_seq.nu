// http_server_seq.nu — Phase 4 acceptance test for
// stdlib/ext/http_server.nu. Opens a real listening socket and runs
// curl as a child process for the client side, so it declares both —
// skipped on hosts without curl.
//
// Round-trip:
//   1. Listen on 127.0.0.1:18766 (loopback only).
//   2. Spawn `curl` as a child process, sending a POST with a body
//      and one custom header; what it prints comes back over its
//      stdout pipe.
//   3. server_run_once accepts → parses the request → calls the
//      echo handler → serialises + writes the response → closes.
//   4. Reap curl, print captured request fields and the response
//      body curl saw.
//
// The handler's job: echo back the request method + path + body,
// JSON-shaped, status 200. That gives us several things to check at
// once (status line, content-type, content-length, body bytes).
// requires: live fibers curl

$ `stdlib/std/net.nu`
$ `compiler/tests/loopback_client_mod.nu`
$ `stdlib/std/process.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

@ println_label s label s value → v {
    ( nurl_print label ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

@ println_label_int s label i value → v {
    ( nurl_print label ) ( nurl_print `=` )
    ( nurl_print ( nurl_str_int value ) ) ( nurl_print `\n` )
}

// Echo handler. Returns a small JSON-ish text response that captures
// the method, path, and body so the test can verify the round-trip
// end-to-end. We use plain text (not actual JSON) to avoid pulling
// the JSON encoder into this test.
unsafe @ echo_handler HttpRequest req → HttpResponse {
    : String body ( string_with_cap 128 )
    ( string_push_str body `method=` )
    ( string_push_str body ( string_data . req method ) )
    ( string_push_str body `\npath=` )
    ( string_push_str body ( string_data . req path ) )
    ( string_push_str body `\nquery=` )
    ( string_push_str body ( string_data . req query ) )
    ( string_push_str body `\nversion=` )
    ( string_push_str body ( string_data . req version ) )
    ( string_push_str body `\nbody=` )
    : i bn ( vec_len [u] . req body )
    : *u bdata ( vec_data [u] . req body )
    : ~ i k 0
    ~ < k bn {
        : u byte . bdata k
        ( string_push_char body # i byte )
        = k + k 1
    }
    ( string_push_str body `\n` )

    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( response_set_header r `X-Echo` `nurl-server` )
    ( string_free body )
    ^ r
}

@ main → i {
    // 1. Listen on loopback.
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` 18766 4 )
    ?? lr {
        T listener → {
            // 2. Start curl as a child process (an argument vector, no
            //    shell: agora #123); it connects while the server below
            //    accepts. `--max-time 2` so a server bug can't pin the
            //    test indefinitely; `-s` for quiet stderr.
            : ( Vec s ) cargs ( vec_new [s] )
            ( vec_push [s] cargs `-s` ) ( vec_push [s] cargs `--max-time` ) ( vec_push [s] cargs `2` )
            ( vec_push [s] cargs `-X` ) ( vec_push [s] cargs `POST` )
            ( vec_push [s] cargs `-H` ) ( vec_push [s] cargs `X-From: nurl-test` )
            ( vec_push [s] cargs `--data` ) ( vec_push [s] cargs `hello srv` )
            ( vec_push [s] cargs `http://127.0.0.1:18766/echo` )
            : !ProcChild ProcessErr cr ( process_spawn `curl` cargs )
            ?? cr {
                T child → {
                    // 3. Build the server and serve exactly one connection. Wrap
                    //    the top-level handler in a closure literal — `(@ R P)` is a
                    //    closure (fn-ptr + env-ptr), bare `@`-functions don't auto-
                    //    coerce to one.
                    : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse { ^ ( echo_handler req ) }
                    : HttpServer srv ( server_new listener handler )
                    : !v NetErr rr ( server_run_once srv )
                    ?? rr {
                        T _ → ( println_label `serve` `OK` )
                        F e → ( println_label `serve` ( net_err_name e ) )
                    }
                    ( server_stop srv )

                    // 4. Reap curl and dump what it saw. curl emits the
                    //    response body verbatim. Print byte-count + body so
                    //    the snapshot captures the round-trip even if
                    //    line-ending normalisation flips on some host.
                    : String client_out ( client_collect_text child 10000 )
                    ( println_label_int `client_out_len` ( string_len client_out ) )
                    ( println_label `client_out` ( string_data client_out ) )
                }
                F e → ( println_label `bg_spawn` ( process_err_name e ) )
            }
        }
        F e → ( println_label `listen` ( net_err_name e ) )
    }
    ^ 0
}
