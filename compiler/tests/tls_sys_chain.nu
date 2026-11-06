// tls_sys_chain.nu — the trust anchor step with the system's verifier
// in it grants no trust it should not.
//
// Verified TLS anchors a chain to a PEM bundle; on Windows, which keeps
// none, the anchor question goes to the system's chain engine (Agora
// #504, runtime_ffi.c §14a). A one-certificate chain of a fresh
// self-signed `localhost` certificate through tls_chain_verify:
//
//   unknown_refused  SSL_CERT_FILE unset: no bundle holds it and the
//                    system does not trust it (Windows: the engine
//                    refuses it; elsewhere there is no system verifier),
//                    so the chain has no trust anchor (code 5)
//   file_anchors     SSL_CERT_FILE = the certificate: it anchors (0)
//   damaged_refused  a chain whose certificate is not DER is refused,
//                    never handed to the system as trusted
//
// The positive half — a public server verifies on Windows with no
// SSL_CERT_FILE — needs the network: tls_sys_chain_live.nu.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/tls_verify.nu`
$ `stdlib/ext/env.nu`

@ chk s label b ok → b {
    ( nurl_print label )
    ( nurl_print ? ok ` ok\n` ` FAIL\n` )
    ^ ok
}

@ push24 ( Vec u ) v i n → v {
    ( vec_push [u] v # u & >> n 16 255 )
    ( vec_push [u] v # u & >> n 8 255 )
    ( vec_push [u] v # u & n 255 )
}

// A TLS 1.2 Certificate handshake message carrying one certificate.
@ cert_msg ( Vec u ) der → ( Vec u ) {
    : i n ( vec_len [u] der )
    : ( Vec u ) m ( vec_new [u] )
    ( vec_push [u] m # u 11 )
    ( push24 m + n 6 )
    ( push24 m + n 3 )
    ( push24 m n )
    ( bytes_extend_bytes m der )
    ^ m
}

@ main → i {
    : ~ b all T
    : !v IoErr e0 ( env_unset `SSL_CERT_FILE` )
    ?? e0 { T _ → {} F _e → {} }

    : X509SelfSigned c ( x509_selfsigned_p256 `localhost` 30 )
    : ( Vec u ) der ?? ( pem_to_der ( string_data . c cert_pem ) ) { T v → v F _e → ( vec_new [u] ) }
    : ( Vec u ) msg ( cert_msg der )
    = all & all ( chk `unknown_refused ` == ( tls_chain_verify msg 1 `localhost` ) 5 )

    : String path ( env_temp_dir )
    ( string_push_str path `/nurl_tls_sys_chain.pem` )
    ?? ( write_file ( string_data path ) ( string_data . c cert_pem ) ) { T _ → {} F _e → { ( chk `write pem       ` F ) ^ 1 } }
    : !v IoErr e1 ( env_set `SSL_CERT_FILE` ( string_data path ) )
    ?? e1 { T _ → {} F _e → {} }
    = all & all ( chk `file_anchors    ` == ( tls_chain_verify msg 1 `localhost` ) 0 )
    : !v IoErr e2 ( env_unset `SSL_CERT_FILE` )
    ?? e2 { T _ → {} F _e → {} }
    ( file_delete ( string_data path ) )

    : ( Vec u ) junk ( cert_msg ( bytes_from_str `not a certificate` ) )
    = all & all ( chk `damaged_refused ` != ( tls_chain_verify junk 1 `localhost` ) 0 )

    ( x509_selfsigned_free c )
    ^ ? all 0 1
}
