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
// A Handshake is a handle: every copy is the same handshake state, and its
// last owner releases it (noise_free is an early release, optional).
//
// Message layout (no payloads):
//   msg1 (init→resp): e(32) | enc(s_static)(48) | enc("")(16)  = 96 bytes
//   msg2 (resp→init): e(32) | enc("")(16)                      = 48 bytes

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/ext/crypto.nu`
$ `stdlib/core/rcbox.nu`

: | NoiseErr {
    NoiseBadMsg  // truncated / wrong-length handshake message
    NoiseAuth  // AEAD authentication failed (tampered / wrong key / wrong psk)
    NoiseCrypto  // an underlying crypto primitive failed
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
@ noise_nonce i n → ( Vec u ) {
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
    : ( Vec u ) out ?? ( hkdf_sha256 ikm ck info * num 32 ) { T x → x F _ → ( vec_new [u] ) }
    ^ out
}

@ __dh ( Vec u ) sk ( Vec u ) pk → ( Vec u ) {
    ^ ?? ( x25519_derive sk pk ) { T x → x F _ → ( vec_new [u] ) }
}

// ── SymmetricState (a value inside the handshake; mutated in place) ────

: SymState {
    ( Vec u ) ck  // chaining key (32)
    ( Vec u ) h  // handshake hash (32)
    ( Vec u ) k  // cipher key (32); empty until the first MixKey
    i nonce
    i has_key
}

@ __sym_new s protocol → SymState {
    : ( Vec u ) name ( vec_new [u] )
    ( bytes_extend_str name protocol )
    // protocol name is > 32 bytes → h = SHA256(name); ck = h.
    : ( Vec u ) h0 ( sha256_pure name )
    ^ @ SymState { ( __slice h0 0 32 ) h0 ( vec_new [u] ) 0 0 }
}

@ __sym_mix_hash inout SymState s ( Vec u ) data → v {
    : ( Vec u ) cat ( __cat . s h data )
    : ( Vec u ) nh ( sha256_pure cat )
    = . s h nh
}

@ __sym_mix_key inout SymState s ( Vec u ) ikm → v {
    : ( Vec u ) out ( __noise_hkdf . s ck ikm 2 )
    = . s ck ( __slice out 0 32 )
    = . s k ( __slice out 32 32 )
    = . s nonce 0
    = . s has_key 1
}

@ __sym_mix_key_and_hash inout SymState s ( Vec u ) ikm → v {
    : ( Vec u ) out ( __noise_hkdf . s ck ikm 3 )
    = . s ck ( __slice out 0 32 )
    : ( Vec u ) temp_h ( __slice out 32 32 )
    ( __sym_mix_hash s temp_h )
    = . s k ( __slice out 64 32 )
    = . s nonce 0
    = . s has_key 1
}

// EncryptAndHash: AEAD(pt) with ad=h (when keyed), then MixHash(ct).
@ __sym_encrypt inout SymState s ( Vec u ) pt → ( Vec u ) {
    ? == . s has_key 0 {
        ( __sym_mix_hash s pt )
        ^ ( __slice pt 0 ( vec_len [u] pt ) )
    } {}
    : ( Vec u ) nonce ( noise_nonce . s nonce )
    : ( Vec u ) ct ?? ( chacha20poly1305_encrypt . s k nonce . s h pt )
    { T x → x F _ → ( vec_new [u] ) }
    = . s nonce + . s nonce 1
    ( __sym_mix_hash s ct )
    ^ ct
}

// DecryptAndHash: MixHash(ct) AFTER decrypting under the pre-update h.
@ __sym_decrypt inout SymState s ( Vec u ) ct → !( Vec u ) NoiseErr {
    ? == . s has_key 0 {
        ( __sym_mix_hash s ct )
        ^ @ !( Vec u ) NoiseErr { T ( __slice ct 0 ( vec_len [u] ct ) ) }
    } {}
    : ( Vec u ) nonce ( noise_nonce . s nonce )
    : !( Vec u ) CryptoErr dr ( chacha20poly1305_decrypt . s k nonce . s h ct )
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

: HandshakeImpl {
    SymState sym
    ( Vec u ) s_priv  // our static private
    ( Vec u ) s_pub  // our static public
    ( Vec u ) e_priv  // our ephemeral private
    ( Vec u ) e_pub  // our ephemeral public
    ( Vec u ) rs  // remote static public
    ( Vec u ) re  // remote ephemeral public
    ( Vec u ) psk  // 32-byte pre-shared key
    i initiator
}

// A Handshake is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same handshake, and the last owner releases it.
: Handshake { s ctl }

@ Handshake_share Handshake h → Handshake { ^ @ Handshake { # s ( rcbox_share # i . h ctl ) } }

@ Handshake_drop sink Handshake h → v {
    ( mem_forget h )
    ( rcbox_release [HandshakeImpl] # i . h ctl )
}

@ __Handshake_ptr Handshake h → *HandshakeImpl { ^ ( rcbox_ptr [HandshakeImpl] # i . h ctl ) }

// Initialise. `rs` is the remote static public key (required for the
// initiator; pass the responder's own static public for the responder so
// the IK pre-message hashes identically on both sides). `psk` is 32 bytes.
@ noise_init i is_initiator CryptoKeypair static_kp ( Vec u ) rs ( Vec u ) psk → Handshake {
    : ~ SymState sym ( __sym_new `Noise_IKpsk2_25519_ChaChaPoly_SHA256` )
    // prologue is empty. IK pre-message `<- s`: both sides MixHash the
    // responder's static public. The initiator holds it as `rs`; the
    // responder passed its own static public as `rs` here, so both hash
    // the same 32 bytes.
    ( __sym_mix_hash sym rs )
    ^ @ Handshake { # s ( rcbox_new [HandshakeImpl] @ HandshakeImpl {
            sym
            ( __slice . static_kp sk 0 32 ) ( __slice . static_kp pk 0 32 )
            ( vec_new [u] ) ( vec_new [u] )
            ( __slice rs 0 ( vec_len [u] rs ) ) ( vec_new [u] )
            ( __slice psk 0 ( vec_len [u] psk ) )
            ? is_initiator 1 0 } ) }
}

// Let go of `h` now rather than at the end of its owner's scope.
@ noise_free sink Handshake h → v {}

@ __hs_gen_ephemeral inout HandshakeImpl h → v {
    ?? ( x25519_keygen ) {
        T kp → {
            = . h e_priv ( __slice . kp sk 0 32 )
            = . h e_pub ( __slice . kp pk 0 32 )
        }
        F _ → {}
    }
}

// The remote static public key, lent: the responder learns it from
// message 1 (it is who is calling).
@ noise_remote_static Handshake h__h → ( Vec u ) {
    : *HandshakeImpl h ( __Handshake_ptr h__h )
    ^ . h rs
}

// Initiator → message 1: e, es, s, ss + empty payload.
@ noise_write_msg1 Handshake h__h → ( Vec u ) {
    : ~ * HandshakeImpl h ( __Handshake_ptr h__h )
    ^ ( __noise_write_msg1_in . h 0 )
}

@ __noise_write_msg1_in inout HandshakeImpl h → ( Vec u ) {
    ( __hs_gen_ephemeral h )
    : ( Vec u ) out ( __slice . h e_pub 0 32 )  // e
    ( __sym_mix_hash . h sym . h e_pub )
    : ( Vec u ) es ( __dh . h e_priv . h rs )  // es
    ( __sym_mix_key . h sym es )
    : ( Vec u ) enc_s ( __sym_encrypt . h sym . h s_pub )  // s
    : ( Vec u ) out2 ( __cat out enc_s )
    : ( Vec u ) ss ( __dh . h s_priv . h rs )  // ss
    ( __sym_mix_key . h sym ss )
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) tag ( __sym_encrypt . h sym empty )  // payload (empty)
    : ( Vec u ) msg ( __cat out2 tag )
    ^ msg
}

// Responder ← message 1.
@ noise_read_msg1 Handshake h__h ( Vec u ) msg → !v NoiseErr {
    : ~ * HandshakeImpl h ( __Handshake_ptr h__h )
    ^ ( __noise_read_msg1_in . h 0 msg )
}

@ __noise_read_msg1_in inout HandshakeImpl h ( Vec u ) msg → !v NoiseErr {
    ? < ( vec_len [u] msg ) 96 { ^ @ !v NoiseErr { F @ NoiseErr { NoiseBadMsg } } } {}
    : ( Vec u ) re ( __slice msg 0 32 )  // e
    = . h re re
    ( __sym_mix_hash . h sym . h re )
    : ( Vec u ) es ( __dh . h s_priv . h re )  // es
    ( __sym_mix_key . h sym es )
    : ( Vec u ) enc_s ( __slice msg 32 48 )  // s (32 + 16 tag)
    : !( Vec u ) NoiseErr ds ( __sym_decrypt . h sym enc_s )
    ^ ?? ds {
        T rs → {
            = . h rs rs
            : ( Vec u ) ss ( __dh . h s_priv . h rs )  // ss
            ( __sym_mix_key . h sym ss )
            // An arm ending in another value-producing `??` does not drop
            // its locals yet: released here by hand until it does.
            ( vec_free [u] ss )  // finding_stdlib_nested_arm_locals
            : ( Vec u ) tag ( __slice msg 80 16 )  // empty payload
            : !( Vec u ) NoiseErr dp ( __sym_decrypt . h sym tag )
            ( vec_free [u] tag )  // finding_stdlib_nested_arm_locals
            ?? dp {
                T pt → { ( vec_free [u] pt ) @ !v NoiseErr { T 0 } }  // finding_stdlib_nested_arm_locals
                F e → @ !v NoiseErr { F # NoiseErr e }
            }
        }
        F e → @ !v NoiseErr { F # NoiseErr e }
    }
}

// Responder → message 2: e, ee, se, psk + empty payload.
@ noise_write_msg2 Handshake h__h → ( Vec u ) {
    : ~ * HandshakeImpl h ( __Handshake_ptr h__h )
    ^ ( __noise_write_msg2_in . h 0 )
}

@ __noise_write_msg2_in inout HandshakeImpl h → ( Vec u ) {
    ( __hs_gen_ephemeral h )
    : ( Vec u ) out ( __slice . h e_pub 0 32 )  // e
    ( __sym_mix_hash . h sym . h e_pub )
    : ( Vec u ) ee ( __dh . h e_priv . h re )  // ee
    ( __sym_mix_key . h sym ee )
    : ( Vec u ) se ( __dh . h e_priv . h rs )  // se (resp e × init s)
    ( __sym_mix_key . h sym se )
    ( __sym_mix_key_and_hash . h sym . h psk )  // psk
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) tag ( __sym_encrypt . h sym empty )  // empty payload
    : ( Vec u ) msg ( __cat out tag )
    ^ msg
}

// Initiator ← message 2.
@ noise_read_msg2 Handshake h__h ( Vec u ) msg → !v NoiseErr {
    : ~ * HandshakeImpl h ( __Handshake_ptr h__h )
    ^ ( __noise_read_msg2_in . h 0 msg )
}

@ __noise_read_msg2_in inout HandshakeImpl h ( Vec u ) msg → !v NoiseErr {
    ? < ( vec_len [u] msg ) 48 { ^ @ !v NoiseErr { F @ NoiseErr { NoiseBadMsg } } } {}
    : ( Vec u ) re ( __slice msg 0 32 )  // e
    = . h re re
    ( __sym_mix_hash . h sym . h re )
    : ( Vec u ) ee ( __dh . h e_priv . h re )  // ee
    ( __sym_mix_key . h sym ee )
    : ( Vec u ) se ( __dh . h s_priv . h re )  // se (init s × resp e)
    ( __sym_mix_key . h sym se )
    ( __sym_mix_key_and_hash . h sym . h psk )  // psk
    : ( Vec u ) tag ( __slice msg 32 16 )  // empty payload
    : !( Vec u ) NoiseErr dp ( __sym_decrypt . h sym tag )
    ^ ?? dp {
        T pt → { @ !v NoiseErr { T 0 } }
        F e → @ !v NoiseErr { F # NoiseErr e }
    }
}

// Transport keys derived after the handshake completes. `send` is what
// THIS side encrypts with, `recv` what it decrypts with.
: NoiseKeys {
    ( Vec u ) send
    ( Vec u ) recv
}

// The keys go with their owner; this lets go of them early (optional).
@ noise_keys_free sink NoiseKeys k → v {}

@ noise_split Handshake h__h → NoiseKeys {
    : ~ * HandshakeImpl h ( __Handshake_ptr h__h )
    ^ ( __noise_split_in . h 0 )
}

@ __noise_split_in inout HandshakeImpl h → NoiseKeys {
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) out ( __noise_hkdf . . h sym ck empty 2 )
    : ( Vec u ) k1 ( __slice out 0 32 )
    : ( Vec u ) k2 ( __slice out 32 32 )
    // Initiator sends with k1/recvs with k2; responder is symmetric.
    ^ ? == . h initiator 1
    @ NoiseKeys { k1 k2 }
    @ NoiseKeys { k2 k1 }
}
