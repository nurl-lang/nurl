// stdlib/net/relay.nu — DERP-style dumb relay for §7.4 Phase 2.
//
// When two peers can't open a direct path (symmetric NAT / CGNAT — see
// net/nat.nu's probe), they reach each other through a relay. The relay is
// deliberately DUMB: Phase 0 (net/securedgram) already encrypts end-to-end,
// so the relay only forwards OPAQUE datagrams addressed by the destination's
// public key — it never decrypts, and never needs the session keys.
//
// Both peers DIAL OUT to the relay over a long-lived TCP connection (a NAT'd
// peer can't accept inbound, but it can hold a connection open), register
// their pubkey, then send/receive {peer_pubkey, opaque_bytes} frames. The
// relay keeps a pubkey → connection table and forwards.
//
// Wire framing (length-prefixed, binary):
//   [type:1][len:4 BE][body]
//     type 1 REGISTER  body = pubkey(32)                  peer → relay
//     type 2 FORWARD   body = dest_pubkey(32) ++ payload  peer → relay
//     type 3 DELIVER   body = src_pubkey(32)  ++ payload  relay → peer
//     type 4 KEEPALIVE body = (empty)                     either way
//     type 5 GJOIN     body = group_id(32)                peer → relay
//     type 6 GLEAVE    body = group_id(32)                peer → relay
//     type 7 GSEND     body = group_id(32) ++ payload     peer → relay
//
// GROUP MULTICAST (broadcast to your own group): members JOIN a 32-byte
// group id; a GSEND fans the OPAQUE payload to every other member of that
// group as an ordinary DELIVER (src = sender's pubkey). One uplink frame,
// N downlinks — the bandwidth shape mobile audio/broadcast needs, with the
// relay still dumb (group_id → connection set, no decryption). The payload
// is whatever the app puts there: a distributed-compute task or an
// Opus-encoded audio packet, E2E-encrypted with the group key.
//
// The frame codec is pure and deterministic (offline-testable). The
// server/client wrappers add TCP I/O; the per-conn handler runs as a fiber
// (tcp_read_chunk / tcp_write_all are reactor-aware), matching the
// server_run_async idiom in ext/http_server.nu. Path-upgrade (start relayed,
// punch in the background, promote to direct, demote when direct goes quiet)
// is wired at the transport seam in Phase 4 — this module is the relay leg.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/async.nu`

// runtime client dial (the listen/accept/read/write/close ops are nurlc
// builtins reached via std/net.nu; only the dial needs an extern decl).
& `libc` @ nurl_tcp_connect s host i port → i

// ── frame types ──────────────────────────────────────────────────
@ relay_reg    → i { ^ 1 }
@ relay_fwd    → i { ^ 2 }
@ relay_del    → i { ^ 3 }
@ relay_ka     → i { ^ 4 }
@ relay_gjoin  → i { ^ 5 }
@ relay_gleave → i { ^ 6 }
@ relay_gsend  → i { ^ 7 }

@ __relay_max → i { ^ 131072 }   // reject frames larger than this (DoS guard)

@ __rcpy ( Vec u ) v → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] ( vec_len [u] v ) )
    ( vec_extend [u] o v )
    ^ o
}

@ __rveq ( Vec u ) a ( Vec u ) b → b {
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

// ── frame codec ──────────────────────────────────────────────────

: RelayFrame {
    i ftype
    ( Vec u ) body
}
@ relay_frame_free RelayFrame fr → v { ( vec_free [u] . fr body ) }

@ __frame i ftype ( Vec u ) body → ( Vec u ) {
    : ( Vec u ) f ( vec_new [u] )
    ( vec_push [u] f # u ftype )
    ( bytes_push_u32_be f # u32 ( vec_len [u] body ) )
    ( vec_extend [u] f body )
    ^ f
}

@ relay_build_register ( Vec u ) pubkey → ( Vec u ) { ^ ( __frame ( relay_reg ) pubkey ) }
@ relay_build_keepalive → ( Vec u ) {
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) f ( __frame ( relay_ka ) empty )
    ( vec_free [u] empty )
    ^ f
}

@ __frame_addressed i ftype ( Vec u ) pk ( Vec u ) payload → ( Vec u ) {
    : ( Vec u ) body ( vec_new [u] )
    ( vec_extend [u] body pk )
    ( vec_extend [u] body payload )
    : ( Vec u ) f ( __frame ftype body )
    ( vec_free [u] body )
    ^ f
}
@ relay_build_forward ( Vec u ) dest_pk ( Vec u ) payload → ( Vec u ) { ^ ( __frame_addressed ( relay_fwd ) dest_pk payload ) }
@ relay_build_deliver ( Vec u ) src_pk ( Vec u ) payload → ( Vec u ) { ^ ( __frame_addressed ( relay_del ) src_pk payload ) }

@ relay_build_group_join  ( Vec u ) group_id → ( Vec u ) { ^ ( __frame ( relay_gjoin ) group_id ) }
@ relay_build_group_leave ( Vec u ) group_id → ( Vec u ) { ^ ( __frame ( relay_gleave ) group_id ) }
@ relay_build_group_send  ( Vec u ) group_id ( Vec u ) payload → ( Vec u ) { ^ ( __frame_addressed ( relay_gsend ) group_id payload ) }

// First 32 bytes of a FORWARD/DELIVER body = the peer pubkey.
@ relay_body_pk ( Vec u ) body → ( Vec u ) {
    : ( Vec u ) pk ( vec_with_cap [u] 32 )
    : ~ i k 0
    ~ < k 32 { ?? ( vec_get [u] body k ) { T b → ( vec_push [u] pk b ) F → {} } = k + k 1 }
    ^ pk
}
// Remaining bytes = the opaque payload.
@ relay_body_payload ( Vec u ) body → ( Vec u ) {
    : i n ( vec_len [u] body )
    : ( Vec u ) pl ( vec_new [u] )
    : ~ i k 32
    ~ < k n { ?? ( vec_get [u] body k ) { T b → ( vec_push [u] pl b ) F → {} } = k + k 1 }
    ^ pl
}

// Parse one frame from the front of a buffer. None if incomplete / oversize.
@ relay_parse ( Vec u ) buf → ?RelayFrame {
    : i n ( vec_len [u] buf )
    ? < n 5 { ^ @ ?RelayFrame { F # RelayFrame 0 } } {}
    : i ftype ?? ( vec_get [u] buf 0 ) { T x → # i x F → -1 }
    : i len ?? ( bytes_read_u32_be buf 1 ) { T x → # i x F → -1 }
    ? > len ( __relay_max ) { ^ @ ?RelayFrame { F # RelayFrame 0 } } {}
    ? < n + 5 len { ^ @ ?RelayFrame { F # RelayFrame 0 } } {}
    : ( Vec u ) body ( vec_with_cap [u] len )
    : ~ i k 0
    ~ < k len { ?? ( vec_get [u] buf + 5 k ) { T b → ( vec_push [u] body b ) F → {} } = k + k 1 }
    ^ @ ?RelayFrame { T @ RelayFrame { ftype body } }
}

// ── streaming frame reader (TcpConn) ─────────────────────────────

@ __read_exact TcpConn c i n → ?( Vec u ) {
    : ( Vec u ) buf ( vec_with_cap [u] n )
    : ~ b fail F
    : ~ i got 0
    ~ & ! fail < got n {
        : !( Vec u ) NetErr r ( tcp_read_chunk c - n got )
        ?? r {
            T chunk → {
                : i cn ( vec_len [u] chunk )
                ? == cn 0 { = fail T } { ( vec_extend [u] buf chunk ) = got + got cn }
                ( vec_free [u] chunk )
            }
            F _ → { = fail T }
        }
    }
    ? fail { ( vec_free [u] buf ) ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    ^ @ ?( Vec u ) { T buf }
}

@ relay_read_frame TcpConn c → ?RelayFrame {
    : ~ ?RelayFrame out @ ?RelayFrame { F # RelayFrame 0 }
    : ?( Vec u ) hdr ( __read_exact c 5 )
    ?? hdr {
        T h → {
            : i ftype ?? ( vec_get [u] h 0 ) { T x → # i x F → -1 }
            : i len ?? ( bytes_read_u32_be h 1 ) { T x → # i x F → -1 }
            ( vec_free [u] h )
            ? & >= len 0 <= len ( __relay_max ) {
                : ?( Vec u ) bd ( __read_exact c len )
                ?? bd {
                    T body → { = out @ ?RelayFrame { T @ RelayFrame { ftype body } } }
                    F → {}
                }
            } {}
        }
        F → {}
    }
    ^ out
}

// ════════════════════════════════════════════════════════════════
// Relay SERVER — pubkey → connection table, opaque forwarding.
// ════════════════════════════════════════════════════════════════

: RelayEntry {
    ( Vec u ) pubkey
    TcpConn conn
    i live       // 1 = registered + connected, 0 = gone
    i sending    // 1 = a forward write to this conn is in flight (write lock)
}

: GroupEntry {
    ( Vec u ) gid       // 32-byte group id
    ( Vec s ) members   // *RelayEntry, NON-owning (entries owned via clients)
}

: RelayServer {
    TcpListener lst
    ( Vec s ) clients   // *RelayEntry
    ( Vec s ) groups    // *GroupEntry
}

@ relay_server_start s host i port → !RelayServer NetErr {
    : !TcpListener NetErr lr ( tcp_listen host port )
    : !RelayServer NetErr out ?? lr {
        T l → @ !RelayServer NetErr { T @ RelayServer { l ( vec_new [s] ) ( vec_new [s] ) } }
        F e → @ !RelayServer NetErr { F e }
    }
    ^ out
}

@ __relay_register_conn *RelayServer rs TcpConn c ( Vec u ) pk → s {
    : *RelayEntry e # *RelayEntry ( nurl_alloc Z RelayEntry )
    = . e pubkey ( __rcpy pk )
    = . e conn c
    = . e live 1
    = . e sending 0
    ( vec_push [s] . rs clients # s e )
    ^ # s e
}

@ __relay_find *RelayServer rs ( Vec u ) pk → s {
    : i n ( vec_len [s] . rs clients )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k n {
        : s pp ?? ( vec_get [s] . rs clients k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *RelayEntry e # *RelayEntry pp
            ? & == . e live 1 ( __rveq . e pubkey pk ) { = found pp } {}
        } {}
        = k + k 1
    }
    ^ found
}

// Serialized write to a destination conn: under cooperative scheduling the
// check-and-set is atomic (no yield between), and tcp_write_all may park —
// other forwarders to the same conn spin-yield until the lock clears, so
// frames never interleave on a shared destination.
@ __relay_send_locked *RelayEntry de ( Vec u ) frame → v {
    ~ == . de sending 1 { ( yield ) }
    = . de sending 1
    ?? ( tcp_write_all . de conn frame ) { T _ → {} F _ → { = . de live 0 } }
    = . de sending 0
}

// ── group multicast tables ───────────────────────────────────────

@ __relay_group_find *RelayServer rs ( Vec u ) gid → s {
    : i n ( vec_len [s] . rs groups )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k n {
        : s pp ?? ( vec_get [s] . rs groups k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *GroupEntry g # *GroupEntry pp
            ? ( __rveq . g gid gid ) { = found pp } {}
        } {}
        = k + k 1
    }
    ^ found
}

@ __relay_group_ensure *RelayServer rs ( Vec u ) gid → s {
    : s ex ( __relay_group_find rs gid )
    ? != # i ex 0 { ^ ex } {}
    : *GroupEntry g # *GroupEntry ( nurl_alloc Z GroupEntry )
    = . g gid ( __rcpy gid )
    = . g members ( vec_new [s] )
    ( vec_push [s] . rs groups # s g )
    ^ # s g
}

// Remove an entry pointer from a group's member list (compacting copy).
@ __grp_remove_member *GroupEntry g s entry_ptr → v {
    : i n ( vec_len [s] . g members )
    : ( Vec s ) keep ( vec_new [s] )
    : ~ i k 0
    ~ < k n {
        : s mp ?? ( vec_get [s] . g members k ) { T x → x F → # s 0 }
        ? != # i mp entry_ptr { ( vec_push [s] keep mp ) } {}
        = k + k 1
    }
    ( vec_free [s] . g members )
    = . g members keep
}

@ __relay_group_join *RelayServer rs s entry_ptr ( Vec u ) gid → v {
    ? == # i entry_ptr 0 { ^ v } {}
    : s gp ( __relay_group_ensure rs gid )
    : *GroupEntry g # *GroupEntry gp
    : i n ( vec_len [s] . g members )
    : ~ b have F : ~ i k 0
    ~ & ! have < k n {
        : s mp ?? ( vec_get [s] . g members k ) { T x → x F → # s 0 }
        ? == # i mp entry_ptr { = have T } {}
        = k + k 1
    }
    ? ! have { ( vec_push [s] . g members entry_ptr ) } {}
}

@ __relay_group_leave *RelayServer rs s entry_ptr ( Vec u ) gid → v {
    : s gp ( __relay_group_find rs gid )
    ? == # i gp 0 { ^ v } {}
    : *GroupEntry g # *GroupEntry gp
    ( __grp_remove_member g entry_ptr )
}

@ __relay_drop_from_groups *RelayServer rs s entry_ptr → v {
    : i gn ( vec_len [s] . rs groups )
    : ~ i gi 0
    ~ < gi gn {
        : s gp ?? ( vec_get [s] . rs groups gi ) { T x → x F → # s 0 }
        ? != # i gp 0 { : *GroupEntry g # *GroupEntry gp ( __grp_remove_member g entry_ptr ) } {}
        = gi + gi 1
    }
}

// Fan an opaque payload to every live member of a group except the sender,
// as a DELIVER carrying the sender's pubkey as src. One uplink → N down.
@ __relay_group_fanout *RelayServer rs s sender_ptr ( Vec u ) gid ( Vec u ) payload → v {
    ? == # i sender_ptr 0 { ^ v } {}
    : s gp ( __relay_group_find rs gid )
    ? == # i gp 0 { ^ v } {}
    : *GroupEntry g # *GroupEntry gp
    : *RelayEntry se # *RelayEntry sender_ptr
    : i n ( vec_len [s] . g members )
    : ~ i k 0
    ~ < k n {
        : s mp ?? ( vec_get [s] . g members k ) { T x → x F → # s 0 }
        ? & != # i mp 0 != # i mp sender_ptr {
            : *RelayEntry de # *RelayEntry mp
            ? == . de live 1 {
                : ( Vec u ) out ( relay_build_deliver . se pubkey payload )
                ( __relay_send_locked de out )
                ( vec_free [u] out )
            } {}
        } {}
        = k + k 1
    }
}

@ __relay_handle_conn *RelayServer rs TcpConn c → v {
    : ~ s self_entry # s 0
    : ~ b done F
    ~ ! done {
        : ?RelayFrame fr ( relay_read_frame c )
        ?? fr {
            T f → {
                : i ft . f ftype
                ? == ft ( relay_reg ) {
                    = self_entry ( __relay_register_conn rs c . f body )
                } {}
                ? == ft ( relay_fwd ) {
                    ? != # i self_entry 0 {
                        : *RelayEntry se # *RelayEntry self_entry
                        : ( Vec u ) dst ( relay_body_pk . f body )
                        : ( Vec u ) pl ( relay_body_payload . f body )
                        : s dp ( __relay_find rs dst )
                        ? != # i dp 0 {
                            : *RelayEntry de # *RelayEntry dp
                            : ( Vec u ) out ( relay_build_deliver . se pubkey pl )
                            ( __relay_send_locked de out )
                            ( vec_free [u] out )
                        } {}
                        ( vec_free [u] dst )
                        ( vec_free [u] pl )
                    } {}
                } {}
                ? == ft ( relay_gjoin ) { ( __relay_group_join rs self_entry . f body ) } {}
                ? == ft ( relay_gleave ) { ( __relay_group_leave rs self_entry . f body ) } {}
                ? == ft ( relay_gsend ) {
                    ? != # i self_entry 0 {
                        : ( Vec u ) gid ( relay_body_pk . f body )
                        : ( Vec u ) pl ( relay_body_payload . f body )
                        ( __relay_group_fanout rs self_entry gid pl )
                        ( vec_free [u] gid )
                        ( vec_free [u] pl )
                    } {}
                } {}
                ( relay_frame_free f )
            }
            F → { = done T }
        }
    }
    ? != # i self_entry 0 {
        : *RelayEntry se # *RelayEntry self_entry
        = . se live 0
        ( __relay_drop_from_groups rs self_entry )
    } {}
    ( tcp_close_conn c )
}

@ __relay_accept_loop *RelayServer rs → v {
    : TcpListener lst . rs lst
    : ~ b done F
    ~ ! done {
        : !TcpConn NetErr cr ( tcp_accept lst )
        ?? cr {
            T c → { ( spawn \ → v { ( __relay_handle_conn rs c ) } ) }
            F e → { = done T }
        }
    }
}

// Run the relay: one accept fiber, a handler fiber per connection. Blocks
// in runtime_run until the listener is closed (relay_server_stop) and every
// in-flight conn fiber drains.
@ relay_server_run *RelayServer rs → v {
    ( tcp_listener_retain . rs lst )
    : ( @ v ) accept_fiber \ → v { ( __relay_accept_loop rs ) }
    ( spawn accept_fiber )
    ( runtime_run )
    ( tcp_listener_release . rs lst )
    : *u accept_env # *u accept_fiber 1
    ( nurl_free # s accept_env )
}

@ relay_server_stop *RelayServer rs → v { ( tcp_close_listener . rs lst ) }

@ relay_server_free *RelayServer rs → v {
    : i n ( vec_len [s] . rs clients )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . rs clients k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *RelayEntry e # *RelayEntry pp
            ( vec_free [u] . e pubkey )
            ( nurl_free # s e )
        } {}
        = k + k 1
    }
    ( vec_free [s] . rs clients )
    : i gn ( vec_len [s] . rs groups )
    : ~ i gi 0
    ~ < gi gn {
        : s gp ?? ( vec_get [s] . rs groups gi ) { T x → x F → # s 0 }
        ? != # i gp 0 {
            : *GroupEntry g # *GroupEntry gp
            ( vec_free [u] . g gid )
            ( vec_free [s] . g members )
            ( nurl_free # s g )
        } {}
        = gi + gi 1
    }
    ( vec_free [s] . rs groups )
    ( nurl_free # s rs )
}

// ════════════════════════════════════════════════════════════════
// Relay CLIENT — dial, register, send/recv opaque datagrams.
// ════════════════════════════════════════════════════════════════

: RelayClient {
    TcpConn conn
}

: RelayMsg {
    ( Vec u ) src
    ( Vec u ) payload
}
@ relay_msg_free RelayMsg m → v { ( vec_free [u] . m src ) ( vec_free [u] . m payload ) }

@ relay_dial s host i port → !RelayClient NetErr {
    : i raw ( nurl_tcp_connect host port )
    ? == raw 0 { ^ @ !RelayClient NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 {
        ( nurl_tcp_close raw )
        ^ @ !RelayClient NetErr { F ( __net_err_of ek ) }
    } {}
    : TcpConn c @ TcpConn { # s raw }
    ^ @ !RelayClient NetErr { T @ RelayClient { c } }
}

@ relay_register RelayClient rc ( Vec u ) pubkey → !v NetErr {
    : ( Vec u ) f ( relay_build_register pubkey )
    : !v NetErr r ( tcp_write_all . rc conn f )
    ( vec_free [u] f )
    ^ r
}

@ relay_send RelayClient rc ( Vec u ) dest_pk ( Vec u ) payload → !v NetErr {
    : ( Vec u ) f ( relay_build_forward dest_pk payload )
    : !v NetErr r ( tcp_write_all . rc conn f )
    ( vec_free [u] f )
    ^ r
}

// Join / leave a 32-byte group on the relay (server fans GSEND to members).
@ relay_group_join RelayClient rc ( Vec u ) group_id → !v NetErr {
    : ( Vec u ) f ( relay_build_group_join group_id )
    : !v NetErr r ( tcp_write_all . rc conn f )
    ( vec_free [u] f )
    ^ r
}
@ relay_group_leave RelayClient rc ( Vec u ) group_id → !v NetErr {
    : ( Vec u ) f ( relay_build_group_leave group_id )
    : !v NetErr r ( tcp_write_all . rc conn f )
    ( vec_free [u] f )
    ^ r
}

// Broadcast an opaque payload to every other member of a group. One uplink
// frame; the relay fans it out. Payload is whatever the app sends — a
// distributed-compute task or an Opus audio packet (E2E group-key encrypted).
@ relay_broadcast RelayClient rc ( Vec u ) group_id ( Vec u ) payload → !v NetErr {
    : ( Vec u ) f ( relay_build_group_send group_id payload )
    : !v NetErr r ( tcp_write_all . rc conn f )
    ( vec_free [u] f )
    ^ r
}

@ relay_keepalive RelayClient rc → !v NetErr {
    : ( Vec u ) f ( relay_build_keepalive )
    : !v NetErr r ( tcp_write_all . rc conn f )
    ( vec_free [u] f )
    ^ r
}

// Block until a DELIVER frame arrives; returns its {src_pubkey, payload}.
// Non-DELIVER frames (keepalive echoes) are skipped. None on disconnect.
@ relay_recv RelayClient rc → ?RelayMsg {
    : ~ ?RelayMsg out @ ?RelayMsg { F # RelayMsg 0 }
    : ~ b done F
    ~ ! done {
        : ?RelayFrame fr ( relay_read_frame . rc conn )
        ?? fr {
            T f → {
                ? == . f ftype ( relay_del ) {
                    : ( Vec u ) src ( relay_body_pk . f body )
                    : ( Vec u ) pl ( relay_body_payload . f body )
                    = out @ ?RelayMsg { T @ RelayMsg { src pl } }
                    = done T
                } {}
                ( relay_frame_free f )
            }
            F → { = done T }
        }
    }
    ^ out
}

@ relay_set_timeout RelayClient rc i ms → v { ( tcp_set_timeout . rc conn ms ) }
@ relay_close RelayClient rc → v { ( tcp_close_conn . rc conn ) }
