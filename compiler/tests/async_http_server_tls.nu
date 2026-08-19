// async_http_server_tls.nu — fiber-driven HTTPS server acceptance test.
//
// The async twin of http_server_tls.nu, exercising the pieces that make
// `server_run_async` viable for TLS listeners:
//   * `tcp_accept_transport` on the accept fiber + the TLS handshake
//     completing on the CONNECTION's fiber (tcp_conn_complete_tls) — so
//     handshakes overlap instead of serialising on the accept loop
//   * the pure TLS stack's record I/O (`__fill` / `_tls_sock_write`)
//     parking on the reactor instead of blocking a worker pthread
//   * a plain-TCP probe against the TLS port: the failed handshake must
//     close only that connection — the accept loop keeps serving (this
//     regressed once: the accept fiber treated every accept-level error
//     as fatal, and one port scan killed the whole server)
//
// Flow: EC P-256 self-signed cert (the curve the bench and a modern
// deployment negotiate) → tcp_listen_tls → server_run_async; a pthread
// runs a shell client that (1) opens and drops a bare TCP conn, then
// (2) drives one HTTPS GET via python3/ssl, then stops the server.
// requires: live fibers openssl python3

$ `stdlib/std/async.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/core/string.nu`

@ tls_async_println s label s value → v {
    ( nurl_print label ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

@ tls_async_handler HttpRequest req → HttpResponse {
    ^ ( response_text 200 `tls-async-ok\n` )
}

@ run_async_tls_test → v {
    : s gen_cmd
    `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -keyout /tmp/nurl_async_tls.key -out /tmp/nurl_async_tls.crt -subj '/CN=localhost' 2>/dev/null`
    : !Output ProcessErr gen_r ( process_run_shell gen_cmd )
    ?? gen_r {
        T go → ( output_free go )
        F e → ( tls_async_println `cert_gen` ( process_err_name e ) )
    }

    ( runtime_init 4 )

    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` 18921 `/tmp/nurl_async_tls.crt` `/tmp/nurl_async_tls.key` )
    ?? lr {
        T listener → {
            : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse { ^ ( tls_async_handler req ) }
            : HttpServer srv ( server_new_with_timeout listener handler 5000 )

            // Client thread: bare-TCP probe (must NOT kill the accept
            // loop), then one HTTPS GET, then stop the server. Runs on
            // a pthread so the blocking shell client cannot deadlock a
            // fiber worker.
            : ( @ v ) client \ → v {
                : s client_cmd
                `python3 -c "import ssl,socket,sys
socket.create_connection(('127.0.0.1',18921)).close()
ctx=ssl.create_default_context()
ctx.check_hostname=False
ctx.verify_mode=ssl.CERT_NONE
s=socket.create_connection(('127.0.0.1',18921))
ss=ctx.wrap_socket(s,server_hostname='localhost')
ss.sendall(b'GET / HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n')
buf=b''
while True:
    c=ss.recv(4096)
    if not c: break
    buf+=c
first=buf.split(b'\\r\\n',1)[0].decode('latin-1')
body=buf.rsplit(b'\\r\\n\\r\\n',1)[-1].decode('latin-1',errors='replace')
sys.stdout.write('tls_status='+first+chr(10))
sys.stdout.write('tls_body='+body)" 2>&1`
                : !Output ProcessErr cr ( process_run_shell client_cmd )
                ?? cr {
                    T co → {
                        ( nurl_print ( output_stdout co ) )
                        ( output_free co )
                    }
                    F e → ( tls_async_println `client` ( process_err_name e ) )
                }
                ( server_stop srv )
            }
            : !Thread ThreadErr ct ( thread_spawn client )

            : !v NetErr sr ( server_run_async srv )
            ?? sr {
                T _ → ( tls_async_println `server_run` `ok` )
                F e → ( tls_async_println `server_run` ( net_err_name e ) )
            }

            ?? ct { T t → { ( thread_join t ) } F _ → {} }
            : *u client_env # *u client 1
            ( nurl_free # s client_env )
            : *u handler_env # *u handler 1
            ( nurl_free # s handler_env )
            ( runtime_shutdown )
        }
        F e → { ( tls_async_println `tls_listen` ( net_err_name e ) ) }
    }
}

@ main → i {
    ( run_async_tls_test )
    ^ 0
}
