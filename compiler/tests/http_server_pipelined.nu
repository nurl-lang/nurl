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
@ pipelined_handler HttpRequest req → HttpResponse {
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
            // Spawn the pipelined client. python3 builds the wire bytes
            // exactly (no shell quoting traps), sends them in ONE send(),
            // shuts down the write half so the server sees EOF after
            // req2, then drains the response stream.
            //
            // Wire:
            //   POST /a HTTP/1.1\r\n
            //   Host: t\r\n
            //   Content-Length: 5\r\n
            //   \r\n
            //   AAAAA
            //   POST /b HTTP/1.1\r\n
            //   Host: t\r\n
            //   Content-Length: 5\r\n
            //   Connection: close\r\n
            //   \r\n
            //   BBBBB
            //
            // Pre-fix bug: bytes after req1's `\r\n\r\n` (i.e.
            // `AAAAAPOST /b ...BBBBB`) get stuffed into req1.body, then
            // the handler runs once on a 60+-byte body and the second
            // request is lost. Post-fix: both runs see body_len=5.
            // The client runs in the background so the server below can
            // accept it, and its result is collected after the serve
            // loop. Two rules make that handoff deterministic:
            //
            //   * it writes to a `.part` file and RENAMES it when done.
            //     rename(2) is atomic, so the collector below either
            //     sees no file at all or sees the complete output — it
            //     can never read a half-flushed one.
            //   * stale files from an earlier run are removed FIRST,
            //     so the collector cannot mistake them for this run's.
            //
            // The background group redirects its OWN stdout/stderr to
            // /dev/null, which is load-bearing, not tidiness: it would
            // otherwise inherit the pipe process_run_shell reads, and
            // that call would block until the client exited — while the
            // client waits on a server this function has not started
            // yet. Redirecting only python's output (what the old shape
            // did) leaves the trailing `mv` holding the pipe.
            //
            // The old shape spawned with `&`, wrote the pid to a file
            // and later ran `wait $(cat pid)`. That never waited for
            // anything: the spawning shell exits at the end of this
            // command, orphaning python, and the `wait` runs in a
            // DIFFERENT shell where that pid is not a child — so it
            // failed instantly (hence the `2>/dev/null`) and `cat`
            // raced the client. Only the trailing `sleep 0.10` made it
            // work, and on a loaded CI runner 100 ms is not enough:
            // the client's two lines went missing and the test failed
            // against its golden.
            : s shell_cmd
            `rm -f /tmp/http_server_pipelined_client.out /tmp/http_server_pipelined_client.part; { python3 -c "import socket,sys
s=socket.socket();s.connect(('127.0.0.1',18768))
req=(b'POST /a HTTP/1.1\\r\\nHost: t\\r\\nContent-Length: 5\\r\\n\\r\\nAAAAA'+b'POST /b HTTP/1.1\\r\\nHost: t\\r\\nContent-Length: 5\\r\\nConnection: close\\r\\n\\r\\nBBBBB')
s.sendall(req);s.shutdown(socket.SHUT_WR)
buf=b''
while True:
    c=s.recv(4096)
    if not c: break
    buf+=c
sys.stdout.write('client_status_lines='+str(buf.count(b'HTTP/1.1 200'))+chr(10))
sys.stdout.write('client_total_bytes='+str(len(buf))+chr(10))" > /tmp/http_server_pipelined_client.part 2>&1; mv /tmp/http_server_pipelined_client.part /tmp/http_server_pipelined_client.out; } >/dev/null 2>&1 &`
            : !Output ProcessErr bg ( process_run_shell shell_cmd )
            ?? bg {
                T bgo → ( output_free bgo )
                F e → ( println_label `bg_spawn` ( process_err_name e ) )
            }

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

            // Collect the client's output: poll for the renamed file
            // rather than assume it has arrived. Bounded at ~10 s so a
            // client that never finishes fails the golden with its two
            // lines missing (a visible failure) instead of hanging the
            // whole run. In practice the file is there on the first or
            // second pass — the serve loop above already waited for the
            // exchange this reads the result of.
            : !Output ProcessErr wait_r ( process_run_shell `for _ in $(seq 1 200); do [ -f /tmp/http_server_pipelined_client.out ] && break; sleep 0.05; done; cat /tmp/http_server_pipelined_client.out 2>/dev/null` )
            ?? wait_r {
                T wo → {
                    : s client_out ( output_stdout wo )
                    ( nurl_print client_out )
                    ( output_free wo )
                }
                F e → ( println_label `wait_client` ( process_err_name e ) )
            }
        }
        F e → ( println_label `listen` ( net_err_name e ) )
    }
}

@ main → i {
    ( run_live_pipelined_test )
    ^ 0
}
