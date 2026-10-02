// Post-handshake framing/transition failures cannot be tested by SSL_key_update,
// whose public API only emits valid messages. These feed the same source parser.
$ `stdlib/std/tls.nu`

// A connection with no socket, keyed for both directions, mid-sequence.
@ ku_state → TlsConn {
    : TlsConn h ( _tls_conn_new 0 )
    : ~ * TlsConnImpl c ( _tls_ptr h )
    ( ku_setup . c 0 )
    ^ h
}

@ ku_setup inout TlsConnImpl c → v {
    : ( Vec u ) ss ( bytes_from_str `01234567890123456789012345678901` )
    : ( Vec u ) cs ( bytes_from_str `12345678901234567890123456789012` )
    ( _set_keys c 0 ss ) ( _set_keys c 1 cs )
    = . c version 13 = . c established 1
    = . c read_nowait 1
    = . c s_seq 42 = . c c_seq 73
}

@ ku_msg i kind i length i request i extra → ( Vec u ) {
    : ( Vec u ) bytes ( vec_new [u] )
    ( vec_push [u] bytes # u kind ) ( _u24 bytes length )
    ( vec_push [u] bytes # u request )
    ? != extra 0 { ( vec_push [u] bytes # u 0 ) } {}
    ^ bytes
}

@ ku_invalid i kind i length i request i extra i direction → b {
    : TlsConn h ( ku_state )
    : ~ * TlsConnImpl c ( _tls_ptr h )
    : ( Vec u ) bytes ( ku_msg kind length request extra )
    : b rejected ?? ( _tls_post_hs . c 0 bytes direction ) { T _ → F F _ → T }
    : b unchanged & == . c s_seq 42 == . c c_seq 73
    : b closed > . c fatal_alert 0
    : ( Vec u ) alert ( vec_new [u] )
    ( _tls_control_to . c 0 alert - 1 direction )
    : b alert_sent & == ( vec_len [u] alert ) 24 == . c closed 1
    ^ & rejected & unchanged & closed alert_sent
}

@ main → i {
    : ~ i failures 0
    ? ! ( ku_invalid 24 0 0 0 0 ) { = failures + failures 1 } {}
    ? ! ( ku_invalid 24 2 0 1 0 ) { = failures + failures 1 } {}
    ? ! ( ku_invalid 24 1 2 0 0 ) { = failures + failures 1 } {}
    ? ! ( ku_invalid 24 1 1 1 0 ) { = failures + failures 1 } {}
    ? ! ( ku_invalid 99 1 0 0 0 ) { = failures + failures 1 } {}
    ? ! ( ku_invalid 4 1 0 0 1 ) { = failures + failures 1 } {}
    : ~ i direction 0
    ~ < direction 2 {
        : TlsConn h ( ku_state )
        : ~ * TlsConnImpl c ( _tls_ptr h )
        : ( Vec u ) first ( ku_msg 24 1 1 0 )
        : ( Vec u ) prefix ( bytes_slice first 0 3 )
        : ( Vec u ) suffix ( bytes_slice first 3 5 )
        ?? ( _tls_post_hs . c 0 prefix direction ) { T _ → {} F _ → { = failures + failures 1 } }
        ? | != . c s_seq 42 != . c c_seq 73 { = failures + failures 1 } {}
        ?? ( _tls_post_hs . c 0 suffix direction ) { T _ → {} F _ → { = failures + failures 1 } }
        ? != ? == direction 0 . c s_seq . c c_seq 0 { = failures + failures 1 } {}
        ? != . c update_pending 1 { = failures + failures 1 } {}
        : ( Vec u ) previous ( bytes_slice ? == direction 0 . c s_secret . c c_secret 0 32 )
        ?? ( _tls_post_hs . c 0 first direction ) { T _ → {} F _ → { = failures + failures 1 } }
        ? ( bytes_eq previous ? == direction 0 . c s_secret . c c_secret ) { = failures + failures 1 } {}
        : ( Vec u ) reply ( vec_new [u] )
        ( _tls_control_to . c 0 reply - 1 direction )
        ? | != ( vec_len [u] reply ) 27 != . c update_pending 0 { = failures + failures 1 } {}
        ? != ? == direction 0 . c c_seq . c s_seq 0 { = failures + failures 1 } {}
        = direction + direction 1
    }
    ( nurl_println ? == failures 0 `key update state: ok` `key update state: FAIL` )
    ^ ? == failures 0 0 1
}
