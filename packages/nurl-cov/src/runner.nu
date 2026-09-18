// nurl-cov/runner.nu — build the suite instrumented, run it, collect the graphs.
//
// A NURL package's tests are programs: one `.nu` per file under `tests/`,
// each importing the package's own modules and exiting non-zero on
// failure. Measuring them means building each one again with the
// compiler's coverage instrumentation, running it, and reading what it
// leaves behind.
//
// Two flags make the difference between a report and a flattering one:
//
//   -O0        the optimiser is free to fold, duplicate and reorder
//              blocks, and a line's count stops being a line's count.
//   --no-dce   dead-code elimination removes functions nothing calls —
//              which is EXACTLY the code a coverage report exists to
//              find. Without it the report cannot see what it is for:
//              on a small sample here that one flag moved the number
//              from 88.9% to an honest 72.7%.
//
// The build driver is resolved the way `nurlpkg test` resolves it, so a
// checkout and an installed toolchain both work without configuration.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`

: RunOne {
    String name
    b built
    b ran
    i code
    String detail  // compiler or runtime output when something went wrong
}

: RunResult {
    ( Vec RunOne ) tests
    i built
    i failed  // tests that exited non-zero
    i broken  // tests that would not build or would not run
}

@ runresult_free sink RunResult r → v {
    : i n ( vec_len [RunOne] . r tests )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [RunOne] . r tests i ) {
            T t → { ( string_free . t name ) ( string_free . t detail ) }
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [RunOne] . r tests )
}

// The build driver, in the order `nurlpkg test` looks for one: an explicit
// override, then a checkout you are standing in, then the installed tool.
@ runner_driver → String {
    ?? ( env_get `NURL_CC` ) {
        T v → ? > ( string_len v ) 0 { ^ v } { ( string_free v ) }
        F _ → {}
    }
    ? ( file_exists `./nurl.sh` ) { ^ ( string_from `./nurl.sh` ) } {}
    ? ( file_exists `../../nurl.sh` ) { ^ ( string_from `../../nurl.sh` ) } {}
    ?? ( env_get `NURL` ) {
        T v → ? > ( string_len v ) 0 { ^ v } { ( string_free v ) }
        F _ → {}
    }
    ^ ( string_from `nurl` )
}

// Every `.nu` directly under `dir`, in name order so a run is repeatable.
@ runner_find_tests s dir → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( dir_list dir ) {
        T names → {
            : i n ( vec_len [String] names )
            : ~ i i 0
            ~ < i n {
                ?? ( vec_get [String] names i ) {
                    T e → {
                        ? ( string_ends_with e `.nu` ) {
                            ( vec_push [String] out ( string_clone e ) )
                        } {}
                        ( string_free e )
                    }
                    F _ → {}
                }
                = i + i 1
            }
            ( vec_free [String] names )
        }
        F _ → {}
    }
    ( __run_sort out )
    ^ out
}

@ __run_sort ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i i 1
    ~ < i n {
        : ~ i j i
        ~ > j 0 {
            : b swap ?? ( vec_get [String] v - j 1 ) {
                T a → ?? ( vec_get [String] v j ) {
                    T b → > ( nurl_str_cmp ( string_data a ) ( string_data b ) ) 0
                    F _ → F
                }
                F _ → F
            }
            ? swap { ( vec_swap [String] v - j 1 j ) = j - j 1 } { = j 0 }
        }
        = i + i 1
    }
}

@ __run_join s a s b → String {
    : String out ( string_from a )
    ? ! ( string_ends_with out `/` ) { ( string_push_char out 47 ) } {}
    ( string_push_str out b )
    ^ out
}

@ __run_stem String name → String {
    : i n ( string_len name )
    ? & > n 3 ( string_ends_with name `.nu` ) { ^ ( string_substr name 0 - n 3 ) } {}
    ^ ( string_clone name )
}

// Build and run one test. The binary and its coverage graphs go to
// `workdir`; the compiler writes `<stem>.gcno` there, and the program
// writes `<stem>.gcda` beside it on exit — both paths are absolute in the
// generated module, so it does not matter where the program is started.
@ runner_one String driver String testpath String stem s workdir → RunOne {
    : String outbin ( __run_join workdir ( string_data stem ) )
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `--coverage` )
    ( vec_push [s] args `--no-dce` )
    ( vec_push [s] args `-O0` )
    ( vec_push [s] args ( string_data testpath ) )
    ( vec_push [s] args ( string_data outbin ) )
    : ~ b built F
    : ~ b ran F
    : ~ i code 0
    : String detail ( string_new )
    ?? ( process_run ( string_data driver ) args `` ) {
        T o → {
            = built ( output_success o )
            ? ! built {
                ( string_push_str detail ( output_stderr o ) )
                ( __run_hint detail )
            } {}
            ( output_free o )
        }
        F e → {
            ( string_push_str detail `could not run the build driver: ` )
            ( string_push_str detail ( process_err_name e ) )
        }
    }
    ( vec_free [s] args )

    ? built {
        : ( Vec s ) none ( vec_new [s] )
        ?? ( process_run ( string_data outbin ) none `` ) {
            T o → {
                = ran T
                = code ( output_exit_code o )
                ? != code 0 { ( string_push_str detail ( output_stderr o ) ) } {}
                ( output_free o )
            }
            F e → {
                ( string_push_str detail `built, but would not run: ` )
                ( string_push_str detail ( process_err_name e ) )
            }
        }
        ( vec_free [s] none )
    } {}

    ( string_free outbin )
    ^ @ RunOne { ( string_clone stem ) built ran code detail }
}

// A driver too old to forward `--no-dce` reads it as the file to compile.
// Say so plainly rather than quietly measuring the wrong thing.
@ __run_hint String detail → v {
    ? ( string_contains detail `--no-dce` ) {
        ( string_push_str detail `\nnurl-cov passes --no-dce so that functions nothing ` )
        ( string_push_str detail `calls still appear in the report. A build driver that ` )
        ( string_push_str detail `does not forward it is too old: upgrade the toolchain ` )
        ( string_push_str detail `(nurl upgrade).\n` )
    } {}
}

@ runner_run_all String driver ( Vec String ) tests s testdir s workdir → RunResult {
    : ( Vec RunOne ) rows ( vec_new [RunOne] )
    : ~ i built 0
    : ~ i failed 0
    : ~ i broken 0
    : i n ( vec_len [String] tests )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] tests i ) {
            T name → {
                : String full ( __run_join testdir ( string_data name ) )
                : String stem ( __run_stem name )
                : RunOne r ( runner_one driver full stem workdir )
                ? . r built { = built + built 1 } { = broken + broken 1 }
                ? & . r ran != 0 . r code { = failed + failed 1 } {}
                ? & . r built ! . r ran { = broken + broken 1 } {}
                ( vec_push [RunOne] rows r )
                ( string_free full )
                ( string_free stem )
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ @ RunResult { rows built failed broken }
}

// Start from a clean slate.
//
// A `.gcda` ACCUMULATES: running an instrumented program again adds to
// the counters already there. That is the right behaviour for a program
// you are exercising by hand, and the wrong one for a suite you are
// measuring — the second `nurl-cov run` would report the first run's
// traffic too, and a `.gcno` left over from a test that has since been
// deleted would keep contributing coverage for code nothing tests any
// more. Both are silent, and both flatter.
@ runner_clean s dir → v {
    ?? ( dir_list dir ) {
        T names → {
            : i n ( vec_len [String] names )
            : ~ i i 0
            ~ < i n {
                ?? ( vec_get [String] names i ) {
                    T e → {
                        ? | ( string_ends_with e `.gcno` ) ( string_ends_with e `.gcda` ) {
                            : String full ( __run_join dir ( string_data e ) )
                            ?? ( file_delete ( string_data full ) ) { T _ → {} F _ → {} }
                            ( string_free full )
                        } {}
                        ( string_free e )
                    }
                    F _ → {}
                }
                = i + i 1
            }
            ( vec_free [String] names )
        }
        F _ → {}
    }
}

// Every coverage object in `dir`: a `.gcno` the compiler wrote, paired
// with the `.gcda` its program left — or not, when the program never ran.
@ runner_objects s dir → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( dir_list dir ) {
        T names → {
            : i n ( vec_len [String] names )
            : ~ i i 0
            ~ < i n {
                ?? ( vec_get [String] names i ) {
                    T e → {
                        ? ( string_ends_with e `.gcno` ) {
                            ( vec_push [String] out ( __run_join dir ( string_data e ) ) )
                        } {}
                        ( string_free e )
                    }
                    F _ → {}
                }
                = i + i 1
            }
            ( vec_free [String] names )
        }
        F _ → {}
    }
    ( __run_sort out )
    ^ out
}

@ runner_data_path s notes → String {
    : i n ( nurl_str_len notes )
    : String out ( string_new )
    ? > n 5 {
        : *u at # *u + # i notes 0
        : String stem ( string_from_bytes at - n 5 )
        ( string_push_str out ( string_data stem ) )
        ( string_free stem )
    } {
        ( string_push_str out notes )
    }
    ( string_push_str out `.gcda` )
    ^ out
}
