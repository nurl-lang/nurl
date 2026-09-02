// stdlib/std/tls.nu — a pure-NURL TLS 1.3 client (RFC 8446).
//
// No OpenSSL, no FFI beyond the libc TCP socket: the handshake crypto
// (X25519, ChaCha20-Poly1305, HKDF, SHA-256) is all pure NURL, so a
// program can open an authenticated, encrypted TLS 1.3 connection on a
// host with nothing installed — Linux, macOS, the BSDs, Windows.
//
// Cipher suites: TLS_AES_128_GCM_SHA256 and TLS_CHACHA20_POLY1305_SHA256
// with the X25519 group — between them accepted by essentially every
// modern TLS 1.3 server (OpenSSL, BoringSSL, nginx, the big CDNs).
//
// Surface:
//   ( tls_connect host port server_name )          → !*TlsConn TlsErr  (verify-full)
//   ( tls_connect_insecure host port server_name ) → !*TlsConn TlsErr  (no cert check)
//   ( tls_write conn bytes )                       → !v TlsErr
//   ( tls_read conn max )                          → !( Vec u ) TlsErr  ([] at EOF)
//   ( tls_close conn )                             → v
//
// `tls_connect` is secure by default: it completes the handshake and then
// verifies the server certificate chain (see verify.nu) against the system
// trust store, failing with TlsBadCert otherwise. `tls_connect_insecure`
// is the encrypted-but-unauthenticated escape hatch.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hkdf.nu`
$ `stdlib/std/x25519.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/chacha20poly1305.nu`
$ `stdlib/std/aes_gcm.nu`
$ `stdlib/std/mlkem.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/tls_verify.nu`

& `libc` @ nurl_tcp_connect s host i port → i

// Fiber/reactor primitives (nurl_fiber_current, nurl_reactor_wait_*,
// nurl_tcp_get_fd / _timeout_ms / _set_nonblock). FFI-only module, so
// this import keeps tls.nu free of any stdlib/std/net.nu dependency —
// net.nu imports THIS module and dispatches its polymorphic TcpConn
// reads/writes to the pure TLS stack without an import cycle.
$ `stdlib/std/async_ffi.nu`

// Park the current fiber until `raw`'s socket is readable (want = 0)
// or writable (want = 1), honouring the handle's configured timeout
// (0 = wait for ever, matching the blocking path's SO_RCVTIMEO
// semantics). Returns T when the socket is ready, F on timeout or a
// missing fiber context.
@ __tls_io_wait i raw i want → b {
    : i fd ( nurl_tcp_get_fd raw )
    : i ms ( nurl_tcp_timeout_ms raw )
    : i deadline ? > ms 0 ms - 0 1
    : i rc ? != want 0 ( nurl_reactor_wait_write fd deadline ) ( nurl_reactor_wait_read fd deadline )
    ^ > rc 0
}

// Write all of `data` to the raw socket fd. Returns F on any error.
//
// Context-aware: on a fiber the socket is flipped non-blocking and an
// EAGAIN parks on the reactor until writable (the worker pthread stays
// free for other fibers); off a fiber the write blocks in the kernel,
// which is what a synchronous client wants.
@ _tls_sock_write i fd ( Vec u ) data → b {
    : *u dp ( vec_data [u] data )
    : i n ( vec_len [u] data )
    : b on_fiber != ( nurl_fiber_current ) 0
    ? on_fiber { ( nurl_tcp_set_nonblock fd 1 ) } {}
    : ~ i off 0
    ~ < off n {
        : i wn ( nurl_tcp_write fd # s + # i dp off - n off )
        ? <= wn 0 {
            : ~ b retry F
            ? & on_fiber == ( nurl_tcp_err_kind fd ) 7 {
                = retry ( __tls_io_wait fd 1 )
            } {}
            ? retry {} { ^ F }
        } {
            = off + off wn
        }
    }
    ^ T
}

& `c` @ nurl_rand_fill *u buf i n → i

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
    TlsBadCert
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
        TlsBadCert → `TlsBadCert`
    }
}

// Live connection state. Vec fields are reassigned as keys rotate
// (handshake → application) and as buffers are consumed.
: TlsConn {
    i fd
    ( Vec u ) rxbuf  // raw socket bytes not yet split into records
    ( Vec u ) hsbuf  // decrypted handshake bytes not yet a full message
    ( Vec u ) appbuf  // decrypted application bytes for the caller
    ( Vec u ) s_key
    ( Vec u ) s_iv
    ( Vec u ) c_key
    ( Vec u ) c_iv
    i s_seq
    i c_seq
    i enc_read  // 1 once server records are encrypted
    i established
    i closed
    ( Vec u ) cert_msg  // raw Certificate handshake message (full chain)
    ( Vec u ) cv_sig  // CertificateVerify signature
    ( Vec u ) th_cert  // transcript hash through Certificate (for CertVerify)
    i cv_scheme  // CertificateVerify SignatureScheme
    i cipher  // 0 = ChaCha20-Poly1305, 1 = AES-128-GCM
    i version  // 13 = TLS 1.3, 12 = TLS 1.2
    ( Vec u ) kx_p256  // P-256 ephemeral private key (empty if X25519 chosen)
    ( Vec u ) kx_mlkem  // ML-KEM-768 decapsulation key (empty unless the
    // hybrid group is chosen)
    i kx_group  // negotiated group: 4588 X25519MLKEM768, 29 x25519,
    // 23 secp256r1, 0 before the handshake reaches it
    ( Vec u ) alpn_sel  // ALPN protocol the server selected (empty if none)
    // ── session resumption (RFC 8446 §4.6.1 / §4.2.11) ──
    i resumed  // 1 when this connection came up from a PSK ticket
    ( Vec u ) res_master  // resumption_master_secret, set when the handshake
    // completes; the PSK of every ticket on this connection derives from it
    ( Vec u ) res_early  // client scratch: early_secret(PSK) while offering
    ( Vec u ) tk_ticket  // newest ticket (to offer next time / being offered)
    ( Vec u ) tk_psk  // its PSK
    i tk_age_add  // its ticket_age_add
    i tk_lifetime  // its ticket_lifetime, seconds
    i tk_received_ms  // wall clock (ms) when it arrived
}

// ── small helpers ─────────────────────────────────────────────────
@ _t_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ _tls_u16 ( Vec u ) v i n → v {
    ( vec_push [u] v # u & >> n 8 255 )
    ( vec_push [u] v # u & n 255 )
}

@ _tls_u32 ( Vec u ) v i n → v {
    ( vec_push [u] v # u & >> n 24 255 )
    ( vec_push [u] v # u & >> n 16 255 )
    ( vec_push [u] v # u & >> n 8 255 )
    ( vec_push [u] v # u & n 255 )
}

@ _tls_u64 ( Vec u ) v i n → v {
    ( _tls_u32 v & >> n 32 4294967295 )
    ( _tls_u32 v & n 4294967295 )
}

@ _u24 ( Vec u ) v i n → v {
    ( vec_push [u] v # u & >> n 16 255 )
    ( vec_push [u] v # u & >> n 8 255 )
    ( vec_push [u] v # u & n 255 )
}

// Bulk append — memcpy via bytes_extend_bytes rather than a per-byte
// push loop; this runs over every received record (socket → rxbuf,
// plaintext → appbuf) on the download hot path.
@ _tls_cat ( Vec u ) dst ( Vec u ) src → v {
    ( bytes_extend_bytes dst src )
}

// Append a 2-byte length prefix + the block bytes.
@ _blk16 ( Vec u ) dst ( Vec u ) sub → v {
    ( _tls_u16 dst ( vec_len [u] sub ) )
    ( _tls_cat dst sub )
}

// Read a big-endian integer of `n` bytes from `v` at `off`.
@ _rdint ( Vec u ) v i off i n → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k n { = acc | << acc 8 ( _t_bget v + off k ) = k + k 1 }
    ^ acc
}

@ _rand_bytes i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    : i r ( nurl_rand_fill # *u ( vec_data [u] v ) n )
    // L4: never proceed with non-CSPRNG bytes. nurl_rand_fill returns 0 only on
    // total entropy failure; these bytes seed ephemeral keys and nonces, so
    // fail closed rather than emit predictable key material.
    ? & > n 0 == r 0 { ( nurl_panic `tls: CSPRNG (nurl_rand_fill) failed` ) } {}
    ^ v
}

// Constant-time all-zero test (OR-accumulate every byte; no early exit). An
// empty vector counts as zero. Used to reject a degenerate ECDHE secret.
@ _all_zero ( Vec u ) v → b {
    : i n ( vec_len [u] v )
    ? == n 0 { ^ T } {}
    : ~ i acc 0
    : ~ i k 0
    ~ < k n { = acc | acc ( _t_bget v k ) = k + k 1 }
    ^ == acc 0
}

// X25519MLKEM768 (RFC 9370 group 0x11ec): turn the server's 1120-byte
// key_share into the 64-byte secret the key schedule consumes.
//
// The server share is `ML-KEM-768 ciphertext (1088) ‖ X25519 public key
// (32)`, and the result is `ML-KEM shared secret ‖ X25519 shared secret`
// in the same order.
//
// Decapsulation cannot report failure — that is the point of ML-KEM's
// implicit rejection, which returns an unpredictable key rather than an
// error so an attacker learns nothing from probing. A wrong ciphertext
// therefore surfaces here as a handshake that fails at Finished, which
// is exactly the intended behaviour.
//
// The X25519 half still gets RFC 8446 §7.4.2's all-zero check on its
// own. Checking only the concatenation would not do: a low-order peer
// point makes the X25519 half all-zero while the ML-KEM half stays
// random, so the pair looks fine and the classical half is silently
// worthless. Returning an empty vector here makes the caller's
// `_all_zero` test fail closed.
@ __hybrid_shared * TlsConn c ( Vec u ) priv ( Vec u ) spub → ( Vec u ) {
    : ( Vec u ) ct ( bytes_slice spub 0 1088 )
    : ( Vec u ) xpub ( bytes_slice spub 1088 1120 )
    : ( Vec u ) xs ( x25519 priv xpub )
    ? ( _all_zero xs ) {
        ( vec_free [u] xs ) ( vec_free [u] xpub ) ( vec_free [u] ct )
        ^ ( vec_new [u] )
    } {}
    : ( Vec u ) out ( mlkem_decaps 768 . c kx_mlkem ct )
    ( bytes_extend_bytes out xs )
    ( vec_free [u] xs )
    ( vec_free [u] xpub )
    ( vec_free [u] ct )
    ^ out
}

// RFC 8446 §4.1.3 downgrade sentinel: a TLS 1.3-capable client that ends up
// on TLS 1.2 must abort if the last 8 bytes of the 32-byte server random are
// "DOWNGRD" + 0x01 (1.2) or + 0x00 (1.1/below) — the server is signalling a
// forced downgrade by an active attacker.
@ __downgrade_sentinel ( Vec u ) srand → b {
    ? < ( vec_len [u] srand ) 32 { ^ F } {}
    : ~ b m T
    ? != ( _t_bget srand 24 ) 68 { = m F } {}  // 'D'
    ? != ( _t_bget srand 25 ) 79 { = m F } {}  // 'O'
    ? != ( _t_bget srand 26 ) 87 { = m F } {}  // 'W'
    ? != ( _t_bget srand 27 ) 78 { = m F } {}  // 'N'
    ? != ( _t_bget srand 28 ) 71 { = m F } {}  // 'G'
    ? != ( _t_bget srand 29 ) 82 { = m F } {}  // 'R'
    ? != ( _t_bget srand 30 ) 68 { = m F } {}  // 'D'
    : i last ( _t_bget srand 31 )
    ? & != last 0 != last 1 { = m F } {}
    ^ m
}

// ── socket record I/O ─────────────────────────────────────────────
// Ensure rxbuf holds at least `n` bytes, reading from the socket.
//
// Context-aware: on a fiber the socket is non-blocking and an EAGAIN
// parks on the reactor until readable — the worker pthread stays free,
// so a fiber HTTP-over-TLS server multiplexes its connections instead
// of pinning one worker per idle keep-alive conn. Off a fiber the raw
// blocking read is what a synchronous client wants (SO_RCVTIMEO still
// bounds it; the reactor deadline mirrors that via __tls_io_wait).
@ __fill * TlsConn c i n → !i TlsErr {
    : i raw . c fd
    : b on_fiber != ( nurl_fiber_current ) 0
    ? on_fiber { ( nurl_tcp_set_nonblock raw 1 ) } {}
    ~ < ( vec_len [u] . c rxbuf ) n {
        // Read straight into rxbuf's spare capacity — the previous
        // per-fill 16 KB scratch Vec + copy-append + free was pure
        // overhead on the record hot path (once per record read, i.e.
        // once per keep-alive HTTPS request). Capacity settles at
        // ~len+16 K and is reused for the connection's lifetime.
        ( vec_reserve [u] . c rxbuf 16384 )
        : i len ( vec_len [u] . c rxbuf )
        : *u p ( vec_data [u] . c rxbuf )
        : s pbuf # s + # i p len
        : ~ i got ( nurl_tcp_read raw pbuf 16384 )
        : ~ b timed_out F
        ~ & ! timed_out & on_fiber & < got 0 == ( nurl_tcp_err_kind raw ) 7 {
            ? ( __tls_io_wait raw 0 ) {
                = got ( nurl_tcp_read raw pbuf 16384 )
            } { = timed_out T }
        }
        ? < got 0 { ^ @ !i TlsErr { F # TlsErr TlsRead } } {}
        ? == got 0 { ^ @ !i TlsErr { F # TlsErr TlsClosed } } {}
        : b _ok ( vec_set_len [u] . c rxbuf + len got )
    }
    ^ @ !i TlsErr { T 1 }
}

// Drop the first `n` bytes of rxbuf (consume them). In place: shift the
// tail down and shrink len — the old slice-copy allocated (and freed) a
// fresh Vec per consumed record. The tail is empty in the common case
// (one record per read), so the memmove is usually zero bytes.
@ __consume * TlsConn c i n → v {
    : ( Vec u ) buf . c rxbuf
    : i total ( vec_len [u] buf )
    ? >= n total { ( vec_clear [u] buf ) ^ v } {}
    : i remaining - total n
    : *u p ( vec_data [u] buf )
    ( nurl_memmove # s p # s # *u + # i p n remaining )
    : b _ok ( vec_set_len [u] buf remaining )
}

// Record = type(1) ver(2) length(2) body. Returns (type, body); body is
// an owned slice the caller frees.
: TlsRecord { i rtype ( Vec u ) body }

@ _read_record * TlsConn c → !TlsRecord TlsErr {
    : !i TlsErr h ( __fill c 5 )
    ?? h { T _ → {} F e → { ^ @ !TlsRecord TlsErr { F e } } }
    : i rtype ( _t_bget . c rxbuf 0 )
    : i len ( _rdint . c rxbuf 3 2 )
    : !i TlsErr b ( __fill c + 5 len )
    ?? b { T _ → {} F e → { ^ @ !TlsRecord TlsErr { F e } } }
    : ( Vec u ) body ( bytes_slice . c rxbuf 5 + 5 len )
    ( __consume c + 5 len )
    ^ @ !TlsRecord TlsErr { T @ TlsRecord { rtype body } }
}

// Build the per-record nonce: static IV with the 64-bit sequence number
// XORed into the low 8 bytes.
@ _nonce ( Vec u ) iv i seq → ( Vec u ) {
    : ( Vec u ) n ( vec_with_cap [u] 12 )
    : ~ i k 0
    ~ < k 12 { ( vec_push [u] n # u ( _t_bget iv k ) ) = k + k 1 }
    : ~ i b 0
    ~ < b 8 {
        : i sb & >> seq * 8 - 7 b 255
        ( vec_set [u] n + 4 b # u ^^ ( _t_bget n + 4 b ) sb )
        = b + b 1
    }
    ^ n
}

// AEAD dispatch on the negotiated cipher suite.
@ _aead_seal i cipher ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → ( Vec u ) {
    ? == cipher 1 { ^ ( aes128_gcm_encrypt key nonce aad pt ) } {}
    ^ ( aead_encrypt key nonce aad pt )
}

@ _aead_open i cipher ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct → ?( Vec u ) {
    ? == cipher 1 { ^ ( aes128_gcm_decrypt key nonce aad ct ) } {}
    ^ ( aead_decrypt key nonce aad ct )
}

// AEAD-decrypt one application_data record body (ct‖tag) → inner plaintext.
@ __decrypt_record * TlsConn c ( Vec u ) body → ?( Vec u ) {
    : i blen ( vec_len [u] body )
    : ( Vec u ) aad ( vec_with_cap [u] 5 )
    ( vec_push [u] aad # u 23 )
    ( vec_push [u] aad # u 3 )
    ( vec_push [u] aad # u 3 )
    ( _tls_u16 aad blen )
    : ( Vec u ) nonce ( _nonce . c s_iv . c s_seq )
    : ?( Vec u ) pt ( _aead_open . c cipher . c s_key nonce aad body )
    ( vec_free [u] aad )
    ( vec_free [u] nonce )
    = . c s_seq + . c s_seq 1
    ^ pt
}

// Strip TLS 1.3 inner padding: trailing zeros then the real content type.
// Returns the content type; truncates `inner` to the real content length.
@ _inner_type ( Vec u ) inner → i {
    : ~ i i - ( vec_len [u] inner ) 1
    ~ & >= i 0 == ( _t_bget inner i ) 0 { = i - i 1 }
    ? < i 0 { ^ 0 } {}
    : i ct ( _t_bget inner i )
    : b _ok ( vec_set_len [u] inner i )
    ^ ct
}

// Encrypt + send one record of `content` under the client keys.
@ __send_encrypted * TlsConn c i content_type ( Vec u ) content → !v TlsErr {
    : ( Vec u ) inner ( vec_with_cap [u] + ( vec_len [u] content ) 1 )
    ( _tls_cat inner content )
    ^ ( __send_inner_encrypted c content_type inner )
}

// Same record, plaintext = bytes [lo, hi) of `head`‖`body`, assembled
// straight from the two buffers (tls_write2's per-record step).
@ __send_encrypted_pair * TlsConn c i content_type ( Vec u ) head ( Vec u ) body i lo i hi → !v TlsErr {
    : ( Vec u ) inner ( _tls_pair_slice head body lo hi )
    ^ ( __send_inner_encrypted c content_type inner )
}

// Seal `inner` (plaintext WITHOUT the type byte yet; consumed here) as
// one TLS 1.3 record under the client write keys and send it.
@ __send_inner_encrypted * TlsConn c i content_type ( Vec u ) inner → !v TlsErr {
    ( vec_push [u] inner # u content_type )
    : i total + ( vec_len [u] inner ) 16
    : ( Vec u ) aad ( vec_with_cap [u] 5 )
    ( vec_push [u] aad # u 23 )
    ( vec_push [u] aad # u 3 )
    ( vec_push [u] aad # u 3 )
    ( _tls_u16 aad total )
    : ( Vec u ) nonce ( _nonce . c c_iv . c c_seq )
    : ( Vec u ) sealed ( _aead_seal . c cipher . c c_key nonce aad inner )
    : ( Vec u ) rec ( vec_with_cap [u] + total 5 )
    ( vec_push [u] rec # u 23 )
    ( vec_push [u] rec # u 3 )
    ( vec_push [u] rec # u 3 )
    ( _tls_u16 rec total )
    ( _tls_cat rec sealed )
    : b w ( _tls_sock_write . c fd rec )
    ( vec_free [u] inner )
    ( vec_free [u] aad )
    ( vec_free [u] nonce )
    ( vec_free [u] sealed )
    ( vec_free [u] rec )
    = . c c_seq + . c c_seq 1
    ^ ? w @ !v TlsErr { T 0 } @ !v TlsErr { F # TlsErr TlsWrite }
}

// Write a plaintext record straight to the socket.
@ _send_plain * TlsConn c i rtype ( Vec u ) body → !v TlsErr {
    : ( Vec u ) rec ( vec_with_cap [u] + ( vec_len [u] body ) 5 )
    ( vec_push [u] rec # u rtype )
    // legacy_record_version 0x0303 (RFC 8446 §5.1: required for every
    // record except the initial ClientHello, where 0x0303 is also valid).
    ( vec_push [u] rec # u 3 )
    ( vec_push [u] rec # u 3 )
    ( _tls_u16 rec ( vec_len [u] body ) )
    ( _tls_cat rec body )
    : b w ( _tls_sock_write . c fd rec )
    ( vec_free [u] rec )
    ^ ? w @ !v TlsErr { T 0 } @ !v TlsErr { F # TlsErr TlsWrite }
}

// ── handshake-message reader ──────────────────────────────────────
// Pull the next complete handshake message (header + body) from hsbuf,
// decrypting more records as needed. CCS records are skipped.
@ __next_hs * TlsConn c → !( Vec u ) TlsErr {
    : ~ i need 1
    ~ == need 1 {
        : i have ( vec_len [u] . c hsbuf )
        ? >= have 4 {
            : i mlen ( _rdint . c hsbuf 1 3 )
            ? >= have + 4 mlen {
                : ( Vec u ) msg ( bytes_slice . c hsbuf 0 + 4 mlen )
                : ( Vec u ) rest ( bytes_slice . c hsbuf + 4 mlen have )
                ( vec_free [u] . c hsbuf )
                = . c hsbuf rest
                ^ @ !( Vec u ) TlsErr { T msg }
            } {}
        } {}
        // Need more bytes: read another record.
        : !TlsRecord TlsErr rr ( _read_record c )
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
                                : i ct ( _inner_type inner )
                                ? == ct 22 {
                                    ( _tls_cat . c hsbuf inner )
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
                            ( _tls_cat . c hsbuf . rec body )
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
@ __build_client_hello s host ( Vec u ) pubkey ( Vec u ) p256pub ( Vec u ) pqpub ( Vec u ) random ( Vec u ) sessid s alpn ( Vec u ) psk_id i obf_age → ( Vec u ) {
    : ( Vec u ) body ( vec_new [u] )
    ( _tls_u16 body 771 )  // legacy_version 0x0303
    ( _tls_cat body random )  // 32-byte random
    ( vec_push [u] body # u 32 )  // session id length
    ( _tls_cat body sessid )
    // cipher_suites: TLS_CHACHA20_POLY1305_SHA256 (0x1303) +
    // TLS_AES_128_GCM_SHA256 (0x1301) — both use the SHA-256 key
    // schedule, so either keeps the rest of the handshake unchanged.
    // ChaCha is listed FIRST on purpose: measured on one core over
    // 16 KB records, ChaCha20-Poly1305 seals at ~370 MB/s and
    // AES-128-GCM — bitsliced, so constant-time without AES
    // instructions — at ~113. Both are now fast enough that a download
    // is not bounded by the record layer, but ChaCha is still the
    // better of the two on a host with no AES hardware, which is every
    // host NURL has a code path for. Servers honouring client
    // preference (Cloudflare et al.) pick ChaCha; AES-only peers still
    // get 0x1301 from the same list.
    // 1.3 suites first, then the TLS 1.2 ECDHE suites for fallback.
    ( _tls_u16 body 12 )
    ( _tls_u16 body 4867 )  // 0x1303 TLS_CHACHA20_POLY1305_SHA256
    ( _tls_u16 body 4865 )  // 0x1301 TLS_AES_128_GCM_SHA256
    ( _tls_u16 body 52393 )  // 0xcca9 ECDHE-ECDSA-CHACHA20-POLY1305
    ( _tls_u16 body 52392 )  // 0xcca8 ECDHE-RSA-CHACHA20-POLY1305
    ( _tls_u16 body 49195 )  // 0xc02b ECDHE-ECDSA-AES128-GCM-SHA256
    ( _tls_u16 body 49199 )  // 0xc02f ECDHE-RSA-AES128-GCM-SHA256
    // compression methods
    ( vec_push [u] body # u 1 )
    ( vec_push [u] body # u 0 )

    // extensions
    : ( Vec u ) ext ( vec_new [u] )

    // server_name (0x0000)
    : ( Vec u ) sni ( vec_new [u] )
    : i hl ( nurl_str_len host )
    ( _tls_u16 sni + hl 3 )  // ServerNameList length
    ( vec_push [u] sni # u 0 )  // name_type host_name
    ( _tls_u16 sni hl )
    : ~ i k 0
    ~ < k hl { ( vec_push [u] sni # u ( nurl_str_get host k ) ) = k + k 1 }
    ( _tls_u16 ext 0 )
    ( _blk16 ext sni )
    ( vec_free [u] sni )

    // supported_groups (0x000a): X25519MLKEM768 (0x11ec) first, then
    // x25519 (0x001d) and secp256r1 (0x0017).
    //
    // The hybrid group leads because it is the only one here that
    // survives a quantum adversary, and because it is what current
    // browsers put first — servers that know it will take it. The two
    // classical groups stay for everything else; PostgreSQL/OpenSSL
    // servers commonly default to P-256. Order is a preference, not a
    // demand: the server picks, and we sent a key share for all three.
    : ( Vec u ) grp ( vec_new [u] )
    ( _tls_u16 grp 6 )
    ( _tls_u16 grp 4588 )  // X25519MLKEM768 0x11ec
    ( _tls_u16 grp 29 )  // x25519
    ( _tls_u16 grp 23 )  // secp256r1
    ( _tls_u16 ext 10 )
    ( _blk16 ext grp )
    ( vec_free [u] grp )

    // signature_algorithms (0x000d)
    // ML-DSA leads: it is the only family here a quantum adversary
    // cannot forge, and a server that has an ML-DSA certificate should
    // use it. The classical schemes follow for everything else — which
    // today is everything with a publicly-issued certificate, since no
    // CA issues ML-DSA yet.
    : ( Vec u ) sa ( vec_new [u] )
    ( _tls_u16 sa 22 )  // list length (11 algs × 2)
    ( _tls_u16 sa 2309 )  // mldsa65                0x0905
    ( _tls_u16 sa 2310 )  // mldsa87                0x0906
    ( _tls_u16 sa 2308 )  // mldsa44                0x0904
    ( _tls_u16 sa 1027 )  // ecdsa_secp256r1_sha256 0x0403
    ( _tls_u16 sa 2052 )  // rsa_pss_rsae_sha256    0x0804
    ( _tls_u16 sa 1025 )  // rsa_pkcs1_sha256       0x0401
    ( _tls_u16 sa 1283 )  // ecdsa_secp384r1_sha384 0x0503
    ( _tls_u16 sa 2053 )  // rsa_pss_rsae_sha384    0x0805
    ( _tls_u16 sa 2054 )  // rsa_pss_rsae_sha512    0x0806
    ( _tls_u16 sa 2055 )  // ed25519                0x0807
    ( _tls_u16 sa 1281 )  // rsa_pkcs1_sha384       0x0501
    ( _tls_u16 ext 13 )
    ( _blk16 ext sa )
    ( vec_free [u] sa )

    // supported_versions (0x002b): TLS 1.3 (0x0304) then TLS 1.2 (0x0303)
    : ( Vec u ) sv ( vec_new [u] )
    ( vec_push [u] sv # u 4 )
    ( _tls_u16 sv 772 )
    ( _tls_u16 sv 771 )
    ( _tls_u16 ext 43 )
    ( _blk16 ext sv )
    ( vec_free [u] sv )

    // ec_point_formats (0x000b): uncompressed — some TLS 1.2 servers require it
    : ( Vec u ) epf ( vec_new [u] )
    ( vec_push [u] epf # u 1 )
    ( vec_push [u] epf # u 0 )
    ( _tls_u16 ext 11 )
    ( _blk16 ext epf )
    ( vec_free [u] epf )

    // key_share (0x0033): a share for each group we offered, so whichever
    // one the server selects we already supplied a matching public key —
    // no HelloRetryRequest round trip.
    //
    // The X25519MLKEM768 share is the concatenation
    // `ML-KEM-768 encapsulation key ‖ X25519 public key` — 1184 + 32 =
    // 1216 bytes, ML-KEM first. That order is specific to this group
    // (SecP256r1MLKEM768 puts the classical part first) and getting it
    // backwards produces a handshake that fails only at Finished.
    //
    // It also makes the ClientHello roughly 1.5 kB, so it no longer fits
    // in one TCP segment. That is ordinary — every browser sending this
    // group has the same shape — but it does mean a path that silently
    // drops large handshake packets will now fail where it used to work.
    : ( Vec u ) ks ( vec_new [u] )
    : ( Vec u ) entry ( vec_new [u] )
    ? > ( vec_len [u] pqpub ) 0 {
        ( _tls_u16 entry 4588 )  // group X25519MLKEM768
        ( _tls_u16 entry + ( vec_len [u] pqpub ) 32 )  // 1216
        ( _tls_cat entry pqpub )
        ( _tls_cat entry pubkey )
    } {}
    ( _tls_u16 entry 29 )  // group x25519
    ( _tls_u16 entry 32 )  // key_exchange length
    ( _tls_cat entry pubkey )
    ( _tls_u16 entry 23 )  // group secp256r1
    ( _tls_u16 entry ( vec_len [u] p256pub ) )  // 65
    ( _tls_cat entry p256pub )
    ( _tls_u16 ks ( vec_len [u] entry ) )
    ( _tls_cat ks entry )
    ( _tls_u16 ext 51 )
    ( _blk16 ext ks )
    ( vec_free [u] entry )
    ( vec_free [u] ks )

    // application_layer_protocol_negotiation (0x0010), one protocol
    // (RFC 7301). Only emitted when a protocol was requested (e.g. "h2");
    // otherwise the ext is omitted and the connect behaves exactly as before.
    : i al ( nurl_str_len alpn )
    ? > al 0 {
        : ( Vec u ) alp ( vec_new [u] )
        ( _tls_u16 alp + al 1 )  // ProtocolNameList length
        ( vec_push [u] alp # u al )  // protocol name length
        : ~ i ak 0
        ~ < ak al { ( vec_push [u] alp # u ( nurl_str_get alpn ak ) ) = ak + ak 1 }
        ( _tls_u16 ext 16 )
        ( _blk16 ext alp )
        ( vec_free [u] alp )
    } {}

    // ── resumption (RFC 8446 §4.2.9 + §4.2.11) ──
    // psk_key_exchange_modes goes in EVERY hello, offer or not: it is
    // how a client says it can resume, and §4.2.9 forbids a server from
    // sending a NewSessionTicket to a client that did not send it —
    // rustls obeys, so without this the client never received a ticket
    // from the Rust peer (openssl and our own server were lenient, which
    // hid it). psk_dhe_ke only — a resumed handshake still runs a fresh
    // (EC)DHE, so a ticket that leaks later never decrypts a recording of
    // this connection.
    : ( Vec u ) modes ( vec_new [u] )
    ( vec_push [u] modes # u 1 )  // list length
    ( vec_push [u] modes # u 1 )  // psk_dhe_ke
    ( _tls_u16 ext 45 )
    ( _blk16 ext modes )
    ( vec_free [u] modes )
    // pre_shared_key MUST be the last extension: its binder is an HMAC
    // over the ClientHello up to (not including) the binders list, so
    // everything else has to be in place first. The binder bytes here
    // are a placeholder the caller overwrites once it has hashed the
    // truncated hello (see _psk_binder_over).
    ? > ( vec_len [u] psk_id ) 0 {
        : ( Vec u ) psk ( vec_new [u] )
        ( _tls_u16 psk + ( vec_len [u] psk_id ) 6 )  // identities: u16 len + id + u32 age
        ( _blk16 psk psk_id )
        ( _tls_u32 psk obf_age )
        ( _tls_u16 psk 33 )  // binders: u8 len + 32 bytes
        ( vec_push [u] psk # u 32 )
        : ~ i bk 0
        ~ < bk 32 { ( vec_push [u] psk # u 0 ) = bk + bk 1 }
        ( _tls_u16 ext 41 )
        ( _blk16 ext psk )
        ( vec_free [u] psk )
    } {}

    ( _blk16 body ext )
    ( vec_free [u] ext )

    // wrap as handshake message: type=1 (client_hello) + 3-byte length
    : ( Vec u ) hs ( vec_with_cap [u] + ( vec_len [u] body ) 4 )
    ( vec_push [u] hs # u 1 )
    ( _u24 hs ( vec_len [u] body ) )
    ( _tls_cat hs body )
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
    = p + p 2  // skip legacy_version
    = p + p 32  // skip random
    : i sidlen ( _t_bget msg p )
    = p + + p 1 sidlen
    : i cipher ( _rdint msg p 2 )
    = p + p 2
    ? & != cipher 4867 != cipher 4865 { ^ @ !( Vec u ) TlsErr { F # TlsErr TlsBadCipher } } {}
    = p + p 1  // skip compression method
    : i extlen ( _rdint msg p 2 )
    = p + p 2
    : i extend + p extlen
    : ~ ( Vec u ) found ( vec_new [u] )
    : ~ i got 0
    ~ < p extend {
        : i etype ( _rdint msg p 2 )
        : i elen ( _rdint msg + p 2 2 )
        : i edata + p 4
        ? == etype 51 {
            // key_share: group(2) ke_len(2) key_exchange
            : i klen ( _rdint msg + edata 2 2 )
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

// The raw cipher suite the server selected (2-byte value).
@ __sh_suite ( Vec u ) msg → i {
    : i sidlen ( _t_bget msg 38 )
    ^ ( _rdint msg + 39 sidlen 2 )
}

// Negotiated TLS version (13/12) from the selected suite: the TLS 1.3
// suites (0x1301/0x1303) imply 1.3, the ECDHE suites imply 1.2.
@ __suite_version i suite → i {
    ^ ? | == suite 4865 == suite 4867 13 12
}

// Our AEAD code (0 ChaCha20 / 1 AES-128-GCM) for a selected suite.
@ __suite_cipher i suite → i {
    ^ ? | | == suite 4865 == suite 49195 == suite 49199 1 0
}

@ __is_hrr ( Vec u ) msg → b {
    // SHA-256("HelloRetryRequest") in the ServerHello random field.
    : i a ( _t_bget msg 6 )
    : i b ( _t_bget msg 7 )
    : i c2 ( _t_bget msg 8 )
    : i d ( _t_bget msg 9 )
    ^ & & & == a 207 == b 33 == c2 173 == d 116
}

// ── traffic-key derivation ────────────────────────────────────────
// From a traffic secret, derive (key, iv) and store on the conn for the
// given direction. dir 0 = server-read, 1 = client-write.
@ _set_keys * TlsConn c i dir ( Vec u ) secret → v {
    : ( Vec u ) emptyc ( vec_new [u] )
    : i klen ? == . c cipher 1 16 32
    : ( Vec u ) key ( hkdf_expand_label secret `key` emptyc klen )
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

// ── PSK key schedule pieces (shared by client and server) ─────────

// early_secret for a PSK: HKDF-Extract(salt = "", IKM = PSK).
@ _psk_early ( Vec u ) psk → ( Vec u ) {
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) early ( hkdf_extract empty psk )
    ( vec_free [u] empty )
    ^ early
}

// The binder for a pre_shared_key offer (RFC 8446 §4.2.11.2): the
// Finished-style MAC under early_secret → "res binder" → "finished", over
// the transcript hash of the ClientHello TRUNCATED to `trunc_len` bytes —
// everything before the binders list. With the extension last that is
// `len - 35` (u16 binders length + u8 binder length + 32 bytes).
@ _psk_binder_over ( Vec u ) early ( Vec u ) ch i trunc_len → ( Vec u ) {
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) ehash ( sha256_pure empty )
    : ( Vec u ) bkey ( derive_secret early `res binder` ehash )
    : ( Vec u ) fkey ( hkdf_expand_label bkey `finished` empty 32 )
    : ( Vec u ) trunc ( bytes_slice ch 0 trunc_len )
    : ( Vec u ) th ( sha256_pure trunc )
    : ( Vec u ) mac ( hmac_sha256_pure fkey th )
    ( vec_free [u] empty ) ( vec_free [u] ehash ) ( vec_free [u] bkey )
    ( vec_free [u] fkey ) ( vec_free [u] trunc ) ( vec_free [u] th )
    ^ mac
}

// Constant-time compare of two 32-byte values (binders, Finished MACs).
@ _ct_eq32 ( Vec u ) a i aoff ( Vec u ) b → b {
    ? | < ( vec_len [u] a ) + aoff 32 < ( vec_len [u] b ) 32 { ^ F } {}
    : ~ i diff 0
    : ~ i k 0
    ~ < k 32 { = diff | diff ^^ ( _t_bget a + aoff k ) ( _t_bget b k ) = k + k 1 }
    ^ == diff 0
}

// Overwrite the last 32 bytes of `ch` (the binder placeholder) with `b`.
@ __ch_patch_binder ( Vec u ) ch ( Vec u ) b → v {
    : i off - ( vec_len [u] ch ) 32
    : *u d ( vec_data [u] ch )
    : ~ i k 0
    ~ < k 32 { = . d + off k # u ( _t_bget b k ) = k + k 1 }
}

// ── session state (client) ────────────────────────────────────────

// Opaque resumption state for a later connection: what the newest
// NewSessionTicket said plus the PSK derived from it. Empty when no
// ticket has arrived — the server sends it right after the handshake,
// inside the application-data stream, so it lands during the first
// tls_read. Hand the bytes to tls_connect_resume / tls_attach_resume;
// they are secret (they hold the PSK) and single-purpose.
@ tls_session_export * TlsConn c → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    ? == ( vec_len [u] . c tk_ticket ) 0 { ^ out } {}
    ( vec_push [u] out # u 1 )  // format version
    ( _tls_u32 out . c tk_age_add )
    ( _tls_u32 out . c tk_lifetime )
    ( _tls_u64 out . c tk_received_ms )
    ( _blk16 out . c tk_psk )
    ( _blk16 out . c tk_ticket )
    ^ out
}

// T when the handshake used a ticket (no certificate was sent; the PSK
// authenticates the server as the one that issued it).
@ tls_is_resumed * TlsConn c → b {
    ^ == . c resumed 1
}

// Load an exported session onto a fresh conn as the offer for its
// handshake. F (and nothing loaded) for an empty, malformed or expired
// blob — the caller then simply does a full handshake.
@ __sess_load * TlsConn c ( Vec u ) sess → b {
    : i n ( vec_len [u] sess )
    ? | < n 21 != ( _t_bget sess 0 ) 1 { ^ F } {}
    : i age_add ( _rdint sess 1 4 )
    : i lifetime ( _rdint sess 5 4 )
    : i received ( _rdint sess 9 8 )
    : i plen ( _rdint sess 17 2 )
    : i tp + 19 plen
    ? > + tp 2 n { ^ F } {}
    : i tlen ( _rdint sess tp 2 )
    ? | == tlen 0 != + + tp 2 tlen n { ^ F } {}
    // RFC 8446 §4.6.1: a ticket is usable for ticket_lifetime seconds
    // (never more than 7 days); past that the server will decline it, so
    // do not offer it.
    : i age_ms - ( now_ms ) received
    ? | < age_ms 0 > age_ms * lifetime 1000 { ^ F } {}
    ( vec_free [u] . c tk_psk ) ( vec_free [u] . c tk_ticket )
    = . c tk_psk ( bytes_slice sess 19 tp )
    = . c tk_ticket ( bytes_slice sess + tp 2 n )
    = . c tk_age_add age_add
    = . c tk_lifetime lifetime
    = . c tk_received_ms received
    ^ T
}

// Post-handshake messages that arrive inside the application-data
// stream. NewSessionTicket (4) is kept — its PSK is derived from this
// connection's resumption_master_secret — so tls_session_export can hand
// it on; KeyUpdate (24) and anything else are ignored, as before.
@ __client_post_hs * TlsConn c ( Vec u ) inner → v {
    ( _tls_cat . c hsbuf inner )
    : ~ b more T
    ~ more {
        = more F
        : i have ( vec_len [u] . c hsbuf )
        ? >= have 4 {
            : i mlen ( _rdint . c hsbuf 1 3 )
            ? >= have + 4 mlen {
                : ( Vec u ) msg ( bytes_slice . c hsbuf 0 + 4 mlen )
                : ( Vec u ) rest ( bytes_slice . c hsbuf + 4 mlen have )
                ( vec_free [u] . c hsbuf )
                = . c hsbuf rest
                ? == ( _t_bget msg 0 ) 4 { ( __client_take_ticket c msg ) } {}
                ( vec_free [u] msg )
                = more T
            } {}
        } {}
    }
}

// NewSessionTicket body: u32 lifetime, u32 age_add, nonce<u8>, ticket<u16>,
// extensions<u16>. PSK = HKDF-Expand-Label(res_master, "resumption", nonce, 32).
@ __client_take_ticket * TlsConn c ( Vec u ) msg → v {
    ? == ( vec_len [u] . c res_master ) 0 { ^ } {}
    : i n ( vec_len [u] msg )
    ? < n 17 { ^ } {}
    : i lifetime ( _rdint msg 4 4 )
    : i age_add ( _rdint msg 8 4 )
    : i nlen ( _t_bget msg 12 )
    : i tp + 13 nlen
    ? > + tp 2 n { ^ } {}
    : i tlen ( _rdint msg tp 2 )
    ? | == tlen 0 > + + tp 2 tlen n { ^ } {}
    : ( Vec u ) nonce ( bytes_slice msg 13 tp )
    : ( Vec u ) psk ( hkdf_expand_label . c res_master `resumption` nonce 32 )
    ( vec_free [u] nonce )
    ( vec_free [u] . c tk_ticket ) ( vec_free [u] . c tk_psk )
    = . c tk_ticket ( bytes_slice msg + tp 2 + + tp 2 tlen )
    = . c tk_psk psk
    = . c tk_age_add age_add
    = . c tk_lifetime lifetime
    = . c tk_received_ms ( now_ms )
}

// Does a ServerHello carry pre_shared_key (41) — i.e. did the server take
// our ticket? Layout after the 4-byte header: ver(2) random(32) sid<u8>
// cipher(2) compression(1) extensions<u16>.
@ __sh_has_psk ( Vec u ) msg → b {
    : ~ i p 38
    : i sidlen ( _t_bget msg p )
    = p + + p 1 sidlen
    = p + p 3
    : i extlen ( _rdint msg p 2 )
    = p + p 2
    : i extend + p extlen
    ~ < + p 4 + extend 1 {
        : i etype ( _rdint msg p 2 )
        : i elen ( _rdint msg + p 2 2 )
        ? == etype 41 { ^ T } {}
        = p + + p 4 elen
    }
    ^ F
}

// HMAC-based Finished verify_data over a traffic secret + transcript hash.
@ _finished_mac ( Vec u ) secret ( Vec u ) thash → ( Vec u ) {
    : ( Vec u ) emptyc ( vec_new [u] )
    : ( Vec u ) fkey ( hkdf_expand_label secret `finished` emptyc 32 )
    : ( Vec u ) mac ( hmac_sha256_pure fkey thash )
    ( vec_free [u] emptyc )
    ( vec_free [u] fkey )
    ^ mac
}

// Establish a TLS 1.3 connection WITHOUT verifying the server
// certificate — encrypted but not authenticated (MITM-able). Use only
// for pinned/self-signed/testing cases. `tls_connect` (below) is the
// secure, verifying entry point. The presented chain, CertificateVerify
// signature and transcript hash are captured on the conn for the
// verifier.
@ tls_connect_insecure s host i port s server_name → !*TlsConn TlsErr {
    : i raw ( nurl_tcp_connect host port )
    ^ ( tls_attach raw server_name )
}

// Run the TLS handshake over a socket that is ALREADY connected (a raw
// libc fd handle as returned by `nurl_tcp_connect`). This is what
// STARTTLS-style protocols need — PostgreSQL's SSLRequest, SMTP STARTTLS,
// IMAP/FTP — where the plaintext leg must exchange a few bytes before the
// channel is upgraded to TLS on the same socket. No certificate
// verification (see `tls_attach_verify` for the secure variant).
// Extract the server-selected ALPN protocol from an EncryptedExtensions
// handshake message (type 8). Returns the protocol bytes (e.g. "h2"), or
// an empty Vec if the server sent no ALPN extension. Message layout:
// [type:1][len:3][exts_len:2] then exts; ALPN ext (0x0010) data is
// [list_len:2][name_len:1][name…].
@ __ee_alpn ( Vec u ) msg → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    : i n ( vec_len [u] msg )
    ? < n 6 { ^ out } {}
    : i extlen ( _rdint msg 4 2 )
    : i end ? > + 6 extlen n n + 6 extlen
    : ~ i p 6
    ~ < p end {
        ? > + p 4 end { ^ out } {}
        : i et ( _rdint msg p 2 )
        : i elen ( _rdint msg + p 2 2 )
        : i edata + p 4
        ? == et 16 {
            ? >= elen 3 {
                : i nl ( _t_bget msg + edata 2 )
                : ~ i j 0
                ~ < j nl {
                    ( vec_push [u] out # u ( _t_bget msg + + edata 3 j ) )
                    = j + j 1
                }
            } {}
            ^ out
        } {}
        = p + + p 4 elen
    }
    ^ out
}

// Core client handshake. `alpn` is a single ALPN protocol to offer (e.g.
// "h2"); empty means no ALPN extension is sent. The negotiated protocol
// (from the server's EncryptedExtensions) is stored in `c.alpn_sel`.
@ __tls_handshake i raw s server_name s alpn ( Vec u ) sess → !*TlsConn TlsErr {
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 { ^ @ !*TlsConn TlsErr { F # TlsErr TlsConnect } } {}
    // Read timeout so an unresponsive/dead peer fails the handshake
    // cleanly instead of blocking the client forever.
    ( nurl_tcp_set_timeout raw 20000 )

    // Heap-allocate the connection so field mutations (key rotation,
    // buffer consumption) in the helpers persist across calls.
    : *TlsConn c # *TlsConn ( nurl_alloc Z TlsConn )
    = . c fd raw
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
    = . c cert_msg ( vec_new [u] )
    = . c cv_sig ( vec_new [u] )
    = . c th_cert ( vec_new [u] )
    = . c cv_scheme 0
    = . c cipher 0
    = . c version 13
    = . c kx_p256 ( vec_new [u] )
    = . c kx_mlkem ( vec_new [u] )
    = . c kx_group 0
    = . c alpn_sel ( vec_new [u] )
    = . c resumed 0
    = . c res_master ( vec_new [u] )
    = . c res_early ( vec_new [u] )
    = . c tk_ticket ( vec_new [u] )
    = . c tk_psk ( vec_new [u] )
    = . c tk_age_add 0
    = . c tk_lifetime 0
    = . c tk_received_ms 0

    // ── resumption offer ──
    // A usable exported session becomes the pre_shared_key offer; the
    // server may still decline it (rotated ticket key, expired, or no
    // resumption at all), in which case the handshake below is simply
    // the full one — nothing here is trusted until the ServerHello says
    // the ticket was taken.
    : ~ i offer 0
    : ~ i obf_age 0
    ? ( __sess_load c sess ) {
        = offer 1
        ( vec_free [u] . c res_early )
        = . c res_early ( _psk_early . c tk_psk )
        : i age - ( now_ms ) . c tk_received_ms
        = obf_age & + age . c tk_age_add 4294967295
    } {}

    // ── key share ──
    : ( Vec u ) priv ( _rand_bytes 32 )
    : ( Vec u ) cpub ( x25519_base priv )
    : ( Vec u ) p256priv ( _rand_bytes 32 )
    : ( Vec u ) p256pub ( p256_ecdh_keygen p256priv )
    ( vec_free [u] . c kx_p256 )
    = . c kx_p256 p256priv
    // ML-KEM-768 for the hybrid group. The decapsulation key lives on the
    // connection until the server's share arrives; the encapsulation key
    // travels in the ClientHello.
    : *MlkemKeys pqkeys ( mlkem_keygen 768 )
    : ( Vec u ) pqpub ( bytes_slice ( mlkem_ek pqkeys ) 0 ( vec_len [u] ( mlkem_ek pqkeys ) ) )
    ( vec_free [u] . c kx_mlkem )
    = . c kx_mlkem ( bytes_slice ( mlkem_dk pqkeys ) 0 ( vec_len [u] ( mlkem_dk pqkeys ) ) )
    ( mlkem_keys_free pqkeys )
    : ( Vec u ) random ( _rand_bytes 32 )
    : ( Vec u ) sessid ( _rand_bytes 32 )

    // ── transcript ──
    : ~ ( Vec u ) tr ( vec_new [u] )

    // ── ClientHello ──
    : ( Vec u ) noid ( vec_new [u] )
    : ( Vec u ) ch ( __build_client_hello server_name cpub p256pub pqpub random sessid alpn ? == offer 1 . c tk_ticket noid obf_age )
    ( vec_free [u] noid )
    ( vec_free [u] pqpub )
    ( vec_free [u] p256pub )
    ? == offer 1 {
        : ( Vec u ) binder ( _psk_binder_over . c res_early ch - ( vec_len [u] ch ) 35 )
        ( __ch_patch_binder ch binder )
        ( vec_free [u] binder )
    } {}
    ( _tls_cat tr ch )
    : !v TlsErr sw ( _send_plain c 22 ch )
    ?? sw { T _ → {} F e → { ^ ( __fail c priv cpub random sessid ch tr e ) } }

    // ── ServerHello ──
    : !( Vec u ) TlsErr shr ( __next_hs c )
    : ( Vec u ) sh ?? shr { T m → m F e → { ^ ( __fail c priv cpub random sessid ch tr e ) } }
    ( _tls_cat tr sh )
    : i suite ( __sh_suite sh )
    = . c version ( __suite_version suite )
    = . c cipher ( __suite_cipher suite )

    // ── TLS 1.2 fallback ──
    ? == . c version 12 {
        ^ ( __tls12_handshake c sh priv cpub random sessid ch tr )
    } {}

    : !( Vec u ) TlsErr spkr ( __parse_server_hello sh )
    : ( Vec u ) spub ?? spkr { T k → k F e → { ( vec_free [u] sh ) ^ ( __fail c priv cpub random sessid ch tr e ) } }

    // ── key schedule (handshake) ──
    // Distinguish the negotiated group by the server key-exchange length:
    // X25519 is 32 bytes, an uncompressed secp256r1 point is 65, and the
    // X25519MLKEM768 share is 1088 + 32 = 1120.
    //
    // For the hybrid group the shared secret handed to the key schedule
    // is `ML-KEM shared secret ‖ X25519 shared secret` — 64 bytes, ML-KEM
    // first, matching the order of the shares. Concatenation is what
    // makes it a hybrid worth having: HKDF-Extract over the pair is at
    // least as strong as either half, so the handshake survives ML-KEM
    // being broken *and* survives X25519 being broken.
    = . c kx_group ? == ( vec_len [u] spub ) 1120 4588 ? == ( vec_len [u] spub ) 65 23 29
    : ( Vec u ) ecdhe ? == ( vec_len [u] spub ) 1120
    ( __hybrid_shared c priv spub )
    ? == ( vec_len [u] spub ) 65 ( p256_ecdh_shared . c kx_p256 spub ) ( x25519 priv spub )
    // H3: RFC 8446 §7.4.2 — abort if the ECDHE output is all-zero (peer sent a
    // low-order / small-subgroup point forcing a known shared secret).
    ? ( _all_zero ecdhe ) {
        ( vec_free [u] sh ) ( vec_free [u] spub ) ( vec_free [u] ecdhe )
        ^ ( __fail c priv cpub random sessid ch tr # TlsErr TlsProtocol )
    } {}
    : ( Vec u ) zeros ( _rand_bytes 0 )
    : ( Vec u ) z32 ( vec_with_cap [u] 32 )
    : ~ i zk 0
    ~ < zk 32 { ( vec_push [u] z32 # u 0 ) = zk + zk 1 }
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) ehash ( sha256_pure empty )
    // The server took our ticket iff its ServerHello carries
    // pre_shared_key; then the early secret is the PSK's and no
    // Certificate / CertificateVerify will follow — the PSK is the proof
    // of identity (only the issuer of the ticket knows it).
    ? & == offer 1 ( __sh_has_psk sh ) { = . c resumed 1 } {}
    : ( Vec u ) early ? == . c resumed 1 ( bytes_slice . c res_early 0 32 ) ( hkdf_extract empty z32 )
    : ( Vec u ) derived1 ( derive_secret early `derived` ehash )
    : ( Vec u ) hs_secret ( hkdf_extract derived1 ecdhe )

    : ( Vec u ) th_sh ( sha256_pure tr )
    : ( Vec u ) c_hs ( derive_secret hs_secret `c hs traffic` th_sh )
    : ( Vec u ) s_hs ( derive_secret hs_secret `s hs traffic` th_sh )
    ( _set_keys c 0 s_hs )
    ( _set_keys c 1 c_hs )
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
                : i t ( _t_bget msg 0 )
                ? == t 20 {
                    : ( Vec u ) th_cv ( sha256_pure tr )
                    : ( Vec u ) expect ( _finished_mac s_hs th_cv )
                    : b okfin ( _cmp_finished msg expect )
                    ( vec_free [u] th_cv )
                    ( vec_free [u] expect )
                    ( _tls_cat tr msg )
                    ? okfin {} { = flighterr 1 }
                    = done 1
                } {
                    ? == t 11 {
                        ( vec_free [u] . c cert_msg )
                        = . c cert_msg ( bytes_slice msg 0 ( vec_len [u] msg ) )
                    } {}
                    ? == t 15 {
                        // CertificateVerify: capture transcript-through-Certificate
                        // (before appending this message) and the scheme + signature.
                        : ( Vec u ) thc ( sha256_pure tr )
                        ( vec_free [u] . c th_cert )
                        = . c th_cert thc
                        = . c cv_scheme ( _rdint msg 4 2 )
                        : i siglen ( _rdint msg 6 2 )
                        ( vec_free [u] . c cv_sig )
                        = . c cv_sig ( bytes_slice msg 8 + 8 siglen )
                    } {}
                    ? == t 8 {
                        // EncryptedExtensions — pick up the negotiated ALPN.
                        : ( Vec u ) sel ( __ee_alpn msg )
                        ? > ( vec_len [u] sel ) 0 {
                            ( vec_free [u] . c alpn_sel )
                            = . c alpn_sel sel
                        } { ( vec_free [u] sel ) }
                    } {}
                    ( _tls_cat tr msg )
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
    : ( Vec u ) cfin ( _finished_mac c_hs th_sf )
    : ( Vec u ) finmsg ( vec_with_cap [u] 36 )
    ( vec_push [u] finmsg # u 20 )
    ( _u24 finmsg 32 )
    ( _tls_cat finmsg cfin )
    // change_cipher_spec for middlebox compatibility
    : ( Vec u ) ccs ( vec_with_cap [u] 1 )
    ( vec_push [u] ccs # u 1 )
    : !v TlsErr cw ( _send_plain c 20 ccs )
    ?? cw { T _ → {} F _ → {} }
    ( vec_free [u] ccs )
    : !v TlsErr fw ( __send_encrypted c 22 finmsg )
    ?? fw { T _ → {} F _ → {} }

    // switch to application traffic keys
    ( _set_keys c 0 s_ap )
    ( _set_keys c 1 c_ap )
    = . c established 1

    // resumption_master_secret: transcript through our own Finished.
    // Every NewSessionTicket the server sends from here on derives its
    // PSK from this (see __client_take_ticket).
    ( _tls_cat tr finmsg )
    : ( Vec u ) th_cf ( sha256_pure tr )
    ( vec_free [u] . c res_master )
    = . c res_master ( derive_secret master `res master` th_cf )
    ( vec_free [u] th_cf )

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

// Upgrade an already-connected fd to TLS (no ALPN). Insecure: does not
// verify the certificate (see tls_attach_verify).
@ tls_attach i raw s server_name → !*TlsConn TlsErr {
    : ( Vec u ) nosess ( vec_new [u] )
    : !*TlsConn TlsErr r ( __tls_handshake raw server_name `` nosess )
    ( vec_free [u] nosess )
    ^ r
}

// Like tls_attach but offers a single ALPN protocol (e.g. "h2"). After a
// successful handshake the negotiated protocol is readable via
// tls_alpn_selected (empty if the server declined ALPN). Insecure variant.
@ tls_attach_alpn i raw s server_name s alpn → !*TlsConn TlsErr {
    : ( Vec u ) nosess ( vec_new [u] )
    : !*TlsConn TlsErr r ( __tls_handshake raw server_name alpn nosess )
    ( vec_free [u] nosess )
    ^ r
}

// tls_attach with a resumption offer: `sess` is what tls_session_export
// returned from an earlier connection to the same server. If the server
// takes it the handshake is the abbreviated PSK one (no certificate, one
// round trip, no signature to verify) and tls_is_resumed answers T;
// otherwise this is exactly tls_attach. Insecure variant — see
// tls_connect_resume for the verifying one.
@ tls_attach_resume i raw s server_name ( Vec u ) sess → !*TlsConn TlsErr {
    ^ ( __tls_handshake raw server_name `` sess )
}

// Unverified connect with a resumption offer (the tls_connect_insecure
// of resumption — pinned / self-signed / test servers).
@ tls_connect_insecure_resume s host i port s server_name ( Vec u ) sess → !*TlsConn TlsErr {
    : i raw ( nurl_tcp_connect host port )
    ^ ( tls_attach_resume raw server_name sess )
}

// Verifying connect with a resumption offer. A resumed connection is
// authenticated by the PSK (the ticket's issuer is the server verified
// when the session was made); a declined offer falls back to the full
// handshake and the usual chain / hostname verification.
@ tls_connect_resume s host i port s server_name ( Vec u ) sess → !*TlsConn TlsErr {
    : i raw ( nurl_tcp_connect host port )
    : !*TlsConn TlsErr r ( tls_attach_resume raw server_name sess )
    ^ ( __verify_conn r server_name )
}

// The ALPN protocol the server selected, as an owned String ("" if none).
// The key-exchange group the server selected, as its IANA number:
//
//   4588  X25519MLKEM768   hybrid, post-quantum + X25519
//     29  x25519
//     23  secp256r1
//      0  not negotiated yet, or a TLS 1.2 handshake
//
// Worth checking rather than assuming: offering the hybrid group does
// not mean getting it, and the difference is the whole point. A server
// that has not deployed ML-KEM silently falls back to X25519, and the
// handshake looks identical from every other angle.
@ tls_group * TlsConn c → i {
    ^ . c kx_group
}

// T when the negotiated group carries a post-quantum component, so the
// session's forward secrecy survives a future quantum adversary
// recording it today.
@ tls_is_post_quantum * TlsConn c → b {
    ^ == . c kx_group 4588
}

// True iff the negotiated ALPN protocol is exactly `proto` — the
// allocation-free form of tls_alpn_selected for the per-connection
// dispatch question ("is this h2?").
@ tls_alpn_is * TlsConn c s proto → b {
    : i n ( vec_len [u] . c alpn_sel )
    ? != n ( nurl_str_len proto ) { ^ F } {}
    : *u p ( vec_data [u] . c alpn_sel )
    : ~ i k 0
    ~ < k n {
        ? != # i . p k ( nurl_str_get proto k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ tls_alpn_selected * TlsConn c → String {
    : String s ( string_new )
    : i n ( vec_len [u] . c alpn_sel )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [u] . c alpn_sel k ) { T b → ( string_push_char s # i b ) F _ → {} }
        = k + k 1
    }
    ^ s
}

// Establish a verified TLS 1.3 connection (the secure default): complete
// the handshake, then verify the server's CertificateVerify signature,
// the certificate chain up to the system trust store, the validity
// window, and that `server_name` matches the leaf SANs. On any failure
// the connection is closed and TlsBadCert is returned.
// TLS 1.2 verification: the ServerKeyExchange signature (authenticating
// the ephemeral key to the leaf cert) + the certificate chain.
@ __verify12 * TlsConn c s hostname → i {
    : X509 leaf ( tls_leaf_cert . c cert_msg 1 )
    ? ! . leaf ok { ( x509_free leaf ) ^ 2 } {}
    : i sk ( tls12_ske_verify leaf . c cv_scheme . c cv_sig . c th_cert )
    ( x509_free leaf )
    ? != sk 0 { ^ sk } {}
    ^ ( tls_chain_verify . c cert_msg 1 hostname )
}

@ tls_connect s host i port s server_name → !*TlsConn TlsErr {
    : !*TlsConn TlsErr r ( tls_connect_insecure host port server_name )
    ^ ( __verify_conn r server_name )
}

// Verifying counterpart of `tls_attach`: upgrade an already-connected
// socket to TLS and verify the chain / hostname against the system trust
// store (the secure default for STARTTLS-style upgrades).
@ tls_attach_verify i raw s server_name → !*TlsConn TlsErr {
    : !*TlsConn TlsErr r ( tls_attach raw server_name )
    ^ ( __verify_conn r server_name )
}

// Verifying counterpart of tls_attach_alpn: offer an ALPN protocol AND
// verify the chain / hostname. The negotiated protocol is then readable
// with tls_alpn_selected.
@ tls_attach_alpn_verify i raw s server_name s alpn → !*TlsConn TlsErr {
    : !*TlsConn TlsErr r ( tls_attach_alpn raw server_name alpn )
    ^ ( __verify_conn r server_name )
}

// Shared post-handshake verification used by both tls_connect and
// tls_attach_verify: check the certificate (TLS 1.3 CertificateVerify or
// TLS 1.2 ServerKeyExchange sig + chain + hostname) and close on failure.
@ __verify_conn ! * TlsConn TlsErr r s server_name → !*TlsConn TlsErr {
    ?? r {
        F e → { ^ @ !*TlsConn TlsErr { F e } }
        T c → {
            // A resumed connection carries no certificate: the PSK it was
            // established from authenticates the server as the issuer of
            // the ticket, which was verified when that session was made.
            : i rc ? == . c resumed 1 0 ? == . c version 12 ( __verify12 c server_name ) ( tls_cert_verify . c cert_msg . c cv_scheme . c cv_sig . c th_cert server_name )
            ? == rc 0 {
                ^ @ !*TlsConn TlsErr { T c }
            } {
                ( tls_close c )
                ^ @ !*TlsConn TlsErr { F # TlsErr TlsBadCert }
            }
        }
    }
}

// Compare a Finished message's verify_data (bytes 4..36) against expected.
@ _cmp_finished ( Vec u ) msg ( Vec u ) expect → b {
    ? < ( vec_len [u] msg ) 36 { ^ F } {}
    : ~ i diff 0
    : ~ i k 0
    ~ < k 32 { = diff | diff ^^ ( _t_bget msg + 4 k ) ( _t_bget expect k ) = k + k 1 }
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
//
// A TLS record carries at most 2^14 bytes of plaintext (RFC 8446 §5.1,
// same limit in 1.2): peers MUST reject anything larger, and past 65535
// the record header's u16 length field wraps outright. Split
// application data into ≤16384-byte records.
@ tls_write * TlsConn c ( Vec u ) data → !v TlsErr {
    : i n ( vec_len [u] data )
    ? <= n 16384 {
        ? == . c version 12 { ^ ( __send_record_12 c 23 data ) } {}
        ^ ( __send_encrypted c 23 data )
    } {}
    : ~ i off 0
    ~ < off n {
        : ~ i hi + off 16384
        ? > hi n { = hi n } {}
        : ( Vec u ) part ( bytes_slice data off hi )
        : ~ ! v TlsErr w @ !v TlsErr { T 0 }
        ? == . c version 12 { = w ( __send_record_12 c 23 part ) } { = w ( __send_encrypted c 23 part ) }
        ( vec_free [u] part )
        ?? w { T _ → {} F e → { ^ @ !v TlsErr { F e } } }
        = off hi
    }
    ^ @ !v TlsErr { T 0 }
}

// Bytes [lo, hi) of the logical concatenation `head`‖`body`, as a fresh
// Vec — the record cutter behind tls_write2 / tls_server_write2. One
// memcpy per source touched; a range inside a single source is one.
// One spare byte of capacity: the sealers push the inner content-type
// byte onto this same Vec, and that must not be a reallocation.
@ _tls_pair_slice ( Vec u ) head ( Vec u ) body i lo i hi → ( Vec u ) {
    : i hn ( vec_len [u] head )
    : i bn ( vec_len [u] body )
    : ~ i a lo
    : ~ i z hi
    ? < a 0 { = a 0 } {}
    ? > z + hn bn { = z + hn bn } {}
    ? < z a { = z a } {}
    : ( Vec u ) out ( vec_with_cap [u] + 1 - z a )
    ? < a hn {
        : i h_hi ? < z hn z hn
        : *u hp ( vec_data [u] head )
        ( bytes_extend_raw out # s + # i hp a - h_hi a )
    } {}
    ? > z hn {
        : i b_lo ? > a hn - a hn 0
        : *u bp ( vec_data [u] body )
        ( bytes_extend_raw out # s + # i bp b_lo - - z hn b_lo )
    } {}
    ^ out
}

// Two-buffer variant of tls_write (client side of tcp_write_all2):
// records are cut from `head`‖`body` without joining the two first.
// TLS 1.3 assembles each record's plaintext straight from the pair;
// TLS 1.2 hands the AEAD a plaintext Vec, so it cuts one per record
// (the same one bytes_slice cut before).
@ tls_write2 * TlsConn c ( Vec u ) head ( Vec u ) body → !v TlsErr {
    : i n + ( vec_len [u] head ) ( vec_len [u] body )
    : ~ i off 0
    ~ < off n {
        : ~ i hi + off 16384
        ? > hi n { = hi n } {}
        : ~ ! v TlsErr w @ !v TlsErr { T 0 }
        ? == . c version 12 {
            : ( Vec u ) part ( _tls_pair_slice head body off hi )
            = w ( __send_record_12 c 23 part )
            ( vec_free [u] part )
        } { = w ( __send_encrypted_pair c 23 head body off hi ) }
        ?? w { T _ → {} F e → { ^ @ !v TlsErr { F e } } }
        = off hi
    }
    ^ @ !v TlsErr { T 0 }
}

// Read up to `max` decrypted application bytes. Returns [] on clean EOF
// (close_notify). Post-handshake messages (tickets, key updates) are
// consumed transparently.
@ tls_read * TlsConn c i max → !( Vec u ) TlsErr {
    ~ & == ( vec_len [u] . c appbuf ) 0 == . c closed 0 {
        : !TlsRecord TlsErr rr ( _read_record c )
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
                    ? == . c version 12 {
                        // TLS 1.2: the record type is the real content type.
                        ?? ( __decrypt_record_12 c . rec rtype . rec body ) {
                            T inner → {
                                ( vec_free [u] . rec body )
                                ? == . rec rtype 23 { ( _tls_cat . c appbuf inner ) } {
                                    ? == . rec rtype 21 { = . c closed 1 } {}
                                    // type 22 (post-handshake, e.g. tickets): ignore
                                }
                                ( vec_free [u] inner )
                            }
                            F _ → {
                                ( vec_free [u] . rec body )
                                ^ @ !( Vec u ) TlsErr { F # TlsErr TlsDecrypt }
                            }
                        }
                    } {
                        ?? ( __decrypt_record c . rec body ) {
                            T inner → {
                                ( vec_free [u] . rec body )
                                : i ct ( _inner_type inner )
                                ? == ct 23 {
                                    ( _tls_cat . c appbuf inner )
                                } {
                                    ? == ct 21 { = . c closed 1 } {}
                                    // post-handshake: keep a NewSessionTicket, ignore the rest
                                    ? == ct 22 { ( __client_post_hs c inner ) } {}
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
            : !v TlsErr _w ? == . c version 12 ( __send_record_12 c 21 alert ) ( __send_encrypted c 21 alert )
            ( vec_free [u] alert )
        } {}
        = . c closed 1
    } {}
    ( nurl_tcp_close . c fd )
    ( vec_free [u] . c rxbuf )
    ( vec_free [u] . c hsbuf )
    ( vec_free [u] . c appbuf )
    ( vec_free [u] . c s_key ) ( vec_free [u] . c s_iv )
    ( vec_free [u] . c c_key ) ( vec_free [u] . c c_iv )
    ( vec_free [u] . c cert_msg )
    ( vec_free [u] . c cv_sig )
    ( vec_free [u] . c th_cert )
    ( vec_free [u] . c kx_p256 )
    ( vec_free [u] . c kx_mlkem )
    ( vec_free [u] . c alpn_sel )
    ( vec_free [u] . c res_master )
    ( vec_free [u] . c res_early )
    ( vec_free [u] . c tk_ticket )
    ( vec_free [u] . c tk_psk )
    ( nurl_free # s c )
}

// ══════════════════════════════════════════════════════════════════
//  TLS 1.2 fallback (RFC 5246 + RFC 5288 GCM + RFC 7905 ChaCha20)
// ══════════════════════════════════════════════════════════════════

// TLS 1.2 PRF (P_SHA256): PRF(secret, label, seed) over HMAC-SHA-256.
@ __prf12 ( Vec u ) secret s label ( Vec u ) seed i outlen → ( Vec u ) {
    : ( Vec u ) fs ( vec_new [u] )
    ( bytes_extend_str fs label )
    ( bytes_extend_bytes fs seed )
    : ( Vec u ) out ( vec_with_cap [u] ? > outlen 0 outlen 1 )
    : ~ ( Vec u ) a ( bytes_slice fs 0 ( vec_len [u] fs ) )
    ~ < ( vec_len [u] out ) outlen {
        : ( Vec u ) anew ( hmac_sha256_pure secret a )
        ( vec_free [u] a )
        = a anew
        : ( Vec u ) cat ( bytes_slice a 0 ( vec_len [u] a ) )
        ( bytes_extend_bytes cat fs )
        : ( Vec u ) chunk ( hmac_sha256_pure secret cat )
        ( vec_free [u] cat )
        : ~ i j 0
        ~ & < j 32 < ( vec_len [u] out ) outlen { ( vec_push [u] out # u ( _t_bget chunk j ) ) = j + j 1 }
        ( vec_free [u] chunk )
    }
    ( vec_free [u] a )
    ( vec_free [u] fs )
    ^ out
}

// TLS 1.2 record AAD: seq(8) || type(1) || 0x0303 || plaintext_len(2).
@ __aad12 i seq i rtype i ptlen → ( Vec u ) {
    : ( Vec u ) a ( vec_with_cap [u] 13 )
    : ~ i k 0
    ~ < k 8 { ( vec_push [u] a # u & >> seq * 8 - 7 k 255 ) = k + k 1 }
    ( vec_push [u] a # u rtype )
    ( vec_push [u] a # u 3 )
    ( vec_push [u] a # u 3 )
    ( _tls_u16 a ptlen )
    ^ a
}

// AES-GCM nonce: 4-byte salt || 8-byte explicit (= seq).
@ __nonce12_aes ( Vec u ) iv4 i seq → ( Vec u ) {
    : ( Vec u ) n ( vec_with_cap [u] 12 )
    : ~ i k 0
    ~ < k 4 { ( vec_push [u] n # u ( _t_bget iv4 k ) ) = k + k 1 }
    : ~ i b 0
    ~ < b 8 { ( vec_push [u] n # u & >> seq * 8 - 7 b 255 ) = b + b 1 }
    ^ n
}

// ChaCha20 nonce (RFC 7905): 12-byte IV XOR (0^4 || seq).
@ __nonce12_chacha ( Vec u ) iv12 i seq → ( Vec u ) {
    : ( Vec u ) n ( vec_with_cap [u] 12 )
    : ~ i k 0
    ~ < k 12 { ( vec_push [u] n # u ( _t_bget iv12 k ) ) = k + k 1 }
    : ~ i b 0
    ~ < b 8 {
        : i sb & >> seq * 8 - 7 b 255
        ( vec_set [u] n + 4 b # u ^^ ( _t_bget n + 4 b ) sb )
        = b + b 1
    }
    ^ n
}

// Send one TLS 1.2 record of `content` (real content type `rtype`).
@ __send_record_12 * TlsConn c i rtype ( Vec u ) content → !v TlsErr {
    : i ptlen ( vec_len [u] content )
    : ( Vec u ) aad ( __aad12 . c c_seq rtype ptlen )
    : ( Vec u ) body ( vec_new [u] )
    ? == . c cipher 1 {
        : ( Vec u ) nonce ( __nonce12_aes . c c_iv . c c_seq )
        : ( Vec u ) sealed ( aes128_gcm_encrypt . c c_key nonce aad content )
        // explicit nonce (= seq) is prepended on the wire
        : ~ i b 0
        ~ < b 8 { ( vec_push [u] body # u & >> . c c_seq * 8 - 7 b 255 ) = b + b 1 }
        ( _tls_cat body sealed )
        ( vec_free [u] nonce )
        ( vec_free [u] sealed )
    } {
        : ( Vec u ) nonce ( __nonce12_chacha . c c_iv . c c_seq )
        : ( Vec u ) sealed ( aead_encrypt . c c_key nonce aad content )
        ( _tls_cat body sealed )
        ( vec_free [u] nonce )
        ( vec_free [u] sealed )
    }
    : ( Vec u ) rec ( vec_with_cap [u] + ( vec_len [u] body ) 5 )
    ( vec_push [u] rec # u rtype )
    ( vec_push [u] rec # u 3 )
    ( vec_push [u] rec # u 3 )
    ( _tls_u16 rec ( vec_len [u] body ) )
    ( _tls_cat rec body )
    : b w ( _tls_sock_write . c fd rec )
    ( vec_free [u] aad )
    ( vec_free [u] body )
    ( vec_free [u] rec )
    = . c c_seq + . c c_seq 1
    ^ ? w @ !v TlsErr { T 0 } @ !v TlsErr { F # TlsErr TlsWrite }
}

// Decrypt a TLS 1.2 record body (real type `rtype`) → plaintext.
@ __decrypt_record_12 * TlsConn c i rtype ( Vec u ) body → ?( Vec u ) {
    : ?( Vec u ) pt ? == . c cipher 1 {
        : i explen 8
        : ( Vec u ) nonce ( vec_with_cap [u] 12 )
        : ~ i k 0
        ~ < k 4 { ( vec_push [u] nonce # u ( _t_bget . c s_iv k ) ) = k + k 1 }
        : ~ i e 0
        ~ < e 8 { ( vec_push [u] nonce # u ( _t_bget body e ) ) = e + e 1 }
        : ( Vec u ) ct ( bytes_slice body 8 ( vec_len [u] body ) )
        : i ptlen - ( vec_len [u] ct ) 16
        : ( Vec u ) aad ( __aad12 . c s_seq rtype ptlen )
        : ?( Vec u ) r ( aes128_gcm_decrypt . c s_key nonce aad ct )
        ( vec_free [u] nonce )
        ( vec_free [u] ct )
        ( vec_free [u] aad )
        r
    } {
        : ( Vec u ) nonce ( __nonce12_chacha . c s_iv . c s_seq )
        : i ptlen - ( vec_len [u] body ) 16
        : ( Vec u ) aad ( __aad12 . c s_seq rtype ptlen )
        : ?( Vec u ) r ( aead_decrypt . c s_key nonce aad body )
        ( vec_free [u] nonce )
        ( vec_free [u] aad )
        r
    }
    = . c s_seq + . c s_seq 1
    ^ pt
}

// Derive the TLS 1.2 key block and install client/server write keys.
@ __tls12_setkeys * TlsConn c ( Vec u ) master ( Vec u ) crand ( Vec u ) srand → v {
    : ( Vec u ) seed ( vec_new [u] )
    ( bytes_extend_bytes seed srand )
    ( bytes_extend_bytes seed crand )
    : i klen ? == . c cipher 1 16 32
    : i ivlen ? == . c cipher 1 4 12
    : i need + * 2 klen * 2 ivlen
    : ( Vec u ) kb ( __prf12 master `key expansion` seed need )
    ( vec_free [u] seed )
    : ( Vec u ) ck ( bytes_slice kb 0 klen )
    : ( Vec u ) sk ( bytes_slice kb klen * 2 klen )
    : ( Vec u ) civ ( bytes_slice kb * 2 klen + * 2 klen ivlen )
    : ( Vec u ) siv ( bytes_slice kb + * 2 klen ivlen + * 2 klen * 2 ivlen )
    ( vec_free [u] . c c_key )
    ( vec_free [u] . c s_key )
    ( vec_free [u] . c c_iv )
    ( vec_free [u] . c s_iv )
    = . c c_key ck
    = . c s_key sk
    = . c c_iv civ
    = . c s_iv siv
    = . c c_seq 0
    = . c s_seq 0
    ( vec_free [u] kb )
}

// Drive the TLS 1.2 handshake after ServerHello. Consumes all the passed
// buffers. On success returns the established (encrypted) connection;
// the certificate chain + ServerKeyExchange signature material are
// captured on `c` for the verifier (cv_sig / cv_scheme / th_cert).
@ __tls12_handshake * TlsConn c ( Vec u ) sh ( Vec u ) priv ( Vec u ) cpub ( Vec u ) random ( Vec u ) sessid ( Vec u ) ch ( Vec u ) tr → !*TlsConn TlsErr {
    : ( Vec u ) srand ( bytes_slice sh 6 38 )
    // M1: we always offer TLS 1.3 in supported_versions, so negotiating 1.2
    // here means a possible forced downgrade — abort on the RFC 8446 sentinel.
    ? ( __downgrade_sentinel srand ) {
        ( vec_free [u] srand ) ( vec_free [u] sh )
        ^ ( __fail c priv cpub random sessid ch tr # TlsErr TlsProtocol )
    } {}

    // ── server flight 1: Certificate, ServerKeyExchange, ServerHelloDone ──
    : ~ ( Vec u ) spub ( vec_new [u] )
    : ~ i kx_curve 29  // named_curve from ServerKeyExchange: 29 x25519, 23 secp256r1
    : ~ i err 0
    : ~ i done 0
    ~ & == done 0 == err 0 {
        : !( Vec u ) TlsErr mr ( __next_hs c )
        ?? mr {
            F _ → { = err 1 }
            T msg → {
                : i t ( _t_bget msg 0 )
                ? == t 11 {
                    ( vec_free [u] . c cert_msg )
                    = . c cert_msg ( bytes_slice msg 0 ( vec_len [u] msg ) )
                } {}
                ? == t 12 {
                    // ServerKeyExchange: curve_type(1) curve(2) pklen(1) pk sig_scheme(2) siglen(2) sig
                    = kx_curve ( _rdint msg 5 2 )
                    : i pklen ( _t_bget msg 7 )
                    ( vec_free [u] spub )
                    = spub ( bytes_slice msg 8 + 8 pklen )
                    : i sp + 8 pklen
                    = . c cv_scheme ( _rdint msg sp 2 )
                    : i siglen ( _rdint msg + sp 2 2 )
                    ( vec_free [u] . c cv_sig )
                    = . c cv_sig ( bytes_slice msg + sp 4 + + sp 4 siglen )
                    // signed data = client_random || server_random || ecdhe_params
                    : ( Vec u ) signed ( vec_new [u] )
                    ( bytes_extend_bytes signed random )
                    ( bytes_extend_bytes signed srand )
                    : ( Vec u ) eparams ( bytes_slice msg 4 + 8 pklen )
                    ( _tls_cat signed eparams )
                    ( vec_free [u] eparams )
                    ( vec_free [u] . c th_cert )
                    = . c th_cert signed
                } {}
                ? == t 14 { = done 1 } {}
                ( _tls_cat tr msg )
                ( vec_free [u] msg )
            }
        }
    }
    ? | == err 1 == ( vec_len [u] spub ) 0 {
        ( vec_free [u] srand ) ( vec_free [u] spub )
        ^ ( __fail c priv cpub random sessid ch tr # TlsErr TlsHandshake )
    } {}

    // ── ECDHE + master secret ──
    // Curve chosen by the server's ServerKeyExchange: secp256r1 (P-256,
    // 23) or x25519 (29). Stock TLS-1.2 servers (e.g. OpenSSL with the
    // default ssl_ecdh_curve=prime256v1) pick P-256, so both are handled.
    : i is_p256 == kx_curve 23
    : ( Vec u ) ckpub ? is_p256 ( p256_ecdh_keygen . c kx_p256 ) cpub
    : ( Vec u ) pms ? is_p256 ( p256_ecdh_shared . c kx_p256 spub ) ( x25519 priv spub )
    : ( Vec u ) cs_seed ( vec_new [u] )
    ( bytes_extend_bytes cs_seed random )
    ( bytes_extend_bytes cs_seed srand )
    : ( Vec u ) master ( __prf12 pms `master secret` cs_seed 48 )
    ( vec_free [u] cs_seed )
    ( __tls12_setkeys c master random srand )

    // ── ClientKeyExchange (plaintext handshake) ──
    // body = pubkey_len(1) || pubkey ; handshake length = 1 + len(pubkey)
    : i cklen ( vec_len [u] ckpub )
    : ( Vec u ) cke ( vec_with_cap [u] + cklen 5 )
    ( vec_push [u] cke # u 16 )
    ( _u24 cke + cklen 1 )
    ( vec_push [u] cke # u cklen )
    ( _tls_cat cke ckpub )
    // ckpub is a fresh P-256 point we own; the x25519 case aliases cpub
    // (freed with the other handshake scratch later), so only free P-256.
    ? is_p256 { ( vec_free [u] ckpub ) } {}
    : !v TlsErr ckw ( _send_plain c 22 cke )
    ?? ckw { T _ → {} F _ → {} }
    ( _tls_cat tr cke )

    // ── ChangeCipherSpec + client Finished (encrypted) ──
    : ( Vec u ) ccs ( vec_with_cap [u] 1 )
    ( vec_push [u] ccs # u 1 )
    : !v TlsErr cw ( _send_plain c 20 ccs )
    ?? cw { T _ → {} F _ → {} }
    ( vec_free [u] ccs )

    : ( Vec u ) th_c ( sha256_pure tr )
    : ( Vec u ) cfin_vd ( __prf12 master `client finished` th_c 12 )
    ( vec_free [u] th_c )
    : ( Vec u ) finmsg ( vec_with_cap [u] 16 )
    ( vec_push [u] finmsg # u 20 )
    ( _u24 finmsg 12 )
    ( _tls_cat finmsg cfin_vd )
    ( vec_free [u] cfin_vd )
    : !v TlsErr fw ( __send_record_12 c 22 finmsg )
    ?? fw { T _ → {} F _ → {} }
    ( _tls_cat tr finmsg )
    ( vec_free [u] finmsg )

    // ── server ChangeCipherSpec + Finished ──
    : ( Vec u ) th_s ( sha256_pure tr )
    : ( Vec u ) sfin_exp ( __prf12 master `server finished` th_s 12 )
    ( vec_free [u] th_s )
    : ~ i serr 0
    : ~ i sdone 0
    ~ & == sdone 0 == serr 0 {
        : !TlsRecord TlsErr rr ( _read_record c )
        ?? rr {
            F _ → { = serr 1 }
            T rec → {
                ? == . rec rtype 20 {
                    ( vec_free [u] . rec body )
                } {
                    ?? ( __decrypt_record_12 c . rec rtype . rec body ) {
                        T inner → {
                            ( vec_free [u] . rec body )
                            // inner = Finished handshake msg: [20][len3][verify_data]
                            // L5: compare the 12-byte verify_data in constant
                            // time (OR-accumulate XOR diffs, no early exit).
                            : ~ i diff ? >= ( vec_len [u] inner ) 16 0 1
                            : ~ i vi 0
                            ~ < vi 12 { = diff | diff ^^ ( _t_bget inner + 4 vi ) ( _t_bget sfin_exp vi ) = vi + vi 1 }
                            ? == diff 0 { = sdone 1 } { = serr 1 }
                            ( vec_free [u] inner )
                        }
                        F _ → { ( vec_free [u] . rec body ) = serr 1 }
                    }
                }
            }
        }
    }
    ( vec_free [u] sfin_exp )

    ( vec_free [u] srand ) ( vec_free [u] spub ) ( vec_free [u] pms ) ( vec_free [u] master )
    ( vec_free [u] priv ) ( vec_free [u] cpub ) ( vec_free [u] random ) ( vec_free [u] sessid )
    ( vec_free [u] ch ) ( vec_free [u] tr ) ( vec_free [u] sh ) ( vec_free [u] cke )

    ? == serr 1 { ( tls_close c ) ^ @ !*TlsConn TlsErr { F # TlsErr TlsHandshake } } {}
    = . c established 1
    ^ @ !*TlsConn TlsErr { T c }
}
