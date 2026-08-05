// http_server_limits.nu — HttpLimits + request_total_timeout_ms
// regression for stdlib/ext/http_server.nu. Two assertions:
//
//   (1) HttpLimits.head_max_bytes shrunk to 256: a request whose
//       header block exceeds the cap returns 413 (entity too large)
//       and the connection closes.
//
//   (2) request_total_timeout_ms = 100 ms: a handler that sleeps
//       200 ms has its response replaced with a stock 504; the
//       connection closes. The handler still ran to completion
//       (we have no thread-cancellation primitives), but the
//       client never sees the over-budget output.
//
// Needs a loopback socket + python3 (same as http_server_seq /
// pipelined). Two listeners on adjacent ports so the cases don't
// interleave.
// requires: live fibers python3

$ `stdlib/std/net.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

@ println_label s label s value → v {
    ( nurl_print label ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

@ ok_handler HttpRequest req → HttpResponse {
    ^ ( response_text 200 `ok\n` )
}

@ slow_handler HttpRequest req → HttpResponse {
    ( sleep_ms 200 )
    ^ ( response_text 200 `slow-ok\n` )
}

// Case 1 — head_max_bytes=256, send a 600-byte header block. Server
// returns 413; client reads status line.
@ run_head_too_large_test → v {
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` 18770 4 )
    ?? lr {
        T listener → {
            // Build a request with one large X-Big header that pushes the
            // head past 256 bytes. python3 client extracts the status line.
            : s shell_cmd
            `python3 -c "import socket,sys
s=socket.socket();s.connect(('127.0.0.1',18770))
big='X'*600
req='GET / HTTP/1.1\\r\\nHost: t\\r\\nX-Big: '+big+'\\r\\n\\r\\n'
s.sendall(req.encode())
s.shutdown(socket.SHUT_WR)
buf=b''
while True:
    c=s.recv(4096)
    if not c: break
    buf+=c
first=buf.split(b'\\r\\n',1)[0].decode('latin-1')
sys.stdout.write('case1_status='+first+chr(10))" > /tmp/http_server_limits1.out 2>&1 & echo $! > /tmp/http_server_limits1.pid; sleep 0.10`
            : !Output ProcessErr bg ( process_run_shell shell_cmd )
            ?? bg {
                T bgo → ( output_free bgo )
                F e → ( println_label `case1_bg` ( process_err_name e ) )
            }

            : HttpLimits lim @ HttpLimits { 256 100 1048576 }
            : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse { ^ ( ok_handler req ) }
            : HttpServer srv ( server_new_complete listener handler 2000 1000 lim 0 )
            : !v NetErr rr ( server_run_once srv )
            ?? rr {
                T _ → {}
                F e → ( println_label `case1_serve` ( net_err_name e ) )
            }
            ( server_stop srv )

            : !Output ProcessErr wait_r ( process_run_shell `wait $(cat /tmp/http_server_limits1.pid 2>/dev/null) 2>/dev/null; cat /tmp/http_server_limits1.out` )
            ?? wait_r {
                T wo → { ( nurl_print ( output_stdout wo ) ) ( output_free wo ) }
                F e → ( println_label `case1_wait` ( process_err_name e ) )
            }
        }
        F e → ( println_label `case1_listen` ( net_err_name e ) )
    }
}

// Case 2 — request_total_timeout_ms=100, handler sleeps 200 ms.
// Expect 504 status line.
@ run_request_timeout_test → v {
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` 18771 4 )
    ?? lr {
        T listener → {
            : s shell_cmd
            `python3 -c "import socket,sys
s=socket.socket();s.connect(('127.0.0.1',18771))
s.sendall(b'GET / HTTP/1.1\\r\\nHost: t\\r\\n\\r\\n')
s.shutdown(socket.SHUT_WR)
buf=b''
while True:
    c=s.recv(4096)
    if not c: break
    buf+=c
first=buf.split(b'\\r\\n',1)[0].decode('latin-1')
sys.stdout.write('case2_status='+first+chr(10))" > /tmp/http_server_limits2.out 2>&1 & echo $! > /tmp/http_server_limits2.pid; sleep 0.10`
            : !Output ProcessErr bg ( process_run_shell shell_cmd )
            ?? bg {
                T bgo → ( output_free bgo )
                F e → ( println_label `case2_bg` ( process_err_name e ) )
            }

            : HttpLimits lim ( http_default_limits )
            : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse { ^ ( slow_handler req ) }
            : HttpServer srv ( server_new_complete listener handler 2000 1000 lim 100 )
            : !v NetErr rr ( server_run_once srv )
            ?? rr {
                T _ → {}
                F e → ( println_label `case2_serve` ( net_err_name e ) )
            }
            ( server_stop srv )

            : !Output ProcessErr wait_r ( process_run_shell `wait $(cat /tmp/http_server_limits2.pid 2>/dev/null) 2>/dev/null; cat /tmp/http_server_limits2.out` )
            ?? wait_r {
                T wo → { ( nurl_print ( output_stdout wo ) ) ( output_free wo ) }
                F e → ( println_label `case2_wait` ( process_err_name e ) )
            }
        }
        F e → ( println_label `case2_listen` ( net_err_name e ) )
    }
}

@ main → i {
    ( run_head_too_large_test )
    ( run_request_timeout_test )
    ^ 0
}
