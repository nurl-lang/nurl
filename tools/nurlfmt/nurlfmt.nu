// tools/nurlfmt/nurlfmt.nu — NURL canonical source formatter.
//
// Specification: docs/FORMAT.md
//
// Implementation strategy
// -----------------------
//
// NURL's regular prefix grammar means the formatter does not need a
// full CST. A two-pass token-stream walker is sufficient:
//
//   Pass 1 — Tokenise (preserving comments and inter-token newline
//            counts) via tools/nurlfmt/tokenize.nu.
//   Pass 2 — Walk the token stream and emit the canonical layout
//            via tools/nurlfmt/pretty.nu.
//
// CLI (final, see docs/FORMAT.md §CLI):
//
//   nurlfmt [--check] [--write] [--stdin] [FILE...]
//
// Exit codes:
//   0 — success (formatted output written, or --check passed)
//   1 — --check found at least one non-canonical file
//   2 — usage error or I/O error

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `tools/nurlfmt/format.nu`

// Print the usage banner to stderr.
@ __usage → v {
    ( nurl_eprint `nurlfmt — NURL canonical source formatter\n` )
    ( nurl_eprint `\n` )
    ( nurl_eprint `Usage: nurlfmt [OPTIONS] [FILE...]\n` )
    ( nurl_eprint `\n` )
    ( nurl_eprint `Options:\n` )
    ( nurl_eprint `    --check    Exit 0 if the input is canonical, 1 otherwise; emit no source.\n` )
    ( nurl_eprint `    --write    Reformat each FILE in place.\n` )
    ( nurl_eprint `    --stdin    Read stdin; combine with --check to validate it.\n` )
    ( nurl_eprint `    --        End options; remaining arguments are file paths.\n` )
    ( nurl_eprint `    --help     Print this message.\n` )
    ( nurl_eprint `    --version  Print the toolchain version (-v too).\n` )
    ( nurl_eprint `\n` )
    ( nurl_eprint `Without FILE and without --stdin, reads stdin → writes stdout.\n` )
}

// The caller retains ownership of body. Output ownership ends here on
// every check, write and stdout path, including failed writes.
@ __run_body s label String body b check_mode b write_mode → i {
    ? != ( string_len body ) ( nurl_str_len ( string_data body ) ) {
        ( nurl_eprintln ( nurl_str_cat3 `nurlfmt: ` label `: NUL byte in source` ) )
        ^ 2
    } {}
    : String out ( format_source body )
    : s out_view ( string_data out )
    : b same != 0 ( nurl_str_eq ( string_data body ) out_view )
    : ~ i rc 0
    ? check_mode {
        ? ! same {
            ( nurl_eprint ( nurl_str_cat3 `nurlfmt: ` label ` needs reformatting\n` ) )
            = rc 1
        } {}
    } {
        ? write_mode {
            ? ! same {
                ?? ( write_file label out_view ) {
                    T → {}
                    F e → {
                        ( nurl_eprintln ( nurl_str_cat3 ( nurl_str_cat3 `nurlfmt: ` label `: ` ) ( io_err_msg # IoErr e ) `` ) )
                        = rc 2
                    }
                }
            } {}
        } { ( nurl_print out_view ) }
    }
    ( string_free out )
    ^ rc
}

@ __run_stdin b check_mode → i {
    ?? ( read_stdin ) {
        F _ → { ( nurl_eprintln `nurlfmt: cannot read stdin` ) ^ 2 }
        T body → {
            : i rc ( __run_body `<stdin>` body check_mode F )
            ( string_free body )
            ^ rc
        }
    }
}

// Preserve the read error. An unreadable file must never be formatted as
// empty input, especially before an in-place write.
@ __run_one s path b check_mode b write_mode → i {
    ?? ( read_file path ) {
        F e → {
            ( nurl_eprintln ( nurl_str_cat3 ( nurl_str_cat3 `nurlfmt: ` path `: ` ) ( io_err_msg # IoErr e ) `` ) )
            ^ 2
        }
        T body → {
            : i rc ( __run_body path body check_mode write_mode )
            ( string_free body )
            ^ rc
        }
    }
}

@ main → i {
    : i argc ( nurl_argv_count )
    : ~ b check_mode F
    : ~ b write_mode F
    : ~ b stdin_mode F
    : ~ b help_mode F
    : ~ b version_mode F
    : ~ b options_done F
    : ~ i rc 0
    : ( Vec String ) paths ( vec_with_cap [String] 4 )
    : ~ i idx 1
    ~ & < idx argc & == rc 0 ! version_mode {
        // Paths adopt the owned argv copy; flags are auto-dropped here.
        // Every collected String is released at the single exit below.
        : s a ( nurl_argv_get idx )
        : ~ b path_arg options_done
        ? ! options_done {
            ? != 0 ( nurl_str_eq a `--` ) { = options_done T } {
                ? | | != 0 ( nurl_str_eq a `--version` ) != 0 ( nurl_str_eq a `-v` ) != 0 ( nurl_str_eq a `version` ) { = version_mode T } {
                    ? != 0 ( nurl_str_eq a `--help` ) { = help_mode T } {
                        ? != 0 ( nurl_str_eq a `--check` ) { = check_mode T } {
                            ? != 0 ( nurl_str_eq a `--write` ) { = write_mode T } {
                                ? != 0 ( nurl_str_eq a `--stdin` ) { = stdin_mode T } {
                                    ? != 0 ( nurl_str_starts a `-` ) {
                                        ( nurl_eprintln ( nurl_str_cat `nurlfmt: unknown option: ` a ) )
                                        = rc 2
                                    } { = path_arg T }
                                }
                            }
                        }
                    }
                }
            }
        } {}
        ? path_arg {
            ( vec_push [String] paths ( string_from_take a + ( nurl_str_len a ) 1 ) )
        } {}
        = idx + idx 1
    }
    : i nfiles ( vec_len [String] paths )
    ? == rc 0 {
        ? version_mode {
            ( nurl_print ( nurl_version ) ) ( nurl_print `\n` )
        } {
            ? help_mode { ( __usage ) } {
                ? & check_mode write_mode {
                    ( nurl_eprintln `nurlfmt: --check and --write are mutually exclusive` )
                    = rc 2
                } {
                    ? & stdin_mode > nfiles 0 {
                        ( nurl_eprintln `nurlfmt: --stdin cannot be combined with file paths` )
                        = rc 2
                    } {
                        ? & write_mode == nfiles 0 {
                            ( nurl_eprintln `nurlfmt: --write requires a file path` )
                            = rc 2
                        } {
                            ? == nfiles 0 { = rc ( __run_stdin check_mode ) } {
                                : ~ i i 0
                                ~ < i nfiles {
                                    ?? ( vec_get [String] paths i ) {
                                        T path → {
                                            : i one ( __run_one ( string_data path ) check_mode write_mode )
                                            ? > one rc { = rc one } {}
                                        }
                                        F _ → {}
                                    }
                                    = i + i 1
                                }
                            }
                        }
                    }
                }
            }
        }
    } {}
    ( vec_free_with [String] paths \ String path → v { ( string_free path ) } )
    ^ rc
}
