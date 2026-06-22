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

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/async.nu`

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

: PeerRecord {
    ( Vec u ) pubkey
    ( Vec s ) endpoints  // *Endpoint
    String relay_host
    i relay_port
}

@ endpoint_free * Endpoint e → v { ( string_free . e host ) ( nurl_free # s e ) }

@ peer_record_new ( Vec u ) pubkey s relay_host i relay_port → s {
    : *PeerRecord r # *PeerRecord ( nurl_alloc Z PeerRecord )
    : ( Vec u ) pk ( vec_with_cap [u] ( vec_len [u] pubkey ) )
    ( vec_extend [u] pk pubkey )
    = . r pubkey pk
    = . r endpoints ( vec_new [s] )
    = . r relay_host ( string_from relay_host )
    = . r relay_port relay_port
    ^ # s r
}

@ peer_record_add_endpoint * PeerRecord r s host i port → v {
    : *Endpoint e # *Endpoint ( nurl_alloc Z Endpoint )
    = . e host ( string_from host )
    = . e port port
    ( vec_push [s] . r endpoints # s e )
}

@ peer_record_free * PeerRecord r → v {
    ( vec_free [u] . r pubkey )
    : i n ( vec_len [s] . r endpoints )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . r endpoints k ) { T x → x F → # s 0 }
        ? != # i pp 0 { ( endpoint_free # *Endpoint pp ) } {}
        = k + k 1
    }
    ( vec_free [s] . r endpoints )
    ( string_free . r relay_host )
    ( nurl_free # s r )
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

@ rz_record_encode * PeerRecord r → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_extend [u] b . r pubkey )
    ( __rz_put_str b . r relay_host )
    ( bytes_push_u16_be b # u16 . r relay_port )
    : i n ( vec_len [s] . r endpoints )
    ( bytes_push_u16_be b # u16 n )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . r endpoints k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *Endpoint e # *Endpoint pp
            ( __rz_put_str b . e host )
            ( bytes_push_u16_be b # u16 . e port )
        } {}
        = k + k 1
    }
    ^ b
}

// cursor-based reader (advances an offset through a buffer)
: RzCursor {
    ( Vec u ) buf
    i off
}

@ __rz_u8 * RzCursor c → i {
    : i v ?? ( vec_get [u] . c buf . c off ) { T x → # i x F → 0 }
    = . c off + . c off 1
    ^ v
}

@ __rz_u16 * RzCursor c → i {
    : i v ?? ( bytes_read_u16_be . c buf . c off ) { T x → # i x F → 0 }
    = . c off + . c off 2
    ^ v
}

@ __rz_take * RzCursor c i n → ( Vec u ) {
    : ( Vec u ) o ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ?? ( vec_get [u] . c buf + . c off k ) { T b → ( vec_push [u] o b ) F → {} } = k + k 1 }
    = . c off + . c off n
    ^ o
}

@ __rz_str * RzCursor c → String {
    : i n ( __rz_u16 c )
    : String s ( string_with_cap n )
    : ~ i k 0
    ~ < k n { ( string_push_char s ( __rz_u8 c ) ) = k + k 1 }
    ^ s
}

// Decode a record from a cursor; returns *PeerRecord.
@ __rz_get_record * RzCursor c → s {
    : *PeerRecord r # *PeerRecord ( nurl_alloc Z PeerRecord )
    = . r pubkey ( __rz_take c 32 )
    = . r relay_host ( __rz_str c )
    = . r relay_port ( __rz_u16 c )
    : i n ( __rz_u16 c )
    = . r endpoints ( vec_new [s] )
    : ~ i k 0
    ~ < k n {
        : *Endpoint e # *Endpoint ( nurl_alloc Z Endpoint )
        = . e host ( __rz_str c )
        = . e port ( __rz_u16 c )
        ( vec_push [s] . r endpoints # s e )
        = k + k 1
    }
    ^ # s r
}

// Decode a standalone record buffer (whole buffer is one record).
@ rz_record_decode ( Vec u ) buf → s {
    : *RzCursor c # *RzCursor ( nurl_alloc Z RzCursor )
    = . c buf buf
    = . c off 0
    : s r ( __rz_get_record c )
    ( nurl_free # s c )
    ^ r
}

// ── frame codec ──────────────────────────────────────────────────

: RzFrame {
    i ftype
    ( Vec u ) body
}

@ rz_frame_free RzFrame fr → v { ( vec_free [u] . fr body ) }

@ __rz_frame i ftype ( Vec u ) body → ( Vec u ) {
    : ( Vec u ) f ( vec_new [u] )
    ( vec_push [u] f # u ftype )
    ( bytes_push_u32_be f # u32 ( vec_len [u] body ) )
    ( vec_extend [u] f body )
    ^ f
}

@ rz_build_register * PeerRecord r → ( Vec u ) {
    : ( Vec u ) body ( rz_record_encode r )
    : ( Vec u ) f ( __rz_frame ( rz_register ) body )
    ( vec_free [u] body )
    ^ f
}

@ rz_build_lookup ( Vec u ) pubkey → ( Vec u ) { ^ ( __rz_frame ( rz_lookup ) pubkey ) }

@ rz_build_ok → ( Vec u ) {
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) f ( __rz_frame ( rz_ok ) empty )
    ( vec_free [u] empty )
    ^ f
}

@ rz_build_record_found * PeerRecord r → ( Vec u ) {
    : ( Vec u ) body ( vec_new [u] )
    ( vec_push [u] body # u 1 )
    : ( Vec u ) rec ( rz_record_encode r )
    ( vec_extend [u] body rec )
    ( vec_free [u] rec )
    : ( Vec u ) f ( __rz_frame ( rz_record ) body )
    ( vec_free [u] body )
    ^ f
}

@ rz_build_record_notfound → ( Vec u ) {
    : ( Vec u ) body ( vec_new [u] )
    ( vec_push [u] body # u 0 )
    : ( Vec u ) f ( __rz_frame ( rz_record ) body )
    ( vec_free [u] body )
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
                ( vec_free [u] chunk )
            }
            F _ → { = fail T }
        }
    }
    ? fail { ( vec_free [u] buf ) ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    ^ @ ?( Vec u ) { T buf }
}

@ rz_read_frame TcpConn c → ?RzFrame {
    : ~ ? RzFrame out @ ?RzFrame { F # RzFrame 0 }
    : ?( Vec u ) hdr ( __rz_read_exact c 5 )
    ?? hdr {
        T h → {
            : i ftype ?? ( vec_get [u] h 0 ) { T x → # i x F → -1 }
            : i len ?? ( bytes_read_u32_be h 1 ) { T x → # i x F → -1 }
            ( vec_free [u] h )
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

: RzServer {
    TcpListener lst
    ( Vec s ) records  // *PeerRecord
}

@ rz_server_start s host i port → !RzServer NetErr {
    : !TcpListener NetErr lr ( tcp_listen host port )
    : !RzServer NetErr out ?? lr {
        T l → @ !RzServer NetErr { T @ RzServer { l ( vec_new [s] ) } }
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

@ __rz_find * RzServer rs ( Vec u ) pk → s {
    : i n ( vec_len [s] . rs records )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k n {
        : s pp ?? ( vec_get [s] . rs records k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *PeerRecord r # *PeerRecord pp
            ? ( __rz_veq . r pubkey pk ) { = found pp } {}
        } {}
        = k + k 1
    }
    ^ found
}

// Insert or replace the record for a pubkey (latest registration wins).
@ __rz_upsert * RzServer rs s newrec → v {
    : *PeerRecord nr # *PeerRecord newrec
    : s old ( __rz_find rs . nr pubkey )
    ? != # i old 0 {
        : i n ( vec_len [s] . rs records )
        : ~ i k 0
        ~ < k n {
            : s pp ?? ( vec_get [s] . rs records k ) { T x → x F → # s 0 }
            ? == # i pp old { ( vec_set [s] . rs records k newrec ) } {}
            = k + k 1
        }
        ( peer_record_free # *PeerRecord old )
    } { ( vec_push [s] . rs records newrec ) }
}

@ __rz_handle_conn * RzServer rs TcpConn c → v {
    : ~ b done F
    ~ ! done {
        : ?RzFrame fr ( rz_read_frame c )
        ?? fr {
            T f → {
                ? == . f ftype ( rz_register ) {
                    : s nr ( rz_record_decode . f body )
                    ( __rz_upsert rs nr )
                    : ( Vec u ) ack ( rz_build_ok )
                    ?? ( tcp_write_all c ack ) { T _ → {} F _ → { = done T } }
                    ( vec_free [u] ack )
                } {}
                ? == . f ftype ( rz_lookup ) {
                    : s found ( __rz_find rs . f body )
                    : ( Vec u ) resp ? != # i found 0 ( rz_build_record_found # *PeerRecord found ) ( rz_build_record_notfound )
                    ?? ( tcp_write_all c resp ) { T _ → {} F _ → { = done T } }
                    ( vec_free [u] resp )
                } {}
                ( rz_frame_free f )
            }
            F → { = done T }
        }
    }
    ( tcp_close_conn c )
}

@ __rz_accept_loop * RzServer rs → v {
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

@ rz_server_run * RzServer rs → v {
    ( tcp_listener_retain . rs lst )
    : ( @ v ) accept_fiber \ → v { ( __rz_accept_loop rs ) }
    ( spawn accept_fiber )
    ( runtime_run )
    ( tcp_listener_release . rs lst )
    : *u accept_env # *u accept_fiber 1
    ( nurl_free # s accept_env )
}

@ rz_server_stop * RzServer rs → v { ( tcp_close_listener . rs lst ) }

@ rz_server_free * RzServer rs → v {
    : i n ( vec_len [s] . rs records )
    : ~ i k 0
    ~ < k n {
        : s pp ?? ( vec_get [s] . rs records k ) { T x → x F → # s 0 }
        ? != # i pp 0 { ( peer_record_free # *PeerRecord pp ) } {}
        = k + k 1
    }
    ( vec_free [s] . rs records )
    ( nurl_free # s rs )
}

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
    ? != ek 0 { ( nurl_tcp_close raw ) ^ @ !RzClient NetErr { F ( __net_err_of ek ) } } {}
    : TcpConn c @ TcpConn { # s raw }
    ^ @ !RzClient NetErr { T @ RzClient { c } }
}

// Publish our record; waits for the server's OK.
@ rz_register_self RzClient rc * PeerRecord r → !v NetErr {
    : ( Vec u ) f ( rz_build_register r )
    : !v NetErr wr ( tcp_write_all . rc conn f )
    ( vec_free [u] f )
    : !v NetErr out ?? wr {
        T _ → {
            ?? ( rz_read_frame . rc conn ) {
                T fr → { : i ok ? == . fr ftype ( rz_ok ) 1 0 ( rz_frame_free fr ) ? == ok 1 @ !v NetErr { T 0 } @ !v NetErr { F # NetErr NetOther } }
                F → @ !v NetErr { F # NetErr NetClosed }
            }
        }
        F e → @ !v NetErr { F e }
    }
    ^ out
}

// Look up a peer's record by pubkey; returns *PeerRecord (0 = not found /
// error). Caller owns it → peer_record_free when done.
@ rz_lookup_peer RzClient rc ( Vec u ) pubkey → s {
    : ( Vec u ) f ( rz_build_lookup pubkey )
    : ~ s out # s 0
    ?? ( tcp_write_all . rc conn f ) {
        T _ → {
            ?? ( rz_read_frame . rc conn ) {
                T fr → {
                    ? == . fr ftype ( rz_record ) {
                        : i found ?? ( vec_get [u] . fr body 0 ) { T x → # i x F → 0 }
                        ? == found 1 {
                            // record body sits after the 1-byte found flag
                            : *RzCursor cur # *RzCursor ( nurl_alloc Z RzCursor )
                            = . cur buf . fr body
                            = . cur off 1
                            = out ( __rz_get_record cur )
                            ( nurl_free # s cur )
                        } {}
                    } {}
                    ( rz_frame_free fr )
                }
                F → {}
            }
        }
        F _ → {}
    }
    ( vec_free [u] f )
    ^ out
}

@ rz_client_close RzClient rc → v { ( tcp_close_conn . rc conn ) }
