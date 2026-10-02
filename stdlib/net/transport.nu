// stdlib/net/transport.nu — the flat pubkey-addressed overlay (§7.4 Phase 4).
//
// THE SEAM. Everything above (SWIM, dchannel, cluster-RPC, a group-audio
// app) addresses peers by their static public key and calls:
//
//     transport_send(t, peer_pubkey, payload)     unicast
//     transport_broadcast(t, group_id, payload)   broadcast to a group
//     transport_recv(t, max) → (src_pubkey, payload)
//
// …with no knowledge of NAT, relays, endpoints, or roaming. The payload is
// arbitrary opaque bytes — a distributed-compute task or an Opus audio
// packet — already E2E-encrypted by the layers below.
//
// Underneath, each peer rides one of two legs:
//   • DIRECT  — net/securedgram (encrypted UDP, roams across wifi↔cellular;
//               chunks big messages itself, so the two legs carry the same
//               16 MiB payloads — the MTU no longer picks the leg)
//   • RELAY   — net/relay (DERP-style dumb forwarder, opaque by pubkey)
//
// PATH POLICY (per peer): start RELAYED for instant connectivity, try a
// direct path in the background (hole punch + securedgram handshake), PROMOTE
// to direct the moment direct data arrives, and DEMOTE back to relay if the
// direct path goes quiet for too long (a mobile path dropped). That policy is
// a pure state machine (transport_note_direct / transport_tick / transport_pick)
// — deterministically testable — and the I/O wrappers just dispatch on it.
//
// Broadcast uses the relay's group multicast (one uplink → N downlinks), the
// bandwidth shape group audio needs.
//
// A Transport is a handle: every copy (a job node's, a membership loop's) is
// the same transport, and its last owner releases it — transport_free is an
// early release, optional. It does not close the legs it was opened over.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/crypto.nu`
$ `stdlib/net/securedgram.nu`
$ `stdlib/net/relay.nu`
$ `stdlib/core/rcbox.nu`

// ── path modes ───────────────────────────────────────────────────
@ mode_none → i { ^ 0 }

@ mode_relay → i { ^ 1 }

@ mode_direct → i { ^ 2 }

@ __tcpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

@ __tveq ( Vec u ) a ( Vec u ) b → b {
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

// ── per-peer path state ──────────────────────────────────────────

: PeerPath {
    ( Vec u ) pubkey
    i mode  // 0 none, 1 relay, 2 direct
    i direct_known  // 1 once a direct session has delivered data
    i idle  // consecutive direct-idle ticks
}

// ── pure path-policy state machine (deterministically testable) ──

// A direct datagram from this peer arrived → promote to direct, reset idle.
@ transport_note_direct * PeerPath pp → v {
    = . pp direct_known 1
    = . pp mode 2
    = . pp idle 0
}

// One policy tick. `saw_direct` = 1 if direct traffic was seen since the last
// tick. After `idle_limit` silent ticks on a direct path, demote to relay —
// the direct (often mobile) path has gone quiet; relay re-establishes reach.
@ transport_tick * PeerPath pp i saw_direct i idle_limit → v {
    ? == . pp mode 2 {
        ? == saw_direct 1 { = . pp idle 0 } {
            = . pp idle + . pp idle 1
            ? >= . pp idle idle_limit {
                = . pp mode 1
                = . pp direct_known 0
                = . pp idle 0
            } {}
        }
    } {}
}

// Which leg to send on right now (given whether a relay is configured).
@ transport_pick * PeerPath pp i has_relay → i {
    ? == . pp mode 2 { ^ 2 } {}
    ? == has_relay 1 { ^ 1 } {}
    ^ 0
}

// ── transport handle ─────────────────────────────────────────────

: TransportImpl {
    s node  // a SecureNode (as its word) for the direct leg, or 0 if direct disabled
    RelayClient relay  // relay client (valid only when has_relay == 1)
    i has_relay
    ( Vec s ) peers  // *PeerPath
}

// A Transport is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: Transport { s ctl }

@ Transport_share Transport h → Transport { ^ @ Transport { # s ( rcbox_share # i . h ctl ) } }

@ Transport_drop sink Transport h → v {
    ( mem_forget h )
    ( rcbox_release [TransportImpl] # i . h ctl )
}

@ __Transport_ptr Transport h → *TransportImpl { ^ ( rcbox_ptr [TransportImpl] # i . h ctl ) }

// The peer paths are raw blocks the Vec only points at: releasing them is
// the transport's own drop, run by its last owner (the Vec goes after it).
// The legs are the caller's: the secure node and the relay connection are
// closed by whoever opened them.
% Drop TransportImpl {
    @ drop TransportImpl t → v {
        : i n ( vec_len [s] . t peers )
        : ~ i k 0
        ~ < k n {
            : s pp ?? ( vec_get [s] . t peers k ) { T x → x F → # s 0 }
            ? != # i pp 0 {
                : *PeerPath p # *PeerPath pp
                ( vec_free [u] . p pubkey )
                ( nurl_free # s p )
            } {}
            = k + k 1
        }
    }
}

: TransportMsg {
    ( Vec u ) src
    ( Vec u ) payload
}

// Let go of `m` now rather than at the end of its owner's scope.
@ transport_msg_free sink TransportMsg m → v {}

// Open over both legs. `node` may be 0 (relay-only peer with no UDP path).
@ transport_open s node RelayClient relay i has_relay → Transport {
    : i t__box ( rcbox_zero [TransportImpl] )
    : *TransportImpl t ( rcbox_ptr [TransportImpl] t__box )
    = . t node node
    = . t relay relay
    = . t has_relay has_relay
    = . t peers ( vec_new [s] )
    ^ @ Transport { # s t__box }
}

@ __tp_find * TransportImpl t ( Vec u ) pk → s {
    : i n ( vec_len [s] . t peers )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k n {
        : s pp ?? ( vec_get [s] . t peers k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *PeerPath p # *PeerPath pp
            ? ( __tveq . p pubkey pk ) { = found pp } {}
        } {}
        = k + k 1
    }
    ^ found
}

// No transport: for a node whose messages ride another bus (dist/sim's
// simulator, an offline test) and which never sends through this one.
@ transport_none → Transport { ^ @ Transport { # s 0 } }

// Register a peer; it starts on the relay leg (or none if no relay).
@ transport_add_peer Transport t__h ( Vec u ) pubkey → v {
    : *TransportImpl t ( __Transport_ptr t__h )
    ? != # i ( __tp_find t pubkey ) 0 { ^ v } {}
    : *PeerPath p # *PeerPath ( nurl_alloc Z PeerPath )
    = . p pubkey ( __tcpy pubkey )
    = . p mode ? == . t has_relay 1 1 0
    = . p direct_known 0
    = . p idle 0
    ( vec_push [s] . t peers # s p )
}

// Begin a direct path to a peer at a known endpoint (e.g. a candidate from
// the rendezvous service): register it with securedgram and start the
// handshake. Stays on relay until the first direct datagram promotes it.
@ transport_try_direct Transport t__h ( Vec u ) pubkey s host i port → !v NetErr {
    : *TransportImpl t ( __Transport_ptr t__h )
    ? == # i . t node 0 { ^ @ !v NetErr { F # NetErr NetOther } } {}
    : SecureNode node # SecureNode . t node
    ( securedgram_add_peer node pubkey host port )
    ^ ( securedgram_connect node pubkey )
}

// Send an opaque payload to a peer over whichever leg is currently chosen.
@ transport_send Transport t__h ( Vec u ) pubkey ( Vec u ) payload → !v NetErr {
    : *TransportImpl t ( __Transport_ptr t__h )
    : s pp ( __tp_find t pubkey )
    // Unknown peer: no direct path is known (it was never added / no
    // candidate), so reach it over the relay if one is configured. The seam's
    // contract is "address ANY pubkey" — requiring transport_add_peer first
    // would break sending to a peer learned at runtime (e.g. a job submitter
    // replying to a result, or dispatch to a key's current owner).
    ? == # i pp 0 {
        ? == . t has_relay 1 { ^ ( relay_send . t relay pubkey payload ) } {}
        ^ @ !v NetErr { F # NetErr NetOther }
    } {}
    : *PeerPath p # *PeerPath pp
    : ~ i leg ( transport_pick p . t has_relay )
    // SIZE picks the leg too, not just liveness. The direct leg is
    // datagrams with no retransmission: it chunks under the MTU, but
    // one lost chunk loses the message, so past securedgram_max_msg a
    // direct send is a bad bet the relay leg (TCP — segmentation and
    // retransmission included) simply does not make. Routing it there
    // is a decision, not a failure; with no relay the direct leg still
    // gets the attempt and refuses it honestly.
    ? & & == leg 2 == . t has_relay 1
    > ( vec_len [u] payload ) ( securedgram_max_msg ) { = leg 1 } {}
    ? == leg 2 {
        : SecureNode node # SecureNode . t node
        ^ ( securedgram_send node pubkey payload )
    } {}
    ? == leg 1 { ^ ( relay_send . t relay pubkey payload ) } {}
    ^ @ !v NetErr { F # NetErr NetOther }
}

// Broadcast to a group via the relay's multicast fanout (one uplink → N).
@ transport_broadcast Transport t__h ( Vec u ) group_id ( Vec u ) payload → !v NetErr {
    : *TransportImpl t ( __Transport_ptr t__h )
    ? == . t has_relay 1 { ^ ( relay_broadcast . t relay group_id payload ) } {}
    ^ @ !v NetErr { F # NetErr NetOther }
}

// Join / leave a multicast group on the relay.
@ transport_group_join Transport t__h ( Vec u ) group_id → !v NetErr {
    : *TransportImpl t ( __Transport_ptr t__h )
    ? == . t has_relay 1 { ^ ( relay_group_join . t relay group_id ) } {}
    ^ @ !v NetErr { F # NetErr NetOther }
}

@ transport_group_leave Transport t__h ( Vec u ) group_id → !v NetErr {
    : *TransportImpl t ( __Transport_ptr t__h )
    ? == . t has_relay 1 { ^ ( relay_group_leave . t relay group_id ) } {}
    ^ @ !v NetErr { F # NetErr NetOther }
}

// Receive one message, polling the direct leg first (promoting the peer's
// path on direct data) then the relay leg. None if neither had a message
// this round — callers loop.
@ transport_recv Transport t__h i max → ?TransportMsg {
    : *TransportImpl t ( __Transport_ptr t__h )
    : ~ ? TransportMsg out @ ?TransportMsg { F # TransportMsg 0 }
    : ~ b got F
    ? != # i . t node 0 {
        : SecureNode node # SecureNode . t node
        ?? ( securedgram_recv node max ) {
            T rd → {
                : s pp ( __tp_find t . rd peer_pubkey )
                ? != # i pp 0 { : *PeerPath p # *PeerPath pp ( transport_note_direct p ) } {}
                = out @ ?TransportMsg { T @ TransportMsg { ( __tcpy . rd peer_pubkey ) ( __tcpy . rd data ) } }
                = got T
            }
            F → {}
        }
    } {}
    ? & ! got == . t has_relay 1 {
        ?? ( relay_recv . t relay ) {
            T rm → {
                = out @ ?TransportMsg { T @ TransportMsg { ( __tcpy . rm src ) ( __tcpy . rm payload ) } }
                = got T
            }
            F → {}
        }
    } {}
    ^ out
}

// Let go of `t` now rather than at the end of its owner's scope.
@ transport_free sink Transport t → v {}
