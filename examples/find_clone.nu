// find_clone.nu — grep-like recursive search over files / directories
//
// Demonstrates:
//   - CLI flag parsing (nurl_argv_get / nurl_argv_count)
//   - File I/O via stdlib/std/fs.nu (read_file + dir_list + IoErr)
//   - Recursive directory walk
//   - Regex engine via stdlib/ext/regex.nu (regex_compile / _test)
//   - Owned-resource auto-drop across function boundaries
//
// Usage:
//   find_clone [MODE] PATTERN [PATH ...]
//
// Modes:
//   (default)              literal substring match
//   --list PAT[,PAT...]    comma-separated alternatives (any match)
//   --regex PAT            POSIX-extended regex
//
// PATH is one or more files or directories. Directories recurse;
// hidden entries (leading ".") are skipped. With no PATH the tool
// reads stdin until EOF. Lines are NUL-byte-safe up to but not
// including the first NUL (NURL strings are NUL-terminated).
//
// Output (per match):
//   path:line:contents
//
// Exit codes:
//   0  one or more matches were printed
//   1  no matches found
//   2  usage / I/O error
//
// Build & run:
//   ./build/nurlc examples/find_clone.nu > /tmp/find_clone.ll
//   clang /tmp/find_clone.ll stdlib/runtime.o -lm -lpthread -o /tmp/find_clone
//   /tmp/find_clone error stdlib/std/log.nu
//   /tmp/find_clone --list error,warn stdlib/std/
//   /tmp/find_clone --regex 'log_[a-z]+f[0-9]' stdlib/std/log.nu

$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/regex.nu`

// ── Line scanning ──────────────────────────────────────────────────
//
// Walk `text` line-by-line, calling the matcher closure for each.
// Returns the number of matches (which we also print as a side effect
// from the closure — the i-return is purely for "any-match" testing
// in main's exit-code decision).

@ scan_lines s path s text ( @ b s ) test → i {
    : i n ( nurl_str_len text )
    : *u p # *u text
    : ~ i hits 0
    : ~ i lineno 1
    : ~ i start 0
    : ~ i k 0
    ~ < k n {
        : i c & # i . p k 255
        ? == c 10 {
            : i ll - k start
            : s line ( nurl_str_slice text start ll )
            ? ( test line ) {
                ( nurl_print path )
                ( nurl_print `:` )
                ( nurl_print ( nurl_str_int lineno ) )
                ( nurl_print `:` )
                ( nurl_print line )
                ( nurl_print `\n` )
                = hits + hits 1
            } {}
            = lineno + lineno 1
            = start + k 1
        } {}
        = k + k 1
    }
    // Trailing line without a closing newline.
    ? > n start {
        : s line ( nurl_str_slice text start - n start )
        ? ( test line ) {
            ( nurl_print path )
            ( nurl_print `:` )
            ( nurl_print ( nurl_str_int lineno ) )
            ( nurl_print `:` )
            ( nurl_print line )
            ( nurl_print `\n` )
            = hits + hits 1
        } {}
    } {}
    ^ hits
}

// ── Walk a single file ─────────────────────────────────────────────
//
// Reads the file's contents and delegates to scan_lines. Errors on
// the read path print to stderr and contribute zero hits — find_clone
// keeps walking the rest of the inputs.

@ scan_file s path ( @ b s ) test → i {
    : !String IoErr r ( read_file path )
    ?? r {
        T content → {
            : i h ( scan_lines path ( string_data content ) test )
            ^ h
        }
        F err → {
            ( nurl_eprint `find_clone: ` )
            ( nurl_eprint path )
            ( nurl_eprint `: read failed\n` )
            ^ 0
        }
    }
}

// ── Recursive directory walk ───────────────────────────────────────
//
// Treats `path` as a directory: lists entries, skips dotfiles, and
// for each non-dotfile entry computes the child path and recurses
// via `walk` so a nested directory descends correctly. Returns the
// total number of hits printed under this subtree. If `dir_list`
// errors out (the path is a regular file, missing, or otherwise
// inaccessible), returns -1 so the caller can fall back to the file
// path.

@ walk_dir s path ( @ b s ) test → i {
    : !( Vec String ) IoErr r ( dir_list path )
    ?? r {
        T entries → {
            : i n ( vec_len [String] entries )
            : ~ i hits 0
            : ~ i k 0
            ~ < k n {
                : ?String e ( vec_get [String] entries k )
                ?? e {
                    T se → {
                        : s name ( string_data se )
                        // Skip "." / ".." and dotfiles
                        ? == 46 & # i . # *u name 0 255 {} {
                            : String sub ( string_from path )
                            ( string_push_str sub `/` )
                            ( string_push_str sub name )
                            = hits + hits ( walk ( string_data sub ) test )
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
            ^ hits
        }
        F err → ^ -1
    }
}

// Dispatch: try directory walk first; if that errors out (it's not a
// directory), treat `path` as a regular file.

@ walk s path ( @ b s ) test → i {
    : i d ( walk_dir path test )
    ? >= d 0 ^ d {}
    ^ ( scan_file path test )
}

// ── stdin path ─────────────────────────────────────────────────────

@ scan_stdin ( @ b s ) test → i {
    : ~ i hits 0
    : ~ i lineno 1
    ~ T {
        : s line ( nurl_read_line )
        ? == 0 # i line { = lineno -1 } {}
        ? < lineno 0 {} {
            ? ( test line ) {
                ( nurl_print `<stdin>:` )
                ( nurl_print ( nurl_str_int lineno ) )
                ( nurl_print `:` )
                ( nurl_print line )
                ( nurl_print `\n` )
                = hits + hits 1
            } {}
            = lineno + lineno 1
        }
        ? < lineno 0 { ^ hits } {}
    }
    ^ hits
}

// ── Pattern matchers (closure-shaped so scan_lines is mode-agnostic) ─

@ make_literal_test s needle → ( @ b s ) {
    ^ \ s line → b { ^ >= ( nurl_str_find line needle ) 0 }
}

@ make_list_test ( Vec String ) needles → ( @ b s ) {
    ^ \ s line → b {
        : i n ( vec_len [String] needles )
        : ~ i k 0
        ~ < k n {
            : ?String e ( vec_get [String] needles k )
            ?? e {
                T se → {
                    ? >= ( nurl_str_find line ( string_data se ) ) 0 { ^ T } {}
                }
                F → {}
            }
            = k + k 1
        }
        ^ F
    }
}

@ make_regex_test Regex rx → ( @ b s ) {
    ^ \ s line → b { ^ ( regex_test rx line ) }
}

// ── CLI parsing helpers ────────────────────────────────────────────

@ split_csv s pats → ( Vec String ) {
    : String holder ( string_from pats )
    : ( Vec String ) parts ( string_split holder `,` )
    ( string_free holder )
    ^ parts
}

@ usage → v {
    ( nurl_eprint `Usage: find_clone [--list PAT[,PAT...] | --regex PAT | PATTERN] [PATH ...]\n` )
    ( nurl_eprint `Reads stdin when no PATH is given.\n` )
}

// Drive a matcher closure over either stdin (no path args) or every
// PATH on argv starting at `first_path`. Returns the total match count.
@ run_with ( @ b s ) test i first_path i argc → i {
    ? <= argc first_path { ^ ( scan_stdin test ) } {}
    : ~ i total 0
    : ~ i i first_path
    ~ < i argc {
        = total + total ( walk ( nurl_argv_get i ) test )
        = i + i 1
    }
    ^ total
}

@ exit_for_hits i hits → i { ^ ? > hits 0 0 1 }

@ main → i {
    : i argc ( nurl_argv_count )
    ? < argc 2 { ( usage ) ^ 2 } {}

    : s flag ( nurl_argv_get 1 )

    // --regex PATTERN [PATH...]
    ? == ( nurl_str_eq flag `--regex` ) 1 {
        ? < argc 3 { ( usage ) ^ 2 } {}
        : !Regex ParseErr c ( regex_compile ( nurl_argv_get 2 ) )
        ?? c {
            T r → {
                : i hits ( run_with ( make_regex_test r ) 3 argc )
                ( regex_free r )
                ^ ( exit_for_hits hits )
            }
            F e → {
                ( nurl_eprint `find_clone: regex_compile failed\n` )
                ^ 2
            }
        }
    } {}

    // --list PAT,PAT,... [PATH...]
    ? == ( nurl_str_eq flag `--list` ) 1 {
        ? < argc 3 { ( usage ) ^ 2 } {}
        : ( Vec String ) pats ( split_csv ( nurl_argv_get 2 ) )
        ^ ( exit_for_hits ( run_with ( make_list_test pats ) 3 argc ) )
    } {}

    // Default: literal substring. `flag` IS the pattern.
    ^ ( exit_for_hits ( run_with ( make_literal_test flag ) 2 argc ) )
}
