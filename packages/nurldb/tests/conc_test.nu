// conc_test.nu — many sessions at once, and a query run by many threads.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/conc_test.nu /tmp/cc && /tmp/cc
//
// Eight sessions on eight threads move money between 50 accounts in SQL
// transactions; a conflict (a serialization failure or a deadlock) rolls
// the transfer back and it is tried again. Two more sessions total the
// balances the whole time: each total, under its own snapshot, is the
// starting total. Then a table of 200 000 rows is aggregated by GROUP BY
// with its pages dealt out to four threads and again with one: the same
// answer, and the plan says which ran.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/time.nu`
$ `src/exec.nu`

: ~ i g_pass 0
: ~ i g_fail 0

: i NACC 50
: i START 1000

@ check s what b ok → v {
    ? ok { = g_pass + g_pass 1 ( nurl_print `  ok ` ) } { = g_fail + g_fail 1 ( nurl_print `  FAIL ` ) }
    ( nurl_println what )
    ( flush )
}

@ sql inout Session s String q → b { ^ ?? ( session_exec s q ) { T _ → T F _ → F } }

@ sqls inout Session s s q → b { ^ ( sql s ( string_from q ) ) }

@ scalar inout Session s s q → i {
    ^ ?? ( session_exec s ( string_from q ) ) {
        T r → ? == 0 ( vec_len [( Vec Value )] . r rows ) -1 ?? ( vec_at [Value] ( vec_at [( Vec Value )] . r rows 0 ) 0 ) { VInt x → x _ → -1 }
        F _ → -1
    }
}

@ text_of inout Session s s q → String {
    : String out ( string_new )
    ?? ( session_exec s ( string_from q ) ) {
        T r → {
            ~ row . r rows {
                ~ cell row { ( string_push_str out ( string_data ( val_text cell ) ) ) ( string_push_char out 44 ) }
                ( string_push_char out 59 )
            }
        }
        F e → { ( string_push_str out ( string_data e ) ) }
    }
    ^ out
}

@ count_char String t i c → i {
    : ~ i n 0
    : ( Slice u ) b ( string_bytes t )
    : ~ i k 0
    ~ < k ( slice_len [u] b ) { ? == ( slice_byte b k ) c { = n + n 1 } {} = k + k 1 }
    ^ n
}

@ main → i {
    : s dir `/tmp/nurldb_conc_test`
    ?? ( file_delete ( nurl_str_cat dir `/data` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat dir `/log` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat dir `/clog` ) ) { T _ → {} F _ → {} }
    : Db d ?? ( db_open dir @ DbOpts { 1024 F } ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }
    : ~ Session s ( session_new d )
    : b _a ( sqls s `CREATE TABLE acct (id INT PRIMARY KEY, bal INT NOT NULL)` )
    : ~ i k 0
    ~ < k NACC {
        : String q ( string_from `INSERT INTO acct VALUES (` )
        ( string_push_int q k ) ( string_push_str q `, ` ) ( string_push_int q START ) ( string_push_str q `)` )
        : b _i ( sql s q )
        = k + k 1
    }

    // ── the bank ──
    : Atomic done ( atomic_new 0 )
    : Atomic retried ( atomic_new 0 )
    : Atomic totals ( atomic_new 0 )
    : Atomic bad ( atomic_new 0 )
    : Atomic writers ( atomic_new 8 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 10 {
        : i me t
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ Session ss ( session_new d )
            ? >= me 8 {
                ~ > ( atomic_load writers ) 0 {
                    ? != ( scalar ss `SELECT SUM(bal) FROM acct` ) * NACC START { ( atomic_add bad 1 ) } {}
                    ( atomic_add totals 1 )
                }
                ^
            } {}
            : Rng g ( rng_seed + 11 me )
            : ~ i n 0
            ~ < n 100 {
                : i a ( rng_below g NACC )
                : i b0 ( rng_below g - NACC 1 )
                : i b ? >= b0 a + b0 1 b0
                : i amt + 1 ( rng_below g 30 )
                : ~ b ok ( sqls ss `BEGIN` )
                ? ok {
                    : String q1 ( string_from `UPDATE acct SET bal = bal - ` )
                    ( string_push_int q1 amt ) ( string_push_str q1 ` WHERE id = ` ) ( string_push_int q1 a )
                    = ok ( sql ss q1 )
                } {}
                ? ok {
                    : String q2 ( string_from `UPDATE acct SET bal = bal + ` )
                    ( string_push_int q2 amt ) ( string_push_str q2 ` WHERE id = ` ) ( string_push_int q2 b )
                    = ok ( sql ss q2 )
                } {}
                ? ok { = ok ( sqls ss `COMMIT` ) } {}
                ? ok { = n + n 1 ( atomic_add done 1 ) } { ( atomic_add retried 1 ) }
            }
            ( atomic_sub writers 1 )
        } )
        ?? r { T h → { ( vec_push [Thread] ts h ) } F _ → {} }
        = t + t 1
    }
    ~ h ts { ( thread_join h ) }
    ( check `800 transfers committed` == ( atomic_load done ) 800 )
    ( check `the money adds up` == ( scalar s `SELECT SUM(bal) FROM acct` ) * NACC START )
    ( check `no concurrent total was off` == ( atomic_load bad ) 0 )
    ( check `the readers totalled while the writers wrote` > ( atomic_load totals ) 0 )
    ( check `conflicts happened, and were retried` > ( atomic_load retried ) 0 )
    ( nurl_print `  (` ) ( nurl_print_int ( atomic_load retried ) ) ( nurl_print ` retries, ` )
    ( nurl_print_int ( atomic_load totals ) ) ( nurl_print ` totals, ` ) ( nurl_print_int ( txn_deadlocks ( db_txnmgr d ) ) ) ( nurl_println ` deadlocks)` )

    // ── a parallel aggregate ──
    : b _c ( sqls s `CREATE TABLE big (id INT, grp INT, v INT)` )
    : TableInfo bi ?? ( db_table d ( string_from `big` ) ) { T x → x F → { ^ 1 } }
    : ( Vec Thread ) ws ( vec_new [Thread] )
    = t 0
    ~ < t 4 {
        : i me t
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ i j 0
            ~ < j 50000 {
                : ~ Txn x ( db_begin d )
                ( db_statement x )
                : ~ i m 0
                ~ < m 500 {
                    : i id + * me 50000 + j m
                    : ( Vec Value ) row ( vec_new [Value] )
                    ( vec_push [Value] row @ Value { VInt id } )
                    ( vec_push [Value] row @ Value { VInt % id 7 } )
                    ( vec_push [Value] row @ Value { VInt % * id 31 1000 } )
                    : i _t ( db_insert d x bi row )
                    = m + m 1
                }
                ( db_commit d x )
                = j + j 500
            }
        } )
        ?? r { T h → { ( vec_push [Thread] ws h ) } F _ → {} }
        = t + t 1
    }
    ~ h ws { ( thread_join h ) }
    ( check `200 000 rows from four threads` == ( scalar s `SELECT COUNT(*) FROM big` ) 200000 )
    : s q `SELECT grp, COUNT(*), SUM(v), MIN(v), MAX(id) FROM big WHERE v >= 10 GROUP BY grp ORDER BY grp`
    : String plan ( text_of s ( nurl_str_cat `EXPLAIN ` q ) )
    ( check `the plan deals the pages out to four threads` >= ( nurl_str_find ( string_data plan ) `Parallel Aggregate, workers: 4` ) 0 )
    : i t0 ( now_ms )
    : String par ( text_of s q )
    : i t1 ( now_ms )
    = g_par_workers 1
    : String one ( text_of s q )
    : i t2 ( now_ms )
    = g_par_workers 4
    ( check `four threads and one give the same answer` != 0 ( nurl_str_eq ( string_data par ) ( string_data one ) ) )
    ( check `seven groups` == 7 ( count_char par 59 ) )
    ( nurl_print `  (aggregate over 200 000 rows: 4 threads ` ) ( nurl_print_int - t1 t0 ) ( nurl_print ` ms, 1 thread ` ) ( nurl_print_int - t2 t1 ) ( nurl_println ` ms)` )
    ( session_close s )
    ( db_close d )
    ( nurl_print `conc_test: ` ) ( nurl_print_int g_pass ) ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_println ` failed` )
    ^ ? == g_fail 0 0 1
}
