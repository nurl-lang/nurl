// net_loopback.nu — Phase 1 acceptance test for HTTP_SERVER_PLAN.
// Opens a real listening socket and shells out to python3 for a
// client-side connect, so it declares both — skipped on hosts
// without python3.
//
// Round-trip:
//   1. Listen on 127.0.0.1:18765 (loopback only).
//   2. Spawn a python3 client (via process.nu) that connects, sends
//      "ping", reads "pong", closes.
//   3. Server accepts, reads "ping", writes "pong", closes the conn.
//   4. Verifies the captured bytes round-trip end-to-end and that
//      tcp_peer_addr is non-empty.
// requires: live fibers python3

$ `stdlib/std/net.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`

// Python one-liner that connects to the server, writes "ping",
// reads back exactly 4 bytes, prints them. Kept inline so the test
// has no external dependencies beyond a python3 interpreter.
@ python_client_src → s {
    ^ `import socket,sys
s = socket.create_connection(('127.0.0.1', 18765), timeout=2.0)
s.sendall(b'ping')
buf = b''
while len(buf) < 4:
  chunk = s.recv(4 - len(buf))
  if not chunk: break
  buf += chunk
s.close()
sys.stdout.write(buf.decode())
`
}

@ print_label_str s label s value → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ print_label_int s label i value → v {
    ( nurl_print label )
    ( nurl_print `=` )
    : s txt ( nurl_str_int value )
    ( nurl_print txt )
    ( nurl_print `\n` )
}

@ print_label_bool s label b v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print ? v `T` `F` )
    ( nurl_print `\n` )
}

// Drain the connection until 4 bytes have been read or an error
// occurs. Returns the (possibly partial) Vec[u] and lets the caller
// decide what to do.
@ recv_4_bytes TcpConn c → ( Vec u ) {
    : ( Vec u ) acc ( vec_with_cap [u] 4 )
    : ~ i remaining 4
    ~ > remaining 0 {
        : !( Vec u ) NetErr r ( tcp_read_chunk c remaining )
        ?? r {
            T chunk → {
                : i n ( vec_len [u] chunk )
                : ~ i k 0
                ~ < k n {
                    : ?u got ( vec_get [u] chunk k )
                    ?? got {
                        T b → ( vec_push [u] acc b )
                        F _ → {}
                    }
                    = k + k 1
                }
                ( vec_free [u] chunk )
                = remaining - remaining n
            }
            F _ → = remaining 0
        }
    }
    ^ acc
}

@ main → i {
    // 1. Listen on loopback. Backlog 4 is plenty for a single client.
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` 18765 4 )
    ?? lr {
        T listener → {
            // 2. Spawn the python client BEFORE accept so it can connect
            //    while we block in accept(2). process_run is synchronous,
            //    so we can't actually overlap — we'd deadlock. Use a tiny
            //    shell wrapper that backgrounds the python and returns
            //    immediately; we then accept + read/write + reap the bg.
            //    Capture the bg pid via a temp file the wrapper writes.
            : s pyclient ( python_client_src )
            : s shell_cmd ( nurl_str_cat3
            `python3 -c "$NURL_PYCLIENT" > /tmp/net_loopback_client.out 2> /tmp/net_loopback_client.err & echo $! > /tmp/net_loopback_client.pid; sleep 0.05`
            ``
            `` )
            // Stash python source in env so quoting stays simple.
            : !v IoErr _es ( env_set `NURL_PYCLIENT` pyclient )
            : !Output ProcessErr bg ( process_run_shell shell_cmd )
            ?? bg {
                T bgo → ( output_free bgo )
                F e → ( print_label_str `bg_spawn` ( process_err_name e ) )
            }

            // 3. Accept the incoming connection.
            : !TcpConn NetErr ar ( tcp_accept listener )
            ?? ar {
                T conn → {
                    : s peer ( tcp_peer_addr conn )
                    ( print_label_bool `peer_addr_nonempty` > ( nurl_str_len peer ) 0 )

                    // 4. Read 4 bytes (= "ping").
                    : ( Vec u ) buf ( recv_4_bytes conn )
                    : i nread ( vec_len [u] buf )
                    ( print_label_int `bytes_read` nread )
                    : String s_in ( bytes_to_str buf )
                    ( print_label_str `payload_in` ( string_data s_in ) )
                    ( string_free s_in )
                    ( vec_free [u] buf )

                    // 5. Write "pong" back.
                    : !v NetErr wr ( tcp_write_str conn `pong` )
                    ?? wr {
                        T _ → ( print_label_str `write_pong` `OK` )
                        F e → ( print_label_str `write_pong` ( net_err_name e ) )
                    }

                    ( tcp_close_conn conn )
                }
                F e → ( print_label_str `accept` ( net_err_name e ) )
            }

            ( tcp_close_listener listener )

            // 6. Reap the bg client + verify it printed "pong".
            : !Output ProcessErr wait_r ( process_run_shell `wait $(cat /tmp/net_loopback_client.pid 2>/dev/null) 2>/dev/null; cat /tmp/net_loopback_client.out` )
            ?? wait_r {
                T wo → {
                    : s client_out ( output_stdout wo )
                    ( print_label_str `client_out` client_out )
                    ( output_free wo )
                }
                F e → ( print_label_str `wait_client` ( process_err_name e ) )
            }
        }
        F e → ( print_label_str `listen` ( net_err_name e ) )
    }

    ^ 0
}
