// packages/psql/tests/live_test.nu — the client against a live server:
// SCRAM over plaintext and TLS, sslmode's verdicts, the simple and the
// extended protocol, typed parameters and binary cells round-tripped
// through real columns, the statement cache (its bound, its eviction, a
// statement gone stale under it), errors and transactions, and pg_pool
// shared by fibers and threads. Releases nothing by hand; runs clean under
// AddressSanitizer.
//
// Needs a server: PSQL_TEST_PORT (and PSQL_TEST_HOST, _USER, _PASSWORD,
// _DB; defaults 127.0.0.1, postgres, empty, postgres) — tests/live_smoke.sh
// starts a throwaway cluster and sets them. Without PSQL_TEST_PORT it
// prints `skipped` and exits 0. The server's certificate is expected to be
// self-signed (verify-full must refuse it).
//
//   cd packages/psql
//   PSQL_TEST_PORT=5432 NURL_SAN=1 NURL_STDLIB=<repo-root> ../../nurl.sh tests/live_test.nu /tmp/plt && /tmp/plt

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/thread.nu`
$ `src/pg.nu`

: ~ i g_fail 0

@ ok s name b cond → v {
    ? cond { ( nurl_print `ok   ` ) } { ( nurl_print `FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}

: Dsn { String host i port String user String password String db }

@ env_or s name s dflt → String {
    ?? ( env_get name ) { T v → ^ v F → ^ ( string_from dflt ) }
}

@ connect Dsn d i sslmode → !PgConn PgErr {
    ^ ( pg_connect ( string_data . d host ) . d port ( string_data . d user ) ( string_data . d password ) ( string_data . d db ) sslmode )
}

// The DSN as a postgres:// URI, user and password percent-encoded.
@ dsn_url Dsn d s sslmode → String {
    : String u ( string_from `postgres://` )
    ( string_append u ( url_percent_encode ( string_data . d user ) ) )
    ( string_push_str u `:` )
    ( string_append u ( url_percent_encode ( string_data . d password ) ) )
    ( string_push_str u `@` )
    ( string_append u . d host )
    ( string_push_str u `:` )
    ( string_push_int u . d port )
    ( string_push_str u `/` )
    ( string_append u ( url_percent_encode ( string_data . d db ) ) )
    ( string_push_str u `?sslmode=` )
    ( string_push_str u sslmode )
    ^ u
}

// T when pg_connect_url refuses `url` as PgBadUrl (before any connection).
@ bad_url s url → b {
    ?? ( pg_connect_url url ) {
        T _ → { ^ F }
        F e → { ^ != 0 ( nurl_str_eq ( pg_err_name e ) `PgBadUrl` ) }
    }
}

@ q PgConn c s sql → b {
    ?? ( pg_query c sql ) {
        T _ → { ^ T }
        F _ → { ( nurl_print `  ` ) ( nurl_print ( string_data ( pg_conn_lasterr c ) ) ) ( nurl_print `\n` ) ^ F }
    }
}

@ opt_i_is ? i o i want → b { ?? o { T x → { ^ == x want } F → { ^ F } } }

@ opt_s_is ? String o s want → b {
    ?? o { T s → { ^ != 0 ( nurl_str_eq ( string_data s ) want ) } F → { ^ F } }
}

@ ival i n → PgVal { ^ @ PgVal { PgInt n } }

@ tval s t → PgVal { ^ @ PgVal { PgText ( string_from t ) } }

@ params1 PgVal a → ( Vec PgVal ) {
    : ( Vec PgVal ) v ( vec_new [PgVal] )
    ( vec_push [PgVal] v a )
    ^ v
}

@ params2 PgVal a PgVal b → ( Vec PgVal ) {
    : ( Vec PgVal ) v ( vec_new [PgVal] )
    ( vec_push [PgVal] v a )
    ( vec_push [PgVal] v b )
    ^ v
}

// The value of a one-cell query, as an integer (-1 on failure).
@ one_int PgConn c s sql ( Vec PgVal ) ps → i {
    ?? ( pg_query_params c sql ps ) {
        T r → { ?? ( pg_row_i r 0 0 ) { T x → ^ x F → ^ -1 } }
        F _ → { ( nurl_print `  ` ) ( nurl_print ( string_data ( pg_conn_lasterr c ) ) ) ( nurl_print `\n` ) ^ -1 }
    }
}

@ main → i {
    ?? ( env_get `PSQL_TEST_PORT` ) { T _ → {} F → { ( nurl_print `skipped (set PSQL_TEST_PORT)\n` ) ^ 0 } }
    : Dsn d @ Dsn {
        ( env_or `PSQL_TEST_HOST` `127.0.0.1` )
        ?? ( string_to_int ( env_or `PSQL_TEST_PORT` `5432` ) ) { T x → x F _ → 5432 }
        ( env_or `PSQL_TEST_USER` `postgres` )
        ( env_or `PSQL_TEST_PASSWORD` `` )
        ( env_or `PSQL_TEST_DB` `postgres` )
    }

    // ── connection URI ──
    ?? ( pg_connect_url ( string_data ( dsn_url d `require` ) ) ) {
        T c → { ( ok `url: a postgres:// URI connects, sslmode=require over TLS` & == ( pg_conn_tls c ) 1 == ( one_int c `SELECT 7` ( vec_new [PgVal] ) ) 7 ) }
        F e → { ( ok `url: a postgres:// URI connects, sslmode=require over TLS` F ) ( nurl_print ( pg_err_name e ) ) ( nurl_print `\n` ) }
    }
    ?? ( pg_connect_url ( string_data ( dsn_url d `disable` ) ) ) {
        T c → { ( ok `url: sslmode=disable stays plaintext` == ( pg_conn_tls c ) 0 ) }
        F e → { ( ok `url: sslmode=disable stays plaintext` F ) }
    }
    ( ok `url: another scheme is refused` ( bad_url `mysql://127.0.0.1/db` ) )
    ( ok `url: no host is refused` ( bad_url `postgres:///db` ) )
    ( ok `url: a parameter it would ignore is refused` ( bad_url `postgres://127.0.0.1/db?connect_timeout=5` ) )
    ( ok `url: an sslmode this client lacks is refused` ( bad_url `postgres://127.0.0.1/db?sslmode=verify-ca` ) )

    // ── sslmode, SCRAM ──
    ?? ( connect d 0 ) {
        T c → { ( ok `disable: plaintext SCRAM login` == ( pg_conn_tls c ) 0 ) }
        F e → { ( ok `disable: plaintext SCRAM login` F ) ( nurl_print ( pg_err_name e ) ) ( nurl_print `\n` ) }
    }
    ?? ( connect d 2 ) {
        T c → { ( ok `require: TLS` == ( pg_conn_tls c ) 1 ) }
        F e → { ( ok `require: TLS` F ) }
    }
    ?? ( connect d 1 ) {
        T c → { ( ok `prefer: TLS when offered` == ( pg_conn_tls c ) 1 ) }
        F e → { ( ok `prefer: TLS when offered` F ) }
    }
    ?? ( connect d 3 ) {
        T c → { ( ok `verify-full refuses a self-signed certificate` F ) }
        F e → { ( ok `verify-full refuses a self-signed certificate` ?? e { PgTls → T _ → F } ) }
    }
    : Dsn bad @ Dsn { ( string_clone . d host ) . d port ( string_clone . d user ) ( string_from `wrong password` ) ( string_clone . d db ) }
    ?? ( connect bad 2 ) {
        T c → { ( ok `a wrong password is refused` F ) }
        F e → { ( ok `a wrong password is refused` ?? e { PgServerError → T PgAuth → T _ → F } ) }
    }

    : PgConn c ?? ( connect d 2 ) { T x → x F e → { ( nurl_print `connect failed\n` ) ^ 1 } }

    // ── the simple protocol: a script ──
    ( ok `script` ( q c `DROP TABLE IF EXISTS nurl_t; CREATE TABLE nurl_t (id int4 PRIMARY KEY, small int2, big int8, name text, score float8, ratio float4, flag bool, born date, seen timestamptz, at timestamp, uid uuid, blob bytea, amount numeric, note varchar(40))` ) )
    ?? ( pg_query c `SELECT 1 AS a; SELECT 2 AS b, 'x' AS c` ) {
        T r → { ( ok `script: the last statement's rows` & == . r ncols 2 ( opt_s_is ( pg_row_s r 0 1 ) `x` ) ) }
        F _ → { ( ok `script: the last statement's rows` F ) }
    }
    ?? ( pg_query c `SELECT 42::int8 AS n, NULL::text AS z, true AS t` ) {
        T r → {
            ( ok `simple: text cells decode as integers` ( opt_i_is ( pg_row_i r 0 0 ) 42 ) )
            ( ok `simple: NULL` ( pg_row_is_null r 0 1 ) )
            ( ok `simple: bool from t` ?? ( pg_row_b r 0 2 ) { T x → x F → F } )
        }
        F _ → { ( ok `simple select` F ) }
    }

    // ── typed parameters into every column, binary cells back ──
    : ( Vec PgVal ) row ( vec_new [PgVal] )
    ( vec_push [PgVal] row ( ival 1 ) )
    ( vec_push [PgVal] row ( ival -32768 ) )
    ( vec_push [PgVal] row ( ival 9007199254740993 ) )
    ( vec_push [PgVal] row ( tval `O'Brien'); DROP TABLE nurl_t; --` ) )
    ( vec_push [PgVal] row @ PgVal { PgFloat 2.5 } )
    ( vec_push [PgVal] row @ PgVal { PgFloat 0.1 } )
    ( vec_push [PgVal] row @ PgVal { PgBool T } )
    ( vec_push [PgVal] row @ PgVal { PgDate 19782 } )
    ( vec_push [PgVal] row @ PgVal { PgTimestamp 1709210096500000 } )
    ( vec_push [PgVal] row ( tval `1999-12-31 23:59:59.999999` ) )
    ( vec_push [PgVal] row ( tval `01234567-89ab-cdef-fedc-ba9876543210` ) )
    : ( Vec u ) blob ( vec_new [u] )
    ( vec_push [u] blob # u 0 ) ( vec_push [u] blob # u 255 ) ( vec_push [u] blob # u 10 )
    ( vec_push [PgVal] row @ PgVal { PgBytes blob } )
    ( vec_push [PgVal] row ( ival 12345678901234 ) )
    ( vec_push [PgVal] row @ PgVal { PgNull } )
    ?? ( pg_query_params c `INSERT INTO nurl_t VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)` row ) {
        T r → { ( ok `insert with typed parameters` == ( pg_result_affected r ) 1 ) }
        F _ → { ( ok `insert with typed parameters` F ) ( nurl_print ( string_data ( pg_conn_lasterr c ) ) ) ( nurl_print `\n` ) }
    }
    ?? ( pg_query_params c `SELECT id, small, big, name, score, ratio, flag, born, seen, at, uid, blob, amount, note FROM nurl_t WHERE id = $1` ( params1 ( ival 1 ) ) ) {
        T r → {
            ( ok `one row back` == . r nrows 1 )
            ( ok `int4` ( opt_i_is ( pg_row_i r 0 0 ) 1 ) )
            ( ok `int2 at its minimum` ( opt_i_is ( pg_row_i r 0 1 ) -32768 ) )
            ( ok `int8 past 2^53` ( opt_i_is ( pg_row_i r 0 2 ) 9007199254740993 ) )
            ( ok `text stored verbatim (no interpolation)` ( opt_s_is ( pg_row_s r 0 3 ) `O'Brien'); DROP TABLE nurl_t; --` ) )
            ( ok `float8` ?? ( pg_row_f r 0 4 ) { T x → == x 2.5 F → F } )
            ( ok `float4 renders shortest` ( opt_s_is ( pg_row_s r 0 5 ) `0.1` ) )
            ( ok `bool` ?? ( pg_row_b r 0 6 ) { T x → x F → F } )
            ( ok `date` ( opt_i_is ( pg_row_date r 0 7 ) 19782 ) )
            ( ok `date renders` ( opt_s_is ( pg_row_s r 0 7 ) `2024-02-29` ) )
            ( ok `timestamptz` ( opt_i_is ( pg_row_ts r 0 8 ) 1709210096500000 ) )
            ( ok `timestamptz renders in UTC` ( opt_s_is ( pg_row_s r 0 8 ) `2024-02-29 12:34:56.5+00` ) )
            ( ok `timestamp from text` ( opt_s_is ( pg_row_s r 0 9 ) `1999-12-31 23:59:59.999999` ) )
            ( ok `uuid` ( opt_s_is ( pg_row_s r 0 10 ) `01234567-89ab-cdef-fedc-ba9876543210` ) )
            ( ok `bytea binary` ?? ( pg_row_bytes r 0 11 ) { T v → & == ( vec_len [u] v ) 3 == # i ( vec_at [u] v 1 ) 255 F → F } )
            ( ok `numeric comes as text` ( opt_s_is ( pg_row_s r 0 12 ) `12345678901234` ) )
            ( ok `numeric as a float` ?? ( pg_row_f r 0 12 ) { T x → == x 12345678901234.0 F → F } )
            ( ok `NULL varchar` ( pg_row_is_null r 0 13 ) )
            ( ok `binary formats were asked for` & == ( pg_result_col_type r 0 ) PG_INT4 == ( pg_result_col_fmt r 0 ) 1 )
            ( ok `text format for numeric` == ( pg_result_col_fmt r 12 ) 0 )
        }
        F _ → { ( ok `select with a parameter` F ) ( nurl_print ( string_data ( pg_conn_lasterr c ) ) ) ( nurl_print `\n` ) }
    }
    // The server infers each parameter's type; a value is sent the way that type takes it.
    ( ok `int into a numeric expression` == ( one_int c `SELECT ($1::numeric * 2)::int8` ( params1 ( ival 21 ) ) ) 42 )
    ( ok `text into an int4` == ( one_int c `SELECT $1::int4 + 1` ( params1 ( tval `41` ) ) ) 42 )
    ( ok `int2 out of range is the server's error` == ( one_int c `SELECT $1::int2` ( params1 ( ival 70000 ) ) ) -1 )
    ( ok `…22003` != 0 ( nurl_str_eq ( string_data ( pg_conn_sqlstate c ) ) `22003` ) )
    ( ok `the connection is still usable` == ( one_int c `SELECT $1::int8` ( params1 ( ival 7 ) ) ) 7 )

    // ── the statement cache ──
    : i n0 ( pg_conn_stmt_count c )
    ( ok `cached: the same SQL again` == ( one_int c `SELECT $1::int8` ( params1 ( ival 8 ) ) ) 8 )
    ( ok `…prepared once` == ( pg_conn_stmt_count c ) n0 )
    ( pg_conn_set_stmt_cache c 2 )
    ( ok `bounded: a` == ( one_int c `SELECT $1::int8 + 100` ( params1 ( ival 1 ) ) ) 101 )
    ( ok `bounded: b` == ( one_int c `SELECT $1::int8 + 200` ( params1 ( ival 1 ) ) ) 201 )
    ( ok `bounded: c` == ( one_int c `SELECT $1::int8 + 300` ( params1 ( ival 1 ) ) ) 301 )
    ( ok `bounded: at most 2 kept` <= ( pg_conn_stmt_count c ) 2 )
    ?? ( pg_query c `SELECT count(*) FROM pg_prepared_statements` ) {
        T r → { ( ok `bounded: the evicted ones closed on the server` <= ?? ( pg_row_i r 0 0 ) { T x → x F → 99 } 2 ) }
        F _ → { ( ok `prepared statements` F ) }
    }
    ( ok `evicted, then needed again` == ( one_int c `SELECT $1::int8 + 100` ( params1 ( ival 2 ) ) ) 102 )
    // A table changing shape under a cached statement: prepared again.
    ( ok `stale: setup` ( q c `DROP TABLE IF EXISTS nurl_s; CREATE TABLE nurl_s (a int4); INSERT INTO nurl_s VALUES (5)` ) )
    ?? ( pg_query_params c `SELECT * FROM nurl_s WHERE a = $1` ( params1 ( ival 5 ) ) ) { T r → { ( ok `stale: first run` == . r ncols 1 ) } F _ → { ( ok `stale: first run` F ) } }
    ( ok `stale: alter` ( q c `ALTER TABLE nurl_s ADD COLUMN b text DEFAULT 'x'` ) )
    ?? ( pg_query_params c `SELECT * FROM nurl_s WHERE a = $1` ( params1 ( ival 5 ) ) ) {
        T r → { ( ok `stale: re-prepared, new shape` & == . r ncols 2 ( opt_s_is ( pg_row_s r 0 1 ) `x` ) ) }
        F _ → { ( ok `stale: re-prepared, new shape` F ) ( nurl_print ( string_data ( pg_conn_lasterr c ) ) ) ( nurl_print `\n` ) }
    }
    ( ok `DEALLOCATE ALL under the cache` ( q c `DEALLOCATE ALL` ) )
    ( ok `…prepared again` == ( one_int c `SELECT $1::int8 + 100` ( params1 ( ival 3 ) ) ) 103 )
    ( pg_conn_set_stmt_cache c 0 )
    ( ok `no cache: unnamed statements` == ( one_int c `SELECT $1::int8 * 3` ( params1 ( ival 3 ) ) ) 9 )
    ( ok `no cache: none kept` == ( pg_conn_stmt_count c ) 0 )
    ( pg_conn_set_stmt_cache c 64 )

    // ── errors and transactions ──
    ?? ( pg_query_params c `SELEKT 1` ( vec_new [PgVal] ) ) {
        T _ → { ( ok `syntax error` F ) }
        F e → { ( ok `syntax error` & ?? e { PgServerError → T _ → F } != 0 ( nurl_str_eq ( string_data ( pg_conn_sqlstate c ) ) `42601` ) ) }
    }
    ( ok `begin` ( q c `BEGIN` ) )
    ( ok `in a transaction` == ( pg_conn_txn_status c ) 84 )
    ( ok `an error inside it` ! ( q c `SELECT 1/0` ) )
    ( ok `…fails the transaction` == ( pg_conn_txn_status c ) 69 )
    ( ok `rollback` ( q c `ROLLBACK` ) )
    ( ok `idle again` == ( pg_conn_txn_status c ) 73 )

    // ── many rows, both protocols ──
    ?? ( pg_query_params c `SELECT g, g * 2 FROM generate_series(1, $1::int4) g` ( params1 ( ival 50000 ) ) ) {
        T r → {
            : ~ i sum 0
            : ~ i k 0
            ~ < k . r nrows { = sum + sum ?? ( pg_row_i r k 1 ) { T x → x F → 0 } = k + k 1 }
            ( ok `50000 binary rows` & == . r nrows 50000 == sum 2500050000 )
        }
        F _ → { ( ok `50000 binary rows` F ) }
    }
    ?? ( pg_query c `SELECT g FROM generate_series(1, 50000) g` ) {
        T r → {
            : ~ i sum 0
            : ~ i k 0
            ~ < k . r nrows { = sum + sum ?? ( pg_row_i r k 0 ) { T x → x F → 0 } = k + k 1 }
            ( ok `50000 text rows` == sum 1250025000 )
        }
        F _ → { ( ok `50000 text rows` F ) }
    }

    // ── the pool: fibers ──
    : ( Pool PgConn PgErr ) pool ( pg_pool_new ( string_data . d host ) . d port ( string_data . d user ) ( string_data . d password ) ( string_data . d db ) 2 @ PoolCfg { 1 3 10000 60000 } )
    ( ok `pool fill` ?? ( pool_fill [PgConn PgErr] pool ) { T _ → T F _ → F } )
    : Atomic good ( atomic_new 0 )
    : Atomic most ( atomic_new 0 )
    ( runtime_init 4 )
    : ~ i f 0
    ~ < f 12 {
        : i me f
        ( spawn \ → v {
            : ~ i k 0
            ~ < k 20 {
                ?? ( pg_pool_get pool ) {
                    T g → {
                        : PgConn pc ( pooled_get [PgConn PgErr] g )
                        ? == ( one_int pc `SELECT $1::int8 + $2::int8` ( params2 ( ival me ) ( ival k ) ) ) + me k { ( atomic_add good 1 ) } {}
                        ( atomic_max most ( pool_live [PgConn PgErr] pool ) )
                    }
                    F _ → {}
                }
                = k + k 1
            }
        } )
        = f + f 1
    }
    ( runtime_run )
    ( ok `pool on fibers: every query` == ( atomic_load good ) 240 )
    ( ok `pool on fibers: never more than max` <= ( atomic_load most ) 3 )

    // ── the pool: threads ──
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : i me + t 100
        ?? ( thread_spawn \ → v {
            : ~ i k 0
            ~ < k 10 {
                ?? ( pg_pool_get pool ) {
                    T g → {
                        ? == ( one_int ( pooled_get [PgConn PgErr] g ) `SELECT $1::int8 + $2::int8` ( params2 ( ival me ) ( ival k ) ) ) + me k { ( atomic_add good 1 ) } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
        } ) { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        = t + t 1
    }
    ~ th ts { ( thread_join th ) }
    ( ok `pool on threads: every query` == ( atomic_load good ) 280 )
    ( ok `pool: never more than max` <= ( pool_live [PgConn PgErr] pool ) 3 )

    // ── pipelining: one connection, many fibers at once ──
    // Every fiber's answers are its own, an error stays with the request
    // that caused it, and a lost stream fails every request on its way.
    : PgConn shared ?? ( connect d 2 ) {
        T x → x
        F _ → { ( nurl_print `connect failed\n` ) ^ 1 }
    }
    : Atomic mine_ok ( atomic_new 0 )
    : ~ i pf 0
    ~ < pf 16 {
        : i me + pf 1000
        : PgConn sc ( PgConn_share shared )
        : Atomic mo ( Atomic_share mine_ok )
        ( spawn \ → v {
            : ~ i k 0
            ~ < k 25 {
                : i x + * me 100 k
                ? == ( one_int sc `SELECT $1::int8 * 2` ( params1 ( ival x ) ) ) * x 2 { ( atomic_add mo 1 ) } {}
                = k + k 1
            }
        } )
        = pf + pf 1
    }
    ( runtime_run )
    ( ok `pipeline: 16 fibers on one connection, every answer its own` == ( atomic_load mine_ok ) 400 )

    : Atomic good_ok ( atomic_new 0 )
    : Atomic bad_failed ( atomic_new 0 )
    = pf 0
    ~ < pf 8 {
        : i me pf
        : PgConn sc ( PgConn_share shared )
        : Atomic go ( Atomic_share good_ok )
        : Atomic bf ( Atomic_share bad_failed )
        ( spawn \ → v {
            : ~ i k 0
            ~ < k 10 {
                ? == ( one_int sc `SELECT $1::int8 + 1` ( params1 ( ival + * me 10 k ) ) ) + + * me 10 k 1 { ( atomic_add go 1 ) } {}
                ?? ( pg_query sc `SELECT 1 / 0` ) { T _ → {} F e → { ? != 0 ( nurl_str_eq ( pg_err_name e ) `PgServerError` ) { ( atomic_add bf 1 ) } {} } }
                = k + k 1
            }
        } )
        = pf + pf 1
    }
    ( runtime_run )
    ( ok `pipeline: interleaved with errors, every good query answered` == ( atomic_load good_ok ) 80 )
    ( ok `pipeline: every failing query fails alone` == ( atomic_load bad_failed ) 80 )
    ( ok `pipeline: the connection is still fine` & ( pg_conn_ok shared ) == ( one_int shared `SELECT $1::int8` ( params1 ( ival 7 ) ) ) 7 )

    // The server ends the session while requests are queued on it.
    : i victim ( one_int shared `SELECT pg_backend_pid()::int8` ( vec_new [PgVal] ) )
    : Atomic lost_n ( atomic_new 0 )
    = pf 0
    ~ < pf 6 {
        : PgConn sc ( PgConn_share shared )
        : Atomic ln ( Atomic_share lost_n )
        ( spawn \ → v {
            ?? ( pg_query sc `SELECT pg_sleep(0.3)` ) { T _ → {} F _ → { ( atomic_add ln 1 ) } }
        } )
        = pf + pf 1
    }
    : PgConn killer ( PgConn_share c )
    ( spawn \ → v {
        ( sleep_ms 100 )
        : ( Vec PgVal ) kp ( params1 ( ival victim ) )
        ?? ( pg_query_params killer `SELECT pg_terminate_backend($1::int4)` kp ) { T _ → {} F _ → {} }
    } )
    ( runtime_run )
    ( ok `pipeline: a lost stream fails every request on it` == ( atomic_load lost_n ) 6 )
    ( ok `pipeline: and the connection says so` ! ( pg_conn_ok shared ) )
    ( ok `pipeline: a request after it fails at once` ?? ( pg_query shared `SELECT 1` ) { T _ → F F e → != 0 ( nurl_str_eq ( pg_err_name e ) `PgConnFail` ) } )

    // A connection given back inside a transaction is rolled back.
    ?? ( pg_pool_get pool ) {
        T g → { ( ok `pool: begin and leave` ( q ( pooled_get [PgConn PgErr] g ) `BEGIN` ) ) }
        F _ → {}
    }
    ?? ( pg_pool_get pool ) {
        T g → { ( ok `pool: the next borrower is idle` == ( pg_conn_txn_status ( pooled_get [PgConn PgErr] g ) ) 73 ) }
        F _ → {}
    }
    ( runtime_shutdown )

    ( ok `cleanup` ( q c `DROP TABLE nurl_t; DROP TABLE nurl_s` ) )
    ? > g_fail 0 {
        ( nurl_print ( nurl_str_int g_fail ) ) ( nurl_print ` FAILED\n` )
        ^ 1
    } {}
    ( nurl_print `all passed\n` )
    ^ 0
}
