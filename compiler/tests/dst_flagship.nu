// dst_flagship: the DST flagship scenario (Agora #262) — a web service and
// its database on a simulated network (std/net_sim.nu), under a partition
// and a crash-restart of the database, in one process.
//
//   node 0  three HTTP clients (packages/http-client through netsim_dialer)
//   node 1  the service: an HttpApp (async), one route, GET /op/:id/:client,
//           which applies operation `id` in one transaction —
//             INSERT INTO ops VALUES (id, client)          -- the receipt
//             UPDATE acct SET bal = bal + 1 WHERE id = 1   -- the effect
//           and answers 200 once the COMMIT returned. A receipt that is
//           already there (a retry of an operation that did commit) is a
//           200 too: the operation is idempotent by its id. Anything else
//           — the database gone, a write conflict — is a 503.
//   node 2  nurldb (packages/nurldb serve_on), its files in a temp dir
//
// Each client applies its operations in turn, retrying one that failed
// with the same id. Meanwhile the harness cuts the service off from the
// database for a while, heals the link, and crashes the database node
// (netsim_crash): every socket gone, the database dropped as a killed
// process leaves it (db_crash) and reopened from its log on the rebooted
// node. At the end, read straight from the database:
//
//   * every operation a client was told succeeded is there (a receipt);
//   * none was applied twice: the balance is the number of receipts;
//   * every client finished — each operation was answered, or given up
//     on after its retries (nobody hangs on a crashed peer: the service
//     reads the database with a timeout, the clients the service).
//
// On the hosted runtime this runs in real time and its interleavings vary
// from run to run; the invariants hold for every one of them. Under the
// deterministic simulation (#260) a seed fixes the run (#261: sweeps).
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/net_sim.nu`
$ `packages/http/src/http.nu`
$ `packages/http-client/src/http_client.nu`
$ `packages/nurldb/src/server.nu`

: i CLIENTS 3
: i OPS 12  // per client
: i TRIES 40  // per operation
: i DB_PORT 5433

@ check s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `: ok\n` `: FAILED\n` )
}

@ sql inout Client c s text → b { ^ ?? ( client_exec c ( string_from text ) ) { T _ → T F _ → F } }

// Apply operation `id` of `client` through `c`: 0 applied now, 1 applied
// before (its receipt is there), 2 not applied (a retry may).
@ apply inout Client c i id i client → i {
    ? ! ( sql c `BEGIN` ) { ^ 2 } {}
    : String ins ( string_from `INSERT INTO ops VALUES (` )
    ( string_push_int ins id )
    ( string_push_str ins `, ` )
    ( string_push_int ins client )
    ( string_push_str ins `)` )
    ?? ( client_exec c ins ) {
        T _ → {}
        F e → {
            : b _r ( sql c `ROLLBACK` )
            ^ ? ( string_contains e `duplicate key` ) 1 2
        }
    }
    ? ! ( sql c `UPDATE acct SET bal = bal + 1 WHERE id = 1` ) {
        : b _r ( sql c `ROLLBACK` )
        ^ 2
    } {}
    ^ ? ( sql c `COMMIT` ) 0 2
}

@ service NetSim net → HttpApp {
    : HttpApp a ( http_app_new )
    ( http_app_quiet a )
    ( http_app_async a 2 )
    ( http_app_get a `/op/:id/:client` \ HttpRequest req Params p → HttpResponse {
        : i id ?? ( params_get p `id` ) { T s → ?? ( string_to_int s ) { T x → x F _ → -1 } F _ → -1 }
        : i cl ?? ( params_get p `client` ) { T s → ?? ( string_to_int s ) { T x → x F _ → -1 } F _ → -1 }
        : ~ Client c ?? ( client_connect_with ( netsim_dialer net 1 ) ( string_data ( netsim_node_ip net 2 ) ) DB_PORT ) {
            T x → x
            F _ → { ^ ( response_text 503 `no database` ) }
        }
        ( client_set_timeout c 500 )
        : i r ( apply c id cl )
        ( client_close c )
        ? < r 2 { ^ ( response_text 200 ? == r 0 `applied` `already applied` ) } {}
        ^ ( response_text 503 `try again` )
    } )
    ^ a
}

// One client: its operations in turn, each retried until it is answered
// 200 or TRIES run out. The ids it was told succeeded go into `acked`;
// `done` counts the clients that finished.
@ client_thread NetSim net i me ( Locked ( Vec i ) ) acked Atomic done → !Thread ThreadErr {
    ^ ( thread_spawn \ → v {
        : HttpClient hc ( http_client_new )
        ( http_client_set_dialer hc ( netsim_dialer net 0 ) )
        ( http_client_set_timeout hc 1500 )
        : ~ i k 0
        ~ < k OPS {
            : i id + * me 1000 k
            : String url ( string_from `http://` )
            ( string_push_str url ( string_data ( netsim_node_ip net 1 ) ) )
            ( string_push_str url `/op/` )
            ( string_push_int url id )
            ( string_push_str url `/` )
            ( string_push_int url me )
            : ~ i t 0
            ~ < t TRIES {
                : ~ b answered F
                ?? ( http_client_get hc ( string_data url ) ) {
                    T r → { = answered == . r status 200 }
                    F _ → {}
                }
                ? answered {
                    ( locked_update [( Vec i )] acked \ inout ( Vec i ) v → v { ( vec_push [i] v id ) } )
                    = t TRIES
                } {
                    ( sleep_ms 20 )
                    = t + t 1
                }
            }
            = k + k 1
        }
        : i _d ( atomic_add done 1 )
    } )
}

// The database node's server: serve_on in a thread of its own.
@ db_server Db d TcpListener l → !Thread ThreadErr {
    ^ ( thread_spawn \ → v {
        : !v String _r ( serve_on d l )
    } )
}

@ join_all ( Vec Thread ) ts → v {
    : ~ i j 0
    ~ < j ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts j ) { T t → { : i _x ( thread_join t ) } F _ → {} }
        = j + j 1
    }
}

@ scalar inout Session s s q → i {
    ^ ?? ( session_exec s ( string_from q ) ) {
        T r → ? == 0 ( vec_len [( Vec Value )] . r rows ) -1 ?? ( vec_at [Value] ( vec_at [( Vec Value )] . r rows 0 ) 0 ) { VInt x → x _ → -1 }
        F _ → -1
    }
}

@ main → i {
    : String dir ?? ( fs_tempdir `/tmp` `nurl_dst` ) {
        T x → x
        F _ → {
            ( nurl_print `no temporary directory\n` )
            ^ 1
        }
    }
    : NetSim net ( netsim_new 3 262 0 1 1 )

    // ── the database, node 2 ──
    : ~ Db d ?? ( db_open ( string_data dir ) ( db_default_opts ) ) {
        T x → x
        F e → {
            ( nurl_println ( string_data e ) )
            ^ 1
        }
    }
    : ~ Session boot ( session_new d )
    : b schema & & ( sql_ok boot `CREATE TABLE acct (id INT PRIMARY KEY, bal INT)` ) ( sql_ok boot `INSERT INTO acct VALUES (1, 0)` ) ( sql_ok boot `CREATE TABLE ops (op INT PRIMARY KEY, client INT)` )
    ( session_close boot )
    ( check `schema` schema )
    : TcpListener l ?? ( netsim_listen net 2 DB_PORT ) {
        T x → x
        F _ → {
            ( nurl_print `listen failed\n` )
            ^ 1
        }
    }
    : ~ ! Thread ThreadErr dbsrv ( db_server ( Db_share d ) l )

    // ── the service, node 1 ──
    : TcpListener hl ?? ( netsim_listen net 1 80 ) {
        T x → x
        F _ → {
            ( nurl_print `listen failed\n` )
            ^ 1
        }
    }
    : TcpListener hstop ( TcpListener_share hl )
    : NetSim snet ( NetSim_share net )
    : !Thread ThreadErr websrv ( thread_spawn \ → v {
        : i _rc ( http_app_serve ( service snet ) ( TcpListener_share hl ) )
    } )

    // ── the clients, node 0 ──
    : ( Locked ( Vec i ) ) acked ( locked_new [( Vec i )] ( vec_new [i] ) )
    : Atomic done ( atomic_new 0 )
    : ( Vec Thread ) clients ( vec_new [Thread] )
    : ~ i me 1
    ~ <= me CLIENTS {
        ?? ( client_thread ( NetSim_share net ) me ( Locked_share [( Vec i )] acked ) ( Atomic_share done ) ) {
            T t → { ( vec_push [Thread] clients t ) }
            F _ → {}
        }
        = me + me 1
    }

    // ── the faults ──
    ( sleep_ms 40 )
    ( netsim_partition net 1 2 )
    ( sleep_ms 300 )
    ( netsim_heal net 1 2 )
    ( sleep_ms 40 )
    ( netsim_crash net 2 )
    ?? dbsrv { T h → { : i _j ( thread_join h ) } F _ → {} }
    ( db_crash d )
    = d ?? ( db_open ( string_data dir ) ( db_default_opts ) ) {
        T x → x
        F e → {
            ( nurl_println ( string_data e ) )
            ^ 1
        }
    }
    : TcpListener l2 ?? ( netsim_listen net 2 DB_PORT ) {
        T x → x
        F _ → {
            ( nurl_print `listen after the crash failed\n` )
            ^ 1
        }
    }
    = dbsrv ( db_server ( Db_share d ) l2 )
    ( nurl_print `faults: the service cut off from the database for 300 ms, then the database crashed and restarted\n` )

    // ── the end ──
    ( join_all clients )
    ( check `every client finished` == ( atomic_load done ) CLIENTS )
    ( tcp_close_listener hstop )
    ?? websrv { T h → { : i _j ( thread_join h ) } F _ → {} }
    ( netsim_crash net 2 )
    ?? dbsrv { T h → { : i _j ( thread_join h ) } F _ → {} }

    : ~ Session s ( session_new d )
    : i receipts ( scalar s `SELECT COUNT(*) FROM ops` )
    : i bal ( scalar s `SELECT bal FROM acct WHERE id = 1` )
    ( check `none applied twice: the balance is the number of receipts` & > receipts 0 == bal receipts )
    : ( Vec i ) ids ( locked_get [( Vec i )] acked )
    : ~ b all_there T
    : ~ i j 0
    ~ < j ( vec_len [i] ids ) {
        : String q ( string_from `SELECT COUNT(*) FROM ops WHERE op = ` )
        ( string_push_int q ( vec_at [i] ids j ) )
        ? != 1 ( scalar s ( string_data q ) ) { = all_there F } {}
        = j + j 1
    }
    ( check `every acknowledged operation is there after the crash` & > ( vec_len [i] ids ) 0 all_there )
    ( session_close s )
    ( db_close d )
    : !v IoErr _rm ( dir_remove_all ( string_data dir ) )
    ^ 0
}

@ sql_ok inout Session s s q → b { ^ ?? ( session_exec s ( string_from q ) ) { T _ → T F _ → F } }
