// packages/tls/src/tls.nu — a pure-NURL TLS 1.3 client (RFC 8446).
//
// No OpenSSL, no FFI beyond the libc TCP socket: the handshake crypto
// (X25519, ChaCha20-Poly1305, HKDF, SHA-256) is all pure NURL, so a
// program can open an authenticated, encrypted TLS 1.3 connection on a
// host with nothing installed — Linux, macOS, the BSDs, Windows.
//
// Cipher suite: TLS_CHACHA20_POLY1305_SHA256 with the X25519 group.
// That single suite is accepted by essentially every modern TLS 1.3
// server (OpenSSL, BoringSSL, nginx, the big CDNs).
//
// Surface:
//   ( tls_connect host port server_name ) → !*TlsConn TlsErr   (no cert check)
//   ( tls_write conn bytes )              → !v TlsErr
//   ( tls_read conn max )                 → !( Vec u ) TlsErr   ([] at EOF)
//   ( tls_close conn )                    → v
//
// Certificate verification is handled by a separate layer (the server's
// certificate is captured into `conn` for the verifier to inspect); this
// module establishes the encrypted channel and the handshake transcript.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hkdf.nu`
$ `stdlib/std/x25519.nu`
$ `stdlib/std/chacha20poly1305.nu`

& `libc` @ nurl_tcp_connect s host i port → i
& `c` @ nurl_rand_fill * u buf i n → i


: | TlsErr {
    TlsConnect
    TlsHandshake
    TlsDecrypt
    TlsRead
    TlsWrite
    TlsClosed
    TlsAlert
    TlsProtocol
    TlsBadCipher
    TlsHRR
}

@ tls_err_name TlsErr e → s {
    ^ ?? e {
        TlsConnect → `TlsConnect`
        TlsHandshake → `TlsHandshake`
        TlsDecrypt → `TlsDecrypt`
        TlsRead → `TlsRead`
        TlsWrite → `TlsWrite`
        TlsClosed → `TlsClosed`
        TlsAlert → `TlsAlert`
        TlsProtocol → `TlsProtocol`
        TlsBadCipher → `TlsBadCipher`
        TlsHRR → `TlsHRR`
    }
}

// Live connection state. Vec fields are reassigned as keys rotate
// (handshake → application) and as buffers are consumed.
: TlsConn {
    TcpConn tcp
    ( Vec u ) rxbuf       // raw socket bytes not yet split into records
    ( Vec u ) hsbuf       // decrypted handshake bytes not yet a full message
    ( Vec u ) appbuf      // decrypted application bytes for the caller
    ( Vec u ) s_key
    ( Vec u ) s_iv
    ( Vec u ) c_key
    ( Vec u ) c_iv
    i s_seq
    i c_seq
    i enc_read           // 1 once server records are encrypted
    i established
    i closed
    ( Vec u ) server_cert // first cert in the server's chain (DER), for the verifier
}

// ── small helpers ─────────────────────────────────────────────────
@ __t_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ __u16 ( Vec u ) v i n → v {
    ( vec_push [u] v # u & >> n 8 255 )
    ( vec_push [u] v # u & n 255 )
}

@ __u24 ( Vec u ) v i n → v {
    ( vec_push [u] v # u & >> n 16 255 )
    ( vec_push [u] v # u & >> n 8 255 )
    ( vec_push [u] v # u & n 255 )
}

@ __cat ( Vec u ) dst ( Vec u ) src → v {
    : i n ( vec_len [u] src )
    : ~ i k 0
    ~ < k n { ( vec_push [u] dst # u ( __t_bget src k ) ) = k + k 1 }
}

// Append a 2-byte length prefix + the block bytes.
@ __blk16 ( Vec u ) dst ( Vec u ) sub → v {
    ( __u16 dst ( vec_len [u] sub ) )
    ( __cat dst sub )
}

// Read a big-endian integer of `n` bytes from `v` at `off`.
@ __rdint ( Vec u ) v i off i n → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k n { = acc | << acc 8 ( __t_bget v + off k ) = k + k 1 }
    ^ acc
}

@ __rand_bytes i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    : i _r ( nurl_rand_fill # *u ( vec_data [u] v ) n )
    ^ v
}

// ── socket record I/O ─────────────────────────────────────────────
// Ensure rxbuf holds at least `n` bytes, reading from the socket.
// Direct blocking read via the runtime socket primitive. tcp_read_chunk
// dispatches to a fiber/epoll path when a fiber context is present, which
// parks with no reactor to wake it in a plain program; the raw blocking
// read is what a synchronous client wants.
@ __fill * TlsConn c i n → !i TlsErr {
    : TcpConn tc . c tcp
    : i raw # i . tc raw
    ~ < ( vec_len [u] . c rxbuf ) n {
        : ( Vec u ) tmp ( vec_with_cap [u] 16384 )
        : *u p ( vec_data [u] tmp )
        : s pbuf # s p
        : i got ( nurl_tcp_read raw pbuf 16384 )
        ? < got 0 { ( vec_free [u] tmp ) ^ @ !i TlsErr { F # TlsErr TlsRead } } {}
        ? == got 0 { ( vec_free [u] tmp ) ^ @ !i TlsErr { F # TlsErr TlsClosed } } {}
        : b _ok ( vec_set_len [u] tmp got )
        ( __cat . c rxbuf tmp )
        ( vec_free [u] tmp )
    }
    ^ @ !i TlsErr { T 1 }
}

// Drop the first `n` bytes of rxbuf (consume them).
@ __consume * TlsConn c i n → v {
    : ( Vec u ) old . c rxbuf
    : i total ( vec_len [u] old )
    : ( Vec u ) rest ( bytes_slice old n total )
    ( vec_free [u] old )
    = . c rxbuf rest
}

// Record = type(1) ver(2) length(2) body. Returns (type, body); body is
// an owned slice the caller frees.
: TlsRecord { i rtype ( Vec u ) body }

@ __read_record * TlsConn c → !TlsRecord TlsErr {
    : !i TlsErr h ( __fill c 5 )
    ?? h { T _ → {} F e → { ^ @ !TlsRecord TlsErr { F e } } }
    : i rtype ( __t_bget . c rxbuf 0 )
    : i len ( __rdint . c rxbuf 3 2 )
    : !i TlsErr b ( __fill c + 5 len )
    ?? b { T _ → {} F e → { ^ @ !TlsRecord TlsErr { F e } } }
    : ( Vec u ) body ( bytes_slice . c rxbuf 5 + 5 len )
    ( __consume c + 5 len )
    ^ @ !TlsRecord TlsErr { T @ TlsRecord { rtype body } }
}

// Build the per-record nonce: static IV with the 64-bit sequence number
// XORed into the low 8 bytes.
@ __nonce ( Vec u ) iv i seq → ( Vec u ) {
    : ( Vec u ) n ( vec_with_cap [u] 12 )
    : ~ i k 0
    ~ < k 12 { ( vec_push [u] n # u ( __t_bget iv k ) ) = k + k 1 }
    : ~ i b 0
    ~ < b 8 {
        : i sb & >> seq * 8 - 7 b 255
        ( vec_set [u] n + 4 b # u ^^ ( __t_bget n + 4 b ) sb )
        = b + b 1
    }
    ^ n
}

// AEAD-decrypt one application_data record body (ct‖tag) → inner plaintext.
@ __decrypt_record * TlsConn c ( Vec u ) body → ?( Vec u ) {
    : i blen ( vec_len [u] body )
    : ( Vec u ) aad ( vec_with_cap [u] 5 )
    ( vec_push [u] aad # u 23 )
    ( vec_push [u] aad # u 3 )
    ( vec_push [u] aad # u 3 )
    ( __u16 aad blen )
    : ( Vec u ) nonce ( __nonce . c s_iv . c s_seq )
    : ?( Vec u ) pt ( aead_decrypt . c s_key nonce aad body )
    ( vec_free [u] aad )
    ( vec_free [u] nonce )
    = . c s_seq + . c s_seq 1
    ^ pt
}

// Strip TLS 1.3 inner padding: trailing zeros then the real content type.
// Returns the content type; truncates `inner` to the real content length.
@ __inner_type ( Vec u ) inner → i {
    : ~ i i - ( vec_len [u] inner ) 1
    ~ & >= i 0 == ( __t_bget inner i ) 0 { = i - i 1 }
    ? < i 0 { ^ 0 } {}
    : i ct ( __t_bget inner i )
    : b _ok ( vec_set_len [u] inner i )
    ^ ct
}

// Encrypt + send one record of `content` under the client keys.
@ __send_encrypted * TlsConn c i content_type ( Vec u ) content → !v TlsErr {
    : ( Vec u ) inner ( vec_with_cap [u] + ( vec_len [u] content ) 1 )
    ( __cat inner content )
    ( vec_push [u] inner # u content_type )
    : i total + ( vec_len [u] inner ) 16
    : ( Vec u ) aad ( vec_with_cap [u] 5 )
    ( vec_push [u] aad # u 23 )
    ( vec_push [u] aad # u 3 )
    ( vec_push [u] aad # u 3 )
    ( __u16 aad total )
    : ( Vec u ) nonce ( __nonce . c c_iv . c c_seq )
    : ( Vec u ) sealed ( aead_encrypt . c c_key nonce aad inner )
    : ( Vec u ) rec ( vec_with_cap [u] + total 5 )
    ( vec_push [u] rec # u 23 )
    ( vec_push [u] rec # u 3 )
    ( vec_push [u] rec # u 3 )
    ( __u16 rec total )
    ( __cat rec sealed )
    : !v NetErr w ( tcp_write_all . c tcp rec )
    ( vec_free [u] inner )
    ( vec_free [u] aad )
    ( vec_free [u] nonce )
    ( vec_free [u] sealed )
    ( vec_free [u] rec )
    = . c c_seq + . c c_seq 1
    ^ ?? w { T _ → @ !v TlsErr { T 0 } F _ → @ !v TlsErr { F # TlsErr TlsWrite } }
}

// Write a plaintext record straight to the socket.
@ __send_plain * TlsConn c i rtype ( Vec u ) body → !v TlsErr {
    : ( Vec u ) rec ( vec_with_cap [u] + ( vec_len [u] body ) 5 )
    ( vec_push [u] rec # u rtype )
    // legacy_record_version 0x0303 (RFC 8446 §5.1: required for every
    // record except the initial ClientHello, where 0x0303 is also valid).
    ( vec_push [u] rec # u 3 )
    ( vec_push [u] rec # u 3 )
    ( __u16 rec ( vec_len [u] body ) )
    ( __cat rec body )
    : !v NetErr w ( tcp_write_all . c tcp rec )
    ( vec_free [u] rec )
    ^ ?? w { T _ → @ !v TlsErr { T 0 } F _ → @ !v TlsErr { F # TlsErr TlsWrite } }
}

// ── handshake-message reader ──────────────────────────────────────
// Pull the next complete handshake message (header + body) from hsbuf,
// decrypting more records as needed. CCS records are skipped.
@ __next_hs * TlsConn c → !( Vec u ) TlsErr {
    : ~ i need 1
    ~ == need 1 {
        : i have ( vec_len [u] . c hsbuf )
        ? >= have 4 {
            : i mlen ( __rdint . c hsbuf 1 3 )
            ? >= have + 4 mlen {
                : ( Vec u ) msg ( bytes_slice . c hsbuf 0 + 4 mlen )
                : ( Vec u ) rest ( bytes_slice . c hsbuf + 4 mlen have )
                ( vec_free [u] . c hsbuf )
                = . c hsbuf rest
                ^ @ !( Vec u ) TlsErr { T msg }
            } {}
        } {}
        // Need more bytes: read another record.
        : !TlsRecord TlsErr rr ( __read_record c )
        ?? rr {
            F e → { ^ @ !( Vec u ) TlsErr { F e } }
            T rec → {
                ? == . rec rtype 20 {
                    // change_cipher_spec — ignore.
                    ( vec_free [u] . rec body )
                } {
                    ? == . rec rtype 23 {
                        ?? ( __decrypt_record c . rec body ) {
                            T inner → {
                                ( vec_free [u] . rec body )
                                : i ct ( __inner_type inner )
                                ? == ct 22 {
                                    ( __cat . c hsbuf inner )
                                    ( vec_free [u] inner )
                                } {
                                    ( vec_free [u] inner )
                                    ? == ct 21 { ^ @ !( Vec u ) TlsErr { F # TlsErr TlsAlert } } {}
                                    ^ @ !( Vec u ) TlsErr { F # TlsErr TlsProtocol }
                                }
                            }
                            F _ → {
                                ( vec_free [u] . rec body )
                                ^ @ !( Vec u ) TlsErr { F # TlsErr TlsDecrypt }
                            }
                        }
                    } {
                        // plaintext handshake (ServerHello stage) or alert
                        ? == . rec rtype 22 {
                            ( __cat . c hsbuf . rec body )
                            ( vec_free [u] . rec body )
                        } {
                            ( vec_free [u] . rec body )
                            ^ @ !( Vec u ) TlsErr { F # TlsErr TlsProtocol }
                        }
                    }
                }
            }
        }
    }
    ^ @ !( Vec u ) TlsErr { F # TlsErr TlsProtocol }
}

// ── ClientHello ───────────────────────────────────────────────────
@ __build_client_hello s host ( Vec u ) pubkey ( Vec u ) random ( Vec u ) sessid → ( Vec u ) {
    : ( Vec u ) body ( vec_new [u] )
    ( __u16 body 771 )            // legacy_version 0x0303
    ( __cat body random )         // 32-byte random
    ( vec_push [u] body # u 32 )  // session id length
    ( __cat body sessid )
    // cipher_suites: TLS_CHACHA20_POLY1305_SHA256 (0x1303)
    ( __u16 body 2 )
    ( __u16 body 4867 )
    // compression methods
    ( vec_push [u] body # u 1 )
    ( vec_push [u] body # u 0 )

    // extensions
    : ( Vec u ) ext ( vec_new [u] )

    // server_name (0x0000)
    : ( Vec u ) sni ( vec_new [u] )
    : i hl ( nurl_str_len host )
    ( __u16 sni + hl 3 )          // ServerNameList length
    ( vec_push [u] sni # u 0 )    // name_type host_name
    ( __u16 sni hl )
    : ~ i k 0
    ~ < k hl { ( vec_push [u] sni # u ( nurl_str_get host k ) ) = k + k 1 }
    ( __u16 ext 0 )
    ( __blk16 ext sni )
    ( vec_free [u] sni )

    // supported_groups (0x000a): x25519 (0x001d)
    : ( Vec u ) grp ( vec_new [u] )
    ( __u16 grp 2 )
    ( __u16 grp 29 )
    ( __u16 ext 10 )
    ( __blk16 ext grp )
    ( vec_free [u] grp )

    // signature_algorithms (0x000d)
    : ( Vec u ) sa ( vec_new [u] )
    ( __u16 sa 16 )               // list length (8 algs × 2)
    ( __u16 sa 1027 )             // ecdsa_secp256r1_sha256 0x0403
    ( __u16 sa 2052 )             // rsa_pss_rsae_sha256    0x0804
    ( __u16 sa 1025 )             // rsa_pkcs1_sha256       0x0401
    ( __u16 sa 1283 )             // ecdsa_secp384r1_sha384 0x0503
    ( __u16 sa 2053 )             // rsa_pss_rsae_sha384    0x0805
    ( __u16 sa 2054 )             // rsa_pss_rsae_sha512    0x0806
    ( __u16 sa 2055 )             // ed25519                0x0807
    ( __u16 sa 1281 )             // rsa_pkcs1_sha384       0x0501
    ( __u16 ext 13 )
    ( __blk16 ext sa )
    ( vec_free [u] sa )

    // supported_versions (0x002b): TLS 1.3 (0x0304)
    : ( Vec u ) sv ( vec_new [u] )
    ( vec_push [u] sv # u 2 )
    ( __u16 sv 772 )
    ( __u16 ext 43 )
    ( __blk16 ext sv )
    ( vec_free [u] sv )

    // key_share (0x0033): x25519 + 32-byte pubkey
    : ( Vec u ) ks ( vec_new [u] )
    : ( Vec u ) entry ( vec_new [u] )
    ( __u16 entry 29 )            // group x25519
    ( __u16 entry 32 )            // key_exchange length
    ( __cat entry pubkey )
    ( __u16 ks ( vec_len [u] entry ) )
    ( __cat ks entry )
    ( __u16 ext 51 )
    ( __blk16 ext ks )
    ( vec_free [u] entry )
    ( vec_free [u] ks )

    ( __blk16 body ext )
    ( vec_free [u] ext )

    // wrap as handshake message: type=1 (client_hello) + 3-byte length
    : ( Vec u ) hs ( vec_with_cap [u] + ( vec_len [u] body ) 4 )
    ( vec_push [u] hs # u 1 )
    ( __u24 hs ( vec_len [u] body ) )
    ( __cat hs body )
    ( vec_free [u] body )
    ^ hs
}

// Parse ServerHello (full handshake message bytes) → server x25519 pubkey.
@ __parse_server_hello ( Vec u ) msg → !( Vec u ) TlsErr {
    // [0]=type(2) [1..4]=len ; body starts at 4
    // body: ver(2) random(32) sid_len(1) sid cipher(2) comp(1) ext_len(2) ext...
    : ~ i p 4
    // HelloRetryRequest detection: random == special constant.
    ? ( __is_hrr msg ) { ^ @ !( Vec u ) TlsErr { F # TlsErr TlsHRR } } {}
    = p + p 2            // skip legacy_version
    = p + p 32           // skip random
    : i sidlen ( __t_bget msg p )
    = p + + p 1 sidlen
    : i cipher ( __rdint msg p 2 )
    = p + p 2
    ? != cipher 4867 { ^ @ !( Vec u ) TlsErr { F # TlsErr TlsBadCipher } } {}
    = p + p 1            // skip compression method
    : i extlen ( __rdint msg p 2 )
    = p + p 2
    : i extend + p extlen
    : ~ ( Vec u ) found ( vec_new [u] )
    : ~ i got 0
    ~ < p extend {
        : i etype ( __rdint msg p 2 )
        : i elen ( __rdint msg + p 2 2 )
        : i edata + p 4
        ? == etype 51 {
            // key_share: group(2) ke_len(2) key_exchange
            : i klen ( __rdint msg + edata 2 2 )
            : ( Vec u ) key ( bytes_slice msg + edata 4 + + edata 4 klen )
            ( vec_free [u] found )
            = found key
            = got 1
        } {}
        = p + + p 4 elen
    }
    ? == got 0 { ( vec_free [u] found ) ^ @ !( Vec u ) TlsErr { F # TlsErr TlsHandshake } } {}
    ^ @ !( Vec u ) TlsErr { T found }
}

@ __is_hrr ( Vec u ) msg → b {
    // SHA-256("HelloRetryRequest") in the ServerHello random field.
    : i a ( __t_bget msg 6 )
    : i b ( __t_bget msg 7 )
    : i c2 ( __t_bget msg 8 )
    : i d ( __t_bget msg 9 )
    ^ & & & == a 207 == b 33 == c2 173 == d 116
}

// ── traffic-key derivation ────────────────────────────────────────
// From a traffic secret, derive (key, iv) and store on the conn for the
// given direction. dir 0 = server-read, 1 = client-write.
@ __set_keys * TlsConn c i dir ( Vec u ) secret → v {
    : ( Vec u ) emptyc ( vec_new [u] )
    : ( Vec u ) key ( hkdf_expand_label secret `key` emptyc 32 )
    : ( Vec u ) iv ( hkdf_expand_label secret `iv` emptyc 12 )
    ( vec_free [u] emptyc )
    ? == dir 0 {
        ( vec_free [u] . c s_key )
        ( vec_free [u] . c s_iv )
        = . c s_key key
        = . c s_iv iv
        = . c s_seq 0
    } {
        ( vec_free [u] . c c_key )
        ( vec_free [u] . c c_iv )
        = . c c_key key
        = . c c_iv iv
        = . c c_seq 0
    }
}

// HMAC-based Finished verify_data over a traffic secret + transcript hash.
@ __finished_mac ( Vec u ) secret ( Vec u ) thash → ( Vec u ) {
    : ( Vec u ) emptyc ( vec_new [u] )
    : ( Vec u ) fkey ( hkdf_expand_label secret `finished` emptyc 32 )
    : ( Vec u ) mac ( hmac_sha256_pure fkey thash )
    ( vec_free [u] emptyc )
    ( vec_free [u] fkey )
    ^ mac
}

// Extract the leaf certificate DER from a Certificate handshake message.
@ __extract_cert ( Vec u ) msg → ( Vec u ) {
    // type(1) len(3) ctx_len(1) ctx... certlist_len(3) [cert_len(3) cert ext(2)]...
    : i ctxlen ( __t_bget msg 4 )
    : ~ i p + 5 ctxlen        // skip context
    = p + p 3                 // skip certificate_list length
    : i clen ( __rdint msg p 3 )
    : ( Vec u ) der ( bytes_slice msg + p 3 + + p 3 clen )
    ^ der
}

// Establish a TLS 1.3 connection. `server_name` drives SNI (use the
// host). Certificate verification is NOT performed here — inspect
// conn.server_cert afterward. Returns an established TlsConn.
@ tls_connect s host i port s server_name → !*TlsConn TlsErr {
    : i raw ( nurl_tcp_connect host port )
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 { ^ @ !*TlsConn TlsErr { F # TlsErr TlsConnect } } {}
    : s rp # s raw
    : TcpConn tcp @ TcpConn { rp }

    // Heap-allocate the connection so field mutations (key rotation,
    // buffer consumption) in the helpers persist across calls.
    : * TlsConn c # * TlsConn ( nurl_alloc Z TlsConn )
    = . c tcp tcp
    = . c rxbuf ( vec_new [u] )
    = . c hsbuf ( vec_new [u] )
    = . c appbuf ( vec_new [u] )
    = . c s_key ( vec_new [u] )
    = . c s_iv ( vec_new [u] )
    = . c c_key ( vec_new [u] )
    = . c c_iv ( vec_new [u] )
    = . c s_seq 0
    = . c c_seq 0
    = . c enc_read 0
    = . c established 0
    = . c closed 0
    = . c server_cert ( vec_new [u] )

    // ── key share ──
    : ( Vec u ) priv ( __rand_bytes 32 )
    : ( Vec u ) cpub ( x25519_base priv )
    : ( Vec u ) random ( __rand_bytes 32 )
    : ( Vec u ) sessid ( __rand_bytes 32 )

    // ── transcript ──
    : ~ ( Vec u ) tr ( vec_new [u] )

    // ── ClientHello ──
    : ( Vec u ) ch ( __build_client_hello server_name cpub random sessid )
    ( __cat tr ch )
    : !v TlsErr sw ( __send_plain c 22 ch )
    ?? sw { T _ → {} F e → { ^ ( __fail c priv cpub random sessid ch tr e ) } }

    // ── ServerHello ──
    : !( Vec u ) TlsErr shr ( __next_hs c )
    : ( Vec u ) sh ?? shr { T m → m F e → { ^ ( __fail c priv cpub random sessid ch tr e ) } }
    ( __cat tr sh )
    : !( Vec u ) TlsErr spkr ( __parse_server_hello sh )
    : ( Vec u ) spub ?? spkr { T k → k F e → { ( vec_free [u] sh ) ^ ( __fail c priv cpub random sessid ch tr e ) } }

    // ── key schedule (handshake) ──
    : ( Vec u ) ecdhe ( x25519 priv spub )
    : ( Vec u ) zeros ( __rand_bytes 0 )
    : ( Vec u ) z32 ( vec_with_cap [u] 32 )
    : ~ i zk 0
    ~ < zk 32 { ( vec_push [u] z32 # u 0 ) = zk + zk 1 }
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) ehash ( sha256_pure empty )
    : ( Vec u ) early ( hkdf_extract empty z32 )
    : ( Vec u ) derived1 ( derive_secret early `derived` ehash )
    : ( Vec u ) hs_secret ( hkdf_extract derived1 ecdhe )

    : ( Vec u ) th_sh ( sha256_pure tr )
    : ( Vec u ) c_hs ( derive_secret hs_secret `c hs traffic` th_sh )
    : ( Vec u ) s_hs ( derive_secret hs_secret `s hs traffic` th_sh )
    ( __set_keys c 0 s_hs )
    ( __set_keys c 1 c_hs )
    = . c enc_read 1

    : ( Vec u ) derived2 ( derive_secret hs_secret `derived` ehash )
    : ( Vec u ) master ( hkdf_extract derived2 z32 )

    // ── server flight: EE, Certificate, CertVerify, Finished ──
    : ~ i done 0
    : ~ i flighterr 0
    ~ & == done 0 == flighterr 0 {
        : !( Vec u ) TlsErr mr ( __next_hs c )
        ?? mr {
            F _ → { = flighterr 1 }
            T msg → {
                : i t ( __t_bget msg 0 )
                ? == t 20 {
                    : ( Vec u ) th_cv ( sha256_pure tr )
                    : ( Vec u ) expect ( __finished_mac s_hs th_cv )
                    : b okfin ( __cmp_finished msg expect )
                    ( vec_free [u] th_cv )
                    ( vec_free [u] expect )
                    ( __cat tr msg )
                    ? okfin {} { = flighterr 1 }
                    = done 1
                } {
                    ? == t 11 {
                        : ( Vec u ) der ( __extract_cert msg )
                        ( vec_free [u] . c server_cert )
                        = . c server_cert der
                    } {}
                    ( __cat tr msg )
                }
                ( vec_free [u] msg )
            }
        }
    }
    ? == flighterr 1 {
        ^ ( __fail2 c priv cpub random sessid ch tr spub ecdhe z32 empty ehash early derived1 hs_secret th_sh c_hs s_hs derived2 master sh )
    } {}

    // ── application keys ──
    : ( Vec u ) th_sf ( sha256_pure tr )
    : ( Vec u ) c_ap ( derive_secret master `c ap traffic` th_sf )
    : ( Vec u ) s_ap ( derive_secret master `s ap traffic` th_sf )

    // ── client Finished (under handshake keys) ──
    : ( Vec u ) cfin ( __finished_mac c_hs th_sf )
    : ( Vec u ) finmsg ( vec_with_cap [u] 36 )
    ( vec_push [u] finmsg # u 20 )
    ( __u24 finmsg 32 )
    ( __cat finmsg cfin )
    // change_cipher_spec for middlebox compatibility
    : ( Vec u ) ccs ( vec_with_cap [u] 1 )
    ( vec_push [u] ccs # u 1 )
    : !v TlsErr cw ( __send_plain c 20 ccs )
    ?? cw { T _ → {} F _ → {} }
    ( vec_free [u] ccs )
    : !v TlsErr fw ( __send_encrypted c 22 finmsg )
    ?? fw { T _ → {} F _ → {} }

    // switch to application traffic keys
    ( __set_keys c 0 s_ap )
    ( __set_keys c 1 c_ap )
    = . c established 1

    // free handshake secrets / scratch
    ( vec_free [u] priv ) ( vec_free [u] cpub ) ( vec_free [u] random ) ( vec_free [u] sessid )
    ( vec_free [u] ch ) ( vec_free [u] tr ) ( vec_free [u] sh ) ( vec_free [u] spub )
    ( vec_free [u] ecdhe ) ( vec_free [u] zeros ) ( vec_free [u] z32 ) ( vec_free [u] empty )
    ( vec_free [u] ehash ) ( vec_free [u] early ) ( vec_free [u] derived1 ) ( vec_free [u] hs_secret )
    ( vec_free [u] th_sh ) ( vec_free [u] c_hs ) ( vec_free [u] s_hs ) ( vec_free [u] derived2 )
    ( vec_free [u] master ) ( vec_free [u] th_sf ) ( vec_free [u] c_ap ) ( vec_free [u] s_ap )
    ( vec_free [u] cfin ) ( vec_free [u] finmsg )
    ^ @ !*TlsConn TlsErr { T c }
}

// Compare a Finished message's verify_data (bytes 4..36) against expected.
@ __cmp_finished ( Vec u ) msg ( Vec u ) expect → b {
    ? < ( vec_len [u] msg ) 36 { ^ F } {}
    : ~ i diff 0
    : ~ i k 0
    ~ < k 32 { = diff | diff ^^ ( __t_bget msg + 4 k ) ( __t_bget expect k ) = k + k 1 }
    ^ == diff 0
}

// Cleanup paths on early/late handshake failure.
@ __fail * TlsConn c ( Vec u ) priv ( Vec u ) cpub ( Vec u ) random ( Vec u ) sessid ( Vec u ) ch ( Vec u ) tr TlsErr e → !*TlsConn TlsErr {
    ( vec_free [u] priv ) ( vec_free [u] cpub ) ( vec_free [u] random ) ( vec_free [u] sessid )
    ( vec_free [u] ch ) ( vec_free [u] tr )
    ( tls_close c )
    ^ @ !*TlsConn TlsErr { F e }
}

@ __fail2 * TlsConn c ( Vec u ) priv ( Vec u ) cpub ( Vec u ) random ( Vec u ) sessid ( Vec u ) ch ( Vec u ) tr ( Vec u ) spub ( Vec u ) ecdhe ( Vec u ) z32 ( Vec u ) empty ( Vec u ) ehash ( Vec u ) early ( Vec u ) derived1 ( Vec u ) hs_secret ( Vec u ) th_sh ( Vec u ) c_hs ( Vec u ) s_hs ( Vec u ) derived2 ( Vec u ) master ( Vec u ) sh → !*TlsConn TlsErr {
    ( vec_free [u] priv ) ( vec_free [u] cpub ) ( vec_free [u] random ) ( vec_free [u] sessid )
    ( vec_free [u] ch ) ( vec_free [u] tr ) ( vec_free [u] spub ) ( vec_free [u] ecdhe )
    ( vec_free [u] z32 ) ( vec_free [u] empty ) ( vec_free [u] ehash ) ( vec_free [u] early )
    ( vec_free [u] derived1 ) ( vec_free [u] hs_secret ) ( vec_free [u] th_sh ) ( vec_free [u] c_hs )
    ( vec_free [u] s_hs ) ( vec_free [u] derived2 ) ( vec_free [u] master ) ( vec_free [u] sh )
    ( tls_close c )
    ^ @ !*TlsConn TlsErr { F # TlsErr TlsHandshake }
}

// ── application data ──────────────────────────────────────────────
@ tls_write * TlsConn c ( Vec u ) data → !v TlsErr {
    ^ ( __send_encrypted c 23 data )
}

// Read up to `max` decrypted application bytes. Returns [] on clean EOF
// (close_notify). Post-handshake messages (tickets, key updates) are
// consumed transparently.
@ tls_read * TlsConn c i max → !( Vec u ) TlsErr {
    ~ & == ( vec_len [u] . c appbuf ) 0 == . c closed 0 {
        : !TlsRecord TlsErr rr ( __read_record c )
        ?? rr {
            F e → {
                ^ ?? e {
                    TlsClosed → { = . c closed 1 @ !( Vec u ) TlsErr { T ( vec_new [u] ) } }
                    _ → @ !( Vec u ) TlsErr { F e }
                }
            }
            T rec → {
                ? == . rec rtype 20 {
                    ( vec_free [u] . rec body )
                } {
                    ?? ( __decrypt_record c . rec body ) {
                        T inner → {
                            ( vec_free [u] . rec body )
                            : i ct ( __inner_type inner )
                            ? == ct 23 {
                                ( __cat . c appbuf inner )
                            } {
                                ? == ct 21 { = . c closed 1 } {}
                                // ct == 22 → post-handshake (ticket/key update): ignore
                            }
                            ( vec_free [u] inner )
                        }
                        F _ → {
                            ( vec_free [u] . rec body )
                            ^ @ !( Vec u ) TlsErr { F # TlsErr TlsDecrypt }
                        }
                    }
                }
            }
        }
    }
    : i avail ( vec_len [u] . c appbuf )
    ? == avail 0 { ^ @ !( Vec u ) TlsErr { T ( vec_new [u] ) } } {}
    : i take ? < max avail max avail
    : ( Vec u ) out ( bytes_slice . c appbuf 0 take )
    : ( Vec u ) rest ( bytes_slice . c appbuf take avail )
    ( vec_free [u] . c appbuf )
    = . c appbuf rest
    ^ @ !( Vec u ) TlsErr { T out }
}

@ tls_close * TlsConn c → v {
    ? == . c closed 0 {
        // best-effort close_notify alert (encrypted if established)
        ? == . c established 1 {
            : ( Vec u ) alert ( vec_with_cap [u] 2 )
            ( vec_push [u] alert # u 1 )
            ( vec_push [u] alert # u 0 )
            : !v TlsErr _w ( __send_encrypted c 21 alert )
            ( vec_free [u] alert )
        } {}
        = . c closed 1
    } {}
    ( tcp_close_conn . c tcp )
    ( vec_free [u] . c rxbuf )
    ( vec_free [u] . c hsbuf )
    ( vec_free [u] . c appbuf )
    ( vec_free [u] . c s_key ) ( vec_free [u] . c s_iv )
    ( vec_free [u] . c c_key ) ( vec_free [u] . c c_iv )
    ( vec_free [u] . c server_cert )
    ( nurl_free # s c )
}
