// stdlib/net/rendezvous.nu — signaling-only control plane (§7.4 Phase 3).
//
// Peers are addressed by static public key, but to open a DIRECT path a peer
// must learn WHERE another peer currently is (its gathered candidates from
// net/nat) and which relay it falls back to. The rendezvous service is that
// directory: a peer REGISTERs (pubkey → candidate endpoints + chosen relay),
// and any peer can LOOKUP another's record by pubkey. The looked-up endpoints
// feed transport_try_direct (hole punch + securedgram handshake); the relay
// is the guaranteed fallback.
//
// This is CONTROL plane only — NO application data, NO media ever flows here.
// It is the offer/answer of endpoints (not SDP); the data plane is
// net/transport (direct via securedgram, relayed via net/relay).
//
// Wire framing (length-prefixed, binary):
//   [type:1][len:4 BE][body]
//     1 REGISTER  body = record                 peer → server
//     2 LOOKUP    body = pubkey(32)             peer → server
//     3 OK        body = (empty)                server → peer   (register ack)
//     4 RECORD    body = found(1) [++ record]   server → peer   (lookup reply)
//
//   record = pubkey(32)
//            ++ str(relay_host) ++ u16(relay_port)
//            ++ u16(n_endpoints) ++ [ str(host) ++ u16(port) ]*
//   str    = u16(len) ++ bytes
//
// The record codec is pure and deterministic (offline-testable); the
// server/client add TCP I/O (the per-conn handler runs as a fiber, like
// ext/http_server's server_run_async).
//
// Memory: a PeerRecord and an RzServer are handles — every copy is the same
// record / server, and the last owner releases it (peer_record_free /
// rz_server_free are early releases, optional). An Endpoint is a plain
// value the record's Vec owns. The server does not close its listener on
// release: rz_server_stop does.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/rcbox.nu`

& `libc` @ nurl_tcp_connect s host i port → i

@ rz_register → i { ^ 1 }

@ rz_lookup → i { ^ 2 }

@ rz_ok → i { ^ 3 }

@ rz_record → i { ^ 4 }

@ __rz_max → i { ^ 65536 }

// ── data model ───────────────────────────────────────────────────

: Endpoint {
    String host
    i port
}

: PeerRecordImpl {
    ( Vec u ) pubkey
    ( Vec Endpoint ) endpoints
    String relay_host
    i relay_port
}

// A PeerRecord is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same record, and the last owner releases it.
: PeerRecord { s ctl }

@ PeerRecord_share PeerRecord h → PeerRecord { ^ @ PeerRecord { # s ( rcbox_share # i . h ctl ) } }

@ PeerRecord_drop sink PeerRecord h → v {
    ( mem_forget h )
    ( rcbox_release [PeerRecordImpl] # i . h ctl )
}

@ __PeerRecord_ptr PeerRecord h → *PeerRecordImpl { ^ ( rcbox_ptr [PeerRecordImpl] # i . h ctl ) }

// Let go of `e` now rather than at the end of its owner's scope.
@ endpoint_free sink Endpoint e → v {}

@ peer_record_new ( Vec u ) pubkey s relay_host i relay_port → PeerRecord {
    : i r__box ( rcbox_zero [PeerRecordImpl] )
    : *PeerRecordImpl r ( rcbox_ptr [PeerRecordImpl] r__box )
    : ( Vec u ) pk ( vec_with_cap [u] ( vec_len [u] pubkey ) )
    ( vec_extend [u] pk pubkey )
    = . r pubkey pk
    = . r endpoints ( vec_new [Endpoint] )
    = . r relay_host ( string_from relay_host )
    = . r relay_port relay_port
    ^ @ PeerRecord { # s r__box }
}

@ peer_record_add_endpoint PeerRecord r__h s host i port → v {
    : *PeerRecordImpl r ( __PeerRecord_ptr r__h )
    ( vec_push [Endpoint] . r endpoints @ Endpoint { ( string_from host ) port } )
}

// Let go of `r` now rather than at the end of its owner's scope.
@ peer_record_free sink PeerRecord r → v {}

// The record's fields, lent (the record owns them).
@ peer_record_pubkey PeerRecord r__h → ( Vec u ) {
    : *PeerRecordImpl r ( __PeerRecord_ptr r__h )
    ^ . r pubkey
}

@ peer_record_endpoints PeerRecord r__h → ( Vec Endpoint ) {
    : *PeerRecordImpl r ( __PeerRecord_ptr r__h )
    ^ . r endpoints
}

@ peer_record_relay_host PeerRecord r__h → String {
    : *PeerRecordImpl r ( __PeerRecord_ptr r__h )
    ^ . r relay_host
}

@ peer_record_relay_port PeerRecord r__h → i {
    : *PeerRecordImpl r ( __PeerRecord_ptr r__h )
    ^ . r relay_port
}

// ── record codec ─────────────────────────────────────────────────

@ __rz_put_str ( Vec u ) b String s → v {
    : i n ( string_len s )
    ( bytes_push_u16_be b # u16 n )
    : s cs ( string_data s )
    : *u sp # *u cs
    : ~ i k 0
    ~ < k n { ( vec_push [u] b # u . sp k ) = k + k 1 }
}

@ rz_record_encode PeerRecord r__h → ( Vec u ) {
    : *PeerRecordImpl r ( __PeerRecord_ptr r__h )
    : ( Vec u ) b ( vec_new [u] )
    ( vec_extend [u] b . r pubkey )
    ( __rz_put_str b . r relay_host )
    ( bytes_push_u16_be b # u16 . r relay_port )
    : i n ( vec_len [Endpoint] . r endpoints )
    ( bytes_push_u16_be b # u16 n )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [Endpoint] . r endpoints k ) {
            T e → {
                ( __rz_put_str b . e host )
                ( bytes_push_u16_be b # u16 . e port )
            }
            F → {}
        }
        = k + k 1
    }
    ^ b
}

// Cursor-based reader: the buffer plus an offset the readers advance in
// place (`inout`) — nothing to allocate, nothing to release.
@ __rz_u8 ( Vec u ) buf inout i off → i {
    : i v ?? ( vec_get [u] buf off ) { T x → # i x F → 0 }
    = off + off 1
    ^ v
}

@ __rz_u16 ( Vec u ) buf inout i off → i {
    : i v ?? ( bytes_read_u16_be buf off ) { T x → # i x F → 0 }
    = off + off 2
    ^ v
}

@ __rz_take ( Vec u ) buf inout i off i n → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ?? ( vec_get [u] buf + off k ) { T b → ( vec_push [u] o b ) F → {} } = k + k 1 }
    = off + off n
    ^ o
}

@ __rz_str ( Vec u ) buf inout i off → String {
    : i n ( __rz_u16 buf off )
    : String s ( string_with_cap n )
    : ~ i k 0
    ~ < k n { ( string_push_char s ( __rz_u8 buf off ) ) = k + k 1 }
    ^ s
}

// Decode a record at `off` in `buf`.
@ __rz_get_record ( Vec u ) buf inout i off → PeerRecord {
    : i r__box ( rcbox_zero [PeerRecordImpl] )
    : *PeerRecordImpl r ( rcbox_ptr [PeerRecordImpl] r__box )
    = . r pubkey ( __rz_take buf off 32 )
    = . r relay_host ( __rz_str buf off )
    = . r relay_port ( __rz_u16 buf off )
    : i n ( __rz_u16 buf off )
    = . r endpoints ( vec_new [Endpoint] )
    : ~ i k 0
    ~ < k n {
        : String host ( __rz_str buf off )
        : i port ( __rz_u16 buf off )
        ( vec_push [Endpoint] . r endpoints @ Endpoint { host port } )
        = k + k 1
    }
    ^ @ PeerRecord { # s r__box }
}

// Decode a standalone record buffer (whole buffer is one record).
@ rz_record_decode ( Vec u ) buf → PeerRecord {
    : ~ i off 0
    ^ ( __rz_get_record buf off )
}

// ── frame codec ──────────────────────────────────────────────────

: RzFrame {
    i ftype
    ( Vec u ) body
}

// Let go of `fr` now rather than at the end of its owner's scope.
@ rz_frame_free sink RzFrame fr → v {}

@ __rz_frame i ftype ( Vec u ) body → ( Vec u ) {
    : ( Vec u ) f ( vec_new [u] )
    ( vec_push [u] f # u ftype )
    ( bytes_push_u32_be f # u32 ( vec_len [u] body ) )
    ( vec_extend [u] f body )
    ^ f
}

@ rz_build_register PeerRecord r → ( Vec u ) {
    : ( Vec u ) body ( rz_record_encode r )
    : ( Vec u ) f ( __rz_frame ( rz_register ) body )
    ^ f
}

@ rz_build_lookup ( Vec u ) pubkey → ( Vec u ) { ^ ( __rz_frame ( rz_lookup ) pubkey ) }

@ rz_build_ok → ( Vec u ) {
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) f ( __rz_frame ( rz_ok ) empty )
    ^ f
}

@ rz_build_record_found PeerRecord r → ( Vec u ) {
    : ( Vec u ) body ( vec_new [u] )
    ( vec_push [u] body # u 1 )
    : ( Vec u ) rec ( rz_record_encode r )
    ( vec_extend [u] body rec )
    : ( Vec u ) f ( __rz_frame ( rz_record ) body )
    ^ f
}

@ rz_build_record_notfound → ( Vec u ) {
    : ( Vec u ) body ( vec_new [u] )
    ( vec_push [u] body # u 0 )
    : ( Vec u ) f ( __rz_frame ( rz_record ) body )
    ^ f
}

@ rz_parse ( Vec u ) buf → ?RzFrame {
    : i n ( vec_len [u] buf )
    ? < n 5 { ^ @ ?RzFrame { F # RzFrame 0 } } {}
    : i ftype ?? ( vec_get [u] buf 0 ) { T x → # i x F → -1 }
    : i len ?? ( bytes_read_u32_be buf 1 ) { T x → # i x F → -1 }
    ? > len ( __rz_max ) { ^ @ ?RzFrame { F # RzFrame 0 } } {}
    ? < n + 5 len { ^ @ ?RzFrame { F # RzFrame 0 } } {}
    : ( Vec u ) body ( vec_with_cap [u] len )
    : ~ i k 0
    ~ < k len { ?? ( vec_get [u] buf + 5 k ) { T b → ( vec_push [u] body b ) F → {} } = k + k 1 }
    ^ @ ?RzFrame { T @ RzFrame { ftype body } }
}

// ── streaming frame reader (TcpConn) ─────────────────────────────

@ __rz_read_exact TcpConn c i n → ?( Vec u ) {
    : ( Vec u ) buf ( vec_with_cap [u] n )
    : ~ b fail F
    : ~ i got 0
    ~ & ! fail < got n {
        : !( Vec u ) NetErr r ( tcp_read_chunk c - n got )
        ?? r {
            T chunk → {
                : i cn ( vec_len [u] chunk )
                ? == cn 0 { = fail T } { ( vec_extend [u] buf chunk ) = got + got cn }
            }
            F _ → { = fail T }
        }
    }
    ? fail { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    ^ @ ?( Vec u ) { T buf }
}

@ rz_read_frame TcpConn c → ?RzFrame {
    : ~ ? RzFrame out @ ?RzFrame { F # RzFrame 0 }
    : ?( Vec u ) hdr ( __rz_read_exact c 5 )
    ?? hdr {
        T h → {
            : i ftype ?? ( vec_get [u] h 0 ) { T x → # i x F → -1 }
            : i len ?? ( bytes_read_u32_be h 1 ) { T x → # i x F → -1 }
            ? & >= len 0 <= len ( __rz_max ) {
                : ?( Vec u ) bd ( __rz_read_exact c len )
                ?? bd {
                    T body → { = out @ ?RzFrame { T @ RzFrame { ftype body } } }
                    F → {}
                }
            } {}
        }
        F → {}
    }
    ^ out
}

// ════════════════════════════════════════════════════════════════
// Rendezvous SERVER — pubkey → PeerRecord directory.
// ════════════════════════════════════════════════════════════════

// The conn fibers run on the M:N runtime — two can run at once on
// different worker threads — so the directory is read and written only
// under `lock`. Each conn writes only its own socket, outside the lock.
: RzServerImpl {
    TcpListener lst
    ( Vec PeerRecord ) records
    Mutex lock
}

// An RzServer is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same server, and the last owner releases it.
: RzServer { s ctl }

@ RzServer_share RzServer h → RzServer { ^ @ RzServer { # s ( rcbox_share # i . h ctl ) } }

@ RzServer_drop sink RzServer h → v {
    ( mem_forget h )
    ( rcbox_release [RzServerImpl] # i . h ctl )
}

@ __RzServer_ptr RzServer h → *RzServerImpl { ^ ( rcbox_ptr [RzServerImpl] # i . h ctl ) }

@ rz_server_start s host i port → !RzServer NetErr {
    : !TcpListener NetErr lr ( tcp_listen host port )
    : !RzServer NetErr out ?? lr {
        T l → @ !RzServer NetErr { T @ RzServer { # s ( rcbox_new [RzServerImpl] @ RzServerImpl { l ( vec_new [PeerRecord] ) ( mutex_new ) } ) } }
        F e → @ !RzServer NetErr { F e }
    }
    ^ out
}

@ __rz_veq ( Vec u ) a ( Vec u ) b → b {
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

// Index of the record for `pk`, or -1. Caller holds the lock.
@ __rz_find * RzServerImpl rs ( Vec u ) pk → i {
    : i n ( vec_len [PeerRecord] . rs records )
    : ~ i found -1
    : ~ i k 0
    ~ & < found 0 < k n {
        ?? ( vec_get [PeerRecord] . rs records k ) {
            T r → { ? ( __rz_veq ( peer_record_pubkey r ) pk ) { = found k } {} }
            F → {}
        }
        = k + k 1
    }
    ^ found
}

// Insert or replace the record for a pubkey (latest registration wins); the
// replaced record goes with its slot. Caller holds the lock.
@ __rz_upsert * RzServerImpl rs PeerRecord newrec → v {
    : i k ( __rz_find rs ( peer_record_pubkey newrec ) )
    ? >= k 0 { ( vec_set [PeerRecord] . rs records k newrec ) } { ( vec_push [PeerRecord] . rs records newrec ) }
}

@ __rz_handle_conn * RzServerImpl rs TcpConn c → v {
    : ~ b done F
    ~ ! done {
        : ?RzFrame fr ( rz_read_frame c )
        ?? fr {
            T f → {
                ? == . f ftype ( rz_register ) {
                    : PeerRecord nr ( rz_record_decode . f body )
                    ( mutex_lock . rs lock )
                    ( __rz_upsert rs nr )
                    ( mutex_unlock . rs lock )
                    : ( Vec u ) ack ( rz_build_ok )
                    ?? ( tcp_write_all c ack ) { T _ → {} F _ → { = done T } }
                } {}
                ? == . f ftype ( rz_lookup ) {
                    ( mutex_lock . rs lock )
                    : i found ( __rz_find rs . f body )
                    : ( Vec u ) resp ?? ( vec_get [PeerRecord] . rs records found ) {
                        T r → ( rz_build_record_found r )
                        F → ( rz_build_record_notfound )
                    }
                    ( mutex_unlock . rs lock )
                    ?? ( tcp_write_all c resp ) { T _ → {} F _ → { = done T } }
                } {}
            }
            F → { = done T }
        }
    }
    ( tcp_close_conn c )
}

@ __rz_accept_loop * RzServerImpl rs → v {
    : TcpListener lst . rs lst
    : ~ b done F
    ~ ! done {
        : !TcpConn NetErr cr ( tcp_accept lst )
        ?? cr {
            T c → { ( spawn \ → v { ( __rz_handle_conn rs c ) } ) }
            F e → { = done T }
        }
    }
}

@ rz_server_run RzServer rs__h → v {
    : *RzServerImpl rs ( __RzServer_ptr rs__h )
    ( tcp_listener_retain . rs lst )
    : ( @ v ) accept_fiber \ → v { ( __rz_accept_loop rs ) }
    ( spawn accept_fiber )
    ( runtime_run )
    ( tcp_listener_release . rs lst )
}

@ rz_server_stop RzServer rs__h → v {
    : *RzServerImpl rs ( __RzServer_ptr rs__h )
    ( tcp_close_listener . rs lst )
}

// Let go of `rs` now rather than at the end of its owner's scope.
@ rz_server_free sink RzServer rs → v {}

// ════════════════════════════════════════════════════════════════
// Rendezvous CLIENT — register self, look up peers.
// ════════════════════════════════════════════════════════════════

: RzClient {
    TcpConn conn
}

@ rz_client_connect s host i port → !RzClient NetErr {
    : i raw ( nurl_tcp_connect host port )
    ? == raw 0 { ^ @ !RzClient NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 { ( nurl_tcp_close raw ) ^ @ !RzClient NetErr { F ( _net_err_of ek ) } } {}
    : TcpConn c @ TcpConn { # s raw 0 0 }
    ^ @ !RzClient NetErr { T @ RzClient { c } }
}

// Publish our record; waits for the server's OK.
@ rz_register_self RzClient rc PeerRecord r → !v NetErr {
    : ( Vec u ) f ( rz_build_register r )
    : !v NetErr wr ( tcp_write_all . rc conn f )
    : !v NetErr out ?? wr {
        T _ → {
            ?? ( rz_read_frame . rc conn ) {
                T fr → { : i ok ? == . fr ftype ( rz_ok ) 1 0 ? == ok 1 @ !v NetErr { T 0 } @ !v NetErr { F # NetErr NetOther } }
                F → @ !v NetErr { F # NetErr NetClosed }
            }
        }
        F e → @ !v NetErr { F e }
    }
    ^ out
}

// Look up a peer's record by pubkey; None when it is not registered (or
// the exchange failed). The caller owns the record.
@ rz_lookup_peer RzClient rc ( Vec u ) pubkey → ?PeerRecord {
    : ( Vec u ) f ( rz_build_lookup pubkey )
    : ~ ? PeerRecord out @ ?PeerRecord { F # PeerRecord 0 }
    ?? ( tcp_write_all . rc conn f ) {
        T _ → {
            ?? ( rz_read_frame . rc conn ) {
                T fr → {
                    ? == . fr ftype ( rz_record ) {
                        : i found ?? ( vec_get [u] . fr body 0 ) { T x → # i x F → 0 }
                        ? == found 1 {
                            // record body sits after the 1-byte found flag
                            : ~ i off 1
                            = out @ ?PeerRecord { T ( __rz_get_record . fr body off ) }
                        } {}
                    } {}
                }
                F → {}
            }
        }
        F _ → {}
    }
    ^ out
}

@ rz_client_close RzClient rc → v { ( tcp_close_conn . rc conn ) }
