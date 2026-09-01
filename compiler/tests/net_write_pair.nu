// net_write_pair.nu — the two-segment write path behind the HTTP server:
// `response_serialize_head_to` + `tcp_write_all2` (head and body as one
// message through one sendmsg) must put exactly the bytes on the wire
// that the single-buffer `response_serialize` + `tcp_write_all` did.
//
// Round-trip over a real loopback socket, blocking (off-fiber) path:
//   1. Listen on 127.0.0.1:18766.
//   2. Spawn a python3 client that connects, SLEEPS before reading (so
//      the 3 MB body fills the socket buffer and the send loop has to
//      continue from short counts, across the head/body boundary), then
//      reads to EOF and prints total length + sha256 of the stream.
//   3. Server accepts and writes two responses with tcp_write_all2:
//      a 3 MB octet-stream (head in the wire buffer, body still in the
//      response — the pair path) and a 204 with an EMPTY body (the
//      one-segment-empty path), then closes.
//   4. Checks that head‖body is byte-identical to response_serialize,
//      and that the client saw the whole stream.
// requires: live fibers python3

$ `stdlib/std/net.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http_response.nu`

@ python_client_src → s {
    ^ `import socket,sys,time,hashlib
s = socket.create_connection(('127.0.0.1', 18766), timeout=10.0)
s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16384)
time.sleep(0.4)
h = hashlib.sha256()
n = 0
while True:
  chunk = s.recv(65536)
  if not chunk: break
  h.update(chunk)
  n += len(chunk)
s.close()
sys.stdout.write('%d %s' % (n, h.hexdigest()[:16]))
`
}

@ print_label_str s label s value → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ print_label_bool s label b v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print ? v `T` `F` )
    ( nurl_print `\n` )
}

// Print header bytes with CR/LF made visible, as http_response_builder does.
@ dump_head ( Vec u ) bytes → v {
    : i n ( vec_len [u] bytes )
    : *u data ( vec_data [u] bytes )
    : ~ i k 0
    ~ < k n {
        : i ib # i . data k
        ? == ib 13 { ( nurl_print `\\r` ) } {}
        ? == ib 10 { ( nurl_print `\\n\n` ) } {}
        ? & != ib 13 != ib 10 {
            : String tmp ( string_with_cap 1 )
            ( string_push_char tmp ib )
            ( nurl_print ( string_data tmp ) )
            ( string_free tmp )
        } {}
        = k + k 1
    }
}

// Deterministic 3 MB body: byte k = (7k + 3) mod 256.
@ make_body i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [u] v # u & + * k 7 3 255 )
        = k + k 1
    }
    ^ v
}

// T when head‖body == full, bytewise.
@ pair_equals_full ( Vec u ) head ( Vec u ) body ( Vec u ) full → b {
    : ( Vec u ) joined ( vec_with_cap [u] + ( vec_len [u] head ) ( vec_len [u] body ) )
    ( bytes_extend_bytes joined head )
    ( bytes_extend_bytes joined body )
    : b eq ( bytes_eq joined full )
    ( vec_free [u] joined )
    ^ eq
}

@ write_pair TcpConn conn s label HttpResponse r ( Vec u ) wire → v {
    ( vec_clear [u] wire )
    ( response_serialize_head_to r wire )
    ( nurl_print `── ` ) ( nurl_print label ) ( nurl_print ` head ──\n` )
    ( dump_head wire )
    : ( Vec u ) full ( response_serialize r )
    ( print_label_bool `head_plus_body_equals_serialize` ( pair_equals_full wire . r body full ) )
    ( vec_free [u] full )
    : !v NetErr wr ( tcp_write_all2 conn wire . r body )
    ?? wr {
        T _ → ( print_label_str `write` `OK` )
        F e → ( print_label_str `write` ( net_err_name e ) )
    }
    ( http_response_free r )
}

@ main → i {
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` 18766 4 )
    ?? lr {
        T listener → {
            : s pyclient ( python_client_src )
            : s shell_cmd `rm -f /tmp/net_write_pair_client.out /tmp/net_write_pair_client.part; { python3 -c "$NURL_PYCLIENT" > /tmp/net_write_pair_client.part 2> /tmp/net_write_pair_client.err; mv /tmp/net_write_pair_client.part /tmp/net_write_pair_client.out; } >/dev/null 2>&1 &`
            : !v IoErr _es ( env_set `NURL_PYCLIENT` pyclient )
            : !Output ProcessErr bg ( process_run_shell shell_cmd )
            ?? bg {
                T bgo → ( output_free bgo )
                F e → ( print_label_str `bg_spawn` ( process_err_name e ) )
            }

            : !TcpConn NetErr ar ( tcp_accept listener )
            ?? ar {
                T conn → {
                    : ( Vec u ) wire ( vec_with_cap [u] 256 )

                    // Response 1: 3 MB body — head in `wire`, body borrowed from r.
                    : ( Vec u ) body ( make_body 3145728 )
                    : HttpResponse r1 ( response_new 200 )
                    ( response_set_header r1 `Content-Type` `application/octet-stream` )
                    ( response_set_body_bytes r1 body )
                    ( vec_free [u] body )
                    ( write_pair conn `big` r1 wire )

                    // Response 2: empty body — the one-segment path of the pair.
                    : HttpResponse r2 ( response_status_only 204 )
                    ( write_pair conn `empty` r2 wire )

                    ( vec_free [u] wire )
                    ( tcp_close_conn conn )
                }
                F e → ( print_label_str `accept` ( net_err_name e ) )
            }

            ( tcp_close_listener listener )

            : !Output ProcessErr wait_r ( process_run_shell `for _ in $(seq 1 400); do [ -f /tmp/net_write_pair_client.out ] && break; sleep 0.05; done; cat /tmp/net_write_pair_client.out 2>/dev/null` )
            ?? wait_r {
                T wo → {
                    ( print_label_str `client_saw` ( output_stdout wo ) )
                    ( output_free wo )
                }
                F e → ( print_label_str `wait_client` ( process_err_name e ) )
            }
        }
        F e → ( print_label_str `listen` ( net_err_name e ) )
    }
    ^ 0
}
