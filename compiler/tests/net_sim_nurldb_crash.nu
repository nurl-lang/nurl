// net_sim_nurldb_crash: nurldb's server on a node of a simulated network
// (std/net_sim.nu), crashed and restarted inside one process — the DB
// half of the DST flagship scenario (Agora #262).
//
// Node 1 serves a database (packages/nurldb serve_on, on a netsim_listen
// listener); node 0 is a client dialing through netsim_dialer
// (client_connect_with). Two rows are committed, a third is inserted in a
// transaction left open, and node 1 crashes (netsim_crash: every socket
// gone at once, no FIN). The client's next statement fails cleanly; the
// server's accept loop and its connection end, serve_on returns, and the
// database is dropped as a killed process would leave it (db_crash: no
// checkpoint, dirty pages lost). Reopened, it recovers from its log: the
// committed rows are there and the open transaction's row is not. The
// rebooted node serves again on the same port, and the client reconnects.
$ `stdlib/core/io.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/net_sim.nu`
$ `packages/nurldb/src/server.nu`

@ check s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `: ok\n` `: FAILED\n` )
}

@ run inout Client c s sql → !String String { ^ ( client_exec c ( string_from sql ) ) }

@ ok inout Client c s sql → b { ^ ?? ( run c sql ) { T _ → T F _ → F } }

// The answer to `sql`, or `error: …`.
@ answer inout Client c s sql → String {
    ^ ?? ( run c sql ) {
        T r → r
        F e → ( string_concat ( string_from `error: ` ) e )
    }
}

@ serve_thread Db d TcpListener l → !Thread ThreadErr {
    ^ ( thread_spawn \ → v {
        : !v String _r ( serve_on d l )
    } )
}

@ main → i {
    // The platform's temp directory (env_temp_dir). On Windows `/tmp`
    // is \tmp on the current drive, which exists only if an earlier
    // test happened to make it.
    : String troot ( env_temp_dir )
    : String dir ?? ( fs_tempdir ( string_data troot ) `nurldb_sim` ) {
        T x → x
        F _ → {
            ( nurl_print `no temporary directory\n` )
            ^ 1
        }
    }
    // Two nodes, a seed, no loss, 1 ms of latency.
    : NetSim net ( netsim_new 2 7 0 1 0 )
    : String host ( netsim_node_ip net 1 )

    // ── first life ──
    : Db d ?? ( db_open ( string_data dir ) ( db_default_opts ) ) {
        T x → x
        F e → {
            ( nurl_println ( string_data e ) )
            ^ 1
        }
    }
    : TcpListener l ?? ( netsim_listen net 1 5433 ) {
        T x → x
        F _ → {
            ( nurl_print `listen failed\n` )
            ^ 1
        }
    }
    : !Thread ThreadErr srv ( serve_thread ( Db_share d ) l )
    : ~ Client c ?? ( client_connect_with ( netsim_dialer net 0 ) ( string_data host ) 5433 ) {
        T x → x
        F e → {
            ( nurl_println ( string_data e ) )
            ^ 1
        }
    }
    ( check `create a table over the simulated network` ( ok c `CREATE TABLE kv (k INT PRIMARY KEY, v INT)` ) )
    ( check `two rows committed` ( ok c `INSERT INTO kv VALUES (1, 10), (2, 20)` ) )
    ( check `a third in a transaction left open` & ( ok c `BEGIN` ) ( ok c `INSERT INTO kv VALUES (3, 30)` ) )

    // ── the crash ──
    ( netsim_crash net 1 )
    ( check `the next statement fails, not hangs` ! ( ok c `SELECT k FROM kv` ) )
    ( client_close c )
    ?? srv {
        T h → { : i _j ( thread_join h ) }
        F _ → {}
    }
    ( check `the server's loop and its connection ended` T )
    ( db_crash d )

    // ── second life: recovery from the log ──
    : Db d2 ?? ( db_open ( string_data dir ) ( db_default_opts ) ) {
        T x → x
        F e → {
            ( nurl_println ( string_data e ) )
            ^ 1
        }
    }
    : TcpListener l2 ?? ( netsim_listen net 1 5433 ) {
        T x → x
        F _ → {
            ( nurl_print `listen after the crash failed\n` )
            ^ 1
        }
    }
    : !Thread ThreadErr srv2 ( serve_thread ( Db_share d2 ) l2 )
    : ~ Client c2 ?? ( client_connect_with ( netsim_dialer net 0 ) ( string_data host ) 5433 ) {
        T x → x
        F e → {
            ( nurl_println ( string_data e ) )
            ^ 1
        }
    }
    : String rows ( answer c2 `SELECT k, v FROM kv ORDER BY k` )
    ( nurl_print `after recovery:\n` )
    ( nurl_print ( string_data rows ) )
    ( check `writes go on after the restart` ( ok c2 `INSERT INTO kv VALUES (4, 40)` ) )
    ( nurl_print ( string_data ( answer c2 `SELECT COUNT(*) FROM kv` ) ) )
    ( client_close c2 )

    // Done: this life ends by a crash too, then a clean close.
    ( netsim_crash net 1 )
    ?? srv2 {
        T h → { : i _j ( thread_join h ) }
        F _ → {}
    }
    ( db_close d2 )
    : !v IoErr _rm ( dir_remove_all ( string_data dir ) )
    ^ 0
}
