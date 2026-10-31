// packages/psql/tests/pipeline_bench.nu — queries per second on ONE
// connection, shared by F fibers (Agora #40). Each fiber runs Q
// parameterised queries (`SELECT $1::int4 + 1`, the statement cached) and
// checks every answer; the program prints one line per F:
//
//   fibers=F queries=N seconds=S qps=R wrong=W
//
// Without pipelining a connection carries one query at a time, so qps is
// one over the round trip whatever F is; with it, F fibers keep up to F
// queries in flight on the one socket.
//
// Needs a server, as tests/live_test.nu: PSQL_TEST_PORT (and _HOST, _USER,
// _PASSWORD, _DB). PSQL_BENCH_FIBERS (default "1 8 32 128"),
// PSQL_BENCH_QUERIES (per fiber, default 2000) and PSQL_BENCH_WORKERS
// (runtime workers, default 1) shape the run.
//
//   cd packages/psql
//   PSQL_TEST_PORT=5432 NURL_STDLIB=<repo-root> ../../nurl.sh tests/pipeline_bench.nu /tmp/pb && /tmp/pb

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/time.nu`
$ `src/pg.nu`

@ env_or s name s dflt → String {
    ?? ( env_get name ) { T v → ^ v F → ^ ( string_from dflt ) }
}

@ env_int s name i dflt → i {
    ?? ( env_get name ) {
        T v → { ?? ( string_to_int v ) { T x → ^ x F _ → ^ dflt } }
        F → ^ dflt
    }
}

// One fiber's share: `n` queries, each checked.
@ run_queries PgConn c i base i n Atomic wrong → v {
    : ~ i k 0
    ~ < k n {
        : i x + base k
        : ( Vec PgVal ) ps ( vec_new [PgVal] )
        ( vec_push [PgVal] ps @ PgVal { PgInt x } )
        ?? ( pg_query_params c `SELECT $1::int4 + 1` ps ) {
            T r → {
                : i got ?? ( pg_row_i r 0 0 ) { T v → v F → -1 }
                ? != got + x 1 { : i _w ( atomic_add wrong 1 ) } {}
            }
            F _ → { : i _e ( atomic_add wrong 1 ) }
        }
        = k + k 1
    }
}

@ main → i {
    : String port_s ( env_or `PSQL_TEST_PORT` `` )
    ? == ( string_len port_s ) 0 {
        ( nurl_print `skipped (no PSQL_TEST_PORT)\n` )
        ^ 0
    } {}
    : i port ?? ( string_to_int port_s ) { T x → x F _ → 5432 }
    : String host ( env_or `PSQL_TEST_HOST` `127.0.0.1` )
    : String user ( env_or `PSQL_TEST_USER` `postgres` )
    : String pw ( env_or `PSQL_TEST_PASSWORD` `` )
    : String db ( env_or `PSQL_TEST_DB` `postgres` )
    : String fibers_s ( env_or `PSQL_BENCH_FIBERS` `1 8 32 128` )
    : i per ( env_int `PSQL_BENCH_QUERIES` 2000 )
    : PgConn c ?? ( pg_connect ( string_data host ) port ( string_data user ) ( string_data pw ) ( string_data db ) 0 ) {
        T x → x
        F e → { ( nurl_print `connect failed: ` ) ( nurl_print ( pg_err_name e ) ) ( nurl_print `\n` ) ^ 1 }
    }
    ( runtime_init ( env_int `PSQL_BENCH_WORKERS` 1 ) )
    : ( Vec String ) counts ( string_split fibers_s ` ` )
    : ~ i ci 0
    ~ < ci ( vec_len [String] counts ) {
        : i f ?? ( string_to_int ( vec_at [String] counts ci ) ) { T x → x F _ → 1 }
        : Atomic wrong ( atomic_new 0 )
        : i t0 ( monotonic_ns )
        : ~ i k 0
        ~ < k f {
            : i base * k 1000000
            : PgConn cc ( PgConn_share c )
            : Atomic ww ( Atomic_share wrong )
            ( spawn_owned \ → v { ( run_queries cc base per ww ) } )
            = k + k 1
        }
        ( runtime_run )
        : i t1 ( monotonic_ns )
        : i n * f per
        : i us / - t1 t0 1000
        ( nurl_print `fibers=` ) ( nurl_print_int f )
        ( nurl_print ` queries=` ) ( nurl_print_int n )
        ( nurl_print ` ms=` ) ( nurl_print_int / us 1000 )
        ( nurl_print ` qps=` ) ( nurl_print_int ? > us 0 / * n 1000000 us 0 )
        ( nurl_print ` wrong=` ) ( nurl_print_int ( atomic_load wrong ) )
        ( nurl_print `\n` )
        = ci + ci 1
    }
    ( runtime_shutdown )
    ^ 0
}
