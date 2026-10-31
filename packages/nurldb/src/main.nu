// packages/nurldb/src/main.nu — the nurldb command.
//
//   nurldb DIR                      a shell: statements end with `;`
//   nurldb DIR -c "SQL; SQL …"      run the statements, print the results
//   nurldb serve DIR [PORT]         serve DIR over TCP (port 5433)
//   nurldb client [HOST] [PORT]     a shell talking to a server
//   nurldb bench DIR [THREADS] [SECONDS]
//                                   transfers from THREADS sessions for
//                                   SECONDS, then a parallel aggregate
//
// In the shell, `\dt` lists the tables and `\q` quits.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/time.nu`
$ `nurldb.nu`

: s VERSION `0.2.0`

@ usage → i {
    ( nurl_println ( nurl_str_cat `nurldb ` VERSION ) )
    ( nurl_println `usage: nurldb DIR [-c SQL] | serve DIR [PORT] | client [HOST] [PORT] | bench DIR [THREADS] [SECONDS]` )
    ^ 2
}

// The statements of `text`, split at each `;` outside a quoted string.
@ split_sql String text → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ( Slice u ) b ( string_bytes text )
    : ~ String cur ( string_new )
    : ~ b quoted F
    : ~ i k 0
    ~ < k ( slice_len [u] b ) {
        : i c ( slice_byte b k )
        ? == c 39 { = quoted ! quoted } {}
        ? & == c 59 ! quoted {
            ? > ( string_len ( string_trim cur ) ) 0 { ( vec_push [String] out cur ) } {}
            = cur ( string_new )
        } { ( string_push_char cur c ) }
        = k + k 1
    }
    ? > ( string_len ( string_trim cur ) ) 0 { ( vec_push [String] out cur ) } {}
    ^ out
}

@ run_one inout Session s String sql → b {
    ^ ?? ( session_exec s sql ) {
        T r → { ( nurl_print ( string_data ( result_text r ) ) ) T }
        F e → { ( nurl_print `ERROR: ` ) ( nurl_println ( string_data e ) ) F }
    }
}

// A shell over stdin: `exec` runs one statement.
@ shell ( @ v String ) exec ( @ v ) tables → v {
    : ~ String pending ( string_new )
    ~ T {
        ( nurl_print ? == 0 ( string_len pending ) `nurldb> ` `   ...> ` )
        ( flush )
        ? ( stdin_eof ) { break } {}
        : String line ( read_line )
        : String t ( string_trim line )
        ? & == 0 ( string_len pending ) != 0 ( nurl_str_eq ( string_data t ) `\\q` ) { break } {}
        ? & == 0 ( string_len pending ) != 0 ( nurl_str_eq ( string_data t ) `\\dt` ) { ( tables ) continue } {}
        ( string_push_str pending ( string_data line ) )
        ( string_push_char pending 32 )
        ? & > ( string_len t ) 0 == ( slice_byte ( string_bytes t ) - ( string_len t ) 1 ) 59 {
            : ( Vec String ) stmts ( split_sql pending )
            ~ st stmts { ( exec st ) }
            = pending ( string_new )
        } {}
        ? & ( stdin_eof ) == 0 ( string_len t ) { break } {}
    }
}

@ local_main s dir ( Vec String ) args → i {
    : Db d ?? ( db_open dir ( db_default_opts ) ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }
    : ~ Session s ( session_new d )
    : ~ i rc 0
    ? & >= ( vec_len [String] args ) 2 != 0 ( nurl_str_eq ( string_data ( vec_at [String] args 0 ) ) `-c` ) {
        : ( Vec String ) stmts ( split_sql ( vec_at [String] args 1 ) )
        ~ st stmts { ? ! ( run_one s st ) { = rc 1 } {} }
    } {
        ( shell \ String st → v { : b _ok ( run_one s st ) } \ → v {
            : ( Vec String ) names ( db_table_names d )
            ~ n names { ( nurl_println ( string_data n ) ) }
        } )
    }
    ( session_close s )
    ( db_close d )
    ^ rc
}

@ client_main s host i port → i {
    : ~ Client c ?? ( client_connect host port ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }
    ( shell \ String st → v {
        ?? ( client_exec c st ) { T out → { ( nurl_print ( string_data out ) ) } F e → { ( nurl_print `ERROR: ` ) ( nurl_println ( string_data e ) ) } }
    } \ → v {} )
    ( client_close c )
    ^ 0
}

@ q inout Session s s sql → b { ^ ?? ( session_exec s ( string_from sql ) ) { T _ → T F _ → F } }

@ bench_main s dir i threads i seconds → i {
    : Db d ?? ( db_open dir @ DbOpts { 4096 T } ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }
    : ~ Session s ( session_new d )
    : i naccts 10000
    : b _a ( q s `CREATE TABLE bench_acct (id INT PRIMARY KEY, bal INT NOT NULL)` )
    : TableInfo ti ?? ( db_table d ( string_from `bench_acct` ) ) { T x → x F → { ^ 1 } }
    {
        : ~ Txn x ( db_begin d )
        ( db_statement x )
        : ~ i k 0
        ~ < k naccts {
            : ( Vec Value ) row ( vec_new [Value] )
            ( vec_push [Value] row @ Value { VInt k } ) ( vec_push [Value] row @ Value { VInt 1000 } )
            : i _t ( db_insert d x ti row )
            = k + k 1
        }
        ( db_commit d x )
    }
    : Atomic commits ( atomic_new 0 )
    : Atomic conflicts ( atomic_new 0 )
    : i deadline + ( now_ms ) * seconds 1000
    : i w0 ( wal_writes . ( db_store d ) wal )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t threads {
        : i me t
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ Session ss ( session_new d )
            : Rng g ( rng_seed + 101 me )
            ~ < ( now_ms ) deadline {
                : i a ( rng_below g naccts )
                : i b ( rng_below g naccts )
                : i amt + 1 ( rng_below g 100 )
                : ~ b ok ( q ss `BEGIN` )
                ? ok {
                    : String q1 ( string_from `UPDATE bench_acct SET bal = bal - ` )
                    ( string_push_int q1 amt ) ( string_push_str q1 ` WHERE id = ` ) ( string_push_int q1 a )
                    = ok ?? ( session_exec ss q1 ) { T _ → T F _ → F }
                } {}
                ? ok {
                    : String q2 ( string_from `UPDATE bench_acct SET bal = bal + ` )
                    ( string_push_int q2 amt ) ( string_push_str q2 ` WHERE id = ` ) ( string_push_int q2 b )
                    = ok ?? ( session_exec ss q2 ) { T _ → T F _ → F }
                } {}
                ? ok { = ok ( q ss `COMMIT` ) } {}
                ? ok { ( atomic_add commits 1 ) } { ( atomic_add conflicts 1 ) }
            }
            ( session_close ss )
        } )
        ?? r { T h → { ( vec_push [Thread] ts h ) } F _ → {} }
        = t + t 1
    }
    ~ h ts { ( thread_join h ) }
    : i n ( atomic_load commits )
    : i writes - ( wal_writes . ( db_store d ) wal ) w0
    ( nurl_print `transfers: ` ) ( nurl_print_int n ) ( nurl_print ` in ` ) ( nurl_print_int seconds ) ( nurl_print ` s = ` )
    ( nurl_print_int / n seconds ) ( nurl_print ` tps with ` ) ( nurl_print_int threads ) ( nurl_print ` sessions; ` )
    ( nurl_print_int ( atomic_load conflicts ) ) ( nurl_print ` conflicts retried; ` ) ( nurl_print_int writes )
    ( nurl_println ` log writes (group commit)` )
    // A parallel aggregate.
    : i t0 ( now_ms )
    : b _g ( q s `SELECT COUNT(*), SUM(bal), MIN(bal), MAX(bal) FROM bench_acct` )
    : i t1 ( now_ms )
    ( nurl_print `aggregate over ` ) ( nurl_print_int naccts ) ( nurl_print ` rows: ` ) ( nurl_print_int - t1 t0 ) ( nurl_println ` ms` )
    ( session_close s )
    ( db_close d )
    ^ 0
}

@ main → i {
    : i argc ( nurl_argv_count )
    ? < argc 2 { ^ ( usage ) } {}
    : s cmd ( nurl_argv_get 1 )
    ? | != 0 ( nurl_str_eq cmd `-h` ) != 0 ( nurl_str_eq cmd `--help` ) { ^ ( usage ) } {}
    ? != 0 ( nurl_str_eq cmd `--version` ) { ( nurl_println ( nurl_str_cat `nurldb ` VERSION ) ) ^ 0 } {}
    ? != 0 ( nurl_str_eq cmd `serve` ) {
        ? < argc 3 { ^ ( usage ) } {}
        : i port ? > argc 3 ( nurl_str_to_int ( nurl_argv_get 3 ) ) 5433
        : Db d ?? ( db_open ( nurl_argv_get 2 ) ( db_default_opts ) ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }
        ( nurl_println ( nurl_str_cat `nurldb: serving on port ` ( nurl_str_int port ) ) )
        ( flush )
        ^ ?? ( serve d `0.0.0.0` port ) { T _ → 0 F e → { ( nurl_println ( string_data e ) ) 1 } }
    } {}
    ? != 0 ( nurl_str_eq cmd `client` ) {
        : s host ? > argc 2 ( nurl_argv_get 2 ) `127.0.0.1`
        : i port ? > argc 3 ( nurl_str_to_int ( nurl_argv_get 3 ) ) 5433
        ^ ( client_main host port )
    } {}
    ? != 0 ( nurl_str_eq cmd `bench` ) {
        ? < argc 3 { ^ ( usage ) } {}
        : i threads ? > argc 3 ( nurl_str_to_int ( nurl_argv_get 3 ) ) 8
        : i secs ? > argc 4 ( nurl_str_to_int ( nurl_argv_get 4 ) ) 5
        ^ ( bench_main ( nurl_argv_get 2 ) threads secs )
    } {}
    : ( Vec String ) rest ( vec_new [String] )
    : ~ i k 2
    ~ < k argc { ( vec_push [String] rest ( string_from ( nurl_argv_get k ) ) ) = k + k 1 }
    ^ ( local_main cmd rest )
}
