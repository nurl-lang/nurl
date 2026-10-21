// tls_record_inplace.nu — the TLS 1.3 record layer sealed and opened in
// place (agora t44), without a socket: two connection states share one
// client traffic secret, records are sealed into the writer's txbuf and
// opened out of the reader's rxbuf, for both suites (ChaCha20-Poly1305
// and AES-128-GCM) and plaintexts of 1 to 40 000 bytes (one record, a
// full 16 KB record, several).
//
// It holds three things the HTTPS tests cannot see from outside:
//   * every byte comes back, record boundaries and all;
//   * in steady state a record costs NO allocation — sealing appends to
//     the reused txbuf, opening decrypts inside rxbuf and copies the
//     plaintext once into the caller's buffer (the per-record key
//     schedule, nonce, AAD, inner-plaintext and MAC-input Vecs are gone);
//   * a record with a flipped bit is refused (TlsDecrypt), and the
//     sequence numbers stay in step across all of it.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/tls_server.nu`

& `libc` @ nurl_alloc_count → i

@ fill i n i seed → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u & + seed * k 131 255 ) = k + k 1 }
    ^ v
}

unsafe @ conn i cipher ( Vec u ) secret → TlsConn {
    : TlsConn t ( _tls_conn_new 0 )
    : ~ * TlsConnImpl c ( _tls_ptr t )
    = . c cipher cipher
    = . c established 1
    ( _set_keys . c 0 1 secret )
    ^ t
}

// Seal `data` as application records on `w` (client direction) and hand
// the wire bytes to `r`'s record buffer.
unsafe @ ship TlsConn w TlsConn r ( Vec u ) data → v {
    : ~ * TlsConnImpl a ( _tls_ptr w )
    : ~ * TlsConnImpl b ( _tls_ptr r )
    ( vec_clear [u] . a txbuf )
    : i n ( vec_len [u] data )
    : ~ i off 0
    ~ < off n {
        : i hi ? < - n off 16384 n + off 16384
        ( _tls_rec_range_to . a 0 . a txbuf 1 23 data off hi )
        = off hi
    }
    ( bytes_extend_bytes . b rxbuf . a txbuf )
}

// Read everything buffered on `r` into `dst`.
unsafe @ drain TlsConn r ( Vec u ) dst → i {
    : ~ * TlsConnImpl b ( _tls_ptr r )
    : ~ i got 0
    ~ > ( vec_len [u] . b rxbuf ) 0 {
        ?? ( tls_server_read_into r dst 65536 ) { T n → { = got + got n } F _ → { ^ -1 } }
    }
    ^ got
}

unsafe @ suite i cipher → i {
    : ~ i bad 0
    : ( Vec u ) secret ( fill 32 9 )
    : TlsConn w ( conn cipher secret )
    : TlsConn r ( conn cipher secret )
    : ( Vec u ) dst ( vec_new [u] )
    // correctness over sizes
    : ~ i n 1
    ~ <= n 40000 {
        : ( Vec u ) data ( fill n n )
        ( vec_clear [u] dst )
        ( ship w r data )
        : i got ( drain r dst )
        ? | != got n ! ( bytes_eq dst data ) {
            ( nurl_print `mismatch at n=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
            = bad + bad 1
        } {}
        = n ? < n 300 + n 37 + * n 3 1
    }
    // steady state: a 1 KB record each way, no allocation
    : ( Vec u ) msg ( fill 1024 5 )
    ( vec_reserve [u] dst 4096 )
    : ~ i warm 0
    ~ < warm 4 { ( vec_clear [u] dst ) ( ship w r msg ) : i _g ( drain r dst ) = warm + warm 1 }
    : i a0 ( nurl_alloc_count )
    : ~ i it 0
    ~ < it 100 { ( vec_clear [u] dst ) ( ship w r msg ) : i _g ( drain r dst ) = it + it 1 }
    : i allocs - ( nurl_alloc_count ) a0
    ? != allocs 0 {
        ( nurl_print `allocations in 100 steady-state records: ` ) ( nurl_print ( nurl_str_int allocs ) ) ( nurl_print `\n` )
        = bad + bad 1
    } {}
    ? ! ( bytes_eq dst msg ) { = bad + bad 1 } {}
    // a flipped ciphertext bit is refused
    : ~ * TlsConnImpl a ( _tls_ptr w )
    : ~ * TlsConnImpl b ( _tls_ptr r )
    ( ship w r msg )
    ( vec_put [u] . b rxbuf 9 # u ^^ # i ( vec_at [u] . b rxbuf 9 ) 4 )
    ( vec_clear [u] dst )
    ?? ( tls_server_read_into r dst 65536 ) {
        T _ → { ( nurl_print `tampered record accepted\n` ) = bad + bad 1 }
        F e → { ?? e { TlsDecrypt → {} _ → { = bad + bad 1 } } }
    }
    ? != . a c_seq . b c_seq { ( nurl_print `sequence numbers out of step\n` ) = bad + bad 1 } {}
    ^ bad
}

unsafe @ main → i {
    : i b0 ( suite 0 )
    : i b1 ( suite 1 )
    ( nurl_print `chacha20-poly1305: ` ) ( nurl_print ? == b0 0 `ok` `FAIL` ) ( nurl_print `\n` )
    ( nurl_print `aes-128-gcm: ` ) ( nurl_print ? == b1 0 `ok` `FAIL` ) ( nurl_print `\n` )
    ^ + b0 b1
}
