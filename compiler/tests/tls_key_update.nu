// Post-handshake framing/transition failures cannot be tested by SSL_key_update,
// whose public API only emits valid messages. These feed the same source parser.
$ `stdlib/std/tls.nu`

@ ku_state → *TlsConn {
    : *TlsConn c # *TlsConn ( nurl_zalloc Z TlsConn )
    = . c hsbuf ( vec_new [u] )
    = . c s_secret ( bytes_from_str `01234567890123456789012345678901` )
    = . c c_secret ( bytes_from_str `12345678901234567890123456789012` )
    = . c s_key ( vec_new [u] ) = . c s_iv ( vec_new [u] )
    = . c c_key ( vec_new [u] ) = . c c_iv ( vec_new [u] )
    ( _set_keys c 0 . c s_secret ) ( _set_keys c 1 . c c_secret )
    = . c version 13 = . c established 1
    = . c read_nowait 1
    = . c s_seq 42 = . c c_seq 73
    ^ c
}

@ ku_free * TlsConn c → v {
    ( vec_free [u] . c hsbuf )
    ( vec_free [u] . c s_secret ) ( vec_free [u] . c c_secret )
    ( vec_free [u] . c s_key ) ( vec_free [u] . c s_iv )
    ( vec_free [u] . c c_key ) ( vec_free [u] . c c_iv )
    ( nurl_free # s c )
}

@ ku_msg i kind i length i request i extra → ( Vec u ) {
    : ( Vec u ) bytes ( vec_new [u] )
    ( vec_push [u] bytes # u kind ) ( _u24 bytes length )
    ( vec_push [u] bytes # u request )
    ? != extra 0 { ( vec_push [u] bytes # u 0 ) } {}
    ^ bytes
}

@ ku_invalid i kind i length i request i extra i direction → b {
    : *TlsConn c ( ku_state )
    : ( Vec u ) bytes ( ku_msg kind length request extra )
    : b rejected ?? ( _tls_post_hs c bytes direction ) { T _ → F F _ → T }
    : b unchanged & == . c s_seq 42 == . c c_seq 73
    : b closed > . c fatal_alert 0
    : ( Vec u ) alert ( vec_new [u] )
    ( _tls_control_to c alert - 1 direction )
    : b alert_sent & == ( vec_len [u] alert ) 24 == . c closed 1
    ( vec_free [u] alert )
    ( vec_free [u] bytes ) ( ku_free c )
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
        : *TlsConn c ( ku_state )
        : ( Vec u ) first ( ku_msg 24 1 1 0 )
        : ( Vec u ) prefix ( bytes_slice first 0 3 )
        : ( Vec u ) suffix ( bytes_slice first 3 5 )
        ?? ( _tls_post_hs c prefix direction ) { T _ → {} F _ → { = failures + failures 1 } }
        ? | != . c s_seq 42 != . c c_seq 73 { = failures + failures 1 } {}
        ?? ( _tls_post_hs c suffix direction ) { T _ → {} F _ → { = failures + failures 1 } }
        ? != ? == direction 0 . c s_seq . c c_seq 0 { = failures + failures 1 } {}
        ? != . c update_pending 1 { = failures + failures 1 } {}
        : ( Vec u ) previous ( bytes_slice ? == direction 0 . c s_secret . c c_secret 0 32 )
        ?? ( _tls_post_hs c first direction ) { T _ → {} F _ → { = failures + failures 1 } }
        ? ( bytes_eq previous ? == direction 0 . c s_secret . c c_secret ) { = failures + failures 1 } {}
        : ( Vec u ) reply ( vec_new [u] )
        ( _tls_control_to c reply - 1 direction )
        ? | != ( vec_len [u] reply ) 27 != . c update_pending 0 { = failures + failures 1 } {}
        ? != ? == direction 0 . c c_seq . c s_seq 0 { = failures + failures 1 } {}
        ( vec_free [u] reply ) ( vec_free [u] previous )
        ( vec_free [u] prefix ) ( vec_free [u] suffix ) ( vec_free [u] first )
        ( ku_free c )
        = direction + direction 1
    }
    ( nurl_println ? == failures 0 `key update state: ok` `key update state: FAIL` )
    ^ ? == failures 0 0 1
}
