// http_server_tls.nu — Phase 9 acceptance test for tcp_listen_tls.
//
// Round-trip:
//   1. Generate a self-signed cert + key in the working directory via
//      `openssl req -nodes -x509 -days 1 -newkey rsa:2048`, run with an
//      argument vector (no shell: agora #123). The `-nodes` flag means
//      the key has no passphrase, and the cert is short-lived (1 day).
//   2. tcp_listen_tls on 127.0.0.1:18772 → HttpServer reuses the
//      returned TcpListener as if it were a plain socket. The
//      runtime's NurlTcp handle now carries an SSL_CTX; accept
//      transparently performs SSL_accept before handing the conn
//      to _serve_keepalive_loop.
//   3. python3 client does an HTTPS GET with verify=False against
//      the self-signed cert; prints status line + body.
//
// Needs a loopback socket + python3 + the openssl CLI for cert gen.
// When openssl wasn't detected at build time
// (stdlib/runtime.openssl absent), tcp_listen_tls returns
// NetTlsCtxInit and the test prints that fact instead — so the
// baseline tells us whether the build-host openssl path is wired.
// requires: live fibers openssl python3

$ `stdlib/std/net.nu`
$ `compiler/tests/loopback_client_mod.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

@ println_label s label s value → v {
    ( nurl_print label ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

@ tls_echo_handler HttpRequest req → HttpResponse {
    : HttpResponse r ( response_text 200 `tls-ok\n` )
    ( response_set_header r `X-TLS` `1` )
    ^ r
}

@ run_live_tls_test → v {
    // Relative to the working directory, which exists on every host.
    : s cert `nurl_test_tls.crt`
    : s key `nurl_test_tls.key`
    ? ! ( openssl_selfsigned `rsa:2048` `` key cert `localhost` ) { ( println_label `cert_gen` `FAIL` ) } {}

    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` 18772 cert key )
    ?? lr {
        T listener → {
            // The client is a child process (an argument vector, no shell: agora
            // #123); it runs while this side accepts and serves.
            : !ProcChild ProcessErr cr ( py_client_spawn `import ssl,socket,sys
ctx=ssl.create_default_context()
ctx.check_hostname=False
ctx.verify_mode=ssl.CERT_NONE
s=socket.create_connection(('127.0.0.1',18772))
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
sys.stdout.write('tls_body='+body)` )
            ?? cr {
                T child → {
                    : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse { ^ ( tls_echo_handler req ) }
                    : HttpServer srv ( server_new_with_timeout listener handler 3000 )
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
        F e → { ( println_label `tls_listen` ( net_err_name e ) ) }
    }
}

@ main → i {
    ( run_live_tls_test )
    ^ 0
}
