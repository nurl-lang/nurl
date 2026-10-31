// net_loopback.nu — Phase 1 acceptance test for HTTP_SERVER_PLAN.
// Opens a real listening socket and runs a python3 client as a child
// process (an argument vector, no shell: agora #123), so it declares
// both — skipped on hosts without python3.
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
$ `compiler/tests/loopback_client_mod.nu`

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
            // 2. Start the python client before accept: it is a child
            //    process, so it connects while we block in accept(2).
            : !ProcChild ProcessErr cr ( py_client_spawn ( python_client_src ) )

            ?? cr {
                T child → {
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

                    // 6. Collect what the client printed ("pong") and reap it.
                    : String client_out ( client_collect child 5000 )
                    ( print_label_str `client_out` ( string_data client_out ) )
                }
                F e → {
                    ( print_label_str `client_spawn` ( process_err_name e ) )
                    ( tcp_close_listener listener )
                }
            }
        }
        F e → ( print_label_str `listen` ( net_err_name e ) )
    }

    ^ 0
}
