// stdlib/net/session.nu — post-handshake transport session.
//
// **Phase 0 of TODO §7.4**, on top of net/noise.nu. After the Noise
// handshake yields a send/recv key pair, a NoiseSession encrypts/decrypts
// datagrams with a per-direction 64-bit counter nonce and rejects replays
// + duplicates via a WireGuard-style sliding window (accepts reordering
// within the window — important on lossy/mobile UDP).
//
//   ( session_new NoiseKeys k )                  → *NoiseSession  (copies keys)
//   ( session_seal *NoiseSession (Vec u) ad (Vec u) pt ) → Sealed { counter, ct }
//   ( session_open *NoiseSession i counter (Vec u) ad (Vec u) ct ) → ?(Vec u)
//        None = AEAD auth failure OR replay/duplicate/too-old.
//   ( session_free *NoiseSession )               → v

$ `stdlib/core/vec.nu`
$ `stdlib/ext/crypto.nu`
$ `stdlib/net/noise.nu`

: NoiseSession {
    ( Vec u ) send_key
    ( Vec u ) recv_key
    i send_n
    i recv_max     // highest accepted recv counter (-1 = none yet)
    i recv_mask    // 64-bit window; bit 0 = recv_max, bit k = recv_max-k
}

@ __vcopy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

@ session_new NoiseKeys k → *NoiseSession {
    : *NoiseSession s # *NoiseSession ( nurl_alloc Z NoiseSession )
    = . s send_key ( __vcopy . k send )
    = . s recv_key ( __vcopy . k recv )
    = . s send_n 0
    = . s recv_max - 0 1
    = . s recv_mask 0
    ^ s
}

@ session_free *NoiseSession s → v {
    ( vec_free [u] . s send_key )
    ( vec_free [u] . s recv_key )
    ( nurl_free # s s )
}

: Sealed {
    i counter
    ( Vec u ) ct
}

@ sealed_free Sealed s → v { ( vec_free [u] . s ct ) }

@ session_seal *NoiseSession s ( Vec u ) ad ( Vec u ) pt → Sealed {
    : i ctr . s send_n
    : ( Vec u ) nonce ( noise_nonce ctr )
    : ( Vec u ) ct ?? ( chacha20poly1305_encrypt . s send_key nonce ad pt )
    { T x → x  F _ → ( vec_new [u] ) }
    ( vec_free [u] nonce )
    = . s send_n + . s send_n 1
    ^ @ Sealed { ctr ct }
}

// Sliding-window replay check + commit. Returns T (accept) only for a
// counter not already seen and not older than the 64-wide window. Mutates
// the window on accept. Call ONLY after a successful AEAD decrypt.
@ __replay_ok *NoiseSession s i c → b {
    : i mx . s recv_max
    ? > c mx {
        : i shift - c mx
        ? >= shift 64 { = . s recv_mask 1 }
        { = . s recv_mask | << . s recv_mask shift 1 }
        = . s recv_max c
        ^ T
    } {}
    : i diff - mx c
    ? >= diff 64 { ^ F } {}
    : i bit << 1 diff
    ? != 0 & . s recv_mask bit { ^ F } {}
    = . s recv_mask | . s recv_mask bit
    ^ T
}

@ session_open *NoiseSession s i counter ( Vec u ) ad ( Vec u ) ct → ?( Vec u ) {
    : ( Vec u ) nonce ( noise_nonce counter )
    : !( Vec u ) CryptoErr dr ( chacha20poly1305_decrypt . s recv_key nonce ad ct )
    ( vec_free [u] nonce )
    ^ ?? dr {
        T pt → {
            ? ( __replay_ok s counter ) {
                @ ?( Vec u ) { T pt }
            } {
                ( vec_free [u] pt )
                @ ?( Vec u ) { F # ( Vec u ) 0 }
            }
        }
        F _ → @ ?( Vec u ) { F # ( Vec u ) 0 }
    }
}
