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
//   ( tls_connect host port server_name )          → !TlsConn TlsErr  (verify-full)
//   ( tls_connect_insecure host port server_name ) → !TlsConn TlsErr  (no cert check)
//   ( tls_write conn bytes )                       → !v TlsErr
//   ( tls_read conn max )                          → !( Vec u ) TlsErr  ([] at EOF)
//   ( tls_close conn )                             → v  close_notify + close the socket
//
// A TlsConn is a handle: every copy is the same connection, and its last
// owner releases it (closing the socket if tls_close has not).
//
// `tls_connect` is secure by default: it completes the handshake and then
// verifies the server certificate chain (see verify.nu) against the system
// trust store, failing with TlsBadCert otherwise. `tls_connect_insecure`
// is the encrypted-but-unauthenticated escape hatch.

$ `stdlib/core/marker.nu`
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
$ `stdlib/core/rcbox.nu`

// Park the current fiber until `raw`'s socket is readable (want = 0)
// or writable (want = 1), honouring the handle's configured timeout
// (0 = wait for ever, matching the blocking path's SO_RCVTIMEO
// semantics). Returns T when the socket is ready, F on timeout or a
// missing fiber context.
@ __tls_io_wait i raw i want → b {
    : i fd ( nurl_tcp_get_fd raw )
    : i ms ( nurl_tcp_timeout_ms raw )
    : i deadline ? != want 0 ( nurl_tcp_write_wait_ms raw ) ? > ms 0 ms - 0 1
    ? == deadline 0 { ^ F } {}
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
: TlsConnImpl {
    i fd
    i owns_fd  // 1 until tls_close closes the socket
    i read_nowait  // one try-read call must not park on partial records
    ( Vec u ) rxbuf  // raw socket bytes not yet split into records
    ( Vec u ) hsbuf  // decrypted handshake bytes not yet a full message
    ( Vec u ) appbuf  // decrypted application bytes for the caller
    ( Vec u ) s_key
    ( Vec u ) s_iv
    ( Vec u ) c_key
    ( Vec u ) c_iv
    ( Vec u ) s_secret  // retained TLS 1.3 traffic secrets for KeyUpdate
    ( Vec u ) c_secret
    i update_pending  // peer requested our next write-key generation
    i fatal_alert  // queued protocol failure, emitted before closing
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

// The socket is the one raw part: a connection nobody tls_close'd is
// closed by its last owner (without a close_notify — that alert is
// tls_close's, said at a point of the caller's choosing).
% Drop TlsConnImpl {
    @ drop TlsConnImpl c → v {
        ? != . c owns_fd 0 { ( nurl_tcp_close . c fd ) } {}
    }
}

// A TlsConn is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same connection, and the last owner releases it.
: TlsConn { s ctl }

// Its drop closes something the outside world sees (stdlib/core/marker.nu).
% Resource TlsConn {}

@ TlsConn_share TlsConn h → TlsConn { ^ @ TlsConn { # s ( rcbox_share # i . h ctl ) } }

@ TlsConn_drop sink TlsConn h → v {
    ( mem_forget h )
    ( rcbox_release [TlsConnImpl] # i . h ctl )
}

@ __TlsConn_ptr TlsConn h → *TlsConnImpl { ^ ( rcbox_ptr [TlsConnImpl] # i . h ctl ) }

// The state in place, for the stdlib's own transport layer (std/net.nu).
@ _tls_ptr TlsConn h → *TlsConnImpl { ^ ( rcbox_ptr [TlsConnImpl] # i . h ctl ) }

// The connection as a word, for a holder that is not a handle itself
// (std/net.nu's TcpConn keeps one): one more owner, which
// `_tls_word_release` gives back.
@ _tls_word TlsConn h → i { ^ ( rcbox_share # i . h ctl ) }

@ _tls_word_release i w → v { ( rcbox_release [TlsConnImpl] w ) }

// A connection over socket `raw`. The connection owns the socket from
// here: tls_close closes it, or else the last owner does. A `raw` of 0 is
// no socket (a connection state built for a test).
@ _tls_conn_new i raw → TlsConn {
    : i c__box ( rcbox_zero [TlsConnImpl] )
    : *TlsConnImpl c ( rcbox_ptr [TlsConnImpl] c__box )
    = . c fd raw
    = . c read_nowait 0
    = . c s_secret ( vec_new [u] )
    = . c c_secret ( vec_new [u] )
    = . c update_pending 0
    = . c fatal_alert 0
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
    = . c owns_fd ? > raw 0 1 0
    ^ @ TlsConn { # s c__box }
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
@ __hybrid_shared ( Vec u ) dk ( Vec u ) priv ( Vec u ) spub → ( Vec u ) {
    : ( Vec u ) ct ( bytes_slice spub 0 1088 )
    : ( Vec u ) xpub ( bytes_slice spub 1088 1120 )
    : ( Vec u ) xs ( x25519 priv xpub )
    ? ( _all_zero xs ) {
        ^ ( vec_new [u] )
    } {}
    : ( Vec u ) out ( mlkem_decaps 768 dk ct )
    ( bytes_extend_bytes out xs )
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
@ __fill inout TlsConnImpl c i n → !i TlsErr {
    : i raw . c fd
    : b on_fiber != ( nurl_fiber_current ) 0
    ? & on_fiber == . c read_nowait 0 { ( nurl_tcp_set_nonblock raw 1 ) } {}
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
        : ~ i got ? != . c read_nowait 0 ( nurl_tcp_read_nowait raw pbuf 16384 ) ( nurl_tcp_read raw pbuf 16384 )
        : ~ b timed_out F
        ~ & == . c read_nowait 0 & ! timed_out & on_fiber & < got 0 == ( nurl_tcp_err_kind raw ) 7 {
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
@ __consume inout TlsConnImpl c i n → v {
    : ( Vec u ) buf . c rxbuf
    : i total ( vec_len [u] buf )
    ? >= n total { ( vec_clear [u] buf ) ^ v } {}
    : i remaining - total n
    : *u p ( vec_data [u] buf )
    ( nurl_memmove # s p # s # *u + # i p n remaining )
    : b _ok ( vec_set_len [u] buf remaining )
}

// Record = type(1) ver(2) length(2) body. Returns (type, body); body is
// an owned slice.
: TlsRecord { i rtype ( Vec u ) body }

@ _read_record inout TlsConnImpl c → !TlsRecord TlsErr {
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
@ __decrypt_record inout TlsConnImpl c ( Vec u ) body → ?( Vec u ) {
    : i blen ( vec_len [u] body )
    : ( Vec u ) aad ( vec_with_cap [u] 5 )
    ( vec_push [u] aad # u 23 )
    ( vec_push [u] aad # u 3 )
    ( vec_push [u] aad # u 3 )
    ( _tls_u16 aad blen )
    : ( Vec u ) nonce ( _nonce . c s_iv . c s_seq )
    : ?( Vec u ) pt ( _aead_open . c cipher . c s_key nonce aad body )
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
@ __send_encrypted inout TlsConnImpl c i content_type ( Vec u ) content → !v TlsErr {
    : ( Vec u ) inner ( vec_with_cap [u] + ( vec_len [u] content ) 1 )
    ( _tls_cat inner content )
    ^ ( __send_inner_encrypted c content_type inner )
}

// Same record, plaintext = bytes [lo, hi) of `head`‖`body`, assembled
// straight from the two buffers (tls_write2's per-record step).
@ __send_encrypted_pair inout TlsConnImpl c i content_type ( Vec u ) head ( Vec u ) body i lo i hi → !v TlsErr {
    : ( Vec u ) inner ( _tls_pair_slice head body lo hi )
    ^ ( __send_inner_encrypted c content_type inner )
}

// Seal `inner` (plaintext WITHOUT the type byte yet; consumed here) as
// one TLS 1.3 record under the client write keys and send it.
@ _tls_seal_inner_to inout TlsConnImpl c ( Vec u ) out i content_type ( Vec u ) inner → v {
    ( _tls_seal_direction_to c out 1 content_type inner )
}

@ _tls_seal_direction_to inout TlsConnImpl c ( Vec u ) out i dir i content_type ( Vec u ) inner → v {
    ( vec_push [u] inner # u content_type )
    : i total + ( vec_len [u] inner ) 16
    : ( Vec u ) aad ( vec_with_cap [u] 5 )
    ( vec_push [u] aad # u 23 )
    ( vec_push [u] aad # u 3 )
    ( vec_push [u] aad # u 3 )
    ( _tls_u16 aad total )
    : ( Vec u ) nonce ( _nonce ? == dir 0 . c s_iv . c c_iv ? == dir 0 . c s_seq . c c_seq )
    : ( Vec u ) sealed ( _aead_seal . c cipher ? == dir 0 . c s_key . c c_key nonce aad inner )
    ( vec_push [u] out # u 23 )
    ( vec_push [u] out # u 3 )
    ( vec_push [u] out # u 3 )
    ( _tls_u16 out total )
    ( _tls_cat out sealed )
    ? == dir 0 { = . c s_seq + . c s_seq 1 } { = . c c_seq + . c c_seq 1 }
}

@ __send_inner_encrypted inout TlsConnImpl c i content_type ( Vec u ) inner → !v TlsErr {
    : ( Vec u ) record ( vec_new [u] )
    ( _tls_seal_inner_to c record content_type inner )
    : b written ( _tls_sock_write . c fd record )
    ? ! written { = . c closed 1 } {}
    ^ ? written @ !v TlsErr { T 0 } @ !v TlsErr { F TlsWrite }
}

// Write a plaintext record straight to the socket.
@ _send_plain inout TlsConnImpl c i rtype ( Vec u ) body → !v TlsErr {
    : ( Vec u ) rec ( vec_with_cap [u] + ( vec_len [u] body ) 5 )
    ( vec_push [u] rec # u rtype )
    // legacy_record_version 0x0303 (RFC 8446 §5.1: required for every
    // record except the initial ClientHello, where 0x0303 is also valid).
    ( vec_push [u] rec # u 3 )
    ( vec_push [u] rec # u 3 )
    ( _tls_u16 rec ( vec_len [u] body ) )
    ( _tls_cat rec body )
    : b w ( _tls_sock_write . c fd rec )
    ^ ? w @ !v TlsErr { T 0 } @ !v TlsErr { F # TlsErr TlsWrite }
}

// ── handshake-message reader ──────────────────────────────────────
// Pull the next complete handshake message (header + body) from hsbuf,
// decrypting more records as needed. CCS records are skipped.
@ __next_hs inout TlsConnImpl c → !( Vec u ) TlsErr {
    : ~ i need 1
    ~ == need 1 {
        : i have ( vec_len [u] . c hsbuf )
        ? >= have 4 {
            : i mlen ( _rdint . c hsbuf 1 3 )
            ? >= have + 4 mlen {
                : ( Vec u ) msg ( bytes_slice . c hsbuf 0 + 4 mlen )
                : ( Vec u ) rest ( bytes_slice . c hsbuf + 4 mlen have )
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
                } {
                    ? == . rec rtype 23 {
                        ?? ( __decrypt_record c . rec body ) {
                            T inner → {
                                : i ct ( _inner_type inner )
                                ? == ct 22 {
                                    ( _tls_cat . c hsbuf inner )
                                } {
                                    ? == ct 21 { ^ @ !( Vec u ) TlsErr { F # TlsErr TlsAlert } } {}
                                    ^ @ !( Vec u ) TlsErr { F # TlsErr TlsProtocol }
                                }
                            }
                            F _ → {
                                ^ @ !( Vec u ) TlsErr { F # TlsErr TlsDecrypt }
                            }
                        }
                    } {
                        // plaintext handshake (ServerHello stage) or alert
                        ? == . rec rtype 22 {
                            ( _tls_cat . c hsbuf . rec body )
                        } {
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
@ __build_client_hello ( Vec u ) host ( Vec u ) pubkey ( Vec u ) p256pub ( Vec u ) pqpub ( Vec u ) random ( Vec u ) sessid ( Vec u ) alp_list ( Vec u ) ext_extra ( Vec u ) psk_id i obf_age → ( Vec u ) {
    : ( Vec u ) body ( vec_new [u] )
    ( _tls_u16 body 771 )  // legacy_version 0x0303
    ( _tls_cat body random )  // 32-byte random
    ( vec_push [u] body # u ( vec_len [u] sessid ) )  // legacy_session_id (empty for QUIC)
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
    : i hl ( vec_len [u] host )
    ( _tls_u16 sni + hl 3 )  // ServerNameList length
    ( vec_push [u] sni # u 0 )  // name_type host_name
    ( _tls_u16 sni hl )
    : ~ i k 0
    ~ < k hl { ( vec_push [u] sni # u ( _t_bget host k ) ) = k + k 1 }
    ( _tls_u16 ext 0 )
    ( _blk16 ext sni )

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

    // supported_versions (0x002b): TLS 1.3 (0x0304) then TLS 1.2 (0x0303)
    : ( Vec u ) sv ( vec_new [u] )
    ( vec_push [u] sv # u 4 )
    ( _tls_u16 sv 772 )
    ( _tls_u16 sv 771 )
    ( _tls_u16 ext 43 )
    ( _blk16 ext sv )

    // ec_point_formats (0x000b): uncompressed — some TLS 1.2 servers require it
    : ( Vec u ) epf ( vec_new [u] )
    ( vec_push [u] epf # u 1 )
    ( vec_push [u] epf # u 0 )
    ( _tls_u16 ext 11 )
    ( _blk16 ext epf )

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

    // application_layer_protocol_negotiation (0x0010), RFC 7301: the
    // protocols we speak, most preferred first — `alp_list` is the wire
    // form tls_alpn_pack makes of "h2 http/1.1", the same list the
    // server's listener takes. Only emitted when at least one protocol
    // was requested; otherwise the extension is omitted and the connect
    // behaves exactly as before.
    ? > ( vec_len [u] alp_list ) 0 {
        : ( Vec u ) alp ( vec_new [u] )
        ( _tls_u16 alp ( vec_len [u] alp_list ) )  // ProtocolNameList length
        ( _tls_cat alp alp_list )
        ( _tls_u16 ext 16 )
        ( _blk16 ext alp )
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
    // Whatever the driver asked for (QUIC: quic_transport_parameters),
    // already wire-framed.
    ( _tls_cat ext ext_extra )
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
    } {}

    ( _blk16 body ext )

    // wrap as handshake message: type=1 (client_hello) + 3-byte length
    : ( Vec u ) hs ( vec_with_cap [u] + ( vec_len [u] body ) 4 )
    ( vec_push [u] hs # u 1 )
    ( _u24 hs ( vec_len [u] body ) )
    ( _tls_cat hs body )
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
            = found key
            = got 1
        } {}
        = p + + p 4 elen
    }
    ? == got 0 { ^ @ !( Vec u ) TlsErr { F # TlsErr TlsHandshake } } {}
    ^ @ !( Vec u ) TlsErr { T found }
}

// The ALPN protocol a TLS 1.2 ServerHello selects (the 1.3 ServerHello
// carries none: there it travels in EncryptedExtensions, __ee_alpn), or
// an empty Vec. Same walk as __parse_server_hello, stopping at extension
// 0x0010; the data is [list_len:2][name_len:1][name…].
@ __sh_alpn ( Vec u ) msg → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    : i n ( vec_len [u] msg )
    ? < n 42 { ^ out } {}
    : ~ i p 38  // past type, len, version, random
    : i sidlen ( _t_bget msg p )
    = p + + p 1 sidlen
    = p + p 3  // cipher, compression
    ? > + p 2 n { ^ out } {}
    : i extlen ( _rdint msg p 2 )
    = p + p 2
    : i extend ? > + p extlen n n + p extlen
    ~ < p extend {
        ? > + p 4 extend { ^ out } {}
        : i etype ( _rdint msg p 2 )
        : i elen ( _rdint msg + p 2 2 )
        : i edata + p 4
        ? == etype 16 {
            ? & >= elen 3 <= + edata elen extend {
                : i nl ( _t_bget msg + edata 2 )
                : ~ i j 0
                ~ & < j nl < + + edata 3 j extend {
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
@ _set_keys inout TlsConnImpl c i dir ( Vec u ) secret → v {
    : ( Vec u ) retained ( bytes_slice secret 0 ( vec_len [u] secret ) )
    : ( Vec u ) emptyc ( vec_new [u] )
    : i klen ? == . c cipher 1 16 32
    : ( Vec u ) key ( hkdf_expand_label secret `key` emptyc klen )
    : ( Vec u ) iv ( hkdf_expand_label secret `iv` emptyc 12 )
    ? == dir 0 {
        = . c s_secret retained
        = . c s_key key
        = . c s_iv iv
        = . c s_seq 0
    } {
        = . c c_secret retained
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
@ tls_session_export TlsConn c__h → ( Vec u ) {
    : *TlsConnImpl c ( __TlsConn_ptr c__h )
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

// The runtime socket handle under the connection — for timeouts and
// readiness polling (nurl_tcp_set_timeout, nurl_tcp_err_kind, …).
@ tls_socket TlsConn c__h → i { ^ . ( __TlsConn_ptr c__h ) fd }

// T when the handshake used a ticket (no certificate was sent; the PSK
// authenticates the server as the one that issued it).
@ tls_is_resumed TlsConn c__h → b {
    : *TlsConnImpl c ( __TlsConn_ptr c__h )
    ^ == . c resumed 1
}

// RFC 8446 §§4.6.3, 7.2: rotate the indicated sender's keys and
// reset that direction's record sequence without retaining old generations.
@ _tls_rotate_keys inout TlsConnImpl c i dir → v {
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) next ( hkdf_expand_label ? == dir 0 . c s_secret . c c_secret `traffic upd` empty 32 )
    ( _set_keys c dir next )
}

// Encoding joins the same FIFO as already prepared ciphertext. The KU
// itself uses the old write keys; all subsequent records use the new ones.
@ _tls_control_to inout TlsConnImpl c ( Vec u ) out i dir → v {
    ? != . c fatal_alert 0 {
        : ( Vec u ) alert ( vec_new [u] )
        ( vec_push [u] alert # u 2 ) ( vec_push [u] alert # u . c fatal_alert )
        ( _tls_seal_direction_to c out dir 21 alert )
        = . c fatal_alert 0 = . c update_pending 0 = . c closed 1
        ^
    } {}
    ? | != . c version 13 == . c update_pending 0 { ^ } {}
    : ( Vec u ) update ( vec_new [u] )
    ( vec_push [u] update # u 24 ) ( _u24 update 1 )
    ( vec_push [u] update # u 0 )
    ( _tls_seal_direction_to c out dir 22 update )
    ( _tls_rotate_keys c dir )
    = . c update_pending 0
}

@ _tls_flush_control inout TlsConnImpl c i dir → !v TlsErr {
    ? & == . c update_pending 0 == . c fatal_alert 0 { ^ @ !v TlsErr { T 0 } } {}
    : ( Vec u ) wire ( vec_new [u] )
    ( _tls_control_to c wire dir )
    : b sent ( _tls_sock_write . c fd wire )
    ? ! sent { = . c closed 1 ^ @ !v TlsErr { F TlsWrite } } {}
    ^ @ !v TlsErr { T 0 }
}

// Blocking readers send the fatal alert before returning the error.
// Try-read leaves it for the existing ordered writer; once encoded, reads
// report closed. Neither path emits further application data after failure.
@ _tls_post_fail inout TlsConnImpl c i peer i alert → !v TlsErr {
    = . c fatal_alert alert
    ? == . c read_nowait 0 {
        : !v TlsErr sent ( _tls_flush_control c - 1 peer )
        ?? sent { T _ → {} F _ → {} }
    } {}
    ^ @ !v TlsErr { F TlsProtocol }
}

// Post-handshake fragments are bounded and cannot cross content-type or
// key-generation boundaries. dir identifies the peer (0 server,1 client).
@ _tls_post_hs inout TlsConnImpl c ( Vec u ) inner i dir → !v TlsErr {
    ? | == ( vec_len [u] inner ) 0 > + ( vec_len [u] . c hsbuf ) ( vec_len [u] inner ) 262144 {
        ^ ( _tls_post_fail c dir 50 )
    } {}
    ( _tls_cat . c hsbuf inner )
    ~ >= ( vec_len [u] . c hsbuf ) 4 {
        : i have ( vec_len [u] . c hsbuf )
        : i kind ( _t_bget . c hsbuf 0 )
        : i mlen ( _rdint . c hsbuf 1 3 )
        ? | > mlen 262140 & != kind 24 | != dir 0 != kind 4 {
            ^ ( _tls_post_fail c dir 10 )
        } {}
        ? & == kind 24 != mlen 1 { ^ ( _tls_post_fail c dir 50 ) } {}
        ? < have + 4 mlen { ^ @ !v TlsErr { T 0 } } {}
        ? == kind 24 {
            // KU must end its record, so no bytes may follow it under old keys.
            : i request ( _t_bget . c hsbuf 4 )
            ? != have 5 { ^ ( _tls_post_fail c dir 10 ) } {}
            ? > request 1 { ^ ( _tls_post_fail c dir 47 ) } {}
            ( vec_clear [u] . c hsbuf )
            ( _tls_rotate_keys c dir )
            ? == request 1 { = . c update_pending 1 } {}
        } {
            : ( Vec u ) msg ( bytes_slice . c hsbuf 0 + 4 mlen )
            : ( Vec u ) rest ( bytes_slice . c hsbuf + 4 mlen have )
            = . c hsbuf rest
            ( __client_take_ticket c msg )
        }
    }
    ^ @ !v TlsErr { T 0 }
}

// NewSessionTicket body: u32 lifetime, u32 age_add, nonce<u8>, ticket<u16>,
// extensions<u16>. PSK = HKDF-Expand-Label(res_master, "resumption", nonce, 32).
@ __client_take_ticket inout TlsConnImpl c ( Vec u ) msg → v {
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
    ^ mac
}

// Establish a TLS 1.3 connection WITHOUT verifying the server
// certificate — encrypted but not authenticated (MITM-able). Use only
// for pinned/self-signed/testing cases. `tls_connect` (below) is the
// secure, verifying entry point. The presented chain, CertificateVerify
// signature and transcript hash are captured on the conn for the
// verifier.
@ tls_connect_insecure s host i port s server_name → !TlsConn TlsErr {
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
// Pack a space-separated protocol list ("h2 http/1.1") into ALPN wire
// form: [len:1][name] per entry, in the given order — the ProtocolNameList
// body of RFC 7301 §3.1, used by both the client's offer and the server's
// listener preference. Names longer than 255 bytes cannot be encoded and
// are dropped; empty tokens are skipped.
@ tls_alpn_pack s list → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    : i n ( nurl_str_len list )
    : ~ i p 0
    ~ < p n {
        ~ & < p n == ( nurl_str_at list n p ) 32 { = p + p 1 }
        : i start p
        ~ & < p n != ( nurl_str_at list n p ) 32 { = p + p 1 }
        : i tl - p start
        ? & > tl 0 <= tl 255 {
            ( vec_push [u] out # u tl )
            : ~ i k start
            ~ < k p { ( vec_push [u] out # u ( nurl_str_at list n k ) ) = k + k 1 }
        } {}
    }
    ^ out
}

// T iff `sel` (a bare protocol name) is one of the entries of the
// space-separated offer `list`.
@ _alpn_offered s list ( Vec u ) sel → b {
    : ( Vec u ) packed ( tls_alpn_pack list )
    : b r ( _alpn_offered_packed packed sel )
    ^ r
}

// The same over an offer already in wire form.
@ _alpn_offered_packed ( Vec u ) packed ( Vec u ) sel → b {
    : i n ( vec_len [u] packed )
    : i sl ( vec_len [u] sel )
    : ~ i p 0
    : ~ b found F
    ~ & ! found < p n {
        : i tl ( _t_bget packed p )
        ? == tl sl {
            : ~ i k 0
            : ~ b same T
            ~ & same < k tl {
                ? != ( _t_bget packed + + p 1 k ) ( _t_bget sel k ) { = same F } {}
                = k + k 1
            }
            = found same
        } {}
        = p + + p 1 tl
    }
    ^ found
}

// Send a fatal alert (RFC 8446 §6) under the current write keys — during
// the server flight those are the handshake keys, so the peer can read
// it. Best effort: the connection is being torn down either way.
@ __send_alert inout TlsConnImpl c i desc → v {
    : ( Vec u ) alert ( vec_with_cap [u] 2 )
    ( vec_push [u] alert # u 2 )
    ( vec_push [u] alert # u desc )
    : !v TlsErr _w ( __send_encrypted c 21 alert )
}

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

// ── the client handshake machine ──────────────────────────────────
//
// `CliHs` is the TLS 1.3 client handshake with no socket in it — the
// same split `std/tls_server.nu` gives the server in `SrvHs`: whole
// handshake messages go in, the messages to send come out, and the
// traffic secrets are read straight off the machine. Two drivers:
//
//   * `__tls_handshake` below (TCP): sends `out_ch` as a plaintext
//     record, feeds the ServerHello and then the encrypted server
//     flight message by message, installs the secrets as record keys,
//     sends `out_fin` under the handshake keys.
//   * `std/quic_tls.nu` (QUIC, RFC 9001, client role): CRYPTO frame
//     bytes per encryption level, packet keys from the same secrets,
//     the quic_transport_parameters extension carried through
//     `ext_out` / `ext_want` / `ext_in`.
//
//   ( _cli_hs_new server_name alpn sess ) → CliHs    `alpn` = "h2 http/1.1" (empty: no ALPN);
//                                                    `sess` = a tls_session_export blob (empty: none) —
//                                                    a usable one becomes the pre_shared_key offer
//   ( _cli_hs_set_ext h ext_out want )    → v        append `ext_out` (wire-framed extension(s)) to the
//                                                    ClientHello; require EE extension `want` (0 = none)
//   ( _cli_hs_set_compat h on )           → v        0 = no middlebox compatibility: an empty
//                                                    legacy_session_id (QUIC, RFC 9001 §8.4); default 1
//   ( _cli_hs_start h )                   → v        key shares + ClientHello into `out_ch`
//   ( _cli_hs_server_hello h sh )         → i        0 ok · alert description otherwise. With TLS 1.2
//                                                    chosen `version` is 12, nothing is derived, `sh`
//                                                    is kept, and the caller decides what to do
//   ( _cli_hs_message h m )               → i        EncryptedExtensions / Certificate /
//                                                    CertificateVerify / Finished; 0 ok · alert
//                                                    description. After the Finished `state` is 3 and
//                                                    out_fin, c_ap / s_ap, res_master are set
//   ( _cli_hs_err h )                     → TlsErr   what a failure was, in the record layer's terms
//   ( _cli_hs_out_ch h ) … ( _cli_hs_s_ap h )         the machine's fields, read (Vecs lent)
//
// `state`: 0 new · 1 ClientHello built (awaiting ServerHello) · 2
// handshake secrets derived (awaiting the server flight) · 3 done ·
// 4 failed. A CliHs is a library handle (docs/MEMORY.md §7.6): its last
// owner releases it, so a handshake abandoned at any step leaks nothing.
// Every `( Vec u )` field is owned by the machine; a caller that wants to
// keep one copies (or, in this file, moves) it.
//
// The certificate is NOT verified here: `cert_msg`, `cv_scheme`,
// `cv_sig` and `th_cert` are captured for `tls_cert_verify`, exactly as
// the record layer has always done (`__verify_conn`). A resumed
// handshake captures nothing — the PSK authenticates the server.

// The machine's state, behind the CliHs handle below.
: CliHsImpl {
    ( Vec u ) sni  // host bytes for server_name
    ( Vec u ) alpn  // ALPN offer, wire form (tls_alpn_pack)
    ( Vec u ) ext_out  // extra ClientHello extension(s), wire-framed
    i ext_want  // EncryptedExtensions extension type required (0 = none)
    ( Vec u ) ext_in  // its body once seen
    i ext_in_present
    i compat  // 1: TLS-over-TCP middlebox compatibility (a 32-byte legacy_session_id, RFC 8446 D.4);
    // 0: QUIC, where the session id MUST be empty (RFC 9001 §8.4)
    i state
    i err  // failure kind: 1 TlsHandshake 2 TlsProtocol 3 TlsBadCipher 4 TlsHRR
    Sha256 trh  // incremental transcript hash
    i cipher  // 0 ChaCha20-Poly1305 · 1 AES-128-GCM
    i version  // 13 / 12, known from the ServerHello on
    i kx_group  // 4588 X25519MLKEM768 · 29 x25519 · 23 secp256r1
    i resumed  // 1 when the server took the offered ticket
    i offer  // 1 when a ticket was offered
    ( Vec u ) x_priv  // X25519 ephemeral
    ( Vec u ) x_pub
    ( Vec u ) p256_priv  // P-256 ephemeral scalar
    ( Vec u ) pq_dk  // ML-KEM-768 decapsulation key
    ( Vec u ) random
    ( Vec u ) sessid
    ( Vec u ) tk_ticket  // the offered ticket and its PSK
    ( Vec u ) tk_psk
    i tk_age_add
    i tk_lifetime
    i tk_received_ms
    ( Vec u ) res_early  // early_secret(PSK) while offering
    ( Vec u ) alpn_sel  // what the server selected (checked against `alpn`)
    ( Vec u ) c_hs
    ( Vec u ) s_hs
    ( Vec u ) master
    ( Vec u ) c_ap
    ( Vec u ) s_ap
    ( Vec u ) res_master
    ( Vec u ) cert_msg  // raw Certificate message, for the verifier
    ( Vec u ) cv_sig  // CertificateVerify signature
    ( Vec u ) th_cert  // transcript hash through Certificate
    i cv_scheme  // CertificateVerify SignatureScheme
    ( Vec u ) out_ch  // the ClientHello, to send in the clear
    ( Vec u ) out_fin  // the client Finished, to send under c_hs
    ( Vec u ) sh  // the ServerHello, kept only for a TLS 1.2 fallback
}

// A CliHs is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: CliHs { s ctl }

@ CliHs_share CliHs h → CliHs { ^ @ CliHs { # s ( rcbox_share # i . h ctl ) } }

@ CliHs_drop sink CliHs h → v {
    ( mem_forget h )
    ( rcbox_release [CliHsImpl] # i . h ctl )
}

@ __CliHs_ptr CliHs h → *CliHsImpl { ^ ( rcbox_ptr [CliHsImpl] # i . h ctl ) }

@ _cli_hs_new s server_name s alpn ( Vec u ) sess → CliHs {
    : i h__box ( rcbox_zero [CliHsImpl] )
    : ~ * CliHsImpl h ( rcbox_ptr [CliHsImpl] h__box )
    = . h sni ( bytes_from_str server_name )
    = . h alpn ( tls_alpn_pack alpn )
    = . h ext_out ( vec_new [u] )
    = . h ext_want 0
    = . h ext_in ( vec_new [u] )
    = . h ext_in_present 0
    = . h compat 1
    = . h state 0
    = . h err 0
    // Incremental transcript hash, snapshotted at the checkpoints —
    // the server's machine hashes the same way.
    = . h trh ( sha256_init )
    = . h cipher 0
    = . h version 13
    = . h kx_group 0
    = . h resumed 0
    = . h offer 0
    = . h x_priv ( vec_new [u] )
    = . h x_pub ( vec_new [u] )
    = . h p256_priv ( vec_new [u] )
    = . h pq_dk ( vec_new [u] )
    = . h random ( vec_new [u] )
    = . h sessid ( vec_new [u] )
    = . h tk_ticket ( vec_new [u] )
    = . h tk_psk ( vec_new [u] )
    = . h tk_age_add 0
    = . h tk_lifetime 0
    = . h tk_received_ms 0
    = . h alpn_sel ( vec_new [u] )
    = . h c_hs ( vec_new [u] )
    = . h s_hs ( vec_new [u] )
    = . h master ( vec_new [u] )
    = . h c_ap ( vec_new [u] )
    = . h s_ap ( vec_new [u] )
    = . h res_master ( vec_new [u] )
    = . h cert_msg ( vec_new [u] )
    = . h cv_sig ( vec_new [u] )
    = . h th_cert ( vec_new [u] )
    = . h cv_scheme 0
    = . h out_ch ( vec_new [u] )
    = . h out_fin ( vec_new [u] )
    = . h sh ( vec_new [u] )
    // A usable exported session becomes the pre_shared_key offer; the
    // server may still decline it (rotated ticket key, expired, or no
    // resumption at all), in which case the handshake is simply the
    // full one — nothing here is trusted until the ServerHello says
    // the ticket was taken.
    ? ( __cli_sess_load . h 0 sess ) {
        = . h offer 1
        = . h res_early ( _psk_early . h tk_psk )
    } { = . h res_early ( vec_new [u] ) }
    ^ @ CliHs { # s h__box }
}

@ _cli_hs_set_ext CliHs h__h ( Vec u ) ext_out i want → v {
    : *CliHsImpl h ( __CliHs_ptr h__h )
    ( vec_clear [u] . h ext_out )
    ( bytes_extend_bytes . h ext_out ext_out )
    = . h ext_want want
}

@ _cli_hs_set_compat CliHs h__h i on → v {
    : *CliHsImpl h ( __CliHs_ptr h__h )
    = . h compat on
}

// What the QUIC driver (std/quic_tls.nu) reads off the machine. Vecs are
// the machine's own, lent.
@ _cli_hs_state CliHs h → i { ^ . ( __CliHs_ptr h ) state }

@ _cli_hs_version CliHs h → i { ^ . ( __CliHs_ptr h ) version }

@ _cli_hs_cipher CliHs h → i { ^ . ( __CliHs_ptr h ) cipher }

@ _cli_hs_kx_group CliHs h → i { ^ . ( __CliHs_ptr h ) kx_group }

@ _cli_hs_resumed CliHs h → i { ^ . ( __CliHs_ptr h ) resumed }

@ _cli_hs_cv_scheme CliHs h → i { ^ . ( __CliHs_ptr h ) cv_scheme }

@ _cli_hs_out_ch CliHs h → ( Vec u ) { ^ . ( __CliHs_ptr h ) out_ch }

@ _cli_hs_out_fin CliHs h → ( Vec u ) { ^ . ( __CliHs_ptr h ) out_fin }

@ _cli_hs_ext_in CliHs h → ( Vec u ) { ^ . ( __CliHs_ptr h ) ext_in }

@ _cli_hs_alpn_sel CliHs h → ( Vec u ) { ^ . ( __CliHs_ptr h ) alpn_sel }

@ _cli_hs_cert_msg CliHs h → ( Vec u ) { ^ . ( __CliHs_ptr h ) cert_msg }

@ _cli_hs_cv_sig CliHs h → ( Vec u ) { ^ . ( __CliHs_ptr h ) cv_sig }

@ _cli_hs_th_cert CliHs h → ( Vec u ) { ^ . ( __CliHs_ptr h ) th_cert }

@ _cli_hs_c_hs CliHs h → ( Vec u ) { ^ . ( __CliHs_ptr h ) c_hs }

@ _cli_hs_s_hs CliHs h → ( Vec u ) { ^ . ( __CliHs_ptr h ) s_hs }

@ _cli_hs_c_ap CliHs h → ( Vec u ) { ^ . ( __CliHs_ptr h ) c_ap }

@ _cli_hs_s_ap CliHs h → ( Vec u ) { ^ . ( __CliHs_ptr h ) s_ap }

@ __cli_hs_fail inout CliHsImpl h i err i alert → i {
    = . h state 4
    = . h err err
    ^ alert
}

@ _cli_hs_err CliHs h__h → TlsErr {
    : ~ * CliHsImpl h ( __CliHs_ptr h__h )
    ^ ( __cli_hs_errk . h 0 )
}

@ __cli_hs_errk inout CliHsImpl h → TlsErr {
    ? == . h err 2 { ^ # TlsErr TlsProtocol } {}
    ? == . h err 3 { ^ # TlsErr TlsBadCipher } {}
    ? == . h err 4 { ^ # TlsErr TlsHRR } {}
    ^ # TlsErr TlsHandshake
}

// Load an exported session onto the machine as the offer for its
// handshake. F (and nothing loaded) for an empty, malformed or expired
// blob — the caller then simply does a full handshake.
@ __cli_sess_load inout CliHsImpl h ( Vec u ) sess → b {
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
    = . h tk_psk ( bytes_slice sess 19 tp )
    = . h tk_ticket ( bytes_slice sess + tp 2 n )
    = . h tk_age_add age_add
    = . h tk_lifetime lifetime
    = . h tk_received_ms received
    ^ T
}

// Fresh key shares for every group we offer and the ClientHello that
// carries them, into `out_ch`.
@ _cli_hs_start CliHs h__h → v {
    : ~ * CliHsImpl h ( __CliHs_ptr h__h )
    ( _cli_hs_start_in . h 0 )
}

@ _cli_hs_start_in inout CliHsImpl h → v {
    ? != . h state 0 { ^ } {}
    = . h x_priv ( _rand_bytes 32 )
    = . h x_pub ( x25519_base . h x_priv )
    = . h p256_priv ( _rand_bytes 32 )
    : ( Vec u ) p256pub ( p256_ecdh_keygen . h p256_priv )
    // ML-KEM-768 for the hybrid group. The decapsulation key stays on
    // the machine until the server's share arrives; the encapsulation
    // key travels in the ClientHello.
    : MlkemKeys pqkeys ( mlkem_keygen 768 )
    : ( Vec u ) pqpub ( bytes_slice ( mlkem_ek pqkeys ) 0 ( vec_len [u] ( mlkem_ek pqkeys ) ) )
    = . h pq_dk ( bytes_slice ( mlkem_dk pqkeys ) 0 ( vec_len [u] ( mlkem_dk pqkeys ) ) )
    = . h random ( _rand_bytes 32 )
    = . h sessid ( _rand_bytes ? != . h compat 0 32 0 )
    : ~ i obf_age 0
    ? == . h offer 1 {
        : i age - ( now_ms ) . h tk_received_ms
        = obf_age & + age . h tk_age_add 4294967295
    } {}
    : ( Vec u ) noid ( vec_new [u] )
    : ( Vec u ) ch ( __build_client_hello . h sni . h x_pub p256pub pqpub . h random . h sessid . h alpn . h ext_out ? == . h offer 1 . h tk_ticket noid obf_age )
    ? == . h offer 1 {
        : ( Vec u ) binder ( _psk_binder_over . h res_early ch - ( vec_len [u] ch ) 35 )
        ( __ch_patch_binder ch binder )
    } {}
    ( sha256_update . h trh ch )
    = . h out_ch ch
    = . h state 1
}

// The ServerHello: cipher and version, the server's key share, and the
// whole handshake key schedule. On success `state` is 2 and c_hs / s_hs
// are the handshake traffic secrets.
@ _cli_hs_server_hello CliHs h__h ( Vec u ) sh → i {
    : ~ * CliHsImpl h ( __CliHs_ptr h__h )
    ^ ( _cli_hs_server_hello_in . h 0 sh )
}

@ _cli_hs_server_hello_in inout CliHsImpl h ( Vec u ) sh → i {
    ? != . h state 1 { ^ ( __cli_hs_fail h 1 10 ) } {}
    // handshake type 2, and at least the fixed part of the body
    ? | < ( vec_len [u] sh ) 42 != ( _t_bget sh 0 ) 2 { ^ ( __cli_hs_fail h 1 50 ) } {}
    : i suite ( __sh_suite sh )
    = . h version ( __suite_version suite )
    = . h cipher ( __suite_cipher suite )
    ? == . h version 12 {
        // TLS 1.2: none of the 1.3 schedule applies. The hello is kept
        // for a caller that speaks 1.2 (the TCP record layer does);
        // QUIC refuses it.
        = . h sh ( bytes_slice sh 0 ( vec_len [u] sh ) )
        ^ 0
    } {}
    : ~ ( Vec u ) spub ( vec_new [u] )
    : ~ i bad 0
    : !( Vec u ) TlsErr spkr ( __parse_server_hello sh )
    ?? spkr {
        T k → { = spub k }
        F e → { = bad ?? e { TlsHRR → 4 TlsBadCipher → 3 _ → 1 } }
    }
    // A HelloRetryRequest is not taken up (every share is in the first
    // hello, so a server has no reason to send one): handshake_failure.
    // A suite or key_share we cannot use is illegal_parameter.
    ? != bad 0 { ^ ( __cli_hs_fail h bad ? == bad 4 40 47 ) } {}
    ( sha256_update . h trh sh )

    // The negotiated group is told by the server key-exchange length:
    // X25519 is 32 bytes, an uncompressed secp256r1 point is 65, and
    // the X25519MLKEM768 share is 1088 + 32 = 1120.
    //
    // For the hybrid group the shared secret handed to the key schedule
    // is `ML-KEM shared secret ‖ X25519 shared secret` — 64 bytes,
    // ML-KEM first, matching the order of the shares. Concatenation is
    // what makes it a hybrid worth having: HKDF-Extract over the pair
    // is at least as strong as either half, so the handshake survives
    // ML-KEM being broken *and* survives X25519 being broken.
    : i sl ( vec_len [u] spub )
    ? & & != sl 1120 != sl 65 != sl 32 { ^ ( __cli_hs_fail h 2 47 ) } {}
    = . h kx_group ? == sl 1120 4588 ? == sl 65 23 29
    : ( Vec u ) ecdhe ? == sl 1120
    ( __hybrid_shared . h pq_dk . h x_priv spub )
    ? == sl 65 ( p256_ecdh_shared . h p256_priv spub ) ( x25519 . h x_priv spub )
    // RFC 8446 §7.4.2 — abort if the ECDHE output is all-zero (peer sent
    // a low-order / small-subgroup point forcing a known shared secret).
    ? ( _all_zero ecdhe ) { ^ ( __cli_hs_fail h 2 47 ) } {}

    : ( Vec u ) z32 ( vec_with_cap [u] 32 )
    : ~ i zk 0
    ~ < zk 32 { ( vec_push [u] z32 # u 0 ) = zk + zk 1 }
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) ehash ( sha256_pure empty )
    // The server took our ticket iff its ServerHello carries
    // pre_shared_key; then the early secret is the PSK's and no
    // Certificate / CertificateVerify will follow — the PSK is the proof
    // of identity (only the issuer of the ticket knows it).
    ? & == . h offer 1 ( __sh_has_psk sh ) { = . h resumed 1 } {}
    : ( Vec u ) early ? == . h resumed 1 ( bytes_slice . h res_early 0 32 ) ( hkdf_extract empty z32 )
    : ( Vec u ) derived1 ( derive_secret early `derived` ehash )
    : ( Vec u ) hs_secret ( hkdf_extract derived1 ecdhe )
    : ( Vec u ) th_sh ( sha256_snapshot . h trh )
    = . h c_hs ( derive_secret hs_secret `c hs traffic` th_sh )
    = . h s_hs ( derive_secret hs_secret `s hs traffic` th_sh )
    : ( Vec u ) derived2 ( derive_secret hs_secret `derived` ehash )
    = . h master ( hkdf_extract derived2 z32 )
    = . h state 2
    ^ 0
}

// Offset of the data of extension `want` within msg[es..ee), or -1.
@ __cli_find_ext ( Vec u ) msg i es i ee i want → i {
    : ~ i p es
    : ~ i found -1
    ~ & < + p 4 + ee 1 == found -1 {
        : i et ( _rdint msg p 2 )
        : i el ( _rdint msg + p 2 2 )
        ? == et want { = found + p 4 } { = p + + p 4 el }
    }
    ^ found
}

// One message of the server's flight, under the handshake keys.
@ _cli_hs_message CliHs h__h ( Vec u ) m → i {
    : ~ * CliHsImpl h ( __CliHs_ptr h__h )
    ^ ( _cli_hs_message_in . h 0 m )
}

@ _cli_hs_message_in inout CliHsImpl h ( Vec u ) m → i {
    ? != . h state 2 { ^ ( __cli_hs_fail h 1 10 ) } {}
    ? < ( vec_len [u] m ) 4 { ^ ( __cli_hs_fail h 1 50 ) } {}
    : i t ( _t_bget m 0 )
    // Nothing but the flight belongs here: a hello, EndOfEarlyData, a
    // ticket or a KeyUpdate before the Finished is unexpected_message.
    ? | | | | == t 1 == t 2 == t 4 == t 5 == t 24 { ^ ( __cli_hs_fail h 1 10 ) } {}

    ? == t 20 {
        // Finished: the MAC is over the transcript BEFORE this message.
        : ( Vec u ) th_cv ( sha256_snapshot . h trh )
        : ( Vec u ) expect ( _finished_mac . h s_hs th_cv )
        : b okfin ( _cmp_finished m expect )
        ? okfin {} { ^ ( __cli_hs_fail h 1 51 ) }
        ( sha256_update . h trh m )
        // application traffic secrets: transcript through the server
        // Finished — also what our own Finished is computed over
        : ( Vec u ) th_sf ( sha256_snapshot . h trh )
        = . h c_ap ( derive_secret . h master `c ap traffic` th_sf )
        = . h s_ap ( derive_secret . h master `s ap traffic` th_sf )
        : ( Vec u ) cfin ( _finished_mac . h c_hs th_sf )
        : ( Vec u ) finmsg ( vec_with_cap [u] 36 )
        ( vec_push [u] finmsg # u 20 )
        ( _u24 finmsg 32 )
        ( _tls_cat finmsg cfin )
        // resumption_master_secret: transcript through our own Finished.
        // Every NewSessionTicket the server sends from here on derives
        // its PSK from this (see __client_take_ticket).
        ( sha256_update . h trh finmsg )
        : ( Vec u ) th_cf ( sha256_final . h trh )
        = . h res_master ( derive_secret . h master `res master` th_cf )
        = . h out_fin finmsg
        = . h state 3
        ^ 0
    } {}

    ? == t 8 {
        // EncryptedExtensions — the negotiated ALPN. The server must
        // pick from OUR list (RFC 7301 §3.2); anything else is a
        // protocol violation answered with no_application_protocol.
        : ( Vec u ) sel ( __ee_alpn m )
        ? > ( vec_len [u] sel ) 0 {
            ? ( _alpn_offered_packed . h alpn sel ) {
                = . h alpn_sel sel
            } {
                ^ ( __cli_hs_fail h 1 120 )
            }
        } {}
        // The extension a driver requires (QUIC: transport parameters).
        ? != . h ext_want 0 {
            : i n ( vec_len [u] m )
            : i extlen ( _rdint m 4 2 )
            : i ee ? > + 6 extlen n n + 6 extlen
            : i xo ( __cli_find_ext m 6 ee . h ext_want )
            ? < xo 0 { ^ ( __cli_hs_fail h 1 109 ) } {}
            : i xl ( _rdint m - xo 2 2 )
            ? > + xo xl ee { ^ ( __cli_hs_fail h 1 50 ) } {}
            = . h ext_in_present 1
            ( vec_clear [u] . h ext_in )
            : ( Vec u ) xb ( bytes_slice m xo + xo xl )
            ( bytes_extend_bytes . h ext_in xb )
        } {}
    } {}
    ? == t 11 {
        = . h cert_msg ( bytes_slice m 0 ( vec_len [u] m ) )
    } {}
    ? == t 15 {
        // CertificateVerify: the transcript through Certificate (before
        // this message), the scheme and the signature — for the verifier.
        ? < ( vec_len [u] m ) 8 { ^ ( __cli_hs_fail h 1 50 ) } {}
        = . h th_cert ( sha256_snapshot . h trh )
        = . h cv_scheme ( _rdint m 4 2 )
        : i siglen ( _rdint m 6 2 )
        ? > + 8 siglen ( vec_len [u] m ) { ^ ( __cli_hs_fail h 1 50 ) } {}
        = . h cv_sig ( bytes_slice m 8 + 8 siglen )
    } {}
    ( sha256_update . h trh m )
    ^ 0
}

// Send an alert record (RFC 8446 §6) the way the peer can read it right
// now: under the current write keys once there are any, in the clear
// before that. Best effort — the connection is being torn down.
@ __cli_say_alert inout TlsConnImpl c i desc → v {
    ? > ( vec_len [u] . c c_key ) 0 { ( __send_alert c desc ) ^ } {}
    : ( Vec u ) alert ( vec_with_cap [u] 2 )
    ( vec_push [u] alert # u 2 )
    ( vec_push [u] alert # u desc )
    : !v TlsErr _w ( _send_plain c 21 alert )
}

// The handshake machine is the caller's binding: it goes with that scope.
@ __cli_abort inout TlsConnImpl c TlsErr e → !v TlsErr {
    ( _tls_close_in c )
    ^ @ !v TlsErr { F e }
}

// Core client handshake over a socket: the record layer around `CliHs`.
// `alpn` is the space-separated list of ALPN protocols to offer, most
// preferred first (e.g. "h2 http/1.1"); empty means no ALPN extension
// is sent. The negotiated protocol (from the server's
// EncryptedExtensions, checked to be one we offered) is stored in
// `c.alpn_sel`.
@ __tls_handshake i raw s server_name s alpn ( Vec u ) sess → !TlsConn TlsErr {
    // The connection owns the socket from here, on every path: a connect
    // that failed is closed with it (it used to be left open).
    : TlsConn c__h ( _tls_conn_new raw )
    ? != ( nurl_tcp_err_kind raw ) 0 { ^ @ !TlsConn TlsErr { F # TlsErr TlsConnect } } {}
    // Read timeout so an unresponsive/dead peer fails the handshake
    // cleanly instead of blocking the client forever.
    ( nurl_tcp_set_timeout raw 20000 )
    : ~ * TlsConnImpl c ( __TlsConn_ptr c__h )
    // The handshake machine goes with this scope, on every path out of it.
    : CliHs hs__h ( _cli_hs_new server_name alpn sess )
    : ~ * CliHsImpl hs ( __CliHs_ptr hs__h )
    : !v TlsErr r ( __cli_connect . c 0 . hs 0 )
    ^ ?? r { T _ → @ !TlsConn TlsErr { T c__h } F e → @ !TlsConn TlsErr { F e } }
}

// The record layer around the machine: ClientHello out, the server's
// flight in, Finished out, keys installed on `c`.
@ __cli_connect inout TlsConnImpl c inout CliHsImpl hs → !v TlsErr {
    // ── ClientHello ──
    ( _cli_hs_start_in hs )
    // The offered ticket stays on the connection: a resumed handshake
    // brings no certificate and need not bring a new ticket, and
    // tls_session_export still has to hand this one on.
    ? == . hs offer 1 {
        = . c tk_ticket ( bytes_slice . hs tk_ticket 0 ( vec_len [u] . hs tk_ticket ) )
        = . c tk_psk ( bytes_slice . hs tk_psk 0 ( vec_len [u] . hs tk_psk ) )
        = . c tk_age_add . hs tk_age_add
        = . c tk_lifetime . hs tk_lifetime
        = . c tk_received_ms . hs tk_received_ms
    } {}
    : !v TlsErr sw ( _send_plain c 22 . hs out_ch )
    ?? sw { T _ → {} F e → { ^ ( __cli_abort c e ) } }

    // ── ServerHello ──
    : !( Vec u ) TlsErr shr ( __next_hs c )
    : ( Vec u ) sh ?? shr { T m → m F e → { ^ ( __cli_abort c e ) } }
    : i shrc ( _cli_hs_server_hello_in hs sh )
    ? != shrc 0 {
        ( __cli_say_alert c shrc )
        ^ ( __cli_abort c ( __cli_hs_errk hs ) )
    } {}
    = . c version . hs version
    = . c cipher . hs cipher

    // ── TLS 1.2 fallback ──
    // The 1.2 path owns what it is handed, so it gets copies of the
    // machine's ephemerals and the hellos, and the machine goes.
    ? == . c version 12 {
        : ( Vec u ) priv ( bytes_slice . hs x_priv 0 ( vec_len [u] . hs x_priv ) )
        : ( Vec u ) cpub ( bytes_slice . hs x_pub 0 ( vec_len [u] . hs x_pub ) )
        : ( Vec u ) random ( bytes_slice . hs random 0 ( vec_len [u] . hs random ) )
        : ( Vec u ) sessid ( bytes_slice . hs sessid 0 ( vec_len [u] . hs sessid ) )
        : ( Vec u ) ch ( bytes_slice . hs out_ch 0 ( vec_len [u] . hs out_ch ) )
        : ( Vec u ) tr ( bytes_slice . hs out_ch 0 ( vec_len [u] . hs out_ch ) )
        ( _tls_cat tr sh )
        = . c kx_p256 ( bytes_slice . hs p256_priv 0 ( vec_len [u] . hs p256_priv ) )
        // ALPN under 1.2 is answered in the ServerHello itself. Without
        // this a load balancer that picked h2 there was spoken to in
        // HTTP/1.1 — and every request to it failed.
        : ( Vec u ) sel12 ( __sh_alpn sh )
        ? & > ( vec_len [u] sel12 ) 0 ( _alpn_offered_packed . hs alpn sel12 ) {
            = . c alpn_sel sel12
        } {}
        ^ ( __tls12_handshake c sh priv cpub random sessid ch tr )
    } {}
    = . c kx_group . hs kx_group
    = . c resumed . hs resumed

    // handshake keys: the client writes under c_hs, reads the server
    // under s_hs
    ( _set_keys c 0 . hs s_hs )
    ( _set_keys c 1 . hs c_hs )
    = . c enc_read 1

    // ── server flight: EE, Certificate, CertVerify, Finished ──
    : ~ i rc 0
    ~ & == rc 0 != . hs state 3 {
        : !( Vec u ) TlsErr mr ( __next_hs c )
        ?? mr {
            F e → { ^ ( __cli_abort c e ) }
            T msg → {
                = rc ( _cli_hs_message_in hs msg )
            }
        }
    }
    ? != rc 0 {
        ( __cli_say_alert c rc )
        ^ ( __cli_abort c ( __cli_hs_errk hs ) )
    } {}
    // what the verifier and the callers read off the connection
    = . c cert_msg . hs cert_msg
    = . hs cert_msg ( vec_new [u] )
    = . c cv_sig . hs cv_sig
    = . hs cv_sig ( vec_new [u] )
    = . c th_cert . hs th_cert
    = . hs th_cert ( vec_new [u] )
    = . c cv_scheme . hs cv_scheme
    = . c alpn_sel . hs alpn_sel
    = . hs alpn_sel ( vec_new [u] )

    // ── client Finished (under handshake keys) ──
    // change_cipher_spec for middlebox compatibility
    : ( Vec u ) ccs ( vec_with_cap [u] 1 )
    ( vec_push [u] ccs # u 1 )
    : !v TlsErr cw ( _send_plain c 20 ccs )
    ?? cw { T _ → {} F _ → {} }
    : !v TlsErr fw ( __send_encrypted c 22 . hs out_fin )
    ?? fw { T _ → {} F _ → {} }

    // switch to application traffic keys
    ( _set_keys c 0 . hs s_ap )
    ( _set_keys c 1 . hs c_ap )
    = . c established 1
    = . c res_master . hs res_master
    = . hs res_master ( vec_new [u] )
    ^ @ !v TlsErr { T 0 }
}

// Upgrade an already-connected fd to TLS (no ALPN). Insecure: does not
// verify the certificate (see tls_attach_verify).
@ tls_attach i raw s server_name → !TlsConn TlsErr {
    : ( Vec u ) nosess ( vec_new [u] )
    : !TlsConn TlsErr r ( __tls_handshake raw server_name `` nosess )
    ^ r
}

// Like tls_attach but offers ALPN protocols ("h2" or a preference list
// "h2 http/1.1"). After a successful handshake the negotiated protocol is
// readable via tls_alpn_selected (empty if the server declined ALPN).
// Insecure variant.
@ tls_attach_alpn i raw s server_name s alpn → !TlsConn TlsErr {
    : ( Vec u ) nosess ( vec_new [u] )
    : !TlsConn TlsErr r ( __tls_handshake raw server_name alpn nosess )
    ^ r
}

// tls_attach with a resumption offer: `sess` is what tls_session_export
// returned from an earlier connection to the same server. If the server
// takes it the handshake is the abbreviated PSK one (no certificate, one
// round trip, no signature to verify) and tls_is_resumed answers T;
// otherwise this is exactly tls_attach. Insecure variant — see
// tls_connect_resume for the verifying one.
@ tls_attach_resume i raw s server_name ( Vec u ) sess → !TlsConn TlsErr {
    ^ ( __tls_handshake raw server_name `` sess )
}

// Unverified connect with a resumption offer (the tls_connect_insecure
// of resumption — pinned / self-signed / test servers).
@ tls_connect_insecure_resume s host i port s server_name ( Vec u ) sess → !TlsConn TlsErr {
    : i raw ( nurl_tcp_connect host port )
    ^ ( tls_attach_resume raw server_name sess )
}

// Verifying connect with a resumption offer. A resumed connection is
// authenticated by the PSK (the ticket's issuer is the server verified
// when the session was made); a declined offer falls back to the full
// handshake and the usual chain / hostname verification.
@ tls_connect_resume s host i port s server_name ( Vec u ) sess → !TlsConn TlsErr {
    : i raw ( nurl_tcp_connect host port )
    : !TlsConn TlsErr r ( tls_attach_resume raw server_name sess )
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
@ tls_group TlsConn c__h → i {
    : *TlsConnImpl c ( __TlsConn_ptr c__h )
    ^ . c kx_group
}

// The SignatureScheme of this connection's CertificateVerify: on a client,
// what the server signed with; on a server, what it chose to sign with
// (ecdsa_secp256r1_sha256 0x0403, rsa_pss_rsae_sha256 0x0804, mldsa44/65/87
// 0x0904–0x0906). 0 on a resumed handshake, which carries no certificate.
@ tls_cv_scheme TlsConn c__h → i {
    : *TlsConnImpl c ( __TlsConn_ptr c__h )
    ^ . c cv_scheme
}

// What a client captured for the verifier (lent; empty on a resumed
// handshake): the raw Certificate message, the CertificateVerify
// signature, and the transcript hash through the Certificate —
// `tls_cv_verify ( tls_cert_msg c ) ( tls_cv_scheme c ) ( tls_cv_sig c )
// ( tls_th_cert c )` re-checks the server's proof of key possession.
@ tls_cert_msg TlsConn c__h → ( Vec u ) { ^ . ( __TlsConn_ptr c__h ) cert_msg }

@ tls_cv_sig TlsConn c__h → ( Vec u ) { ^ . ( __TlsConn_ptr c__h ) cv_sig }

@ tls_th_cert TlsConn c__h → ( Vec u ) { ^ . ( __TlsConn_ptr c__h ) th_cert }

// T when the negotiated group carries a post-quantum component, so the
// session's forward secrecy survives a future quantum adversary
// recording it today.
@ tls_is_post_quantum TlsConn c__h → b {
    : *TlsConnImpl c ( __TlsConn_ptr c__h )
    ^ == . c kx_group 4588
}

// True iff the negotiated ALPN protocol is exactly `proto` — the
// allocation-free form of tls_alpn_selected for the per-connection
// dispatch question ("is this h2?").
@ tls_alpn_is TlsConn c__h s proto → b {
    : *TlsConnImpl c ( __TlsConn_ptr c__h )
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

@ tls_alpn_selected TlsConn c__h → String {
    : *TlsConnImpl c ( __TlsConn_ptr c__h )
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
@ __verify12 inout TlsConnImpl c s hostname → i {
    : X509 leaf ( tls_leaf_cert . c cert_msg 1 )
    ? ! . leaf ok { ^ 2 } {}
    : i sk ( tls12_ske_verify leaf . c cv_scheme . c cv_sig . c th_cert )
    ? != sk 0 { ^ sk } {}
    ^ ( tls_chain_verify . c cert_msg 1 hostname )
}

@ tls_connect s host i port s server_name → !TlsConn TlsErr {
    : !TlsConn TlsErr r ( tls_connect_insecure host port server_name )
    ^ ( __verify_conn r server_name )
}

// Verifying counterpart of `tls_attach`: upgrade an already-connected
// socket to TLS and verify the chain / hostname against the system trust
// store (the secure default for STARTTLS-style upgrades).
@ tls_attach_verify i raw s server_name → !TlsConn TlsErr {
    : !TlsConn TlsErr r ( tls_attach raw server_name )
    ^ ( __verify_conn r server_name )
}

// Verifying counterpart of tls_attach_alpn: offer an ALPN protocol AND
// verify the chain / hostname. The negotiated protocol is then readable
// with tls_alpn_selected.
@ tls_attach_alpn_verify i raw s server_name s alpn → !TlsConn TlsErr {
    : !TlsConn TlsErr r ( tls_attach_alpn raw server_name alpn )
    ^ ( __verify_conn r server_name )
}

// Every client knob in one call: upgrade an already-connected socket to
// TLS offering the ALPN list `alpn` ("" = none) AND the resumption
// session `sess` (empty = none), verifying the chain / hostname when
// `verify` is non-zero. The one-knob variants above are this with a
// blank somewhere; an HTTP client that wants to resume a session on the
// same connection it negotiates HTTP/2 over needs all of them at once.
@ tls_attach_full i raw s server_name s alpn ( Vec u ) sess i verify → !TlsConn TlsErr {
    : !TlsConn TlsErr r ( __tls_handshake raw server_name alpn sess )
    ? != verify 0 { ^ ( __verify_conn r server_name ) } {}
    ^ r
}

// tls_attach_full over a fresh TCP connection to host:port.
@ tls_connect_full s host i port s server_name s alpn ( Vec u ) sess i verify → !TlsConn TlsErr {
    : i raw ( nurl_tcp_connect host port )
    ^ ( tls_attach_full raw server_name alpn sess verify )
}

// Shared post-handshake verification used by both tls_connect and
// tls_attach_verify: check the certificate (TLS 1.3 CertificateVerify or
// TLS 1.2 ServerKeyExchange sig + chain + hostname) and close on failure.
@ __verify_conn sink ! TlsConn TlsErr r s server_name → !TlsConn TlsErr {
    ?? r {
        F e → { ^ @ !TlsConn TlsErr { F e } }
        T h → {
            : ~ * TlsConnImpl c ( __TlsConn_ptr h )
            // A resumed connection carries no certificate: the PSK it was
            // established from authenticates the server as the issuer of
            // the ticket, which was verified when that session was made.
            : i rc ? == . c resumed 1 0 ? == . c version 12 ( __verify12 . c 0 server_name ) ( tls_cert_verify . c cert_msg . c cv_scheme . c cv_sig . c th_cert server_name )
            ? == rc 0 {
                ^ @ !TlsConn TlsErr { T h }
            } {
                ( _tls_close_in . c 0 )
                ^ @ !TlsConn TlsErr { F # TlsErr TlsBadCert }
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
@ __fail inout TlsConnImpl c TlsErr e → !v TlsErr {
    ( _tls_close_in c )
    ^ @ !v TlsErr { F e }
}

// ── application data ──────────────────────────────────────────────
//
// A TLS record carries at most 2^14 bytes of plaintext (RFC 8446 §5.1,
// same limit in 1.2): peers MUST reject anything larger, and past 65535
// the record header's u16 length field wraps outright. Split
// application data into ≤16384-byte records.
@ tls_write TlsConn c__h ( Vec u ) data → !v TlsErr {
    : ~ * TlsConnImpl c ( __TlsConn_ptr c__h )
    ^ ( _tls_write_in . c 0 data )
}

@ _tls_write_in inout TlsConnImpl c ( Vec u ) data → !v TlsErr {
    ?? ( _tls_flush_control c 1 ) { T _ → {} F error → { ^ @ !v TlsErr { F error } } }
    ? != . c closed 0 { ^ @ !v TlsErr { F TlsClosed } } {}
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

// Encode application records once for a nonblocking FIFO writer. The
// returned bytes own their storage; advancing the sequence belongs here,
// never in a retry of a partial socket write. No socket I/O occurs.
@ tls_prepare_write TlsConn c__h ( Vec u ) data → !( Vec u ) TlsErr {
    : ~ * TlsConnImpl c ( __TlsConn_ptr c__h )
    ^ ( _tls_prepare_write_in . c 0 data )
}

@ _tls_prepare_write_in inout TlsConnImpl c ( Vec u ) data → !( Vec u ) TlsErr {
    ? | != . c closed 0 != . c established 1 {
        ^ @ !( Vec u ) TlsErr { F TlsClosed }
    } {}
    ? & != . c fatal_alert 0 > ( vec_len [u] data ) 0 { ^ @ !( Vec u ) TlsErr { F TlsProtocol } } {}
    : ( Vec u ) wire ( vec_new [u] )
    ( _tls_control_to c wire 1 )
    : ~ i offset 0
    : i size ( vec_len [u] data )
    ~ < offset size {
        : i end ? < - size offset 16384 size + offset 16384
        : ( Vec u ) part ( bytes_slice data offset end )
        ? == . c version 12 {
            ( _tls_record12_to c wire 23 part )
        } { ( _tls_seal_inner_to c wire 23 part ) }
        = offset end
    }
    ^ @ !( Vec u ) TlsErr { T wire }
}

// Pair variant of tls_prepare_write: records cut from `head`‖`body` are
// sealed straight into `out`, the caller's ciphertext FIFO. No socket I/O.
@ tls_prepare_write2_to TlsConn c__h ( Vec u ) out ( Vec u ) head ( Vec u ) body → !v TlsErr {
    : ~ * TlsConnImpl c ( __TlsConn_ptr c__h )
    ^ ( _tls_prepare_write2_to_in . c 0 out head body )
}

@ _tls_prepare_write2_to_in inout TlsConnImpl c ( Vec u ) out ( Vec u ) head ( Vec u ) body → !v TlsErr {
    ? | != . c closed 0 != . c established 1 { ^ @ !v TlsErr { F TlsClosed } } {}
    : i n + ( vec_len [u] head ) ( vec_len [u] body )
    ? & != . c fatal_alert 0 > n 0 { ^ @ !v TlsErr { F TlsProtocol } } {}
    ( _tls_control_to c out 1 )
    : ~ i off 0
    ~ < off n {
        : ~ i hi + off 16384
        ? > hi n { = hi n } {}
        : ( Vec u ) part ( _tls_pair_slice head body off hi )
        ? == . c version 12 {
            ( _tls_record12_to c out 23 part )
        } { ( _tls_seal_inner_to c out 23 part ) }
        = off hi
    }
    ^ @ !v TlsErr { T 0 }
}

// Two-buffer variant of tls_write (client side of tcp_write_all2):
// records are cut from `head`‖`body` without joining the two first.
// TLS 1.3 assembles each record's plaintext straight from the pair;
// TLS 1.2 hands the AEAD a plaintext Vec, so it cuts one per record
// (the same one bytes_slice cut before).
@ tls_write2 TlsConn c__h ( Vec u ) head ( Vec u ) body → !v TlsErr {
    : ~ * TlsConnImpl c ( __TlsConn_ptr c__h )
    ^ ( _tls_write2_in . c 0 head body )
}

@ _tls_write2_in inout TlsConnImpl c ( Vec u ) head ( Vec u ) body → !v TlsErr {
    ?? ( _tls_flush_control c 1 ) { T _ → {} F error → { ^ @ !v TlsErr { F error } } }
    ? != . c closed 0 { ^ @ !v TlsErr { F TlsClosed } } {}
    : i n + ( vec_len [u] head ) ( vec_len [u] body )
    : ~ i off 0
    ~ < off n {
        : ~ i hi + off 16384
        ? > hi n { = hi n } {}
        : ~ ! v TlsErr w @ !v TlsErr { T 0 }
        ? == . c version 12 {
            : ( Vec u ) part ( _tls_pair_slice head body off hi )
            = w ( __send_record_12 c 23 part )
        } { = w ( __send_encrypted_pair c 23 head body off hi ) }
        ?? w { T _ → {} F e → { ^ @ !v TlsErr { F e } } }
        = off hi
    }
    ^ @ !v TlsErr { T 0 }
}

// Read up to `max` decrypted application bytes. Returns [] on clean EOF
// (close_notify). Post-handshake messages (tickets, key updates) are
// consumed transparently.
@ tls_read TlsConn c__h i max → !( Vec u ) TlsErr {
    : ~ * TlsConnImpl c ( __TlsConn_ptr c__h )
    ^ ( _tls_read_in . c 0 max )
}

@ _tls_read_in inout TlsConnImpl c i max → !( Vec u ) TlsErr {
    ~ & == ( vec_len [u] . c appbuf ) 0 == . c closed 0 {
        ? != . c fatal_alert 0 { ^ @ !( Vec u ) TlsErr { F TlsProtocol } } {}
        ? != . c update_pending 0 {
            ? != . c read_nowait 0 { ^ @ !( Vec u ) TlsErr { F TlsRead } } {}
            ?? ( _tls_flush_control c 1 ) { T _ → {} F error → { ^ @ !( Vec u ) TlsErr { F error } } }
        } {}
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
                } {
                    ? == . c version 12 {
                        // TLS 1.2: the record type is the real content type.
                        ?? ( __decrypt_record_12 c . rec rtype . rec body ) {
                            T inner → {
                                ? == . rec rtype 23 { ( _tls_cat . c appbuf inner ) } {
                                    ? == . rec rtype 21 { = . c closed 1 } {}
                                    // type 22 (post-handshake, e.g. tickets): ignore
                                }
                            }
                            F _ → {
                                ^ @ !( Vec u ) TlsErr { F # TlsErr TlsDecrypt }
                            }
                        }
                    } {
                        ?? ( __decrypt_record c . rec body ) {
                            T inner → {
                                : i ct ( _inner_type inner )
                                ? == ct 23 {
                                    ? != ( vec_len [u] . c hsbuf ) 0 {
                                        : !v TlsErr failed ( _tls_post_fail c 0 10 )
                                        ?? failed { T _ → {} F _ → {} }
                                        ^ @ !( Vec u ) TlsErr { F TlsProtocol }
                                    } {}
                                    ( _tls_cat . c appbuf inner )
                                } {
                                    ? == ct 21 { = . c closed 1 } {}
                                    ? == ct 22 {
                                        ?? ( _tls_post_hs c inner 0 ) {
                                            T _ → {}
                                            F error → { ^ @ !( Vec u ) TlsErr { F error } }
                                        }
                                    } {}
                                }
                            }
                            F _ → {
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
    = . c appbuf rest
    ^ @ !( Vec u ) TlsErr { T out }
}

// Say close_notify (best effort) and close the socket. Safe to repeat;
// the connection's memory goes with its last owner.
@ tls_close TlsConn c__h → v {
    : ~ * TlsConnImpl c ( __TlsConn_ptr c__h )
    ( _tls_close_in . c 0 )
}

@ _tls_close_in inout TlsConnImpl c → v {
    ? != . c fatal_alert 0 {
        : !v TlsErr sent ( _tls_flush_control c 1 )
        ?? sent { T _ → {} F _ → {} }
    } {}
    ? == . c closed 0 {
        // best-effort close_notify alert (encrypted if established)
        ? == . c established 1 {
            : ( Vec u ) alert ( vec_with_cap [u] 2 )
            ( vec_push [u] alert # u 1 )
            ( vec_push [u] alert # u 0 )
            : !v TlsErr _w ? == . c version 12 ( __send_record_12 c 21 alert ) ( __send_encrypted c 21 alert )
        } {}
        = . c closed 1
    } {}
    // The socket goes now; the state goes with the handle's last owner.
    ? != . c owns_fd 0 { ( nurl_tcp_close . c fd ) = . c owns_fd 0 } {}
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
        = a anew
        : ( Vec u ) cat ( bytes_slice a 0 ( vec_len [u] a ) )
        ( bytes_extend_bytes cat fs )
        : ( Vec u ) chunk ( hmac_sha256_pure secret cat )
        : ~ i j 0
        ~ & < j 32 < ( vec_len [u] out ) outlen { ( vec_push [u] out # u ( _t_bget chunk j ) ) = j + j 1 }
    }
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
@ _tls_record12_to inout TlsConnImpl c ( Vec u ) out i rtype ( Vec u ) content → v {
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
    } {
        : ( Vec u ) nonce ( __nonce12_chacha . c c_iv . c c_seq )
        : ( Vec u ) sealed ( aead_encrypt . c c_key nonce aad content )
        ( _tls_cat body sealed )
    }
    ( vec_push [u] out # u rtype )
    ( vec_push [u] out # u 3 )
    ( vec_push [u] out # u 3 )
    ( _tls_u16 out ( vec_len [u] body ) )
    ( _tls_cat out body )
    = . c c_seq + . c c_seq 1
}

@ __send_record_12 inout TlsConnImpl c i rtype ( Vec u ) content → !v TlsErr {
    : ( Vec u ) record ( vec_new [u] )
    ( _tls_record12_to c record rtype content )
    : b written ( _tls_sock_write . c fd record )
    ? ! written { = . c closed 1 } {}
    ^ ? written @ !v TlsErr { T 0 } @ !v TlsErr { F TlsWrite }
}

// Decrypt a TLS 1.2 record body (real type `rtype`) → plaintext.
@ __decrypt_record_12 inout TlsConnImpl c i rtype ( Vec u ) body → ?( Vec u ) {
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
        r
    } {
        : ( Vec u ) nonce ( __nonce12_chacha . c s_iv . c s_seq )
        : i ptlen - ( vec_len [u] body ) 16
        : ( Vec u ) aad ( __aad12 . c s_seq rtype ptlen )
        : ?( Vec u ) r ( aead_decrypt . c s_key nonce aad body )
        r
    }
    = . c s_seq + . c s_seq 1
    ^ pt
}

// Derive the TLS 1.2 key block and install client/server write keys.
@ __tls12_setkeys inout TlsConnImpl c ( Vec u ) master ( Vec u ) crand ( Vec u ) srand → v {
    : ( Vec u ) seed ( vec_new [u] )
    ( bytes_extend_bytes seed srand )
    ( bytes_extend_bytes seed crand )
    : i klen ? == . c cipher 1 16 32
    : i ivlen ? == . c cipher 1 4 12
    : i need + * 2 klen * 2 ivlen
    : ( Vec u ) kb ( __prf12 master `key expansion` seed need )
    : ( Vec u ) ck ( bytes_slice kb 0 klen )
    : ( Vec u ) sk ( bytes_slice kb klen * 2 klen )
    : ( Vec u ) civ ( bytes_slice kb * 2 klen + * 2 klen ivlen )
    : ( Vec u ) siv ( bytes_slice kb + * 2 klen ivlen + * 2 klen * 2 ivlen )
    = . c c_key ck
    = . c s_key sk
    = . c c_iv civ
    = . c s_iv siv
    = . c c_seq 0
    = . c s_seq 0
}

// Drive the TLS 1.2 handshake after ServerHello. Consumes all the passed
// buffers. On success returns the established (encrypted) connection;
// the certificate chain + ServerKeyExchange signature material are
// captured on `c` for the verifier (cv_sig / cv_scheme / th_cert).
@ __tls12_handshake inout TlsConnImpl c ( Vec u ) sh ( Vec u ) priv ( Vec u ) cpub ( Vec u ) random ( Vec u ) sessid ( Vec u ) ch ( Vec u ) tr → !v TlsErr {
    : ( Vec u ) srand ( bytes_slice sh 6 38 )
    // M1: we always offer TLS 1.3 in supported_versions, so negotiating 1.2
    // here means a possible forced downgrade — abort on the RFC 8446 sentinel.
    ? ( __downgrade_sentinel srand ) {
        ^ ( __fail c # TlsErr TlsProtocol )
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
                    = . c cert_msg ( bytes_slice msg 0 ( vec_len [u] msg ) )
                } {}
                ? == t 12 {
                    // ServerKeyExchange: curve_type(1) curve(2) pklen(1) pk sig_scheme(2) siglen(2) sig
                    = kx_curve ( _rdint msg 5 2 )
                    : i pklen ( _t_bget msg 7 )
                    = spub ( bytes_slice msg 8 + 8 pklen )
                    : i sp + 8 pklen
                    = . c cv_scheme ( _rdint msg sp 2 )
                    : i siglen ( _rdint msg + sp 2 2 )
                    = . c cv_sig ( bytes_slice msg + sp 4 + + sp 4 siglen )
                    // signed data = client_random || server_random || ecdhe_params
                    : ( Vec u ) signed ( vec_new [u] )
                    ( bytes_extend_bytes signed random )
                    ( bytes_extend_bytes signed srand )
                    : ( Vec u ) eparams ( bytes_slice msg 4 + 8 pklen )
                    ( _tls_cat signed eparams )
                    = . c th_cert signed
                } {}
                ? == t 14 { = done 1 } {}
                ( _tls_cat tr msg )
            }
        }
    }
    ? | == err 1 == ( vec_len [u] spub ) 0 {
        ^ ( __fail c # TlsErr TlsHandshake )
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
    ( __tls12_setkeys c master random srand )

    // ── ClientKeyExchange (plaintext handshake) ──
    // body = pubkey_len(1) || pubkey ; handshake length = 1 + len(pubkey)
    : i cklen ( vec_len [u] ckpub )
    : ( Vec u ) cke ( vec_with_cap [u] + cklen 5 )
    ( vec_push [u] cke # u 16 )
    ( _u24 cke + cklen 1 )
    ( vec_push [u] cke # u cklen )
    ( _tls_cat cke ckpub )
    : !v TlsErr ckw ( _send_plain c 22 cke )
    ?? ckw { T _ → {} F _ → {} }
    ( _tls_cat tr cke )

    // ── ChangeCipherSpec + client Finished (encrypted) ──
    : ( Vec u ) ccs ( vec_with_cap [u] 1 )
    ( vec_push [u] ccs # u 1 )
    : !v TlsErr cw ( _send_plain c 20 ccs )
    ?? cw { T _ → {} F _ → {} }

    : ( Vec u ) th_c ( sha256_pure tr )
    : ( Vec u ) cfin_vd ( __prf12 master `client finished` th_c 12 )
    : ( Vec u ) finmsg ( vec_with_cap [u] 16 )
    ( vec_push [u] finmsg # u 20 )
    ( _u24 finmsg 12 )
    ( _tls_cat finmsg cfin_vd )
    : !v TlsErr fw ( __send_record_12 c 22 finmsg )
    ?? fw { T _ → {} F _ → {} }
    ( _tls_cat tr finmsg )

    // ── server ChangeCipherSpec + Finished ──
    : ( Vec u ) th_s ( sha256_pure tr )
    : ( Vec u ) sfin_exp ( __prf12 master `server finished` th_s 12 )
    : ~ i serr 0
    : ~ i sdone 0
    ~ & == sdone 0 == serr 0 {
        : !TlsRecord TlsErr rr ( _read_record c )
        ?? rr {
            F _ → { = serr 1 }
            T rec → {
                ? == . rec rtype 20 {
                } {
                    ?? ( __decrypt_record_12 c . rec rtype . rec body ) {
                        T inner → {
                            // inner = Finished handshake msg: [20][len3][verify_data]
                            // L5: compare the 12-byte verify_data in constant
                            // time (OR-accumulate XOR diffs, no early exit).
                            : ~ i diff ? >= ( vec_len [u] inner ) 16 0 1
                            : ~ i vi 0
                            ~ < vi 12 { = diff | diff ^^ ( _t_bget inner + 4 vi ) ( _t_bget sfin_exp vi ) = vi + vi 1 }
                            ? == diff 0 { = sdone 1 } { = serr 1 }
                        }
                        F _ → { = serr 1 }
                    }
                }
            }
        }
    }

    ? == serr 1 { ( _tls_close_in c ) ^ @ !v TlsErr { F # TlsErr TlsHandshake } } {}
    = . c established 1
    ^ @ !v TlsErr { T 0 }
}
