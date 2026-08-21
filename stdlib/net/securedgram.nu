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
//
// INSIDE the AEAD, every transport payload carries one framing byte —
// the answer to "UDP does no MTU chunking" that kept the unikernel
// worker pinned to the relay leg (plan B10's v1 decision, now lifted):
//   [0][payload…]                                whole message
//   [1][msg_id:4][idx:2][cnt:2][chunk bytes…]     one chunk of a big one
// A message longer than securedgram_chunk_bytes is split; the receiver
// reassembles and securedgram_recv returns only WHOLE messages. The
// chunk header is inside the AEAD, so a forged chunk cannot enter a
// reassembly; what a hostile peer can still do is bounded on purpose:
// at most __sdg_max_partials messages reassemble per peer (oldest is
// evicted), a message is capped at securedgram_max_msg, and a chunk
// whose length or indices disagree with its header is dropped. Loss
// semantics stay datagram: a lost chunk is a lost MESSAGE, never a
// stall — there is no ARQ here, the layers above already own retries.
// (Wire format bump: both ends must speak the framing byte.)
//
// WHAT CHUNKING DOES AND DOES NOT BUY, stated because the difference
// decides which leg a payload should take. It removes the MTU as a
// size limit. It does NOT add reliability: with no ARQ, ONE lost
// chunk loses the whole message, and the chance of that grows with
// the chunk count — a thousand-chunk message on a path that drops one
// datagram in a thousand essentially never arrives. Nor does it make
// a burst fit: chunks go out back to back, so the receiver's socket
// buffer must hold whatever it has not drained yet (a receiver
// sitting in a recv loop drains as they land; one that sends first
// and reads afterwards does not, and FreeBSD's default UDP receive
// space is a fifth of Linux's — this is why the cap below is modest
// rather than the relay leg's 16 MiB). So: securedgram_max_msg is the
// size at which a direct datagram is still a REASONABLE bet, and
// net/transport routes anything larger over the relay leg, where TCP
// owns segmentation and retransmission. That is a routing decision,
// not an error.

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
    i tx_msg_id  // last chunked-message id sent to this peer
    ( Vec s ) partials  // *Partial — messages mid-reassembly, oldest first
}

// One message mid-reassembly. `chunks` holds a *ChunkBox per index
// (0 = not yet arrived) so out-of-order arrival needs no sorting and a
// duplicate is a filled slot, not a corruption. The box exists because
// a Vec handle is a by-value struct: parking one in a `( Vec s )` slot
// means boxing it, not casting it.
: ChunkBox {
    ( Vec u ) v
}

: Partial {
    i msg_id
    i cnt
    i got
    i bytes
    ( Vec s ) chunks
}

// The plaintext bytes one chunk carries. 1152 + the 9-byte inner
// header + the 13-byte wire header + the 16-byte AEAD tag + IP/UDP
// stays under 1200 — clear of the 1280 IPv6 floor and every MTU this
// project has met in the wild (a 1440-MTU path once blackholed
// package publishes).
@ securedgram_chunk_bytes → i { ^ 1152 }

// The biggest message this leg will send or reassemble: 256 KiB, i.e.
// 228 chunks. Chosen against loss rather than against the header's
// range — see the note above; the relay leg carries anything bigger
// and net/transport routes it there. A send past this is refused up
// front (NetWrite), never truncated and never half-sent.
@ securedgram_max_msg → i { ^ 262144 }

@ __sdg_max_partials → i { ^ 4 }

@ __partial_free * Partial q → v {
    : i n ( vec_len [s] . q chunks )
    : ~ i k 0
    ~ < k n {
        : s cp ?? ( vec_get [s] . q chunks k ) { T x → x F → # s 0 }
        ? != # i cp 0 {
            : *ChunkBox cbx # *ChunkBox cp
            ( vec_free [u] . cbx v )
            ( nurl_free cp )
        } {}
        = k + k 1
    }
    ( vec_free [s] . q chunks )
    ( nurl_free # s q )
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
    = . p tx_msg_id 0
    = . p partials ( vec_new [s] )
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

// Seal one inner frame and put it on the wire. BORROWS `inner`.
@ __send_inner * SecureNode n * PeerState p ( Vec u ) inner → v {
    : *NoiseSession sess # *NoiseSession . p session
    : ( Vec u ) ad ( vec_new [u] )
    : Sealed sealed ( session_seal sess ad inner )
    ( vec_free [u] ad )
    : ( Vec u ) pkt ( vec_new [u] )
    ( vec_push [u] pkt # u 4 )
    ( bytes_push_u32_be pkt # u32 . p remote_index )
    ( bytes_push_u64_be pkt # u64 . sealed counter )
    ( vec_extend [u] pkt . sealed ct )
    ( sealed_free sealed )
    ( __send_pkt n p pkt )
    ( vec_free [u] pkt )
}

@ securedgram_send * SecureNode n ( Vec u ) peer_pk ( Vec u ) data → !v NetErr {
    : s pp ( __find_pk n peer_pk )
    ? == # i pp 0 { ^ @ !v NetErr { F @ NetErr { NetOther } } } {}
    : *PeerState p # *PeerState pp
    ? == . p established 0 { ^ @ !v NetErr { F @ NetErr { NetOther } } } {}
    : i len ( vec_len [u] data )
    : i cb ( securedgram_chunk_bytes )
    ? <= len cb {
        // one datagram: [0][payload]
        : ( Vec u ) inner ( vec_with_cap [u] + len 1 )
        ( vec_push [u] inner # u 0 )
        ( vec_extend [u] inner data )
        ( __send_inner n p inner )
        ( vec_free [u] inner )
        ^ @ !v NetErr { T 0 }
    } {}
    ? > len ( securedgram_max_msg ) { ^ @ !v NetErr { F @ NetErr { NetWrite } } } {}
    = . p tx_msg_id + . p tx_msg_id 1
    : i msg_id & . p tx_msg_id 4294967295
    : i cnt / + len - cb 1 cb
    : ~ i idx 0
    ~ < idx cnt {
        : i off * idx cb
        : i take ? > + off cb len - len off cb
        : ( Vec u ) inner ( vec_with_cap [u] + take 9 )
        ( vec_push [u] inner # u 1 )
        ( bytes_push_u32_be inner # u32 msg_id )
        ( bytes_push_u16_be inner # u16 idx )
        ( bytes_push_u16_be inner # u16 cnt )
        : ~ i j 0
        ~ < j take { ( vec_push [u] inner # u ?? ( vec_get [u] data + off j ) { T x → # i x F → 0 } ) = j + j 1 }
        ( __send_inner n p inner )
        ( vec_free [u] inner )
        = idx + idx 1
    }
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
            ( __handle_inner p pt )
        }
        F → @ ?RecvData { F # RecvData 0 }
    }
}

// The framing byte inside the AEAD (see the header). CONSUMES `pt`.
@ __handle_inner * PeerState p ( Vec u ) pt → ?RecvData {
    : i len ( vec_len [u] pt )
    ? < len 1 { ( vec_free [u] pt ) ^ @ ?RecvData { F # RecvData 0 } } {}
    : i tag ?? ( vec_get [u] pt 0 ) { T x → # i x F → 255 }
    ? == tag 0 {
        : ( Vec u ) body ( __slc pt 1 - len 1 )
        ( vec_free [u] pt )
        ^ @ ?RecvData { T @ RecvData { ( __cpy . p pubkey ) body } }
    } {}
    ? != tag 1 { ( vec_free [u] pt ) ^ @ ?RecvData { F # RecvData 0 } } {}
    ? < len 10 { ( vec_free [u] pt ) ^ @ ?RecvData { F # RecvData 0 } } {}
    : i msg_id ( __sdg_u32 pt 1 )
    : i idx ?? ( bytes_read_u16_be pt 5 ) { T x → # i x F → 0 }
    : i cnt ?? ( bytes_read_u16_be pt 7 ) { T x → # i x F → 0 }
    : ( Vec u ) body ( __slc pt 9 - len 9 )
    ( vec_free [u] pt )
    : ?( Vec u ) whole ( __sdg_reasm p msg_id idx cnt body )
    ^ ?? whole {
        T w → @ ?RecvData { T @ RecvData { ( __cpy . p pubkey ) w } }
        F → @ ?RecvData { F # RecvData 0 }
    }
}

// Feed one authenticated chunk into the peer's reassembly. CONSUMES
// `body`. Returns the whole message when this chunk completed it.
// Every bound here is a refusal of a hostile-but-authentic peer's
// worst case, never a crash: a chunk that disagrees with its own
// header is dropped, and the partial table cannot grow past
// __sdg_max_partials in-flight messages (oldest evicted).
@ __sdg_reasm * PeerState p i msg_id i idx i cnt ( Vec u ) body → ?( Vec u ) {
    : i cb ( securedgram_chunk_bytes )
    : i blen ( vec_len [u] body )
    : i max_cnt / + ( securedgram_max_msg ) - cb 1 cb
    : ~ b bad F
    ? | < cnt 2 > cnt max_cnt { = bad T } {}
    ? >= idx cnt { = bad T } {}
    // every chunk but the last is exactly full; the last is 1..cb
    ? && < idx - cnt 1 != blen cb { = bad T } {}
    ? && == idx - cnt 1 | == blen 0 > blen cb { = bad T } {}
    ? bad { ( vec_free [u] body ) ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    // find (or open) the partial for this msg_id
    : ~ s qp # s 0
    : i qn ( vec_len [s] . p partials )
    : ~ i qk 0
    ~ & == # i qp 0 < qk qn {
        : s c ?? ( vec_get [s] . p partials qk ) { T x → x F → # s 0 }
        ? != # i c 0 { ? == . # *Partial c msg_id msg_id { = qp c } {} } {}
        = qk + qk 1
    }
    ? == # i qp 0 {
        ? >= qn ( __sdg_max_partials ) {
            // full: the OLDEST in-flight message pays for the new one
            : s old ?? ( vec_get [s] . p partials 0 ) { T x → x F → # s 0 }
            ? != # i old 0 { ( __partial_free # *Partial old ) } {}
            ( vec_remove [s] . p partials 0 )
        } {}
        : *Partial q # *Partial ( nurl_alloc Z Partial )
        = . q msg_id msg_id
        = . q cnt cnt
        = . q got 0
        = . q bytes 0
        = . q chunks ( vec_new [s] )
        : ~ i z 0
        ~ < z cnt { ( vec_push [s] . q chunks # s 0 ) = z + z 1 }
        ( vec_push [s] . p partials # s q )
        = qp # s q
    } {}
    : *Partial q # *Partial qp
    // a chunk whose cnt disagrees with the one that opened the entry
    // is not the same message, whatever its id claims
    ? != . q cnt cnt { ( vec_free [u] body ) ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : s slot ?? ( vec_get [s] . q chunks idx ) { T x → x F → # s 0 }
    ? != # i slot 0 { ( vec_free [u] body ) ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : *ChunkBox nb # *ChunkBox ( nurl_alloc Z ChunkBox )
    = . nb v body
    : b _w ( vec_set [s] . q chunks idx # s nb )
    = . q got + . q got 1
    = . q bytes + . q bytes blen
    ? < . q got . q cnt { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    // complete: splice in index order, drop the partial
    : ( Vec u ) whole ( vec_with_cap [u] . q bytes )
    : ~ i a 0
    ~ < a cnt {
        : s cp ?? ( vec_get [s] . q chunks a ) { T x → x F → # s 0 }
        ? != # i cp 0 {
            : *ChunkBox cbx # *ChunkBox cp
            ( vec_extend [u] whole . cbx v )
        } {}
        = a + a 1
    }
    // remove q from the partials list, then free it
    : i pn2 ( vec_len [s] . p partials )
    : ~ i r 0
    : ~ i found -1
    ~ & < r pn2 < found 0 {
        : s c2 ?? ( vec_get [s] . p partials r ) { T x → x F → # s 0 }
        ? == c2 qp { = found r } {}
        = r + r 1
    }
    ? >= found 0 { ( vec_remove [s] . p partials found ) } {}
    ( __partial_free q )
    ^ @ ?( Vec u ) { T whole }
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
    : i qn ( vec_len [s] . p partials )
    : ~ i qk 0
    ~ < qk qn {
        : s qp ?? ( vec_get [s] . p partials qk ) { T x → x F → # s 0 }
        ? != # i qp 0 { ( __partial_free # *Partial qp ) } {}
        = qk + qk 1
    }
    ( vec_free [s] . p partials )
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
