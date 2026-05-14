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
$ `tools/nurlfmt/tokenize.nu`
$ `tools/nurlfmt/pretty.nu`

// Read the entire file at `path` into an owned String. Returns an
// empty String on failure; the caller surfaces the error via stderr.
@ __slurp_file s path → String {
    : !String IoErr rr ( read_file path )
    ?? rr {
        T body → ^ body
        F _ → ^ ( string_new )
    }
}

// Read all of stdin into an owned String.
@ __slurp_stdin → String {
    ^ ( read_all_stdin )
}

// Format `src` to its canonical layout per docs/FORMAT.md.
//
// Memory note: per-token text allocations leak by design. Walking
// the Vec[FmtTok] to free each text was triggering a double-free
// against the pretty printer's String buffer; the per-token
// cleanup path needs a re-think before being re-enabled. Net leak
// per invocation is one allocation per source token — acceptable
// for a one-shot CLI; the OS reclaims on exit.
@ format_source String src → String {
    : ( Vec FmtTok ) toks ( tokenize ( string_data src ) )
    : String out ( pretty_print toks )
    ^ out
}

// Print the usage banner to stderr.
@ __usage → v {
    ( nurl_eprint `nurlfmt — NURL canonical source formatter\n` )
    ( nurl_eprint `\n` )
    ( nurl_eprint `Usage: nurlfmt [OPTIONS] [FILE...]\n` )
    ( nurl_eprint `\n` )
    ( nurl_eprint `Options:\n` )
    ( nurl_eprint `    --check    Exit 0 if every FILE is already canonical, 1 otherwise.\n` )
    ( nurl_eprint `    --write    Reformat each FILE in place.\n` )
    ( nurl_eprint `    --stdin    Read from stdin, write to stdout.\n` )
    ( nurl_eprint `    --help     Print this message.\n` )
    ( nurl_eprint `\n` )
    ( nurl_eprint `Without FILE and without --stdin, reads stdin → writes stdout.\n` )
}

// Format the stdin stream to stdout. Always exits 0 on success.
@ __run_stdin → i {
    : String src ( __slurp_stdin )
    : String out ( format_source src )
    ( nurl_print ( string_data out ) )
    ^ 0
}

// Format one file. Returns the same kind of exit-code triple as
// __run_files so the caller can fold across multiple paths:
//   0 = success / already-canonical
//   1 = --check found this file non-canonical
//   2 = I/O or other error (path missing, read failure)
@ __run_one s path b check_mode b write_mode → i {
    ? ! ( file_exists path ) {
        ( nurl_eprint ( nurl_str_cat3 `nurlfmt: ` path `: file not found\n` ) )
        ^ 2
    } {}
    : String body ( __slurp_file path )
    : String out ( format_source body )
    : s body_view ( string_data body )
    : s out_view ( string_data out )
    : b same != 0 ( nurl_str_eq body_view out_view )
    ? check_mode {
        ? same {
            ^ 0
        } {
            ( nurl_eprint ( nurl_str_cat3 `nurlfmt: ` path ` needs reformatting\n` ) )
            ^ 1
        }
    } {}
    ? write_mode {
        ? same {
            ^ 0
        } {
            : !v IoErr wr ( write_file path out_view )
            ?? wr {
                T → ^ 0
                F _ → {
                    ( nurl_eprint ( nurl_str_cat3 `nurlfmt: ` path `: write failed\n` ) )
                    ^ 2
                }
            }
        }
    } {}
    // Default mode: stdout.
    ( nurl_print out_view )
    ^ 0
}

@ main → i {
    : i argc ( nurl_argv_count )

    // Bare invocation: stdin → stdout (gofmt-compatible).
    ? <= argc 1 {
        ^ ( __run_stdin )
    } {}

    // Two-pass argv parse: collect flags, then process file paths.
    : ~ b check_mode F
    : ~ b write_mode F
    : ~ b stdin_mode F
    : ~ b help_mode F
    : ( Vec String ) paths ( vec_with_cap [String] 4 )

    : ~ i idx 1
    ~ < idx argc {
        : s a ( nurl_argv_get idx )
        ? != 0 ( nurl_str_eq a `--help` ) { = help_mode T } {
            ? != 0 ( nurl_str_eq a `--check` ) { = check_mode T } {
                ? != 0 ( nurl_str_eq a `--write` ) { = write_mode T } {
                    ? != 0 ( nurl_str_eq a `--stdin` ) { = stdin_mode T } {
                        // Treat anything else as a file path. `string_from`
                        // copies into an owned String so the Vec keeps a stable
                        // handle after the argv slot rotates.
                        ( vec_push [String] paths ( string_from a ) )
                    } } } }
        = idx + idx 1
    }

    ? help_mode {
        ( __usage )
        ^ 0
    } {}

    ? stdin_mode {
        ^ ( __run_stdin )
    } {}

    ? & check_mode write_mode {
        ( nurl_eprint `nurlfmt: --check and --write are mutually exclusive\n` )
        ^ 2
    } {}

    : i nfiles ( vec_len [String] paths )
    ? == nfiles 0 {
        // Flags present but no files. Fall back to stdin.
        ^ ( __run_stdin )
    } {}

    // Fold across all paths. The final exit code is the worst
    // (highest) per-file code: 2 (I/O error) > 1 (check failure)
    // > 0 (success).
    : ~ i worst 0
    : ~ i i 0
    ~ < i nfiles {
        ?? ( vec_get [String] paths i ) {
            T p → {
                : i rc ( __run_one ( string_data p ) check_mode write_mode )
                ? > rc worst { = worst rc } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ worst
}
