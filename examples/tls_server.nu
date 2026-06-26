// examples/tls_server.nu — a pure-NURL HTTPS "hello" server.
//
// Serves one TLS 1.3 connection with no OpenSSL: the handshake (ECDHE,
// AEAD, the ECDSA CertificateVerify) is all pure NURL via std/tls_server.
// Interoperates with curl / browsers / openssl s_client.
//
// Make a self-signed EC P-256 cert first:
//   openssl ecparam -genkey -name prime256v1 -noout -out key.pem
//   openssl req -new -x509 -key key.pem -out cert.pem -days 365 \
//       -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost"
//   openssl x509 -in cert.pem -outform DER -out cert.der
//
// Run:  tls_server cert.der key.pem 8443
//   then:  curl -k https://localhost:8443/

$ `stdlib/std/tls_server.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`

@ __arg ( Vec String ) v i idx → String {
    ?? ( vec_get [String] v idx ) { T s → ^ s F _ → ^ ( string_new ) }
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    ? < ( vec_len [String] args ) 4 {
        ( nurl_print `usage: tls_server <cert.der> <key.pem> <port>\n` )
        ^ 1
    } {}
    : s certpath ( string_data ( __arg args 1 ) )
    : s keypath ( string_data ( __arg args 2 ) )
    : i port ( nurl_str_to_int ( string_data ( __arg args 3 ) ) )

    : ( Vec u ) cert ?? ( read_file_bytes certpath ) { T v → v F _ → ( vec_new [u] ) }
    : String keypem ?? ( read_file keypath ) { T s → s F _ → ( string_new ) }
    : ( Vec u ) priv ?? ( ec_p256_priv_from_pem ( string_data keypem ) ) { T v → v F _ → ( vec_new [u] ) }
    ? | == ( vec_len [u] cert ) 0 != ( vec_len [u] priv ) 32 {
        ( nurl_print `failed to load cert/key\n` )
        ( vec_free [u] cert ) ( vec_free [u] priv ) ( string_free keypem )
        ^ 1
    } {}

    ?? ( tcp_listen `0.0.0.0` port ) {
        F _ → { ( nurl_print `listen failed\n` ) }
        T lst → {
            ( nurl_print `pure-NURL HTTPS server listening\n` )
            ?? ( tcp_accept lst ) {
                F _ → { ( nurl_print `accept failed\n` ) }
                T conn → {
                    // cert_chain is a framed CertificateEntry list — one leaf here.
                    : ( Vec u ) chain ( tls_cert_entry cert )
                    ?? ( tls_accept # i . conn raw chain priv ) {
                        F e → { ( nurl_print `handshake failed: ` ) ( nurl_print ( tls_err_name e ) ) ( nurl_print `\n` ) }
                        T c → {
                            ?? ( tls_server_read c 8192 ) { T req → ( vec_free [u] req ) F _ → {} }
                            : ( Vec u ) resp ( bytes_from_str `HTTP/1.1 200 OK\r\nContent-Length: 12\r\nConnection: close\r\n\r\nhello, pure!` )
                            ?? ( tls_server_write c resp ) { T _ → {} F _ → {} }
                            ( vec_free [u] resp )
                            ( tls_close c )
                        }
                    }
                    ( vec_free [u] chain )
                }
            }
            ( tcp_close_listener lst )
        }
    }
    ( vec_free [u] cert ) ( vec_free [u] priv ) ( string_free keypem )
    ^ 0
}
