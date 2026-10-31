// http_server_pipelined.nu — pipelining-correctness acceptance test
// for stdlib/ext/http_server.nu (carry-buffer refactor).
//
// Background: prior to the carry-buffer refactor, `_read_request_head`
// allocated a fresh `Vec[u] buf` per call and copied any bytes past the
// parsed head wholesale into `req.body`. When the peer pipelined two
// requests in a single send() — i.e. req2's head arrived inside the
// same TCP read as req1's head/body — req2's bytes silently
// disappeared into req1.body and the next iteration's
// `_read_request_head` saw an empty socket / NetClosed. Result: one
// corrupted request processed, the second one lost.
//
// This test reproduces that exact wire shape and verifies BOTH requests
// reach the handler with the correct (5-byte) body. Pre-fix snapshot:
// exactly one `handled` line in the output. Post-fix snapshot: two
// `handled` lines, body_len=5 each.
//
// Needs a loopback socket + a python3 client. The listen / accept /
// serve plumbing is already covered by `http_server_seq.nu`; this test
// isolates the pipelining correctness story.
// requires: live fibers python3

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

// Echo handler. Prints a `handled` line per invocation so the test
// snapshot reflects how many requests actually reached the handler
// and what their body length / first byte were. Returns a tiny
// `ok\n` body for the client side.
unsafe @ pipelined_handler HttpRequest req → HttpResponse {
    : i bn ( vec_len [u] . req body )
    : ~ i first_byte 0
    ? > bn 0 {
        : *u bdata ( vec_data [u] . req body )
        : u b0 . bdata 0
        = first_byte # i b0
    } {}
    ( nurl_print `handled path=` )
    ( nurl_print ( string_data . req path ) )
    ( nurl_print ` body_len=` )
    ( nurl_print ( nurl_str_int bn ) )
    ( nurl_print ` body0=` )
    ( nurl_print ( nurl_str_int first_byte ) )
    ( nurl_print `\n` )
    ^ ( response_text 200 `ok\n` )
}

@ run_live_pipelined_test → v {
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` 18768 4 )
    ?? lr {
        T listener → {
            // The client is a child process (an argument vector, no shell: agora
            // #123); it runs while this side accepts and serves.
            : !ProcChild ProcessErr cr ( py_client_spawn `import socket,sys
s=socket.socket();s.connect(('127.0.0.1',18768))
req=(b'POST /a HTTP/1.1\\r\\nHost: t\\r\\nContent-Length: 5\\r\\n\\r\\nAAAAA'+b'POST /b HTTP/1.1\\r\\nHost: t\\r\\nContent-Length: 5\\r\\nConnection: close\\r\\n\\r\\nBBBBB')
s.sendall(req);s.shutdown(socket.SHUT_WR)
buf=b''
while True:
    c=s.recv(4096)
    if not c: break
    buf+=c
sys.stdout.write('client_status_lines='+str(buf.count(b'HTTP/1.1 200'))+chr(10))
sys.stdout.write('client_total_bytes='+str(len(buf))+chr(10))` )
            ?? cr {
                T child → {
                    // Short idle timeout so a buggy server's second
                    // `_read_request_head` call observes the client-side
                    // shutdown(SHUT_WR) → NetClosed promptly. 2s leaves
                    // plenty of margin for the python startup + sendall
                    // round-trip on slow CI.
                    : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse { ^ ( pipelined_handler req ) }
                    : HttpServer srv ( server_new_with_timeout listener handler 2000 )
                    : !v NetErr rr ( server_run_once srv )
                    ?? rr {
                        T _ → ( println_label `serve` `OK` )
                        F e → ( println_label `serve` ( net_err_name e ) )
                    }
                    ( server_stop srv )

                    // Collect the client's output from its stdout. Bounded at
                    // 10 s, so a client that never finishes fails the golden
                    // with its lines missing (a visible failure) instead of
                    // hanging the whole run.
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
    ( run_live_pipelined_test )
    ^ 0
}
