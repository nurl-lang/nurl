// net_sim_clients.nu — client libraries over the simulated network
// (agora #249, DST): http-client and psql dial through a NetDialer made
// from a NetSim node (std/net_sim.nu's netsim_dialer) instead of the
// kernel's TCP, and run unchanged — http-client against the HttpApp
// facade served on node 1, psql against a minimal PostgreSQL server on
// node 2 (below: the v3 protocol's startup, extended query flow and simple
// query, echoing a text parameter back). Every byte crosses the sans-IO
// TCP/IP stacks and the simulated bus; no operating system socket is
// opened (strace shows none).
//
// TLS runs over the dialed connections too (#250, #289): http-client's
// https request reaches an HttpApp on a TLS listener of the simulated
// network (netsim_listen_tls), and psql's SSLRequest is answered — by a
// server that declines (prefer goes plaintext, require is PgTls) and by
// one that upgrades the connection in place (tcp_starttls_server), whose
// queries then run over TLS.
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/net_sim.nu`
$ `stdlib/std/x509_gen.nu`
$ `packages/http/src/http.nu`
$ `packages/http-client/src/http_client.nu`
$ `packages/psql/src/pg.nu`

: ~ i g_fail 0

@ check s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `ok` `FAIL` )
    ( nurl_print `\n` )
    ? ! ok { = g_fail + g_fail 1 } {}
}

// ── node 1: the HttpApp facade, as main() would build it ──────────────
@ build_app → HttpApp {
    : HttpApp a ( http_app_new )
    ( http_app_quiet a )
    ( http_app_get a `/hello/:name` \ HttpRequest req Params p → HttpResponse {
        : String out ( string_from `hello ` )
        ?? ( params_get p `name` ) {
            T nm → { ( string_push_str out ( string_data nm ) ) }
            F _ → {}
        }
        ^ ( response_text 200 ( string_data out ) )
    } )
    ^ a
}

// ── node 2: a minimal PostgreSQL server ───────────────────────────────

// The big-endian integer of `n` bytes at `at`.
@ be_int ( Vec u ) b i at i n → i {
    : ~ i v 0
    : ~ i k 0
    ~ < k n { = v | << v 8 # i ( vec_at [u] b + at k ) = k + k 1 }
    ^ v
}

// The end (exclusive) of the C string at `at`.
@ cstr_end ( Vec u ) b i at → i {
    : ~ i k at
    ~ & < k ( vec_len [u] b ) != 0 # i ( vec_at [u] b k ) { = k + k 1 }
    ^ k
}

// A backend message: its type, then its length and payload.
@ be_msg ( Vec u ) out i mtype ( Vec u ) payload → v {
    ( vec_push [u] out # u mtype )
    ( pgw_put32 out + 4 ( vec_len [u] payload ) )
    ( bytes_extend_bytes out payload )
}

@ be_ready ( Vec u ) out → v {
    : ( Vec u ) z ( vec_new [u] )
    ( vec_push [u] z # u 73 )
    ( be_msg out 90 z )
}

// One text column called "v".
@ be_row_desc ( Vec u ) out → v {
    : ( Vec u ) t ( vec_new [u] )
    ( pgw_put16 t 1 )
    ( pgw_put_cstr t `v` )
    ( pgw_put32 t 0 ) ( pgw_put16 t 0 ) ( pgw_put32 t 25 ) ( pgw_put16 t -1 ) ( pgw_put32 t -1 ) ( pgw_put16 t 0 )
    ( be_msg out 84 t )
}

@ be_data_row ( Vec u ) out ( Vec u ) value → v {
    : ( Vec u ) d ( vec_new [u] )
    ( pgw_put16 d 1 )
    ( pgw_put32 d ( vec_len [u] value ) )
    ( bytes_extend_bytes d value )
    ( be_msg out 68 d )
}

@ be_complete ( Vec u ) out → v {
    : ( Vec u ) c ( vec_new [u] )
    ( pgw_put_cstr c `SELECT 1` )
    ( be_msg out 67 c )
}

@ be_empty ( Vec u ) out i mtype → v { ( be_msg out mtype ( vec_new [u] ) ) }

// Serve one client until it says Terminate: answers go out at each Sync
// (and after a simple Query), as PostgreSQL flushes them. Counts the
// statements it was asked to parse and the SSL requests it saw. With an
// identity it accepts an SSLRequest and upgrades the connection in place.
@ pg_fake TcpConn c Atomic parses Atomic ssl_asks ? ( Arc TlsIdent ) tls → v {
    : ~ b upgrade F
    : ( Vec u ) in ( vec_new [u] )
    : ( Vec u ) out ( vec_new [u] )
    : ( Vec u ) value ( vec_new [u] )
    : ~ b started F
    : ~ i at 0
    ~ T {
        // Every whole message already in.
        : ~ b more T
        ~ more {
            : i have - ( vec_len [u] in ) at
            ? ! started {
                ? < have 8 { = more F } {
                    : i len ( be_int in at 4 )
                    ? < have len { = more F } {
                        : i code ( be_int in + at 4 4 )
                        ? == code 80877103 {
                            : i _n ( atomic_add ssl_asks 1 )
                            ?? tls {
                                T _ → {
                                    ( vec_push [u] out # u 83 )
                                    = upgrade T
                                }
                                F → { ( vec_push [u] out # u 78 ) }
                            }
                        } {
                            = started T
                            : ( Vec u ) auth ( vec_new [u] )
                            ( pgw_put32 auth 0 )
                            ( be_msg out 82 auth )
                            : ( Vec u ) ps ( vec_new [u] )
                            ( pgw_put_cstr ps `server_version` ) ( pgw_put_cstr ps `16.0-sim` )
                            ( be_msg out 83 ps )
                            : ( Vec u ) key ( vec_new [u] )
                            ( pgw_put32 key 4242 ) ( pgw_put32 key 7 )
                            ( be_msg out 75 key )
                            ( be_ready out )
                        }
                        = at + at len
                        ?? ( tcp_write_all c out ) { T _ → {} F _ → { ^ v } }
                        ( vec_clear [u] out )
                        ? upgrade {
                            = upgrade F
                            ?? tls {
                                T id → {
                                    ?? ( tcp_starttls_server c ( arc_clone [TlsIdent] id ) ( vec_new [u] ) ) {
                                        T _ → {}
                                        F _ → { ^ v }
                                    }
                                }
                                F → {}
                            }
                        } {}
                    }
                }
            } {
                ? < have 5 { = more F } {
                    : i mtype # i ( vec_at [u] in at )
                    : i len + 1 ( be_int in + at 1 4 )
                    ? < have len { = more F } {
                        : i body + at 5
                        ? == mtype 80 {  // Parse
                            : i _n ( atomic_add parses 1 )
                            ( be_empty out 49 )
                        } {}
                        ? == mtype 68 {  // Describe: one text parameter, one text column
                            : ( Vec u ) pd ( vec_new [u] )
                            ( pgw_put16 pd 1 ) ( pgw_put32 pd 25 )
                            ( be_msg out 116 pd )
                            ( be_row_desc out )
                        } {}
                        ? == mtype 66 {  // Bind: keep the first parameter's bytes
                            : ~ i p ( cstr_end in body )
                            = p ( cstr_end in + p 1 )
                            = p + p 1
                            : i nfmt ( be_int in p 2 )
                            = p + + p 2 * 2 nfmt
                            : i nparams ( be_int in p 2 )
                            = p + p 2
                            ( vec_clear [u] value )
                            ? > nparams 0 {
                                : i plen ( be_int in p 4 )
                                ? > plen 0 { ( vec_extend_range [u] value in + p 4 plen ) } {}
                            } {}
                            ( be_empty out 50 )
                        } {}
                        ? == mtype 69 {  // Execute
                            ( be_data_row out value )
                            ( be_complete out )
                        } {}
                        ? == mtype 67 { ( be_empty out 51 ) } {}  // Close
                        ? == mtype 83 {  // Sync
                            ( be_ready out )
                            ?? ( tcp_write_all c out ) { T _ → {} F _ → { ^ v } }
                            ( vec_clear [u] out )
                        } {}
                        ? == mtype 81 {  // simple Query
                            ( be_row_desc out )
                            : ( Vec u ) ok ( vec_new [u] )
                            ( bytes_extend_str ok `ok` )
                            ( be_data_row out ok )
                            ( be_complete out )
                            ( be_ready out )
                            ?? ( tcp_write_all c out ) { T _ → {} F _ → { ^ v } }
                            ( vec_clear [u] out )
                        } {}
                        ? == mtype 88 { ^ v } {}  // Terminate
                        = at + at len
                    }
                }
            }
        }
        ?? ( tcp_read_into c in 4096 ) { T _ → {} F _ → { ^ v } }
    }
}

@ pg_opt_is ? String o s want → b {
    ?? o { T x → { ^ == 0 ( nurl_str_cmp ( string_data x ) want ) } F → { ^ F } }
}

@ main → i {
    : NetSim net ( netsim_new 3 11 0 1 0 )
    : TcpListener hl ?? ( netsim_listen net 1 80 ) { T x → x F _ → { ( check `listen on node 1: ` F ) ^ 1 } }
    : TcpListener pl ?? ( netsim_listen net 2 5432 ) { T x → x F _ → { ( check `listen on node 2: ` F ) ^ 1 } }
    : TcpListener hstop ( TcpListener_share hl )
    : Atomic parses ( atomic_new 0 )
    : Atomic ssl_asks ( atomic_new 0 )
    : Atomic p2 ( Atomic_share parses )
    : Atomic s2 ( Atomic_share ssl_asks )
    : !Thread ThreadErr hsrv ( thread_spawn \ → v { : i _rc ( http_app_serve ( build_app ) ( TcpListener_share hl ) ) } )
    // Two connections: sslmode prefer (declined: plaintext) and require
    // (declined: PgTls).
    : !Thread ThreadErr psrv ( thread_spawn \ → v {
        : ~ i n 0
        ~ < n 2 {
            ?? ( tcp_accept ( TcpListener_share pl ) ) {
                T c → { ( pg_fake c ( Atomic_share p2 ) ( Atomic_share s2 ) @ ?( Arc TlsIdent ) { F } ) }
                F _ → {}
            }
            = n + n 1
        }
    } )
    // TLS on the simulated network: an identity generated in memory, an
    // HttpApp on a TLS listener (node 1, 443) and a PostgreSQL that says
    // yes to SSLRequest (node 2, 5433).
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : ( Arc TlsIdent ) id ?? ( tls_ident_pem ( string_clone . cert cert_pem ) ( string_clone . cert key_pem ) ) {
        T x → x
        F _ → {
            ( check `a TLS identity: ` F )
            ^ 1
        }
    }
    : TcpListener tl ?? ( netsim_listen_tls net 1 443 ( arc_clone [TlsIdent] id ) `http/1.1` ) {
        T x → x
        F _ → {
            ( check `a TLS listener on node 1: ` F )
            ^ 1
        }
    }
    : TcpListener tstop ( TcpListener_share tl )
    : !Thread ThreadErr tsrv ( thread_spawn \ → v { : i _rc ( http_app_serve ( build_app ) ( TcpListener_share tl ) ) } )
    : TcpListener ptl ?? ( netsim_listen net 2 5433 ) {
        T x → x
        F _ → {
            ( check `listen on node 2, 5433: ` F )
            ^ 1
        }
    }
    : Atomic tparses ( atomic_new 0 )
    : Atomic tasks ( atomic_new 0 )
    : Atomic tp2 ( Atomic_share tparses )
    : Atomic ts2 ( Atomic_share tasks )
    : ( Arc TlsIdent ) pid ( arc_clone [TlsIdent] id )
    : !Thread ThreadErr ptsrv ( thread_spawn \ → v {
        ?? ( tcp_accept ( TcpListener_share ptl ) ) {
            T c → { ( pg_fake c ( Atomic_share tp2 ) ( Atomic_share ts2 ) @ ?( Arc TlsIdent ) { T ( arc_clone [TlsIdent] pid ) } ) }
            F _ → {}
        }
    } )

    // ── http-client from node 0 ──
    : HttpClient hc ( http_client_new )
    ( http_client_set_dialer hc ( netsim_dialer net 0 ) )
    ( http_client_set_timeout hc 5000 )
    ?? ( http_client_get hc `http://10.0.0.2/hello/sim` ) {
        T r → { ( check `http-client over the sim: 200 hello sim: ` & == . r status 200 ( slice_bytes_eq ( slice_from_vec [u] . r body ) ( slice_of_str `hello sim` ) ) ) }
        F e → { ( check `http-client over the sim: 200 hello sim: ` F ) ( nurl_print ( http_client_err_name e ) ) ( nurl_print `\n` ) }
    }
    ?? ( http_client_get hc `http://10.0.0.2/hello/again` ) {
        T r → { ( check `a second request on the client's connection: ` == . r status 200 ) }
        F _ → { ( check `a second request on the client's connection: ` F ) }
    }
    ( http_client_set_verify hc F )
    ?? ( http_client_get hc `https://10.0.0.2/hello/tls` ) {
        T r → { ( check `https over the sim: 200 hello tls: ` & == . r status 200 ( slice_bytes_eq ( slice_from_vec [u] . r body ) ( slice_of_str `hello tls` ) ) ) }
        F e → { ( check `https over the sim: 200 hello tls: ` F ) ( nurl_print ( http_client_err_name e ) ) ( nurl_print `\n` ) }
    }
    ?? ( http_client_get hc `https://10.0.0.2/hello/again` ) {
        T r → { ( check `a second https request: ` == . r status 200 ) }
        F _ → { ( check `a second https request: ` F ) }
    }

    // ── psql from node 0 ──
    ?? ( pg_connect_with ( netsim_dialer net 0 ) `10.0.0.3` 5432 `u` `` `d` 1 ) {
        T c → {
            ( check `psql connects over the sim, plaintext: ` == ( pg_conn_tls c ) 0 )
            ( check `sslmode prefer asked, the server declined: ` == ( atomic_load ssl_asks ) 1 )
            : ( Vec PgVal ) ps ( vec_new [PgVal] )
            ( vec_push [PgVal] ps @ PgVal { PgText ( string_from `hello` ) } )
            ?? ( pg_query_params c `SELECT $1::text` ps ) {
                T r → { ( check `pg_query_params over the sim: ` ( pg_opt_is ( pg_row_s r 0 0 ) `hello` ) ) }
                F e → { ( check `pg_query_params over the sim: ` F ) ( nurl_print ( pg_err_name e ) ) ( nurl_print `\n` ) }
            }
            : ( Vec ( Vec PgVal ) ) sets ( vec_new [( Vec PgVal )] )
            : ~ i k 0
            ~ < k 3 {
                : ( Vec PgVal ) one ( vec_new [PgVal] )
                : String v ( string_from `v` )
                ( string_push_int v k )
                ( vec_push [PgVal] one @ PgVal { PgText v } )
                ( vec_push [( Vec PgVal )] sets one )
                = k + k 1
            }
            ?? ( pg_query_many c `SELECT $1::text` sets ) {
                T rs → {
                    : b all & & == ( vec_len [PgResult] rs ) 3 ( pg_opt_is ( pg_row_s ( vec_at [PgResult] rs 0 ) 0 0 ) `v0` ) & ( pg_opt_is ( pg_row_s ( vec_at [PgResult] rs 1 ) 0 0 ) `v1` ) ( pg_opt_is ( pg_row_s ( vec_at [PgResult] rs 2 ) 0 0 ) `v2` )
                    ( check `pg_query_many over the sim, in order: ` all )
                }
                F _ → { ( check `pg_query_many over the sim, in order: ` F ) }
            }
            ( check `the statement was parsed once (the cache): ` == ( atomic_load parses ) 1 )
            ?? ( pg_query c `SELECT 1` ) {
                T r → { ( check `a simple query over the sim: ` ( pg_opt_is ( pg_row_s r 0 0 ) `ok` ) ) }
                F _ → { ( check `a simple query over the sim: ` F ) }
            }
        }
        F e → { ( check `psql connects over the sim, plaintext: ` F ) ( nurl_print ( pg_err_name e ) ) ( nurl_print `\n` ) }
    }
    ?? ( pg_connect_with ( netsim_dialer net 0 ) `10.0.0.3` 5432 `u` `` `d` 2 ) {
        T _ → { ( check `sslmode require, the server declined: PgTls: ` F ) }
        F e → { ( check `sslmode require, the server declined: PgTls: ` == 0 ( nurl_str_cmp ( pg_err_name e ) `PgTls` ) ) }
    }
    ?? ( pg_connect_with ( netsim_dialer net 0 ) `10.0.0.3` 5433 `u` `` `d` 2 ) {
        T c → {
            ( check `sslmode require over the sim: TLS: ` == ( pg_conn_tls c ) 1 )
            : ( Vec PgVal ) ps ( vec_new [PgVal] )
            ( vec_push [PgVal] ps @ PgVal { PgText ( string_from `over tls` ) } )
            ?? ( pg_query_params c `SELECT $1::text` ps ) {
                T r → { ( check `a query over TLS over the sim: ` ( pg_opt_is ( pg_row_s r 0 0 ) `over tls` ) ) }
                F e → { ( check `a query over TLS over the sim: ` F ) ( nurl_print ( pg_err_name e ) ) ( nurl_print `\n` ) }
            }
        }
        F e → { ( check `sslmode require over the sim: TLS: ` F ) ( nurl_print ( pg_err_name e ) ) ( nurl_print `\n` ) }
    }

    ( tcp_close_listener hstop )
    ( tcp_close_listener tstop )
    ?? hsrv { T t → { ( thread_join t ) } F _ → { ( check `http server thread: ` F ) } }
    ?? tsrv { T t → { ( thread_join t ) } F _ → { ( check `https server thread: ` F ) } }
    ?? psrv { T t → { ( thread_join t ) } F _ → { ( check `pg server thread: ` F ) } }
    ?? ptsrv { T t → { ( thread_join t ) } F _ → { ( check `pg TLS server thread: ` F ) } }
    ( nurl_print ? == g_fail 0 `net_sim_clients: all ok\n` `net_sim_clients: FAILURES\n` )
    ^ ? == g_fail 0 0 1
}
