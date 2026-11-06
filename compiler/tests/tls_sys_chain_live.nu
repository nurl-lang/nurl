// tls_sys_chain_live.nu — verify-full reaches public servers with the
// system's own trust, SSL_CERT_FILE unset (network-gated).
//
// Windows keeps no CA bundle file, and its certificate store holds only
// the roots this machine has needed so far: with nothing but the Unix
// bundle paths to read, every verified https connection on Windows failed
// (Agora #504). The anchor question now goes to the system's chain
// engine there, which fetches a trusted root it has not seen yet. Two
// servers whose roots differ: example.com (SSL.com TLS ECC Root CA 2022,
// absent from a fresh Windows store) and huggingface.co (Amazon). On
// Linux and macOS the same connects anchor to the bundle file as before.
//
// Manual run:
//   NURL_HTTP_TESTS=1 ./build.sh         (Linux/macOS)
//   set NURL_HTTP_TESTS=1 & build.bat    (Windows cmd)
// requires: internet
$ `stdlib/core/string.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/ext/env.nu`

@ chk s label b ok → b {
    ( nurl_print label )
    ( nurl_print ? ok ` ok\n` ` FAIL\n` )
    ^ ok
}

@ verifies s host → b {
    ?? ( tls_connect host 443 host ) {
        T conn → { ( tls_close conn ) ^ T }
        F _e → { ^ F }
    }
}

@ main → i {
    : !v IoErr e0 ( env_unset `SSL_CERT_FILE` )
    ?? e0 { T _ → {} F _e → {} }
    : ~ b all T
    = all & all ( chk `example.com     ` ( verifies `example.com` ) )
    = all & all ( chk `huggingface.co  ` ( verifies `huggingface.co` ) )
    ^ ? all 0 1
}
