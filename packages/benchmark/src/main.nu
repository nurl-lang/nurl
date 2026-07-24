// packages/benchmark — the CLI.
//
//   benchmark                 run the whole suite, print a table
//   benchmark <name…>         run only the named benchmarks
//   benchmark --list          list the benchmark names
//   benchmark --json          emit the measurements as JSON
//   benchmark --help
//
// Every number is measured on the machine it runs on. Pure NURL, zero
// dependencies beyond the standard library — no GPU, model or network.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `src/report.nu`
$ `src/suite.nu`

// the registry of benchmarks: name → thunk producing its row
@ __bench_count → i { ^ 7 }

@ __bench_name i idx → s {
    ? == idx 0 { ^ `sha256` } {}
    ? == idx 1 { ^ `json parse` } {}
    ? == idx 2 { ^ `sort i64` } {}
    ? == idx 3 { ^ `cbor decode` } {}
    ? == idx 4 { ^ `utf8 decode` } {}
    ? == idx 5 { ^ `int loop` } {}
    ^ `csv sort 1M×8`
}

@ __bench_run_one i idx → BenchRow {
    ? == idx 0 { ^ ( bench_sha256 ) } {}
    ? == idx 1 { ^ ( bench_json_parse ) } {}
    ? == idx 2 { ^ ( bench_sort ) } {}
    ? == idx 3 { ^ ( bench_cbor_decode ) } {}
    ? == idx 4 { ^ ( bench_utf8_decode ) } {}
    ? == idx 5 { ^ ( bench_int_loop ) } {}
    ^ ( bench_csv_sort )
}

// was `name` asked for? (no positional filters → everything)
@ __bench_selected ( Vec String ) filters s name → b {
    ? == ( vec_len [String] filters ) 0 { ^ T } {}
    : ~ i k 0
    ~ < k ( vec_len [String] filters ) {
        ?? ( vec_get [String] filters k ) {
            T f → { ? != 0 ( nurl_str_eq ( string_data f ) name ) { ^ T } {} }
            F → {}
        }
        = k + k 1
    }
    ^ F
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    : ~ b as_json F
    : ~ b do_list F
    : ~ b do_help F
    : ( Vec String ) filters ( vec_new [String] )
    : ~ i k 1
    ~ < k ( vec_len [String] av ) {
        ?? ( vec_get [String] av k ) {
            T a → {
                : s ad ( string_data a )
                ? != 0 ( nurl_str_eq ad `--json` ) { = as_json T } {
                    ? != 0 ( nurl_str_eq ad `--list` ) { = do_list T } {
                        ? | != 0 ( nurl_str_eq ad `--help` ) != 0 ( nurl_str_eq ad `-h` ) { = do_help T } {
                            ( vec_push [String] filters ( string_from ad ) )
                        }
                    }
                }
            }
            F → {}
        }
        = k + k 1
    }

    ? do_help {
        ( nurl_print `benchmark — reproduce NURL's throughput claims on this machine.\n\n` )
        ( nurl_print `  benchmark              run the whole suite\n` )
        ( nurl_print `  benchmark <name…>      run only the named benchmarks\n` )
        ( nurl_print `  benchmark --list       list the benchmark names\n` )
        ( nurl_print `  benchmark --json       emit the measurements as JSON\n\n` )
        ( nurl_print `Pure NURL, no GPU / model / network. Throughput is MB/s, M/s (millions\nof elements or iterations per second), measured with std/bench.\n` )
        ( __bench_free_args av filters )
        ^ 0
    } {}

    ? do_list {
        : ~ i i 0
        ~ < i ( __bench_count ) {
            ( nurl_print ( __bench_name i ) ) ( nurl_print `\n` )
            = i + i 1
        }
        ( __bench_free_args av filters )
        ^ 0
    } {}

    ? as_json {} {
        ( nurl_print `NURL benchmark suite — pure-NURL throughput on this machine\n\n` )
    }

    : ~ b first T
    ? as_json { ( nurl_print `[` ) } {}
    : ~ i i 0
    ~ < i ( __bench_count ) {
        ? ( __bench_selected filters ( __bench_name i ) ) {
            : BenchRow r ( __bench_run_one i )
            ? as_json {
                ? first { = first F } { ( nurl_print `,` ) }
                : String j ( bench_row_json r )
                ( nurl_print ( string_data j ) )
                ( string_free j )
            } {
                ( bench_row_print r )
            }
            ( bench_row_free r )
        } {}
        = i + i 1
    }
    ? as_json { ( nurl_print `]\n` ) } {}

    ( __bench_free_args av filters )
    ^ 0
}

@ __bench_free_args ( Vec String ) av ( Vec String ) filters → v {
    ( vec_free_with [String] av \ String s → v { ( string_free s ) } )
    ( vec_free_with [String] filters \ String s → v { ( string_free s ) } )
}
