// lsmdb — a crash-safe embedded key/value store on the command line.
//
//   lsmdb put user:42 '{"name":"ada"}'      # write (fsynced before it returns)
//   lsmdb get user:42                       # read
//   lsmdb del user:42                       # delete
//   lsmdb scan --from user: --limit 20      # ordered range
//   lsmdb load < dump.tsv                   # bulk import, key<TAB>value lines
//   lsmdb get user:42 --at 7                # read the database as of write #7
//   lsmdb compact                           # merge tables, reclaim space
//   lsmdb stats                             # what is on disk
//   lsmdb bench -n 100000                   # writes/s and reads/s here
//
// The database is a directory (-d, $LSMDB_DIR, or ./lsmdb). Values are
// written and printed as raw bytes, so binary values survive the round
// trip; `get` exits 1 when the key is absent, which makes it usable in a
// shell conditional.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/args.nu`
$ `memtable.nu`
$ `sst.nu`
$ `wal.nu`
$ `lsmdb.nu`

// ── small helpers ───────────────────────────────────────────────────

@ __opt_int ArgParser p s name i dflt → i {
    ?? ( args_value p name ) {
        T v → { : i n ( nurl_str_to_int ( string_data v ) ) ( string_free v ) ^ n }
        F _ → { ^ dflt }
    }
}

@ __opt_str ArgParser p s name s dflt → String {
    ?? ( args_value p name ) {
        T v → { ^ v }
        F _ → { ^ ( string_from dflt ) }
    }
}

@ __pos ( Vec String ) ps i k → s {
    ^ ?? ( vec_get [String] ps k ) { T s → ( string_data s ) F _ → `` }
}

@ __free_strvec ( Vec String ) v → v {
    ( vec_free_with [String] v \ String s → v { ( string_free s ) } )
}

@ __die s msg → v {
    ( nurl_eprint `lsmdb: ` )
    ( nurl_eprintln msg )
}

// ── commands ────────────────────────────────────────────────────────

@ __cmd_put * Lsm db s key s val → i {
    : ( Vec u ) k ( bytes_from_str key )
    : ( Vec u ) v ( bytes_from_str val )
    : ~ i rc 0
    ?? ( lsm_put db k v ) {
        T _ → {}
        F e → { ( __die ( string_data e ) ) ( string_free e ) = rc 3 }
    }
    ( vec_free [u] k ) ( vec_free [u] v )
    ^ rc
}

@ __cmd_del * Lsm db s key → i {
    : ( Vec u ) k ( bytes_from_str key )
    : ~ i rc 0
    ?? ( lsm_del db k ) {
        T _ → {}
        F e → { ( __die ( string_data e ) ) ( string_free e ) = rc 3 }
    }
    ( vec_free [u] k )
    ^ rc
}

// Absent key → exit 1 with nothing on stdout, so `lsmdb get k || …`
// works in a shell.
@ __cmd_get * Lsm db s key i snap b raw → i {
    : ( Vec u ) k ( bytes_from_str key )
    : ~ i rc 0
    ?? ( lsm_get_at db k snap ) {
        T g → {
            ? == . g found 1 {
                ( write_bytes . g val )
                ? raw {} { ( nurl_print `
` ) }
            } { = rc 1 }
            ( lsm_get_free g )
        }
        F e → { ( __die ( string_data e ) ) ( string_free e ) = rc 3 }
    }
    ( vec_free [u] k )
    ^ rc
}

@ __cmd_scan * Lsm db s from s to i limit i snap → i {
    : ( Vec u ) f ( bytes_from_str from )
    : ( Vec u ) t ( bytes_from_str to )
    : ~ i rc 0
    ?? ( lsm_scan db f t limit snap ) {
        T sc → {
            : ~ i k 0
            ~ < k ( lsm_scan_count sc ) {
                : ( Vec u ) key ( lsm_scan_key sc k )
                : ( Vec u ) val ( lsm_scan_val sc k )
                ( write_bytes key )
                ( nurl_print `	` )
                ( write_bytes val )
                ( nurl_print `
` )
                ( vec_free [u] key ) ( vec_free [u] val )
                = k + k 1
            }
            ( lsm_scan_free sc )
        }
        F e → { ( __die ( string_data e ) ) ( string_free e ) = rc 3 }
    }
    ( vec_free [u] f ) ( vec_free [u] t )
    ^ rc
}

// Bulk import: `key<TAB>value` lines on stdin. One fsync at the end
// instead of one per row — an import is a single unit of work, and the
// log still makes the whole batch replayable if it dies midway.
@ __cmd_load * Lsm db → i {
    ( lsm_set_durable db F )
    : String text ( read_all_stdin )
    : ( Vec String ) lines ( string_split text `
` )
    ( string_free text )
    : ~ i n 0
    : ~ i rc 0
    : ~ i k 0
    ~ < k ( vec_len [String] lines ) {
        ?? ( vec_get [String] lines k ) {
            T ln → {
                ?? ( string_index_of ln `	` ) {
                    T tab → {
                        : String kk ( string_substr ln 0 tab )
                        : String vv ( string_substr ln + tab 1 - - ( string_len ln ) tab 1 )
                        ? > ( string_len kk ) 0 {
                            ? == 0 ( __cmd_put db ( string_data kk ) ( string_data vv ) ) {
                                = n + n 1
                            } { = rc 1 }
                        } {}
                        ( string_free kk ) ( string_free vv )
                    }
                    F → {}
                }
            }
            F → {}
        }
        = k + k 1
    }
    ( __free_strvec lines )
    ( lsm_set_durable db T )
    ?? ( lsm_sync db ) { T _ → {} F e → { ( __die ( string_data e ) ) ( string_free e ) = rc 3 } }
    : String out ( string_with_cap 32 )
    ( string_push_int out n )
    ( string_push_str out ` rows
` )
    ( nurl_print ( string_data out ) )
    ( string_free out )
    ^ rc
}

@ __cmd_stats * Lsm db → i {
    : LsmStats st ( lsm_stats db )
    : String out ( string_with_cap 256 )
    ( string_push_str out `tables      ` ) ( string_push_int out . st tables )
    ( string_push_str out `
entries     ` ) ( string_push_int out . st entries )
    ( string_push_str out `
table bytes ` ) ( string_push_int out . st filebytes )
    ( string_push_str out `
memtable    ` ) ( string_push_int out . st memcount )
    ( string_push_str out ` entries, ` ) ( string_push_int out . st membytes )
    ( string_push_str out ` bytes
sequence    ` ) ( string_push_int out . st seq )
    ( string_push_char out 10 )
    ( nurl_print ( string_data out ) )
    ( string_free out )
    ^ 0
}

// ── benchmark ───────────────────────────────────────────────────────

@ __bench_key String buf i n → v {
    ( string_clear buf )
    ( string_push_str buf `key:` )
    : String d ( string_with_cap 16 )
    ( string_push_int d n )
    : ~ i pad - 9 ( string_len d )
    ~ > pad 0 { ( string_push_char buf 48 ) = pad - pad 1 }
    ( string_push_str buf ( string_data d ) )
    ( string_free d )
}

@ __rate i ops i ns → i {
    ? <= ns 0 { ^ 0 } {}
    ^ / * ops 1000000000 ns
}

@ __report s label i ops i ns → v {
    : String out ( string_with_cap 64 )
    ( string_push_str out label )
    ( string_push_int out ( __rate ops ns ) )
    ( string_push_str out ` ops/s  (` )
    ( string_push_int out / ns 1000000 )
    ( string_push_str out ` ms for ` )
    ( string_push_int out ops )
    ( string_push_str out `)
` )
    ( nurl_print ( string_data out ) )
    ( string_free out )
}

// Three numbers that actually describe an LSM tree: the durable write
// rate (one fsync per write), the batched write rate (fsync once), and
// the point-read rate after the data has been flushed to tables — the
// last is the one the Bloom filter and the block index exist for.
@ __cmd_bench * Lsm db i n → i {
    : String kb ( string_with_cap 32 )
    : ( Vec u ) val ( bytes_from_str `0123456789abcdef0123456789abcdef0123456789abcdef` )
    : ~ i rc 0

    : i durable_n ? > n 2000 2000 n
    : i t0 ( monotonic_ns )
    : ~ i i 0
    ~ < i durable_n {
        ( __bench_key kb i )
        : ( Vec u ) k ( bytes_from_str ( string_data kb ) )
        ?? ( lsm_put db k val ) { T _ → {} F e → { ( string_free e ) = rc 3 } }
        ( vec_free [u] k )
        = i + i 1
    }
    : i t1 ( monotonic_ns )
    ( __report `durable writes  ` durable_n - t1 t0 )

    ( lsm_set_durable db F )
    : i t2 ( monotonic_ns )
    : ~ i j 0
    ~ < j n {
        ( __bench_key kb + j 1000000 )
        : ( Vec u ) k ( bytes_from_str ( string_data kb ) )
        ?? ( lsm_put db k val ) { T _ → {} F e → { ( string_free e ) = rc 3 } }
        ( vec_free [u] k )
        = j + j 1
    }
    : i t3 ( monotonic_ns )
    ( __report `batched writes  ` n - t3 t2 )
    ( lsm_set_durable db T )

    ?? ( lsm_flush db ) { T _ → {} F e → { ( string_free e ) = rc 3 } }

    : i t4 ( monotonic_ns )
    : ~ i hits 0
    : ~ i q 0
    ~ < q n {
        ( __bench_key kb + q 1000000 )
        : ( Vec u ) k ( bytes_from_str ( string_data kb ) )
        ?? ( lsm_get db k ) {
            T g → { ? == . g found 1 { = hits + hits 1 } {} ( lsm_get_free g ) }
            F e → { ( string_free e ) = rc 3 }
        }
        ( vec_free [u] k )
        = q + q 1
    }
    : i t5 ( monotonic_ns )
    ( __report `point reads     ` n - t5 t4 )

    : i t6 ( monotonic_ns )
    : ~ i misses 0
    : ~ i m 0
    ~ < m n {
        ( __bench_key kb + m 9000000 )
        : ( Vec u ) k ( bytes_from_str ( string_data kb ) )
        ?? ( lsm_get db k ) {
            T g → { ? == . g found 0 { = misses + misses 1 } {} ( lsm_get_free g ) }
            F e → { ( string_free e ) = rc 3 }
        }
        ( vec_free [u] k )
        = m + m 1
    }
    : i t7 ( monotonic_ns )
    ( __report `absent reads    ` n - t7 t6 )

    ? != hits n { ( __die `benchmark read-back mismatch` ) = rc 1 } {}
    ? != misses n { ( __die `benchmark absent-key mismatch` ) = rc 1 } {}
    ( string_free kb )
    ( vec_free [u] val )
    ^ rc
}

// ── entry point ─────────────────────────────────────────────────────

@ __usage ArgParser p → v {
    : String h ( args_usage p )
    ( nurl_print `lsmdb — a crash-safe embedded key/value store

Commands:
  put <key> <value>     store a value (durable when it returns)
  get <key>             print the value; exit 1 if the key is absent
  del <key>             delete a key
  scan                  print key<TAB>value for a range, in order
  load                  bulk import key<TAB>value lines from stdin
  flush                 force the memtable out into a table
  compact               merge every table into one, dropping dead data
  stats                 tables, entries, bytes, sequence
  bench                 measure writes/s and reads/s on this machine

` )
    ( nurl_print ( string_data h ) )
    ( string_free h )
}

@ main → i {
    : ArgParser p ( args_new `lsmdb` `a crash-safe embedded key/value store` )
    ( args_flag p `help` 104 `show this help` )  // -h
    ( args_flag p `raw` 114 `get: no trailing newline after the value` )  // -r
    ( args_flag p `no-sync` 0 `do not fsync each write (faster, unsafe)` )
    ( args_opt p `dir` 100 `DIR` `database directory ($LSMDB_DIR, else ./lsmdb)` )  // -d
    ( args_opt p `from` 102 `KEY` `scan: start key (inclusive)` )  // -f
    ( args_opt p `to` 116 `KEY` `scan: end key (exclusive)` )  // -t
    ( args_opt p `limit` 108 `N` `scan: stop after N rows` )  // -l
    ( args_opt p `at` 0 `SEQ` `read as of sequence number SEQ (a snapshot)` )
    ( args_opt p `num` 110 `N` `bench: operations per phase (default 20000)` )  // -n

    // argv[1..] — env_args_list includes the program name.
    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i ai 1
    ~ < ai ac {
        ( vec_push [String] argv ( env_arg ai ) )
        = ai + ai 1
    }
    : ~ i rc 0
    ? ( args_parse p argv ) {} {
        ( __die ( args_error p ) )
        ( args_free p ) ( __free_strvec argv )
        ^ 2
    }
    ? | ( args_present p `help` ) == 0 ( args_positional_count p ) {
        ( __usage p )
        ( args_free p ) ( __free_strvec argv )
        ^ 0
    } {}

    : ( Vec String ) ps ( args_positionals p )
    : s cmd ( __pos ps 0 )

    : ~ String dirstr ( __opt_str p `dir` `` )
    ? == 0 ( string_len dirstr ) {
        ( string_free dirstr )
        = dirstr ( env_var_or `LSMDB_DIR` `lsmdb` )
    } {}

    : !*Lsm String opened ( lsm_open ( string_data dirstr ) )
    : ~ * Lsm db # *Lsm 0
    ?? opened {
        T h → { = db h }
        F e → {
            ( __die ( string_data e ) ) ( string_free e )
            ( string_free dirstr ) ( args_free p ) ( __free_strvec argv )
            ^ 1
        }
    }
    ( string_free dirstr )
    ? ( args_present p `no-sync` ) { ( lsm_set_durable db F ) } {}
    : i snap ( __opt_int p `at` ( lsm_seq db ) )

    ? ( nurl_str_eq cmd `put` ) {
        ? < ( args_positional_count p ) 3 {
            ( __die `put needs a key and a value` ) = rc 2
        } { = rc ( __cmd_put db ( __pos ps 1 ) ( __pos ps 2 ) ) }
    } {
        ? ( nurl_str_eq cmd `get` ) {
            ? < ( args_positional_count p ) 2 {
                ( __die `get needs a key` ) = rc 2
            } { = rc ( __cmd_get db ( __pos ps 1 ) snap ( args_present p `raw` ) ) }
        } {
            ? ( nurl_str_eq cmd `del` ) {
                ? < ( args_positional_count p ) 2 {
                    ( __die `del needs a key` ) = rc 2
                } { = rc ( __cmd_del db ( __pos ps 1 ) ) }
            } {
                ? ( nurl_str_eq cmd `scan` ) {
                    : String from ( __opt_str p `from` `` )
                    : String to ( __opt_str p `to` `` )
                    = rc ( __cmd_scan db ( string_data from ) ( string_data to )
                    ( __opt_int p `limit` 0 ) snap )
                    ( string_free from ) ( string_free to )
                } {
                    ? ( nurl_str_eq cmd `load` ) { = rc ( __cmd_load db ) } {
                        ? ( nurl_str_eq cmd `stats` ) { = rc ( __cmd_stats db ) } {
                            ? ( nurl_str_eq cmd `flush` ) {
                                ?? ( lsm_flush db ) {
                                    T n → {
                                        : String out ( string_with_cap 32 )
                                        ( string_push_int out n )
                                        ( string_push_str out ` entries flushed
` )
                                        ( nurl_print ( string_data out ) )
                                        ( string_free out )
                                    }
                                    F e → { ( __die ( string_data e ) ) ( string_free e ) = rc 3 }
                                }
                            } {
                                ? ( nurl_str_eq cmd `compact` ) {
                                    ?? ( lsm_compact db ) {
                                        T n → {
                                            : String out ( string_with_cap 32 )
                                            ( string_push_int out n )
                                            ( string_push_str out ` live entries kept
` )
                                            ( nurl_print ( string_data out ) )
                                            ( string_free out )
                                        }
                                        F e → { ( __die ( string_data e ) ) ( string_free e ) = rc 3 }
                                    }
                                } {
                                    ? ( nurl_str_eq cmd `bench` ) {
                                        = rc ( __cmd_bench db ( __opt_int p `num` 20000 ) )
                                    } {
                                        ( __die `unknown command (try --help)` )
                                        = rc 2
                                    } } } } } } } } }

    ( lsm_close db )
    ( args_free p )
    ( __free_strvec argv )
    ( flush )
    ^ rc
}
