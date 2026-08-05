// tls_large_record.nu — lock for TLS record splitting on large writes.
//
// A pure-NURL TLS 1.3 server (self-signed P-256 minted by std/x509_gen,
// so the EC path — tls_accept, net.nu kind 2 — is the one serving)
// answers one HTTPS GET with a 100 000-byte body. RFC 8446 §5.1 caps a
// record's plaintext at 2^14 bytes: peers must reject anything larger,
// and past 65535 the record header's u16 length field wraps outright.
// Before the 2026-07-06 fix, tls_server_write / tls_write shipped the
// whole payload as ONE record, so any response over ~16 KB (fatally,
// over 64 KB) made OpenSSL clients abort with "bad record mac" — found
// live by yoloe-demo's ~90 KB /detect responses over --tls.
//
// The python client reads to EOF and prints the body length plus a
// content check (repeating '0123456789' pattern), both deterministic.
// Needs a loopback socket + python3, like http_server_tls.nu.
// requires: live fibers python3

$ `stdlib/std/net.nu`
$ `stdlib/std/process.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

@ println_label s label s value → v {
    ( nurl_print label ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

// 100 000 bytes: '0123456789' × 10 000 — five-plus full TLS records.
@ big_body_handler HttpRequest req → HttpResponse {
    : String body ( string_with_cap 100016 )
    : ~ i k 0
    ~ < k 10000 {
        ( string_push_str body `0123456789` )
        = k + k 1
    }
    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( string_free body )
    ^ r
}

@ run_live_test → v {
    // pure-NURL self-signed cert (EC P-256 → the pure tls_accept path)
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : s cp `/tmp/nurl_tls_large_record.crt`
    : s kp `/tmp/nurl_tls_large_record.key`
    ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → { ( println_label `cert_write` `FAIL` ) } }
    ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → { ( println_label `key_write` `FAIL` ) } }
    ( x509_selfsigned_free cert )

    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` 18774 cp kp )
    ?? lr {
        T listener → {
            : s shell_cmd
            `python3 -c "import ssl,socket,sys
ctx=ssl.create_default_context()
ctx.check_hostname=False
ctx.verify_mode=ssl.CERT_NONE
s=socket.create_connection(('127.0.0.1',18774))
ss=ctx.wrap_socket(s,server_hostname='localhost')
ss.sendall(b'GET / HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n')
buf=b''
while True:
    c=ss.recv(65536)
    if not c: break
    buf+=c
body=buf.rsplit(b'\\r\\n\\r\\n',1)[-1]
sys.stdout.write('body_len='+str(len(body))+chr(10))
sys.stdout.write('body_ok='+str(body==b'0123456789'*10000)+chr(10))" > /tmp/nurl_tls_large_record.out 2>&1 & echo $! > /tmp/nurl_tls_large_record.pid; sleep 0.20`
            : !Output ProcessErr bg ( process_run_shell shell_cmd )
            ?? bg {
                T bgo → ( output_free bgo )
                F e → ( println_label `bg_spawn` ( process_err_name e ) )
            }

            : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse { ^ ( big_body_handler req ) }
            : HttpServer srv ( server_new_with_timeout listener handler 5000 )
            : !v NetErr rr ( server_run_once srv )
            ?? rr {
                T _ → ( println_label `serve` `OK` )
                F e → ( println_label `serve` ( net_err_name e ) )
            }
            ( server_stop srv )

            : !Output ProcessErr wait_r ( process_run_shell `wait $(cat /tmp/nurl_tls_large_record.pid 2>/dev/null) 2>/dev/null; cat /tmp/nurl_tls_large_record.out` )
            ?? wait_r {
                T wo → { ( nurl_print ( output_stdout wo ) ) ( output_free wo ) }
                F e → ( println_label `wait_client` ( process_err_name e ) )
            }
        }
        F e → { ( println_label `tls_listen` ( net_err_name e ) ) }
    }
}

@ main → i {
    ( run_live_test )
    ^ 0
}
