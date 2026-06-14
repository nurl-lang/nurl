// stdlib/net/noise.nu — Noise_IKpsk2_25519_ChaChaPoly_SHA256 handshake.
//
// **Phase 0 of TODO §7.4** — the security-critical core of the NAT/mobile
// transport. The IK pattern: the initiator already knows the responder's
// static public key (it is the peer's *address*), so the handshake is one
// round trip and the initiator's identity is encrypted. `psk2` mixes a
// pre-shared key in the second message for an extra (post-quantum-ish)
// authentication layer.
//
// Built entirely on existing primitives (ext/crypto + std/hash_sha256):
//   DH    = X25519            (x25519_derive)
//   HASH  = SHA-256           (sha256_pure — used for MixHash; this is the
//                              SHA256 Noise suite, not WireGuard's BLAKE2s,
//                              so it is NURL↔NURL, not WireGuard-interop)
//   KDF   = HKDF-SHA256       (hkdf_sha256)
//   AEAD  = ChaCha20-Poly1305 (chacha20poly1305_*)
//
// This module is the handshake only. It outputs two transport keys (send
// + recv); the datagram session (counter nonce, replay window) and the
// UDP/roaming layer sit above it (later Phase-0 commits).
//
// Message layout (no payloads):
//   msg1 (init→resp): e(32) | enc(s_static)(48) | enc("")(16)  = 96 bytes
//   msg2 (resp→init): e(32) | enc("")(16)                      = 48 bytes

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/ext/crypto.nu`

: | NoiseErr {
    NoiseBadMsg      // truncated / wrong-length handshake message
    NoiseAuth        // AEAD authentication failed (tampered / wrong key / wrong psk)
    NoiseCrypto      // an underlying crypto primitive failed
}

@ noise_err_name NoiseErr e → s {
    ^ ?? e {
        NoiseBadMsg → `NoiseBadMsg`
        NoiseAuth → `NoiseAuth`
        NoiseCrypto → `NoiseCrypto`
    }
}

// ── byte helpers ─────────────────────────────────────────────────────

@ __cat ( Vec u ) a ( Vec u ) b → ( Vec u ) {
    : ( Vec u ) o ( vec_new [u] )
    ( vec_extend [u] o a )
    ( vec_extend [u] o b )
    ^ o
}

@ __slice ( Vec u ) v i off i n → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [u] v + off k ) { T b → ( vec_push [u] o b ) F → {} }
        = k + k 1
    }
    ^ o
}

// 12-byte ChaChaPoly nonce per Noise: 4 zero bytes then the 64-bit counter
// little-endian.
@ __noise_nonce i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 12 )
    : ~ i z 0
    ~ < z 4 { ( vec_push [u] v # u 0 ) = z + z 1 }
    : u64 un # u64 n
    : ~ i b 0
    ~ < b 8 { ( vec_push [u] v # u & >> un * b 8 255 ) = b + b 1 }
    ^ v
}

// Noise HKDF(ck, ikm, num) → num*32 bytes (RFC 5869 with salt=ck, info="").
@ __noise_hkdf ( Vec u ) ck ( Vec u ) ikm i num → ( Vec u ) {
    : ( Vec u ) info ( vec_new [u] )
    : ( Vec u ) out ?? ( hkdf_sha256 ikm ck info * num 32 ) { T x → x  F _ → ( vec_new [u] ) }
    ( vec_free [u] info )
    ^ out
}

@ __dh ( Vec u ) sk ( Vec u ) pk → ( Vec u ) {
    ^ ?? ( x25519_derive sk pk ) { T x → x  F _ → ( vec_new [u] ) }
}

// ── SymmetricState (heap; mutated through the handshake) ──────────────

: SymState {
    ( Vec u ) ck       // chaining key (32)
    ( Vec u ) h        // handshake hash (32)
    ( Vec u ) k        // cipher key (32); empty until the first MixKey
    i nonce
    i has_key
}

@ __sym_new s protocol → *SymState {
    : *SymState s # *SymState ( nurl_alloc Z SymState )
    : ( Vec u ) name ( vec_new [u] )
    ( bytes_extend_str name protocol )
    // protocol name is > 32 bytes → h = SHA256(name); ck = h.
    : ( Vec u ) h0 ( sha256_pure name )
    ( vec_free [u] name )
    = . s ck ( __slice h0 0 32 )
    = . s h h0
    = . s k ( vec_new [u] )
    = . s nonce 0
    = . s has_key 0
    ^ s
}

@ __sym_free *SymState s → v {
    ( vec_free [u] . s ck )
    ( vec_free [u] . s h )
    ( vec_free [u] . s k )
    ( nurl_free # s s )
}

@ __sym_mix_hash *SymState s ( Vec u ) data → v {
    : ( Vec u ) cat ( __cat . s h data )
    : ( Vec u ) nh ( sha256_pure cat )
    ( vec_free [u] cat )
    ( vec_free [u] . s h )
    = . s h nh
}

@ __sym_mix_key *SymState s ( Vec u ) ikm → v {
    : ( Vec u ) out ( __noise_hkdf . s ck ikm 2 )
    ( vec_free [u] . s ck )
    = . s ck ( __slice out 0 32 )
    ( vec_free [u] . s k )
    = . s k ( __slice out 32 32 )
    ( vec_free [u] out )
    = . s nonce 0
    = . s has_key 1
}

@ __sym_mix_key_and_hash *SymState s ( Vec u ) ikm → v {
    : ( Vec u ) out ( __noise_hkdf . s ck ikm 3 )
    ( vec_free [u] . s ck )
    = . s ck ( __slice out 0 32 )
    : ( Vec u ) temp_h ( __slice out 32 32 )
    ( __sym_mix_hash s temp_h )
    ( vec_free [u] temp_h )
    ( vec_free [u] . s k )
    = . s k ( __slice out 64 32 )
    ( vec_free [u] out )
    = . s nonce 0
    = . s has_key 1
}

// EncryptAndHash: AEAD(pt) with ad=h (when keyed), then MixHash(ct).
@ __sym_encrypt *SymState s ( Vec u ) pt → ( Vec u ) {
    ? == . s has_key 0 {
        ( __sym_mix_hash s pt )
        ^ ( __slice pt 0 ( vec_len [u] pt ) )
    } {}
    : ( Vec u ) nonce ( __noise_nonce . s nonce )
    : ( Vec u ) ct ?? ( chacha20poly1305_encrypt . s k nonce . s h pt )
    { T x → x  F _ → ( vec_new [u] ) }
    ( vec_free [u] nonce )
    = . s nonce + . s nonce 1
    ( __sym_mix_hash s ct )
    ^ ct
}

// DecryptAndHash: MixHash(ct) AFTER decrypting under the pre-update h.
@ __sym_decrypt *SymState s ( Vec u ) ct → !( Vec u ) NoiseErr {
    ? == . s has_key 0 {
        ( __sym_mix_hash s ct )
        ^ @ !( Vec u ) NoiseErr { T ( __slice ct 0 ( vec_len [u] ct ) ) }
    } {}
    : ( Vec u ) nonce ( __noise_nonce . s nonce )
    : !( Vec u ) CryptoErr dr ( chacha20poly1305_decrypt . s k nonce . s h ct )
    ( vec_free [u] nonce )
    ^ ?? dr {
        T pt → {
            = . s nonce + . s nonce 1
            ( __sym_mix_hash s ct )
            @ !( Vec u ) NoiseErr { T pt }
        }
        F _ → @ !( Vec u ) NoiseErr { F @ NoiseErr { NoiseAuth } }
    }
}

// ── HandshakeState ───────────────────────────────────────────────────

: Handshake {
    s sym              // *SymState
    ( Vec u ) s_priv   // our static private
    ( Vec u ) s_pub    // our static public
    ( Vec u ) e_priv   // our ephemeral private
    ( Vec u ) e_pub    // our ephemeral public
    ( Vec u ) rs       // remote static public
    ( Vec u ) re       // remote ephemeral public
    ( Vec u ) psk      // 32-byte pre-shared key
    i initiator
}

@ __hs_sym *Handshake h → *SymState { ^ # *SymState . h sym }

// Initialise. `rs` is the remote static public key (required for the
// initiator; pass the responder's own static public for the responder so
// the IK pre-message hashes identically on both sides). `psk` is 32 bytes.
@ noise_init i is_initiator CryptoKeypair static_kp ( Vec u ) rs ( Vec u ) psk → *Handshake {
    : *Handshake h # *Handshake ( nurl_alloc Z Handshake )
    : *SymState sym ( __sym_new `Noise_IKpsk2_25519_ChaChaPoly_SHA256` )
    = . h sym # s sym
    = . h s_priv ( __slice . static_kp sk 0 32 )
    = . h s_pub ( __slice . static_kp pk 0 32 )
    = . h e_priv ( vec_new [u] )
    = . h e_pub ( vec_new [u] )
    = . h rs ( __slice rs 0 ( vec_len [u] rs ) )
    = . h re ( vec_new [u] )
    = . h psk ( __slice psk 0 ( vec_len [u] psk ) )
    = . h initiator ? is_initiator 1 0
    // prologue is empty. IK pre-message `<- s`: both sides MixHash the
    // responder's static public. The initiator holds it as `rs`; the
    // responder passed its own static public as `rs` here, so both hash
    // the same 32 bytes.
    ( __sym_mix_hash sym . h rs )
    ^ h
}

@ noise_free *Handshake h → v {
    ( __sym_free ( __hs_sym h ) )
    ( vec_free [u] . h s_priv )
    ( vec_free [u] . h s_pub )
    ( vec_free [u] . h e_priv )
    ( vec_free [u] . h e_pub )
    ( vec_free [u] . h rs )
    ( vec_free [u] . h re )
    ( vec_free [u] . h psk )
    ( nurl_free # s h )
}

@ __hs_gen_ephemeral *Handshake h → v {
    ?? ( x25519_keygen ) {
        T kp → {
            ( vec_free [u] . h e_priv )
            = . h e_priv ( __slice . kp sk 0 32 )
            ( vec_free [u] . h e_pub )
            = . h e_pub ( __slice . kp pk 0 32 )
            ( vec_free [u] . kp sk )
            ( vec_free [u] . kp pk )
        }
        F _ → {}
    }
}

// Initiator → message 1: e, es, s, ss + empty payload.
@ noise_write_msg1 *Handshake h → ( Vec u ) {
    : *SymState sym ( __hs_sym h )
    ( __hs_gen_ephemeral h )
    : ( Vec u ) out ( __slice . h e_pub 0 32 )      // e
    ( __sym_mix_hash sym . h e_pub )
    : ( Vec u ) es ( __dh . h e_priv . h rs )        // es
    ( __sym_mix_key sym es )
    ( vec_free [u] es )
    : ( Vec u ) enc_s ( __sym_encrypt sym . h s_pub ) // s
    : ( Vec u ) out2 ( __cat out enc_s )
    ( vec_free [u] out )
    ( vec_free [u] enc_s )
    : ( Vec u ) ss ( __dh . h s_priv . h rs )         // ss
    ( __sym_mix_key sym ss )
    ( vec_free [u] ss )
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) tag ( __sym_encrypt sym empty )       // payload (empty)
    ( vec_free [u] empty )
    : ( Vec u ) msg ( __cat out2 tag )
    ( vec_free [u] out2 )
    ( vec_free [u] tag )
    ^ msg
}

// Responder ← message 1.
@ noise_read_msg1 *Handshake h ( Vec u ) msg → !v NoiseErr {
    ? < ( vec_len [u] msg ) 96 { ^ @ !v NoiseErr { F @ NoiseErr { NoiseBadMsg } } } {}
    : *SymState sym ( __hs_sym h )
    : ( Vec u ) re ( __slice msg 0 32 )               // e
    ( vec_free [u] . h re )
    = . h re re
    ( __sym_mix_hash sym . h re )
    : ( Vec u ) es ( __dh . h s_priv . h re )          // es
    ( __sym_mix_key sym es )
    ( vec_free [u] es )
    : ( Vec u ) enc_s ( __slice msg 32 48 )            // s (32 + 16 tag)
    : !( Vec u ) NoiseErr ds ( __sym_decrypt sym enc_s )
    ( vec_free [u] enc_s )
    ^ ?? ds {
        T rs → {
            ( vec_free [u] . h rs )
            = . h rs rs
            : ( Vec u ) ss ( __dh . h s_priv . h rs )   // ss
            ( __sym_mix_key sym ss )
            ( vec_free [u] ss )
            : ( Vec u ) tag ( __slice msg 80 16 )       // empty payload
            : !( Vec u ) NoiseErr dp ( __sym_decrypt sym tag )
            ( vec_free [u] tag )
            ?? dp {
                T pt → { ( vec_free [u] pt ) @ !v NoiseErr { T 0 } }
                F e → @ !v NoiseErr { F # NoiseErr e }
            }
        }
        F e → @ !v NoiseErr { F # NoiseErr e }
    }
}

// Responder → message 2: e, ee, se, psk + empty payload.
@ noise_write_msg2 *Handshake h → ( Vec u ) {
    : *SymState sym ( __hs_sym h )
    ( __hs_gen_ephemeral h )
    : ( Vec u ) out ( __slice . h e_pub 0 32 )         // e
    ( __sym_mix_hash sym . h e_pub )
    : ( Vec u ) ee ( __dh . h e_priv . h re )           // ee
    ( __sym_mix_key sym ee )
    ( vec_free [u] ee )
    : ( Vec u ) se ( __dh . h e_priv . h rs )           // se (resp e × init s)
    ( __sym_mix_key sym se )
    ( vec_free [u] se )
    ( __sym_mix_key_and_hash sym . h psk )              // psk
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) tag ( __sym_encrypt sym empty )         // empty payload
    ( vec_free [u] empty )
    : ( Vec u ) msg ( __cat out tag )
    ( vec_free [u] out )
    ( vec_free [u] tag )
    ^ msg
}

// Initiator ← message 2.
@ noise_read_msg2 *Handshake h ( Vec u ) msg → !v NoiseErr {
    ? < ( vec_len [u] msg ) 48 { ^ @ !v NoiseErr { F @ NoiseErr { NoiseBadMsg } } } {}
    : *SymState sym ( __hs_sym h )
    : ( Vec u ) re ( __slice msg 0 32 )                 // e
    ( vec_free [u] . h re )
    = . h re re
    ( __sym_mix_hash sym . h re )
    : ( Vec u ) ee ( __dh . h e_priv . h re )            // ee
    ( __sym_mix_key sym ee )
    ( vec_free [u] ee )
    : ( Vec u ) se ( __dh . h s_priv . h re )            // se (init s × resp e)
    ( __sym_mix_key sym se )
    ( vec_free [u] se )
    ( __sym_mix_key_and_hash sym . h psk )               // psk
    : ( Vec u ) tag ( __slice msg 32 16 )                // empty payload
    : !( Vec u ) NoiseErr dp ( __sym_decrypt sym tag )
    ( vec_free [u] tag )
    ^ ?? dp {
        T pt → { ( vec_free [u] pt ) @ !v NoiseErr { T 0 } }
        F e → @ !v NoiseErr { F # NoiseErr e }
    }
}

// Transport keys derived after the handshake completes. `send` is what
// THIS side encrypts with, `recv` what it decrypts with.
: NoiseKeys {
    ( Vec u ) send
    ( Vec u ) recv
}

@ noise_keys_free NoiseKeys k → v {
    ( vec_free [u] . k send )
    ( vec_free [u] . k recv )
}

@ noise_split *Handshake h → NoiseKeys {
    : *SymState sym ( __hs_sym h )
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) out ( __noise_hkdf . sym ck empty 2 )
    ( vec_free [u] empty )
    : ( Vec u ) k1 ( __slice out 0 32 )
    : ( Vec u ) k2 ( __slice out 32 32 )
    ( vec_free [u] out )
    // Initiator sends with k1/recvs with k2; responder is symmetric.
    ^ ? == . h initiator 1
    @ NoiseKeys { k1 k2 }
    @ NoiseKeys { k2 k1 }
}
