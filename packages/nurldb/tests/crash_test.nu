// crash_test.nu — a crash at any moment loses no committed transaction
// and leaves no half of one.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/crash_test.nu /tmp/ct && /tmp/ct
//
// The test runs itself as a child: four threads moving money between 100
// accounts, each transfer one transaction that also logs a sequence
// number, and the child reports every number whose COMMIT has returned.
// After a while the parent kills the child with SIGKILL — no shutdown, no
// flush, in the middle of whatever it was writing — and opens the
// database itself: recovery replays the log. Every reported commit must be
// there, the money must add up (no transfer half applied), the primary key
// must still find every account. Then the same again on the recovered
// database, and once more after a clean close.
//
// Last, a transaction still running at the crash whose change is in the
// log (another transaction's commit flushed past it): recovery must keep
// it undone, also once new transactions are under way — ids it hands out
// must not include the crashed one's, or a new transaction's commit would
// make the old change its own.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/process.nu`
$ `src/exec.nu`

: ~ i g_pass 0
: ~ i g_fail 0

: i NACC 100
: i START 1000

@ check s what b ok → v {
    ? ok { = g_pass + g_pass 1 ( nurl_print `  ok ` ) } { = g_fail + g_fail 1 ( nurl_print `  FAIL ` ) }
    ( nurl_println what )
    ( flush )
}

@ sql inout Session s String q → b {
    ^ ?? ( session_exec s q ) { T _ → T F _ → F }
}

@ sqls inout Session s s q → b { ^ ( sql s ( string_from q ) ) }

// The first column of the first row of `q`, as an INT (-1: none).
@ scalar inout Session s s q → i {
    ^ ?? ( session_exec s ( string_from q ) ) {
        T r → ? == 0 ( vec_len [( Vec Value )] . r rows ) -1 ?? ( vec_at [Value] ( vec_at [( Vec Value )] . r rows 0 ) 0 ) { VInt x → x _ → -1 }
        F _ → -1
    }
}

// ── the child ──────────────────────────────────────────────────────────

@ child s dir → i {
    : DbOpts o @ DbOpts { 256 T }
    : Db d ?? ( db_open dir o ) { T x → x F e → { ( nurl_eprintln ( string_data e ) ) ^ 1 } }
    : ~ Session s ( session_new d )
    ? < ( scalar s `SELECT COUNT(*) FROM acct` ) 0 {
        : b _a ( sqls s `CREATE TABLE acct (id INT PRIMARY KEY, bal INT NOT NULL)` )
        : b _b ( sqls s `CREATE TABLE seqlog (seq INT PRIMARY KEY, who INT)` )
        : b _c ( sqls s `BEGIN` )
        : ~ i k 0
        ~ < k NACC {
            : String q ( string_from `INSERT INTO acct VALUES (` )
            ( string_push_int q k ) ( string_push_str q `, ` ) ( string_push_int q START ) ( string_push_str q `)` )
            : b _i ( sql s q )
            = k + k 1
        }
        : b _d ( sqls s `COMMIT` )
    } {}
    : ~ i base ( scalar s `SELECT MAX(seq) FROM seqlog` )
    ? < base 0 { = base 0 } {}
    ( nurl_println `ready` )
    ( flush )
    : Atomic seq ( atomic_new + base 1 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : i me t
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ Session ss ( session_new d )
            : Rng g ( rng_seed + ( now_ms ) * me 7919 )
            ~ T {
                : i a ( rng_below g NACC )
                : i b0 ( rng_below g - NACC 1 )
                : i b ? >= b0 a + b0 1 b0
                : i amt + 1 ( rng_below g 20 )
                ? ! ( sqls ss `BEGIN` ) { continue } {}
                : String q1 ( string_from `UPDATE acct SET bal = bal - ` )
                ( string_push_int q1 amt ) ( string_push_str q1 ` WHERE id = ` ) ( string_push_int q1 a )
                ? ! ( sql ss q1 ) { continue } {}
                : String q2 ( string_from `UPDATE acct SET bal = bal + ` )
                ( string_push_int q2 amt ) ( string_push_str q2 ` WHERE id = ` ) ( string_push_int q2 b )
                ? ! ( sql ss q2 ) { continue } {}
                : i n ( atomic_add seq 1 )
                : String q3 ( string_from `INSERT INTO seqlog VALUES (` )
                ( string_push_int q3 n ) ( string_push_str q3 `, ` ) ( string_push_int q3 me ) ( string_push_str q3 `)` )
                ? ! ( sql ss q3 ) { continue } {}
                ? ( sqls ss `COMMIT` ) {
                    // One write per line: four threads report at once.
                    ( nurl_print ( nurl_str_cat3 `c ` ( nurl_str_int n ) `\n` ) )
                    ( flush )
                } {}
            }
        } )
        ?? r { T h → { ( vec_push [Thread] ts h ) } F _ → {} }
        = t + t 1
    }
    ~ h ts { ( thread_join h ) }
    ^ 0
}

// A fresh database, then two transactions: the first to begin commits
// after the second has changed an account, and the child waits to be
// killed with the second still running.
@ half s dir → i {
    : Db d ?? ( db_open dir @ DbOpts { 256 T } ) { T x → x F e → { ( nurl_eprintln ( string_data e ) ) ^ 1 } }
    : ~ Session s1 ( session_new d )
    : ~ Session s2 ( session_new d )
    : b _a ( sqls s1 `CREATE TABLE acct (id INT PRIMARY KEY, bal INT NOT NULL)` )
    : b _b ( sqls s1 `CREATE TABLE seqlog (seq INT PRIMARY KEY, who INT)` )
    : b _c ( sqls s1 `BEGIN` )
    : ~ i k 0
    ~ < k NACC {
        : String q ( string_from `INSERT INTO acct VALUES (` )
        ( string_push_int q k ) ( string_push_str q `, ` ) ( string_push_int q START ) ( string_push_str q `)` )
        : b _i ( sql s1 q )
        = k + k 1
    }
    : b _d ( sqls s1 `COMMIT` )
    : b _e ( sqls s1 `BEGIN` )
    : b _f ( sqls s2 `BEGIN` )
    : b _g ( sqls s2 `UPDATE acct SET bal = bal - 500 WHERE id = 0` )
    : b _h ( sqls s1 `INSERT INTO seqlog VALUES (1, 1)` )
    : b _j ( sqls s1 `COMMIT` )
    ( nurl_println `ready` )
    ( flush )
    ~ T { ( sleep_ms 1000 ) }
    ^ 0
}

// ── the parent ─────────────────────────────────────────────────────────

// Run the child until it has reported `want` commits (or a few seconds
// went by), then kill it: the numbers it reported.
@ crash_once s self s dir i want → ( Vec i ) {
    : ( Vec i ) got ( vec_new [i] )
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `child` )
    ( vec_push [s] args dir )
    : ProcChild p ?? ( process_spawn self args ) { T c → c F _ → { ( nurl_println `  cannot start the child` ) ^ got } }
    : i t0 ( now_ms )
    : ~ b ready F
    ~ & < ( vec_len [i] got ) want < - ( now_ms ) t0 20000 {
        ?? ( proc_read_line p 100 ) {
            T line → {
                : String l ( string_trim line )
                ? != 0 ( nurl_str_eq ( string_data l ) `ready` ) { = ready T } {
                    ? & > ( string_len l ) 2 != 0 ( nurl_str_eq ( nurl_str_slice ( string_data l ) 0 2 ) `c ` ) {
                        ( vec_push [i] got ( nurl_str_to_int ( nurl_str_slice ( string_data l ) 2 - ( string_len l ) 2 ) ) )
                    } {}
                }
            }
            F → {}
        }
    }
    // SIGKILL: no shutdown of any kind.
    : i _k ( proc_kill p 9 )
    : i _w ( proc_wait p )
    ^ got
}

@ crash_half s self s dir → v {
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `half` )
    ( vec_push [s] args dir )
    : ProcChild p ?? ( process_spawn self args ) { T c → c F _ → { ( check `the child starts` F ) ^ } }
    : i t0 ( now_ms )
    : ~ b ready F
    ~ & ! ready < - ( now_ms ) t0 20000 {
        ?? ( proc_read_line p 100 ) { T line → { ? != 0 ( nurl_str_eq ( string_data ( string_trim line ) ) `ready` ) { = ready T } {} } F → {} }
    }
    : i _k ( proc_kill p 9 )
    : i _w ( proc_wait p )
    ( check `the child got its two transactions going` ready )
    : Db d ?? ( db_open dir @ DbOpts { 256 T } ) { T x → x F e → { ( check `the database opens after the crash` F ) ^ } }
    : ~ Session s ( session_new d )
    : b _a ( sqls s `INSERT INTO seqlog VALUES (2, 2)` )
    : b _b ( sqls s `UPDATE acct SET bal = bal + 0 WHERE id = 1` )
    ( check `a transaction running at the crash stays undone` == ( scalar s `SELECT SUM(bal) FROM acct` ) * NACC START )
    ( check `the one that committed stays done` == ( scalar s `SELECT COUNT(*) FROM seqlog` ) 2 )
    ( session_close s )
    ( db_close d )
}

@ verify s dir ( Vec i ) reported s when → v {
    : DbOpts o @ DbOpts { 256 T }
    : Db d ?? ( db_open dir o ) { T x → x F e → { ( check ( nurl_str_cat `the database opens ` when ) F ) ^ } }
    : ~ Session s ( session_new d )
    ( check ( nurl_str_cat `the money adds up ` when ) == ( scalar s `SELECT SUM(bal) FROM acct` ) * NACC START )
    ( check ( nurl_str_cat `every account is there ` when ) == ( scalar s `SELECT COUNT(*) FROM acct` ) NACC )
    // Every reported commit survived.
    : ( Vec i ) present ( vec_new [i] )
    ?? ( session_exec s ( string_from `SELECT seq FROM seqlog` ) ) {
        T r → { ~ row . r rows { ( vec_push [i] present ?? ( vec_at [Value] row 0 ) { VInt x → x _ → -1 } ) } }
        F _ → {}
    }
    : ~ i lost 0
    ~ n reported {
        : ~ b found F
        ~ m present { ? == m n { = found T } {} }
        ? ! found { = lost + lost 1 } {}
    }
    ( check ( nurl_str_cat ( nurl_str_cat `every reported commit is there ` when ) ( nurl_str_cat ` (` ( nurl_str_cat ( nurl_str_int ( vec_len [i] reported ) ) `)` ) ) ) == lost 0 )
    // The primary key finds each account (index and heap agree).
    : ~ i found 0
    : ~ i k 0
    ~ < k NACC {
        : String q ( string_from `SELECT COUNT(*) FROM acct WHERE id = ` )
        ( string_push_int q k )
        ?? ( session_exec s q ) { T r → { ? == ( vec_len [( Vec Value )] . r rows ) 1 { = found + found ?? ( vec_at [Value] ( vec_at [( Vec Value )] . r rows 0 ) 0 ) { VInt x → x _ → 0 } } {} } F _ → {} }
        = k + k 1
    }
    ( check ( nurl_str_cat `the primary key finds every account ` when ) == found NACC )
    ( session_close s )
    ( db_close d )
}

@ main → i {
    ? > ( nurl_argv_count ) 2 {
        ? != 0 ( nurl_str_eq ( nurl_argv_get 1 ) `child` ) { ^ ( child ( nurl_argv_get 2 ) ) } {}
        ? != 0 ( nurl_str_eq ( nurl_argv_get 1 ) `half` ) { ^ ( half ( nurl_argv_get 2 ) ) } {}
    } {}
    : s self ( nurl_argv_get 0 )
    : s dir `/tmp/nurldb_crash_test`
    ?? ( file_delete ( nurl_str_cat dir `/data` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat dir `/log` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat dir `/clog` ) ) { T _ → {} F _ → {} }
    : ( Vec i ) r1 ( crash_once self dir 300 )
    ( check `the child committed before it was killed` > ( vec_len [i] r1 ) 0 )
    ( verify dir r1 `after the first crash` )
    : ( Vec i ) r2 ( crash_once self dir 300 )
    ( verify dir r2 `after a crash of the recovered database` )
    ( verify dir r2 `after a clean close` )
    : s hdir `/tmp/nurldb_crash_test_half`
    ?? ( file_delete ( nurl_str_cat hdir `/data` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat hdir `/log` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat hdir `/clog` ) ) { T _ → {} F _ → {} }
    ( crash_half self hdir )
    ( nurl_print `crash_test: ` ) ( nurl_print_int g_pass ) ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_println ` failed` )
    ^ ? == g_fail 0 0 1
}
