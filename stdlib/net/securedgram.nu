// stdlib/net/securedgram.nu — pubkey-addressed encrypted UDP datagrams.
//
// **Phase 0 finale of TODO §7.4.** Ties net/noise (handshake) + net/session
// (transport AEAD + replay window) onto a UDP socket, behind the only API
// the layers above ever see: send_to(pubkey, bytes) / recv() → (pubkey,
// bytes). Peers are addressed by their STATIC PUBLIC KEY; the endpoint
// (host:port) is mutable and updated on every *authenticated* inbound
// datagram — the roaming rule that keeps mobile sessions alive across
// wifi↔cellular swaps with no restart.
//
// Wire framing (WireGuard-style, index-routed):
//   [1][sender_index:4][noise_msg1:96]                  handshake init
//   [2][sender_index:4][receiver_index:4][noise_msg2:48] handshake resp
//   [4][receiver_index:4][counter:8][ciphertext…]        transport data
// `receiver_index` is the index the *recipient* assigned and advertised,
// so a node maps an incoming datagram to a session in O(1)-ish by its own
// index. The mesh PSK is node-wide for now (per-peer PSK is a follow-up).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/ext/crypto.nu`
$ `stdlib/net/noise.nu`
$ `stdlib/net/session.nu`

@ __cpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

@ __veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a )
    ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n {
        : i x ?? ( vec_get [u] a k ) { T t → # i t F → -1 }
        : i y ?? ( vec_get [u] b k ) { T t → # i t F → -2 }
        ? != x y { = e F } {}
        = k + k 1
    }
    ^ e
}

@ __slc ( Vec u ) v i off i n → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ?? ( vec_get [u] v + off k ) { T b → ( vec_push [u] o b ) F → {} } = k + k 1 }
    ^ o
}

@ __sdg_u32 ( Vec u ) v i off → i { ^ ?? ( bytes_read_u32_be v off ) { T x → # i x F → 0 } }

@ __u64 ( Vec u ) v i off → i { ^ ?? ( bytes_read_u64_be v off ) { T x → # i x F → 0 } }

: PeerState {
    ( Vec u ) pubkey
    String ehost
    i eport
    i local_index  // we assigned; the peer echoes it in datagrams to us
    i remote_index  // the peer assigned; we put it in datagrams to them
    s hs  // *Handshake during the handshake, else 0
    s session  // *NoiseSession once established, else 0
    i established
}

: SecureNode {
    UdpSocket sock
    ( Vec u ) s_priv
    ( Vec u ) s_pub
    ( Vec u ) psk
    ( Vec s ) peers  // *PeerState pointers
    i next_index
}

@ securedgram_open s host i port CryptoKeypair static ( Vec u ) psk → !*SecureNode NetErr {
    : !UdpSocket NetErr sr ( udp_bind host port )
    ^ ?? sr {
        T sock → {
            ( udp_set_timeout sock 500 )
            : *SecureNode n # *SecureNode ( nurl_alloc Z SecureNode )
            = . n sock sock
            = . n s_priv ( __cpy . static sk )
            = . n s_pub ( __cpy . static pk )
            = . n psk ( __cpy psk )
            = . n peers ( vec_new [s] )
            = . n next_index 1
            @ !*SecureNode NetErr { T n }
        }
        F e → @ !*SecureNode NetErr { F # NetErr e }
    }
}

@ __node_kp * SecureNode n → CryptoKeypair { ^ @ CryptoKeypair { . n s_priv . n s_pub } }

// Re-bind the local socket (network change / roaming). Sessions + peer
// state survive; the peer learns our new source on the next datagram via
// its own roaming rule.
@ securedgram_rebind * SecureNode n s host i port → !v NetErr {
    : !UdpSocket NetErr sr ( udp_bind host port )
    ^ ?? sr {
        T sock → {
            ( udp_close . n sock )
            ( udp_set_timeout sock 500 )
            = . n sock sock
            @ !v NetErr { T 0 }
        }
        F e → @ !v NetErr { F # NetErr e }
    }
}

// Local endpoint ("host:port") — for telling a peer where to reach us.
@ securedgram_local_addr * SecureNode n → String { ^ ( udp_local_addr . n sock ) }

@ securedgram_add_peer * SecureNode n ( Vec u ) pubkey s host i port → v {
    : *PeerState p # *PeerState ( nurl_alloc Z PeerState )
    = . p pubkey ( __cpy pubkey )
    = . p ehost ( string_from host )
    = . p eport port
    = . p local_index . n next_index
    = . n next_index + . n next_index 1
    = . p remote_index 0
    = . p hs # s 0
    = . p session # s 0
    = . p established 0
    ( vec_push [s] . n peers # s p )
}

@ __find_pk * SecureNode n ( Vec u ) pk → s {
    : i cnt ( vec_len [s] . n peers )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k cnt {
        : s pp ?? ( vec_get [s] . n peers k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *PeerState p # *PeerState pp
            ? ( __veq . p pubkey pk ) { = found pp } {}
        } {}
        = k + k 1
    }
    ^ found
}

@ __find_idx * SecureNode n i idx → s {
    : i cnt ( vec_len [s] . n peers )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k cnt {
        : s pp ?? ( vec_get [s] . n peers k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *PeerState p # *PeerState pp
            ? == . p local_index idx { = found pp } {}
        } {}
        = k + k 1
    }
    ^ found
}

// Update a peer's endpoint from a "host:port" source string (last ':' is
// the port separator — fine for IPv4 and "[v6]:port"). The roaming rule.
@ __roam * PeerState p String src → v {
    : s cs ( string_data src )
    : i n ( string_len src )
    : *u sp # *u cs
    : ~ i colon - 0 1
    : ~ i k 0
    ~ < k n { ? == # i . sp k 58 { = colon k } {} = k + k 1 }
    ? < colon 0 { ^ v } {}
    : String host ( string_with_cap colon )
    : ~ i h 0
    ~ < h colon { ( string_push_char host # i . sp h ) = h + h 1 }
    : ~ i port 0
    : ~ i d + colon 1
    ~ < d n {
        : i c # i . sp d
        ? & >= c 48 <= c 57 { = port + * port 10 - c 48 } {}
        = d + d 1
    }
    ( string_free . p ehost )
    = . p ehost host
    = . p eport port
}

@ __send_pkt * SecureNode n * PeerState p ( Vec u ) pkt → v {
    : !i NetErr r ( udp_send_to . n sock pkt ( string_data . p ehost ) . p eport )
    ?? r { T _ → {} F _ → {} }
}

// Initiate a handshake to a known peer (send msg1).
@ securedgram_connect * SecureNode n ( Vec u ) peer_pk → !v NetErr {
    : s pp ( __find_pk n peer_pk )
    ? == # i pp 0 { ^ @ !v NetErr { F @ NetErr { NetOther } } } {}
    : *PeerState p # *PeerState pp
    : *Handshake hs ( noise_init T ( __node_kp n ) . p pubkey . n psk )
    = . p hs # s hs
    : ( Vec u ) msg1 ( noise_write_msg1 hs )
    : ( Vec u ) pkt ( vec_new [u] )
    ( vec_push [u] pkt # u 1 )
    ( bytes_push_u32_be pkt # u32 . p local_index )
    ( vec_extend [u] pkt msg1 )
    ( vec_free [u] msg1 )
    ( __send_pkt n p pkt )
    ( vec_free [u] pkt )
    ^ @ !v NetErr { T 0 }
}

@ securedgram_send * SecureNode n ( Vec u ) peer_pk ( Vec u ) data → !v NetErr {
    : s pp ( __find_pk n peer_pk )
    ? == # i pp 0 { ^ @ !v NetErr { F @ NetErr { NetOther } } } {}
    : *PeerState p # *PeerState pp
    ? == . p established 0 { ^ @ !v NetErr { F @ NetErr { NetOther } } } {}
    : *NoiseSession sess # *NoiseSession . p session
    : ( Vec u ) ad ( vec_new [u] )
    : Sealed sealed ( session_seal sess ad data )
    ( vec_free [u] ad )
    : ( Vec u ) pkt ( vec_new [u] )
    ( vec_push [u] pkt # u 4 )
    ( bytes_push_u32_be pkt # u32 . p remote_index )
    ( bytes_push_u64_be pkt # u64 . sealed counter )
    ( vec_extend [u] pkt . sealed ct )
    ( sealed_free sealed )
    ( __send_pkt n p pkt )
    ( vec_free [u] pkt )
    ^ @ !v NetErr { T 0 }
}

// Responder side: process a handshake init, reply with msg2, establish.
@ __handle_init * SecureNode n String src ( Vec u ) buf → v {
    ? < ( vec_len [u] buf ) 101 { ^ v } {}
    : i sender_index ( __sdg_u32 buf 1 )
    : ( Vec u ) msg1 ( __slc buf 5 96 )
    : *Handshake hs ( noise_init F ( __node_kp n ) . n s_pub . n psk )
    : !v NoiseErr r1 ( noise_read_msg1 hs msg1 )
    ( vec_free [u] msg1 )
    ?? r1 {
        T _ → {
            : s pp ( __find_pk n . hs rs )
            ? == # i pp 0 { ( noise_free hs ) ^ v } {}
            : *PeerState p # *PeerState pp
            ( __roam p src )
            = . p remote_index sender_index
            : ( Vec u ) msg2 ( noise_write_msg2 hs )
            : NoiseKeys keys ( noise_split hs )
            : *NoiseSession sess ( session_new keys )
            ( noise_keys_free keys )
            ? != # i . p session 0 { ( session_free # *NoiseSession . p session ) } {}
            = . p session # s sess
            = . p established 1
            ( noise_free hs )
            : ( Vec u ) pkt ( vec_new [u] )
            ( vec_push [u] pkt # u 2 )
            ( bytes_push_u32_be pkt # u32 . p local_index )
            ( bytes_push_u32_be pkt # u32 sender_index )
            ( vec_extend [u] pkt msg2 )
            ( vec_free [u] msg2 )
            ( __send_pkt n p pkt )
            ( vec_free [u] pkt )
        }
        F _ → ( noise_free hs )
    }
}

// Initiator side: process the handshake response, establish.
@ __handle_resp * SecureNode n String src ( Vec u ) buf → v {
    ? < ( vec_len [u] buf ) 57 { ^ v } {}
    : i resp_index ( __sdg_u32 buf 1 )
    : i our_index ( __sdg_u32 buf 5 )
    : ( Vec u ) msg2 ( __slc buf 9 48 )
    : s pp ( __find_idx n our_index )
    ? == # i pp 0 { ( vec_free [u] msg2 ) ^ v } {}
    : *PeerState p # *PeerState pp
    ? == # i . p hs 0 { ( vec_free [u] msg2 ) ^ v } {}
    : *Handshake hs # *Handshake . p hs
    : !v NoiseErr r2 ( noise_read_msg2 hs msg2 )
    ( vec_free [u] msg2 )
    ?? r2 {
        T _ → {
            ( __roam p src )
            = . p remote_index resp_index
            : NoiseKeys keys ( noise_split hs )
            : *NoiseSession sess ( session_new keys )
            ( noise_keys_free keys )
            = . p session # s sess
            = . p established 1
            ( noise_free hs )
            = . p hs # s 0
        }
        F _ → {}
    }
}

: RecvData {
    ( Vec u ) peer_pubkey
    ( Vec u ) data
}

@ recvdata_free RecvData r → v {
    ( vec_free [u] . r peer_pubkey )
    ( vec_free [u] . r data )
}

// Transport: decrypt, roam, deliver. None on a non-data / unauthenticated
// datagram.
@ __handle_data * SecureNode n String src ( Vec u ) buf → ?RecvData {
    ? < ( vec_len [u] buf ) 13 { ^ @ ?RecvData { F # RecvData 0 } } {}
    : i recv_index ( __sdg_u32 buf 1 )
    : i counter ( __u64 buf 5 )
    : ( Vec u ) ct ( __slc buf 13 - ( vec_len [u] buf ) 13 )
    : s pp ( __find_idx n recv_index )
    : *PeerState p # *PeerState pp
    ? | == # i pp 0 == . p established 0 {
        ( vec_free [u] ct )
        ^ @ ?RecvData { F # RecvData 0 }
    } {}
    : *NoiseSession sess # *NoiseSession . p session
    : ( Vec u ) ad ( vec_new [u] )
    : ?( Vec u ) opened ( session_open sess counter ad ct )
    ( vec_free [u] ad )
    ( vec_free [u] ct )
    ^ ?? opened {
        T pt → {
            ( __roam p src )
            @ ?RecvData { T @ RecvData { ( __cpy . p pubkey ) pt } }
        }
        F → @ ?RecvData { F # RecvData 0 }
    }
}

// Receive one datagram and process it. Returns app data (with the sender's
// pubkey) for a transport packet; None for a handshake packet, a dropped
// packet, or a recv timeout — callers loop.
@ securedgram_recv * SecureNode n i max → ?RecvData {
    : !UdpPacket NetErr rr ( udp_recv_from . n sock max )
    ^ ?? rr {
        T pkt → {
            : i len ( vec_len [u] . pkt data )
            : i ty ? > len 0 ?? ( vec_get [u] . pkt data 0 ) { T x → # i x F → 0 } - 0 1
            : ?RecvData out ? == ty 1 { ( __handle_init n . pkt peer . pkt data ) @ ?RecvData { F # RecvData 0 } }
            ? == ty 2 { ( __handle_resp n . pkt peer . pkt data ) @ ?RecvData { F # RecvData 0 } }
            ? == ty 4 { ( __handle_data n . pkt peer . pkt data ) }
            @ ?RecvData { F # RecvData 0 }
            ( udp_packet_free pkt )
            out
        }
        F _ → @ ?RecvData { F # RecvData 0 }
    }
}

@ __peer_free * PeerState p → v {
    ( vec_free [u] . p pubkey )
    ( string_free . p ehost )
    ? != # i . p hs 0 { ( noise_free # *Handshake . p hs ) } {}
    ? != # i . p session 0 { ( session_free # *NoiseSession . p session ) } {}
    ( nurl_free # s p )
}

@ securedgram_close * SecureNode n → v {
    : i cnt ( vec_len [s] . n peers )
    : ~ i k 0
    ~ < k cnt {
        : s pp ?? ( vec_get [s] . n peers k ) { T x → x F → # s 0 }
        ? != # i pp 0 { ( __peer_free # *PeerState pp ) } {}
        = k + k 1
    }
    ( vec_free [s] . n peers )
    ( udp_close . n sock )
    ( vec_free [u] . n s_priv )
    ( vec_free [u] . n s_pub )
    ( vec_free [u] . n psk )
    ( nurl_free # s n )
}
