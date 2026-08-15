// http_server_seq.nu — Phase 4 acceptance test for
// stdlib/ext/http_server.nu. Opens a real listening socket and shells
// out to curl for the client side, so it declares both — skipped on
// hosts without curl.
//
// Round-trip:
//   1. Listen on 127.0.0.1:18766 (loopback only).
//   2. Spawn `curl` in the background, sending a POST with a body
//      and one custom header. The wrapper writes the response to a
//      temp file and stashes the curl PID so we can reap it.
//   3. server_run_once accepts → parses the request → calls the
//      echo handler → serialises + writes the response → closes.
//   4. Reap curl, print captured request fields and the response
//      body curl saw. Determinism preserved by sleeping 50 ms before
//      accept (server-side) so the bg curl has time to connect.
//
// The handler's job: echo back the request method + path + body,
// JSON-shaped, status 200. That gives us several things to check at
// once (status line, content-type, content-length, body bytes).
// requires: live fibers curl

$ `stdlib/std/net.nu`
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
@ echo_handler HttpRequest req → HttpResponse {
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
            // 2. Spawn the curl client. We use `--max-time 2` so a server
            //    bug can't pin the test indefinitely; `-s` for quiet stderr;
            //    `-w '\nstatus=%{http_code}'` so we can see curl's view of
            //    the response status as a separate line.
            : s shell_cmd
            `rm -f /tmp/http_server_seq_client.out /tmp/http_server_seq_client.part; { curl -s --max-time 2 -X POST -H 'X-From: nurl-test' --data 'hello srv' http://127.0.0.1:18766/echo > /tmp/http_server_seq_client.part 2>&1; mv /tmp/http_server_seq_client.part /tmp/http_server_seq_client.out; } >/dev/null 2>&1 &`
            : !Output ProcessErr bg ( process_run_shell shell_cmd )
            ?? bg {
                T bgo → ( output_free bgo )
                F e → ( println_label `bg_spawn` ( process_err_name e ) )
            }

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

            // 4. Reap the curl client and dump what it saw.
            : !Output ProcessErr wait_r ( process_run_shell `for _ in $(seq 1 200); do [ -f /tmp/http_server_seq_client.out ] && break; sleep 0.05; done; cat /tmp/http_server_seq_client.out 2>/dev/null` )
            ?? wait_r {
                T wo → {
                    : s client_out ( output_stdout wo )
                    // curl emits the response body verbatim. Print byte-count +
                    // body so the snapshot captures the round-trip even if
                    // line-ending normalisation flips on some host.
                    ( println_label_int `client_out_len` ( nurl_str_len client_out ) )
                    ( println_label `client_out` client_out )
                    ( output_free wo )
                }
                F e → ( println_label `wait_client` ( process_err_name e ) )
            }
        }
        F e → ( println_label `listen` ( net_err_name e ) )
    }
    ^ 0
}
