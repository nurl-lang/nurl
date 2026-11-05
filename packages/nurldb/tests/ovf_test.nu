// ovf_test.nu — TEXT values longer than a page, and the directory lock.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/ovf_test.nu /tmp/ot && /tmp/ot
//
// Values on both sides of every edge — none, short, just under and over
// the out-of-line target, exactly one overflow page and one byte more,
// many pages — go in through SQL and come back byte for byte: by key, in
// a scan, through LIKE, after an UPDATE of another column and of the long
// one itself, with two long columns in one row. A rolled-back insert of a
// long value is not seen. Four threads insert and read long rows at once.
// The values survive a clean close and a crash (db_crash: the overflow
// pages were never written to the data file, so redo rebuilds them from
// the log).
//
// The lock: while a Db has the directory, a second db_open — in this
// process, or in a child process — is refused; once it is closed, both
// open it.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/process.nu`
$ `src/exec.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check s what b ok → v {
    ? ok { = g_pass + g_pass 1 ( nurl_print `  ok ` ) } { = g_fail + g_fail 1 ( nurl_print `  FAIL ` ) }
    ( nurl_println what )
    ( flush )
}

@ sqls inout Session s s q → b {
    ^ ?? ( session_exec s ( string_from q ) ) { T _ → T F e → { ( nurl_println ( string_data e ) ) ^ F } }
}

@ sql inout Session s String q → b {
    ^ ?? ( session_exec s q ) { T _ → T F e → { ( nurl_println ( string_data e ) ) ^ F } }
}

@ scalar inout Session s s q → i {
    ^ ?? ( session_exec s ( string_from q ) ) {
        T r → ? == 0 ( vec_len [( Vec Value )] . r rows ) -1 ?? ( vec_at [Value] ( vec_at [( Vec Value )] . r rows 0 ) 0 ) { VInt x → x _ → -1 }
        F _ → -1
    }
}

// The TEXT in column `col` of the first row of `q` ("<none>" when there
// is no row, "<null>" for NULL).
@ text_of inout Session s String q i col → String {
    ^ ?? ( session_exec s q ) {
        T r → ? == 0 ( vec_len [( Vec Value )] . r rows ) ( string_from `<none>` ) ?? ( vec_at [Value] ( vec_at [( Vec Value )] . r rows 0 ) col ) { VText x → ( string_clone x ) _ → ( string_from `<null>` ) }
        F _ → ( string_from `<error>` )
    }
}

// `n` bytes of text that differ with `seed`: letters, a space every so
// often, a newline now and then, and a quote (written '' in SQL).
@ gen i n i seed → String {
    : String out ( string_new )
    : ~ i k 0
    ~ < k n {
        : i r % + * k 7 * seed 13 977
        ? == r 0 { ( string_push_char out 39 ) } {
            ? == % r 61 0 { ( string_push_char out 10 ) } {
                ? == % r 9 0 { ( string_push_char out 32 ) } { ( string_push_char out + 97 % + k seed 26 ) }
            }
        }
        = k + k 1
    }
    ^ out
}

// `t` as an SQL literal.
@ lit String t → String {
    : String q ( string_from `'` )
    : ( Slice u ) b ( string_bytes t )
    : ~ i k 0
    ~ < k ( slice_len [u] b ) {
        : i c ( slice_byte b k )
        ? == c 39 { ( string_push_str q `''` ) } { ( string_push_char q c ) }
        = k + k 1
    }
    ( string_push_str q `'` )
    ^ q
}

@ insert inout Session s i id String body String note → b {
    : String q ( string_from `INSERT INTO doc VALUES (` )
    ( string_push_int q id )
    ( string_push_str q `, 't', ` )
    ( string_push_str q ( string_data ( lit body ) ) )
    ( string_push_str q `, ` )
    ( string_push_str q ( string_data ( lit note ) ) )
    ( string_push_str q `)` )
    ^ ( sql s q )
}

@ body_of inout Session s i id → String {
    : String q ( string_from `SELECT body FROM doc WHERE id = ` )
    ( string_push_int q id )
    ^ ( text_of s q 0 )
}

// The sizes: none, short, at and around the out-of-line target (2048 for
// the whole tuple), one overflow page (8160) and one byte more, many.
@ sizes → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 0 ) ( vec_push [i] v 64 ) ( vec_push [i] v 65 ) ( vec_push [i] v 1900 )
    ( vec_push [i] v 2048 ) ( vec_push [i] v 8160 ) ( vec_push [i] v 8161 ) ( vec_push [i] v 16320 )
    ( vec_push [i] v 50000 ) ( vec_push [i] v 300000 )
    ^ v
}

// Every size's row reads back as it went in.
@ verify_sizes inout Session s s when → v {
    : ~ b all T
    : ~ i k 0
    : ( Vec i ) sz ( sizes )
    ~ n sz {
        : String want ( gen n k )
        : String got ( body_of s + 100 k )
        ? ! ( string_eq got want ) { = all F ( nurl_print `    differs at size ` ) ( nurl_println_int n ) } {}
        = k + k 1
    }
    ( check ( nurl_str_cat `every size reads back byte for byte ` when ) all )
}

// ── the lock, from another process ─────────────────────────────────────

@ probe s dir → i {
    ?? ( db_open dir ( db_default_opts ) ) {
        T d → { ( nurl_println `opened` ) ( db_close d ) }
        F e → { ( nurl_println ( string_data e ) ) }
    }
    ( flush )
    ^ 0
}

// What a child process's db_open of `dir` says: `opened`, or the error.
@ probe_child s self s dir → String {
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `probe` )
    ( vec_push [s] args dir )
    : ProcChild p ?? ( process_spawn self args ) { T c → c F _ → { ^ ( string_from `cannot start the child` ) } }
    : ~ String said ( string_from `no answer` )
    : i t0 ( now_ms )
    : ~ b done F
    ~ & ! done < - ( now_ms ) t0 20000 {
        ?? ( proc_read_line p 100 ) { T line → { = said ( string_trim line ) = done T } F → {} }
    }
    : i _w ( proc_wait p )
    ^ said
}

@ main → i {
    ? > ( nurl_argv_count ) 2 {
        ? != 0 ( nurl_str_eq ( nurl_argv_get 1 ) `probe` ) { ^ ( probe ( nurl_argv_get 2 ) ) } {}
    } {}
    : s self ( nurl_argv_get 0 )
    : s dir `/tmp/nurldb_ovf_test`
    ?? ( file_delete ( nurl_str_cat dir `/data` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat dir `/log` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat dir `/clog` ) ) { T _ → {} F _ → {} }

    : Db d ?? ( db_open dir @ DbOpts { 64 T } ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }

    // The lock.
    ?? ( db_open dir ( db_default_opts ) ) {
        T d2 → { ( check `a second db_open in this process is refused` F ) ( db_close d2 ) }
        F e → { ( check `a second db_open in this process is refused` >= ( nurl_str_find ( string_data e ) `already open` ) 0 ) }
    }
    : String said ( probe_child self dir )
    ( check `a db_open in another process is refused` >= ( nurl_str_find ( string_data said ) `already open` ) 0 )

    : ~ Session s ( session_new d )
    : b _c ( sqls s `CREATE TABLE doc (id INT PRIMARY KEY, title TEXT, body TEXT, note TEXT)` )

    // Every size, in one row each.
    : ~ b put T
    : ~ i k 0
    : ( Vec i ) sz ( sizes )
    ~ n sz {
        ? ! ( insert s + 100 k ( gen n k ) ( string_from `short` ) ) { = put F } {}
        = k + k 1
    }
    ( check `every size goes in` put )
    ( verify_sizes s `by key` )
    ( check `a scan sees every row` == ( scalar s `SELECT COUNT(*) FROM doc` ) ( vec_len [i] ( sizes ) ) )

    // The total length through a scan: SUM over a computed column reads
    // every value, long ones from their pages.
    : ~ i total 0
    : ( Vec i ) sz ( sizes )
    ~ n sz { = total + total n }
    : ~ i scanned 0
    ?? ( session_exec s ( string_from `SELECT body FROM doc` ) ) {
        T r → { ~ row . r rows { ?? ( vec_at [Value] row 0 ) { VText x → { = scanned + scanned ( string_len x ) } _ → {} } } }
        F _ → {}
    }
    ( check `a scan reads every value whole` == scanned total )

    // LIKE finds a pattern near the end of the longest value.
    : String longest ( gen 300000 9 )
    : String needle ( string_from `%` )
    ( string_push_window needle ( string_bytes longest ) 299980 12 )
    ( string_push_str needle `%` )
    : String lq ( string_from `SELECT COUNT(*) FROM doc WHERE body LIKE ` )
    ( string_push_str lq ( string_data ( lit needle ) ) )
    : i liked ?? ( session_exec s lq ) { T r → ?? ( vec_at [Value] ( vec_at [( Vec Value )] . r rows 0 ) 0 ) { VInt x → x _ → -1 } F _ → -1 }
    ( check `LIKE reaches into a value's last page` >= liked 1 )

    // Two long columns in one row.
    : ~ b two ( insert s 1 ( gen 10000 1 ) ( gen 12000 2 ) )
    : String n1 ( text_of s ( string_from `SELECT note FROM doc WHERE id = 1` ) 0 )
    ( check `two long columns in one row` & two & ( string_eq ( body_of s 1 ) ( gen 10000 1 ) ) ( string_eq n1 ( gen 12000 2 ) ) )

    // An UPDATE of another column keeps the long one; an UPDATE of the long
    // one makes a new value.
    : b _u ( sqls s `UPDATE doc SET note = 'changed' WHERE id = 1` )
    ( check `an UPDATE of another column keeps the long value` ( string_eq ( body_of s 1 ) ( gen 10000 1 ) ) )
    : b _v ( sqls s `UPDATE doc SET body = body || 'tail' WHERE id = 1` )
    : String grown ( gen 10000 1 )
    ( string_push_str grown `tail` )
    ( check `an UPDATE of the long value itself` ( string_eq ( body_of s 1 ) grown ) )

    // A rolled-back insert of a long value is not there.
    : b _b ( sqls s `BEGIN` )
    : b _i ( insert s 2 ( gen 40000 3 ) ( string_from `x` ) )
    : b _r ( sqls s `ROLLBACK` )
    ( check `a rolled-back long value is not seen` ( string_eq ( body_of s 2 ) ( string_from `<none>` ) ) )

    // Four threads, each inserting and reading its own long rows.
    : Atomic bad ( atomic_new 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : i me t
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ Session ss ( session_new d )
            : ~ i j 0
            ~ < j 25 {
                : i id + + 1000 * me 100 j
                : i len + 3000 * j 997
                ? ! ( insert ss id ( gen len id ) ( string_from `t` ) ) { ( atomic_add bad 1 ) } {}
                ? ! ( string_eq ( body_of ss id ) ( gen len id ) ) { ( atomic_add bad 1 ) } {}
                = j + j 1
            }
            ( session_close ss )
        } )
        ?? r { T h → { ( vec_push [Thread] ts h ) } F _ → {} }
        = t + t 1
    }
    ~ h ts { ( thread_join h ) }
    ( check `four threads insert and read long rows` == ( atomic_load bad ) 0 )

    // A clean close, then the lock is free for this process and another.
    ( session_close s )
    ( db_close d )
    : String said2 ( probe_child self dir )
    ( check `once closed, another process opens it` ( string_eq said2 ( string_from `opened` ) ) )
    : Db d3 ?? ( db_open dir @ DbOpts { 64 T } ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }
    : ~ Session s3 ( session_new d3 )
    ( verify_sizes s3 `after a clean close` )

    // A crash: what this session writes now reaches the log only — with a
    // pool of 64 frames and 300 KB values, some of it also the data file.
    : b _c4 ( insert s3 3 ( gen 70000 4 ) ( string_from `crash` ) )
    : b _c5 ( insert s3 4 ( gen 9000 5 ) ( gen 9000 6 ) )
    ( session_close s3 )
    ( db_crash d3 )
    : Db d4 ?? ( db_open dir @ DbOpts { 64 T } ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }
    : ~ Session s4 ( session_new d4 )
    : String n4 ( text_of s4 ( string_from `SELECT note FROM doc WHERE id = 4` ) 0 )
    ( check `long values committed before a crash are back` & & ( string_eq ( body_of s4 3 ) ( gen 70000 4 ) ) ( string_eq ( body_of s4 4 ) ( gen 9000 5 ) ) ( string_eq n4 ( gen 9000 6 ) ) )
    ( verify_sizes s4 `after the crash` )
    ( session_close s4 )
    ( db_close d4 )

    ( nurl_print `ovf_test: ` ) ( nurl_print_int g_pass ) ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_println ` failed` )
    ^ ? == g_fail 0 0 1
}
