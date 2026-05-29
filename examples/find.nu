// find.nu — a cross-platform search tool for humans *and* LLMs
//
// `find` takes a starting PATH and one or more search terms, then walks
// the path (recursing into directories) and reports every line that
// matches any of the terms. Output is line-oriented and stable, so it
// reads cleanly in a terminal and parses cleanly when piped into a
// language model.
//
// Works the same on Linux and Windows: paths may use `/` or `\`, and
// drive-letter roots like `c:\tools` are fine. The recursion preserves
// whichever separator the input path uses, so reported paths look
// native on either OS.
//
// Demonstrates:
//   - CLI flag + positional parsing (nurl_argv_*)
//   - File I/O via stdlib/std/fs.nu (read_file + dir_list + IoErr)
//   - Recursive directory walk with OS-agnostic path joins
//   - Multi-pattern matching: literal substrings OR regex
//     (stdlib/ext/regex.nu), reported with the match column
//   - Optional context lines (previous / next)
//
// Usage:
//   find [OPTIONS] PATH TERM [TERM ...]
//
// Options:
//   -e, --regex     treat every TERM as a POSIX-extended regex
//                   (default: literal substring)
//   -C, --context   also print the line before and after each match
//   -h, --help      show this help
//
// A line matches if ANY term matches it. The reported column is the
// 1-based offset of the leftmost matching term on that line.
//
// Output (one match):
//   PATH:LINE:COL: full line text
//
// With --context, the surrounding lines use a `-` separator (grep
// style), so matches stay visually distinct from context:
//   PATH-LINE- previous line
//   PATH:LINE:COL: matched line
//   PATH-LINE- next line
//
// Matches from different files are separated by one blank line.
//
// Exit codes:
//   0  at least one match was printed
//   1  no matches found
//   2  usage / argument error
//
// Build & run:
//   ./nurl.sh examples/find.nu find
//   ./find /etc hosts localhost
//   ./find -e '[0-9]{1,3}\.[0-9]{1,3}' /etc/hosts
//   ./find -C examples error panic            # literal, with context
//   ./find c:\tools TODO FIXME                # Windows path + 2 terms

$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/regex.nu`

// ── Output helpers ──────────────────────────────────────────────────

// Both builders assemble the whole line in one String and emit it with
// a single nurl_print, so the int fields use the leak-free
// string_push_int rather than the malloc-per-call nurl_str_int.

@ print_match s path i lineno i col s line → v {
    : String out ( string_from path )
    ( string_push_char out 58 ) ( string_push_int out lineno )
    ( string_push_char out 58 ) ( string_push_int out col )
    ( string_push_str out `: ` ) ( string_push_str out line )
    ( string_push_char out 10 )
    ( nurl_print ( string_data out ) )
    ( string_free out )
}

@ print_ctx s path i lineno s line → v {
    : String out ( string_from path )
    ( string_push_char out 45 ) ( string_push_int out lineno )
    ( string_push_str out `- ` ) ( string_push_str out line )
    ( string_push_char out 10 )
    ( nurl_print ( string_data out ) )
    ( string_free out )
}

// ── Matchers (closure-shaped so the scanner is mode-agnostic) ────────
//
// A matcher maps a line to the 0-based byte column of the leftmost
// match (across all terms), or -1 when the line doesn't match. The
// scanner adds 1 for a human/grep-style column in the output.

@ make_literal_matcher ( Vec String ) needles → ( @ i s ) {
    ^ \ s line → i {
        : ~ i best -1
        : i n ( vec_len [String] needles )
        : ~ i k 0
        ~ < k n {
            : ?String e ( vec_get [String] needles k )
            ?? e {
                T se → {
                    : i f ( nurl_str_find line ( string_data se ) )
                    ? >= f 0 { ? | < best 0 < f best { = best f } {} } {}
                }
                F → {}
            }
            = k + k 1
        }
        ^ best
    }
}

@ make_regex_matcher ( Vec Regex ) rxs → ( @ i s ) {
    ^ \ s line → i {
        : ~ i best -1
        : i n ( vec_len [Regex] rxs )
        : ~ i k 0
        ~ < k n {
            : ?Regex e ( vec_get [Regex] rxs k )
            ?? e {
                T rx → {
                    : ?Match m ( regex_find rx line )
                    ?? m {
                        T mm → { : i f . mm start ? | < best 0 < f best { = best f } {} }
                        F → {}
                    }
                }
                F → {}
            }
            = k + k 1
        }
        ^ best
    }
}

// ── Path utilities (OS-agnostic) ────────────────────────────────────

// First byte of a NUL-terminated string as an int (0 on empty).
@ find_first_byte s name → i { ^ & # i . # *u name 0 255 }

// Skip "." / ".." and dotfiles — the first byte is '.' (46).
@ find_is_dot s name → b { ^ == 46 ( find_first_byte name ) }

// Join `name` onto `parent`, stripping any trailing separator and
// reusing whichever separator the parent already uses. Backslash wins
// only when the parent actually contains one; otherwise we default to
// '/', which every Windows file API also accepts.
@ join_path s parent s name → String {
    : String out ( string_from parent )
    : i pl ( nurl_str_len parent )
    ? > pl 0 {
        : i lastc & # i . # *u parent - pl 1 255
        ? | == lastc 47 == lastc 92 {
            : String t ( string_substr out 0 - pl 1 )
            ( string_free out ) = out t
        } {}
    } {}
    : s sep ? >= ( nurl_str_find parent `\\` ) 0 `\\` `/`
    ( string_push_str out sep )
    ( string_push_str out name )
    ^ out
}

// ── Scanning one file ───────────────────────────────────────────────
//
// `flag` is a 1-element Vec used as a shared mutable cell: flag[0] is 1
// once any file has printed at least one match. We consult it to emit
// the single blank-line separator before each *subsequent* matching
// file.

@ scan_file s path ( @ i s ) matcher b context ( Vec i ) flag → i {
    : !String IoErr r ( read_file path )
    ?? r {
        T content → {
            : ( Vec String ) lines ( string_split content `\n` )
            : i total ( vec_len [String] lines )
            // A trailing newline yields a phantom empty final element;
            // drop it so line numbers line up with editors.
            : ~ i nlines total
            ? > total 0 {
                : ?String last ( vec_get [String] lines - total 1 )
                ?? last { T ls → { ? == ( nurl_str_len ( string_data ls ) ) 0 { = nlines - total 1 } {} } F → {} }
            } {}
            : ~ i hits 0
            : ~ i i 0
            ~ < i nlines {
                : ?String le ( vec_get [String] lines i )
                ?? le {
                    T lse → {
                        : s line ( string_data lse )
                        : i col ( matcher line )
                        ? >= col 0 {
                            ? == hits 0 {
                                : ?i fp ( vec_get [i] flag 0 )
                                ?? fp { T fv → { ? > fv 0 { ( nurl_print `\n` ) } {} } F → {} }
                            } {}
                            : i lineno + i 1
                            ? & context > i 0 {
                                : ?String pe ( vec_get [String] lines - i 1 )
                                ?? pe { T ps → { ( print_ctx path - lineno 1 ( string_data ps ) ) } F → {} }
                            } {}
                            ( print_match path lineno + col 1 line )
                            ? & context < + i 1 nlines {
                                : ?String ne ( vec_get [String] lines + i 1 )
                                ?? ne { T ns → { ( print_ctx path + lineno 1 ( string_data ns ) ) } F → {} }
                            } {}
                            = hits + hits 1
                            ( vec_set [i] flag 0 1 )
                        } {}
                    }
                    F → {}
                }
                = i + i 1
            }
            ( vec_free_with [String] lines \ String s → v { ( string_free s ) } )
            ( string_free content )
            ^ hits
        }
        F err → {
            ( nurl_eprint `find: ` ) ( nurl_eprint path ) ( nurl_eprint `: read failed\n` )
            ^ 0
        }
    }
}

// ── Recursive directory walk ────────────────────────────────────────
//
// Returns the hit count for this subtree, or -1 from walk_dir when the
// path is not a directory so `walk` can fall back to treating it as a
// regular file.

@ walk_dir s path ( @ i s ) matcher b context ( Vec i ) flag → i {
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
                        ? ( find_is_dot name ) {} {
                            : String sub ( join_path path name )
                            = hits + hits ( walk ( string_data sub ) matcher context flag )
                            ( string_free sub )
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] entries \ String s → v { ( string_free s ) } )
            ^ hits
        }
        F err → ^ -1
    }
}

@ walk s path ( @ i s ) matcher b context ( Vec i ) flag → i {
    : i d ( walk_dir path matcher context flag )
    ? >= d 0 ^ d {}
    ^ ( scan_file path matcher context flag )
}

// ── CLI ─────────────────────────────────────────────────────────────

@ usage → v {
    ( nurl_eprint `Usage: find [OPTIONS] PATH TERM [TERM ...]\n` )
    ( nurl_eprint `  -e, --regex     treat each TERM as a regex\n` )
    ( nurl_eprint `  -C, --context   print the line before and after each match\n` )
    ( nurl_eprint `  -h, --help      show this help\n` )
}

@ is_flag s a → b { ^ == 45 ( find_first_byte a ) }

@ main → i {
    : i argc ( nurl_argv_count )
    ? < argc 2 { ( usage ) ^ 2 } {}

    : ~ i ai 1
    : ~ b use_regex F
    : ~ b context F
    : ~ b bad F
    ~ & < ai argc ( is_flag ( nurl_argv_get ai ) ) {
        : s f ( nurl_argv_get ai )
        ? | == ( nurl_str_eq f `--regex` ) 1 == ( nurl_str_eq f `-e` ) 1 { = use_regex T } {
        ? | == ( nurl_str_eq f `--context` ) 1 == ( nurl_str_eq f `-C` ) 1 { = context T } {
        ? | == ( nurl_str_eq f `--help` ) 1 == ( nurl_str_eq f `-h` ) 1 { ( usage ) ^ 0 } {
            ( nurl_eprint `find: unknown option\n` ) = bad T
        }}}
        = ai + ai 1
    }
    ? bad { ( usage ) ^ 2 } {}

    // Need a PATH plus at least one TERM.
    ? < - argc ai 2 { ( usage ) ^ 2 } {}

    : s path ( nurl_argv_get ai )
    : i pat_start + ai 1

    : ( Vec i ) flag ( vec_new [i] ) ( vec_push [i] flag 0 )

    : ~ i hits 0
    ? use_regex {
        : ( Vec Regex ) rxs ( vec_new [Regex] )
        : ~ b ok T
        : ~ i pi pat_start
        ~ & < pi argc ok {
            : !Regex ParseErr c ( regex_compile ( nurl_argv_get pi ) )
            ?? c {
                T rx → { ( vec_push [Regex] rxs rx ) }
                F e → { ( nurl_eprint `find: invalid regex: ` ) ( nurl_eprint ( nurl_argv_get pi ) ) ( nurl_eprint `\n` ) = ok F }
            }
            = pi + pi 1
        }
        ? ok { = hits ( walk path ( make_regex_matcher rxs ) context flag ) } {}
        ( vec_free_with [Regex] rxs \ Regex r → v { ( regex_free r ) } )
        ? ok {} { ( vec_free [i] flag ) ^ 2 }
    } {
        : ( Vec String ) needles ( vec_new [String] )
        : ~ i pi pat_start
        ~ < pi argc {
            ( vec_push [String] needles ( string_from ( nurl_argv_get pi ) ) )
            = pi + pi 1
        }
        = hits ( walk path ( make_literal_matcher needles ) context flag )
        ( vec_free_with [String] needles \ String s → v { ( string_free s ) } )
    }
    ( vec_free [i] flag )
    ^ ? > hits 0 0 1
}
