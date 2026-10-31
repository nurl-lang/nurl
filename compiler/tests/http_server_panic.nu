// http_server_panic.nu — handler-panic recovery regression for
// stdlib/ext/http_server.nu's _serve_keepalive_loop.
//
// Round trip:
//   1. Listen on 127.0.0.1:18773.
//   2. Register a handler that ALWAYS calls `panic` (simulates a
//      handler bug — a real-world version would be an unguarded
//      dictionary lookup, an unwrapped Result, etc.).
//   3. Spawn a python3 client that does an HTTP GET; expect a
//      500 status line on the wire. The client is this process's own
//      child (process_spawn, agora #123), so the test reads its line
//      from the child's stdout and reaps it: no sleep, no polled temp
//      file, and no stale output from an earlier run to pass a broken
//      server.
//   4. server_run_once accepts → _serve_keepalive_loop wraps the
//      handler call in `recover`; the panic is caught, a stock 500
//      response is substituted, connection closes.
//
// Pre-fix (no panic model): the handler's `panic` would abort the
// process — the test would die before producing any client output.
// Post-fix: the panic is recovered, 500 sent, process keeps running.
// requires: live fibers python3

$ `stdlib/std/net.nu`
$ `compiler/tests/loopback_client_mod.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

@ println_label s label s value → v {
    ( nurl_print label ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

@ panicking_handler HttpRequest req → HttpResponse {
    ( panic `handler bug: forced panic` )
    // Unreachable — `panic` never returns. The compiler doesn't yet
    // know this so we still need a syntactic response value that
    // type-checks; recover ensures it's never observed.
    ^ ( response_text 200 `unreachable\n` )
}

@ run_live_panic_test → v {
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` 18773 4 )
    ?? lr {
        T listener → {
            // The client is a child process (an argument vector, no shell: agora
            // #123); it runs while this side accepts and serves.
            : !ProcChild ProcessErr cr ( py_client_spawn `import socket,sys
s=socket.socket();s.connect(('127.0.0.1',18773))
s.sendall(b'GET / HTTP/1.1\\r\\nHost: t\\r\\nConnection: close\\r\\n\\r\\n')
s.shutdown(socket.SHUT_WR)
buf=b''
while True:
    c=s.recv(4096)
    if not c: break
    buf+=c
first=buf.split(b'\\r\\n',1)[0].decode('latin-1')
sys.stdout.write('client_status='+first+chr(10))` )
            ?? cr {
                T child → {
                    : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse { ^ ( panicking_handler req ) }
                    : HttpServer srv ( server_new_with_timeout listener handler 2000 )
                    : !v NetErr rr ( server_run_once srv )
                    ?? rr {
                        T _ → ( println_label `serve` `OK` )
                        F e → ( println_label `serve` ( net_err_name e ) )
                    }
                    ( server_stop srv )
                    : String client_out ( client_collect child 10000 )
                    ( nurl_print ( string_data client_out ) ) ( nurl_print `\n` )
                }
                F e → {
                    ( println_label `bg_spawn` ( process_err_name e ) )
                }
            }
        }
        F e → ( println_label `listen` ( net_err_name e ) )
    }
}

@ main → i {
    ( run_live_panic_test )
    ^ 0
}
