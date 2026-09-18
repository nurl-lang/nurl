// nurl-cov — test-coverage mapper for NURL.
//
//   nurl-cov run                     build tests/ instrumented, run, report
//   nurl-cov report <dir>            report on coverage graphs already there
//   nurl-cov gcov <dir|file.gcno>    gcov-style annotated source
//
// Options that shape the output apply to `run` and `report` alike:
//   --uncovered        list the line ranges nothing executed
//   --lcov FILE        write an LCOV tracefile
//   --html FILE        write one self-contained HTML report
//   --json FILE        write machine-readable JSON
//   --fail-under PCT   exit non-zero below this line coverage
//   --include PREFIX   keep only files under PREFIX (repeatable)
//   --all              keep every file, the stdlib included
//
//   nurl-cov run --fail-under 80 --lcov coverage.info
//
// Exit codes: 0 all good · 1 below the floor, or a test failed · 2 usage
// or a broken build. A gate that cannot tell "untested" from "failed to
// build" is not a gate, so those are different codes and different words.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `gcov.nu`
$ `lines.nu`
$ `model.nu`
$ `gcovtext.nu`
$ `report.nu`
$ `lcov.nu`
$ `html.nu`
$ `jsonout.nu`
$ `runner.nu`

: s NURLCOV_VERSION `0.1.0`

@ __usage → v {
    ( nurl_print `nurl-cov — test-coverage mapper for NURL\n\n` )
    ( nurl_print `Usage:\n` )
    ( nurl_print `  nurl-cov run [options]            build tests/ instrumented, run them, report\n` )
    ( nurl_print `  nurl-cov report <dir> [options]   report on coverage graphs already written\n` )
    ( nurl_print `  nurl-cov gcov <dir|file.gcno>     annotated source, gcov's own format\n\n` )
    ( nurl_print `Options:\n` )
    ( nurl_print `  --tests DIR      where the tests live (default tests)\n` )
    ( nurl_print `  --work DIR       where instrumented binaries go (default .nurl-cov)\n` )
    ( nurl_print `  --include PREFIX keep only files under PREFIX (repeatable; default src)\n` )
    ( nurl_print `  --all            keep every file, the stdlib included\n` )
    ( nurl_print `  --uncovered      list the line ranges nothing executed\n` )
    ( nurl_print `  --lcov FILE      write an LCOV tracefile\n` )
    ( nurl_print `  --html FILE      write one self-contained HTML report\n` )
    ( nurl_print `  --json FILE      write machine-readable JSON\n` )
    ( nurl_print `  --fail-under PCT exit non-zero below this line coverage\n` )
    ( nurl_print `  --quiet          suppress the summary table\n` )
    ( nurl_print `  --no-color       plain text, even at a terminal\n` )
    ( nurl_print `  --version        print the version and exit\n\n` )
    ( nurl_print `Coverage needs the toolchain's GCOV instrumentation: nurl-cov builds\n` )
    ( nurl_print `each test with --coverage --no-dce -O0, so that functions nothing\n` )
    ( nurl_print `calls are still in the binary and still counted — as zero.\n` )
}

@ __mkparser → ArgParser {
    : ArgParser p ( args_new `nurl-cov` `test-coverage mapper for NURL` )
    ( args_flag p `help` 104 `show this help` )
    ( args_flag p `version` 118 `print the version and exit` )
    ( args_flag p `uncovered` 117 `list the line ranges nothing executed` )
    ( args_flag p `all` 97 `keep every file, the stdlib included` )
    ( args_flag p `quiet` 113 `suppress the summary table` )
    ( args_flag p `no-color` 0 `plain text, even at a terminal` )
    ( args_opt p `tests` 116 `DIR` `where the tests live (default tests)` )
    ( args_opt p `work` 119 `DIR` `where instrumented binaries go (default .nurl-cov)` )
    ( args_opt p `include` 0 `PREFIX` `keep only files under PREFIX (repeatable)` )
    ( args_opt p `lcov` 0 `FILE` `write an LCOV tracefile` )
    ( args_opt p `html` 0 `FILE` `write one self-contained HTML report` )
    ( args_opt p `json` 0 `FILE` `write machine-readable JSON` )
    ( args_opt p `fail-under` 0 `PCT` `exit non-zero below this line coverage` )
    ^ p
}

@ __argv → ( Vec String ) {
    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i i 1
    ~ < i ac { ( vec_push [String] argv ( env_arg i ) ) = i + i 1 }
    ^ argv
}

@ __free_strs ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] v i ) { T s → ( string_free s ) F _ → {} }
        = i + i 1
    }
    ( vec_free [String] v )
}

@ __opt_or ArgParser p s name s dflt → String {
    ^ ?? ( args_value p name ) { T v → v F _ → ( string_from dflt ) }
}

// A percentage on the command line is written the way people write it —
// "80", or "79.5". It is carried in tenths so the comparison against the
// report is exact.
@ __pct_tenths s text → i {
    : i n ( nurl_str_len text )
    : ~ i whole 0
    : ~ i frac 0
    : ~ b after F
    : ~ i k 0
    ~ < k n {
        : i ch ( nurl_str_at text n k )
        ? == ch 46 { = after T } {
            ? & >= ch 48 <= ch 57 {
                ? after {
                    ? == frac 0 { = frac - ch 48 } {}
                } { = whole + * whole 10 - ch 48 }
            } {}
        }
        = k + k 1
    }
    ^ + * whole 10 frac
}

@ __write_out s path String body s label → b {
    ?? ( write_file path ( string_data body ) ) {
        T _ → {
            ( nurl_eprint `nurl-cov: wrote ` )
            ( nurl_eprint label )
            ( nurl_eprint ` to ` )
            ( nurl_eprintln path )
            ^ T
        }
        F _ → {
            ( nurl_eprint `nurl-cov: cannot write ` )
            ( nurl_eprintln path )
            ^ F
        }
    }
}

// ── Collecting ───────────────────────────────────────────────────

@ __collect * Cov c s dir → i {
    : ( Vec String ) notes ( runner_objects dir )
    : i n ( vec_len [String] notes )
    : ~ i ok 0
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] notes i ) {
            T np → {
                : String dp ( runner_data_path ( string_data np ) )
                ?? ( gcov_read ( string_data np ) ( string_data dp ) ) {
                    T o → {
                        ( cov_add_object c o )
                        ( gcov_free o )
                        = ok + ok 1
                    }
                    F e → {
                        ( nurl_eprint `nurl-cov: ` )
                        ( nurl_eprint ( string_data np ) )
                        ( nurl_eprint `: ` )
                        ( nurl_eprintln ( gcov_err_name e ) )
                    }
                }
                ( string_free dp )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( __free_strs notes )
    ^ ok
}

@ __prefixes ArgParser p b all → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ? all { ^ out } {}
    : ( Vec String ) given ( args_values p `include` )
    : i n ( vec_len [String] given )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] given k ) {
            T v → {
                ( vec_push [String] out ( __abs ( string_data v ) ) )
                ( string_free v )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [String] given )
    ? > ( vec_len [String] out ) 0 { ^ out } {}
    ( vec_push [String] out ( __abs `src` ) )
    ^ out
}

// Coverage graphs name their sources by absolute path, because the
// compiler wrote them that way so a program can be started from anywhere.
// A filter given as `src` has to be made absolute to match.
@ __abs s rel → String {
    ? == 47 ( nurl_str_at rel ( nurl_str_len rel ) 0 ) { ^ ( string_from rel ) } {}
    ^ ?? ( env_cwd ) {
        T cwd → {
            : String out ( string_clone cwd )
            ( string_free cwd )
            ? ! ( string_ends_with out `/` ) { ( string_push_char out 47 ) } {}
            ( string_push_str out rel )
            out
        }
        F _ → ( string_from rel )
    }
}

// ── Output ───────────────────────────────────────────────────────

@ __emit ArgParser p * Cov c i floor_tenths → b {
    : String root ?? ( env_cwd ) { T d → d F _ → ( string_new ) }
    : ~ b ok T
    ? ! ( args_present p `quiet` ) {
        : b colour & ! ( args_present p `no-color` ) ( report_colour_wanted )
        : RepStyle st ( report_style colour floor_tenths )
        : String table ( report_render c st ( string_data root ) )
        ( nurl_print ( string_data table ) )
        ( string_free table )
    } {}
    ? ( args_present p `uncovered` ) {
        : String u ( report_uncovered c ( string_data root ) )
        ( nurl_print `\n` )
        ( nurl_print ( string_data u ) )
        ( string_free u )
    } {}
    ?? ( args_value p `lcov` ) {
        T f → {
            : String body ( lcov_render c )
            ? ! ( __write_out ( string_data f ) body `LCOV` ) { = ok F } {}
            ( string_free body )
            ( string_free f )
        }
        F _ → {}
    }
    ?? ( args_value p `html` ) {
        T f → {
            : String body ( html_render c floor_tenths `NURL coverage` ( string_data root ) )
            ? ! ( __write_out ( string_data f ) body `HTML report` ) { = ok F } {}
            ( string_free body )
            ( string_free f )
        }
        F _ → {}
    }
    ?? ( args_value p `json` ) {
        T f → {
            : String body ( json_render c )
            ? ! ( __write_out ( string_data f ) body `JSON` ) { = ok F } {}
            ( string_free body )
            ( string_free f )
        }
        F _ → {}
    }
    ( string_free root )
    ^ ok
}

@ __gate * Cov c i floor_tenths → b {
    ? <= floor_tenths 0 { ^ T } {}
    : CovStat t ( cov_total c )
    : i got ( cov_pct_tenths . t lines_hit . t lines_found )
    ? >= got floor_tenths { ^ T } {}
    ( nurl_eprint `nurl-cov: line coverage ` )
    ( __eprint_tenths got )
    ( nurl_eprint ` is below the required ` )
    ( __eprint_tenths floor_tenths )
    ( nurl_eprintln `` )
    ^ F
}

@ __eprint_tenths i tenths → v {
    : String s ( string_with_cap 16 )
    ( string_push_int s / tenths 10 )
    ( string_push_char s 46 )
    ( string_push_int s % tenths 10 )
    ( string_push_char s 37 )
    ( nurl_eprint ( string_data s ) )
    ( string_free s )
}

// ── Subcommands ──────────────────────────────────────────────────

@ __cmd_run ArgParser p → i {
    : String testdir ( __opt_or p `tests` `tests` )
    : String workdir ( __opt_or p `work` `.nurl-cov` )
    ? ! ( file_exists ( string_data testdir ) ) {
        ( nurl_eprint `nurl-cov: no test directory: ` )
        ( nurl_eprintln ( string_data testdir ) )
        ( nurl_eprintln `nurl-cov: point --tests at one, or run 'nurl-cov report <dir>'` )
        ( string_free testdir )
        ( string_free workdir )
        ^ 2
    } {}
    ?? ( dir_create_all ( string_data workdir ) ) { T _ → {} F _ → {} }
    // Counters accumulate across runs, so a fresh measurement starts from
    // a fresh work directory: see `runner_clean`.
    ( runner_clean ( string_data workdir ) )

    : ( Vec String ) tests ( runner_find_tests ( string_data testdir ) )
    ? == 0 ( vec_len [String] tests ) {
        ( nurl_eprint `nurl-cov: no .nu tests in ` )
        ( nurl_eprintln ( string_data testdir ) )
        ( __free_strs tests )
        ( string_free testdir )
        ( string_free workdir )
        ^ 2
    } {}

    : String driver ( runner_driver )
    ( nurl_eprint `nurl-cov: building ` )
    ( __eprint_int ( vec_len [String] tests ) )
    ( nurl_eprint ` test(s) with coverage using ` )
    ( nurl_eprintln ( string_data driver ) )

    : RunResult r ( runner_run_all driver tests ( string_data testdir )
    ( string_data workdir ) )
    ( __report_runs r )

    : ~ i rc 0
    ? > . r broken 0 { = rc 2 } {}
    ? & == rc 0 > . r failed 0 { = rc 1 } {}

    : *Cov c ( cov_new )
    : i objects ( __collect c ( string_data workdir ) )
    ? == objects 0 {
        ( nurl_eprintln `nurl-cov: no coverage graphs were produced` )
        ( cov_free c )
        ( runresult_free r )
        ( __free_strs tests )
        ( string_free driver )
        ( string_free testdir )
        ( string_free workdir )
        ^ 2
    } {}
    : i out ( __finish p c )
    ? & == rc 0 != out 0 { = rc out } {}

    ( cov_free c )
    ( runresult_free r )
    ( __free_strs tests )
    ( string_free driver )
    ( string_free testdir )
    ( string_free workdir )
    ^ rc
}

@ __eprint_int i n → v {
    : String s ( string_with_cap 24 )
    ( string_push_int s n )
    ( nurl_eprint ( string_data s ) )
    ( string_free s )
}

@ __report_runs RunResult r → v {
    : i n ( vec_len [RunOne] . r tests )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [RunOne] . r tests i ) {
            T t → {
                ? ! . t built {
                    ( nurl_eprint `  BUILD FAIL ` )
                    ( nurl_eprintln ( string_data . t name ) )
                    ( nurl_eprintln ( string_data . t detail ) )
                } {
                    ? ! . t ran {
                        ( nurl_eprint `  NO RUN     ` )
                        ( nurl_eprintln ( string_data . t name ) )
                        ( nurl_eprintln ( string_data . t detail ) )
                    } {
                        ? == 0 . t code {
                            ( nurl_eprint `  ok         ` )
                            ( nurl_eprintln ( string_data . t name ) )
                        } {
                            ( nurl_eprint `  FAIL       ` )
                            ( nurl_eprint ( string_data . t name ) )
                            ( nurl_eprint ` (exit ` )
                            ( __eprint_int . t code )
                            ( nurl_eprintln `)` )
                        }
                    }
                }
            }
            F _ → {}
        }
        = i + i 1
    }
}

@ __finish ArgParser p * Cov c → i {
    : b all ( args_present p `all` )
    : ( Vec String ) keep ( __prefixes p all )
    ( cov_keep_only c keep )
    ( __free_strs keep )
    ( cov_sort c )
    ? == 0 ( cov_file_count c ) {
        ( nurl_eprintln `nurl-cov: nothing left after filtering — try --all or --include` )
        ^ 2
    } {}
    : ~ i floor_tenths 0
    ?? ( args_value p `fail-under` ) {
        T v → { = floor_tenths ( __pct_tenths ( string_data v ) ) ( string_free v ) }
        F _ → {}
    }
    ? ! ( __emit p c floor_tenths ) { ^ 2 } {}
    ? ! ( __gate c floor_tenths ) { ^ 1 } {}
    ^ 0
}

@ __cmd_report ArgParser p String dir → i {
    : *Cov c ( cov_new )
    : i objects ( __collect c ( string_data dir ) )
    ? == objects 0 {
        ( nurl_eprint `nurl-cov: no .gcno coverage graphs in ` )
        ( nurl_eprintln ( string_data dir ) )
        ( cov_free c )
        ^ 2
    } {}
    : i rc ( __finish p c )
    ( cov_free c )
    ^ rc
}

// The annotated listing, byte-compatible with `llvm-cov gcov -b -c`.
@ __cmd_gcov String target → i {
    : ~ ( Vec String ) notes ( vec_new [String] )
    ? ( string_ends_with target `.gcno` ) {
        ( vec_push [String] notes ( string_clone target ) )
    } {
        ( __free_strs notes )
        = notes ( runner_objects ( string_data target ) )
    }
    : i n ( vec_len [String] notes )
    ? == 0 n {
        ( nurl_eprint `nurl-cov: no coverage graphs at ` )
        ( nurl_eprintln ( string_data target ) )
        ( __free_strs notes )
        ^ 2
    } {}
    : ~ i rc 0
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] notes i ) {
            T np → {
                : String dp ( runner_data_path ( string_data np ) )
                ?? ( gcov_read ( string_data np ) ( string_data dp ) ) {
                    T o → {
                        : i nf ( gcov_file_count o )
                        : ~ i k 0
                        ~ < k nf {
                            : String text ( gcovtext_render o k )
                            ( nurl_print ( string_data text ) )
                            ( string_free text )
                            = k + k 1
                        }
                        ( gcov_free o )
                    }
                    F e → {
                        ( nurl_eprint `nurl-cov: ` )
                        ( nurl_eprintln ( gcov_err_name e ) )
                        = rc 2
                    }
                }
                ( string_free dp )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( __free_strs notes )
    ^ rc
}

@ main → i {
    : ArgParser p ( __mkparser )
    : ( Vec String ) argv ( __argv )
    : ~ i rc 0
    ? ( args_parse p argv ) {
        ? ( args_present p `version` ) {
            ( nurl_print `nurl-cov ` )
            ( nurl_print NURLCOV_VERSION )
            ( nurl_print `\n` )
        } {
            : i np ( args_positional_count p )
            ? | ( args_present p `help` ) == np 0 { ( __usage ) } {
                // BORROWED from the parser: args_free owns these.
                : ( Vec String ) pos ( args_positionals p )
                : String cmd ?? ( vec_get [String] pos 0 ) {
                    T s → ( string_clone s )
                    F _ → ( string_new )
                }
                ? != 0 ( nurl_str_eq ( string_data cmd ) `run` ) {
                    = rc ( __cmd_run p )
                } {
                    ? != 0 ( nurl_str_eq ( string_data cmd ) `report` ) {
                        ?? ( vec_get [String] pos 1 ) {
                            T d → = rc ( __cmd_report p d )
                            F _ → {
                                ( nurl_eprintln `nurl-cov: report needs a directory` )
                                = rc 2
                            }
                        }
                    } {
                        ? != 0 ( nurl_str_eq ( string_data cmd ) `gcov` ) {
                            ?? ( vec_get [String] pos 1 ) {
                                T d → = rc ( __cmd_gcov d )
                                F _ → {
                                    ( nurl_eprintln `nurl-cov: gcov needs a directory or a .gcno file` )
                                    = rc 2
                                }
                            }
                        } {
                            ( nurl_eprint `nurl-cov: unknown command: ` )
                            ( nurl_eprintln ( string_data cmd ) )
                            = rc 2
                        }
                    }
                }
                ( string_free cmd )
            }
        }
    } {
        ( nurl_eprint `nurl-cov: ` )
        ( nurl_eprintln ( args_error p ) )
        ( nurl_eprintln `try 'nurl-cov --help'` )
        = rc 2
    }
    ( args_free p )
    ( __free_strs argv )
    ^ rc
}
