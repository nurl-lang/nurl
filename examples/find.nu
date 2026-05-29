// find.nu — a cross-platform search tool for humans *and* LLMs
//
// `find` searches files for one or more terms and reports every line
// that matches any of them. Terms are positional; the path is given
// with -p and defaults to the current directory. Output is
// line-oriented and stable, so it reads cleanly in a terminal and
// parses cleanly when piped into a language model.
//
// Works the same on Linux and Windows: paths may use `/` or `\`,
// drive-letter roots like `c:\tools` are fine, and ANSI colour is
// enabled on Windows 10+ consoles (nurl_enable_vt) as well as on
// POSIX terminals.
//
// Demonstrates:
//   - CLI flag + positional parsing (nurl_argv_*)
//   - File I/O via stdlib/std/fs.nu (read_file + dir_list + path type)
//   - Optional recursive directory walk with OS-agnostic path joins
//   - Multi-pattern matching: literal substrings OR regex, with the
//     match span (column + length) reported and highlighted
//   - Case-insensitive matching by default (literal mode)
//   - TTY-aware ANSI colour (stdlib/runtime: isatty + enable_vt)
//
// Usage:
//   find [OPTIONS] TERM [TERM ...]
//
// Options:
//   -p, --path PATH      where to search (default: current directory)
//   -r, --recursive      descend into sub-directories
//   -e, --regex          treat each TERM as a POSIX-extended regex
//                        (regex matching is always case-sensitive)
//   -s, --strict         case-sensitive literal matching
//                        (default: case-insensitive)
//   -C, --context        also print the line before and after a match
//       --color=WHEN     auto (default) | always | never
//   -h, --help           show this help
//
// A line matches when ANY term matches it. The reported column is the
// 1-based offset of the leftmost matching term on that line.
//
// Output (one match):
//   PATH:LINE:COL: full line text
//
// With --context the surrounding lines use a `-` separator (grep
// style) so matches stay visually distinct:
//   PATH-LINE- previous line
//   PATH:LINE:COL: matched line
//   PATH-LINE- next line
//
// In colour mode the PATH:LINE:COL location is cyan and the matched
// substring is bold red. Matches from different files are separated by
// one blank line.
//
// Exit codes:
//   0  at least one match was printed
//   1  no matches found
//   2  usage / argument error
//
// Build & run:
//   ./nurl.sh examples/find.nu find
//   ./find error warn                      # CI literal, current dir
//   ./find -r -p /etc hosts localhost      # recurse under /etc
//   ./find -s -p src TODO                  # case-sensitive
//   ./find -e -p . '[0-9]+\.[0-9]+'        # regex
//   ./find --color=always error > out.txt  # keep colour when redirected

$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/regex.nu`

// Terminal helpers added to stdlib/runtime.c: report whether stdout is
// a real terminal, and (Windows only) turn on ANSI escape processing.
& `c` @ nurl_stdout_isatty → i

& `c` @ nurl_enable_vt → v

// ── ANSI colour ─────────────────────────────────────────────────────
//
// We never bake raw ESC bytes into source literals; push_ansi writes
// ESC '[' <code> 'm' so the codes stay readable.

@ push_ansi String out s code → v {
    ( string_push_char out 27 ) ( string_push_char out 91 )
    ( string_push_str out code ) ( string_push_char out 109 )
}

// ── Output helpers ──────────────────────────────────────────────────
//
// Each builder assembles the whole line in one String and emits it with
// a single nurl_print: the int fields use the leak-free string_push_int
// (not the malloc-per-call nurl_str_int), and colour is applied inline.

@ print_match b color s path i lineno i col i mlen s line → v {
    : String out ( string_new )
    ? color { ( push_ansi out `36` ) } {}
    ( string_push_str out path ) ( string_push_char out 58 )
    ( string_push_int out lineno ) ( string_push_char out 58 )
    ( string_push_int out col )
    ? color { ( push_ansi out `0` ) } {}
    ( string_push_str out `: ` )
    : i ln ( nurl_str_len line )
    ? color {
        : i s0 - col 1
        : i e0 + s0 mlen
        : ~ b open F
        : ~ i i 0
        ~ < i ln {
            ? == i s0 { ( push_ansi out `1;31` ) = open T } {}
            ? & open == i e0 { ( push_ansi out `0` ) = open F } {}
            ( string_push_char out ( nurl_str_get line i ) )
            = i + i 1
        }
        ? open { ( push_ansi out `0` ) } {}
    } { ( string_push_str out line ) }
    ( string_push_char out 10 )
    ( nurl_print ( string_data out ) )
    ( string_free out )
}

@ print_ctx b color s path i lineno s line → v {
    : String out ( string_new )
    ? color { ( push_ansi out `36` ) } {}
    ( string_push_str out path ) ( string_push_char out 45 ) ( string_push_int out lineno )
    ? color { ( push_ansi out `0` ) } {}
    ( string_push_str out `- ` ) ( string_push_str out line )
    ( string_push_char out 10 )
    ( nurl_print ( string_data out ) )
    ( string_free out )
}

// ── Matchers (closure-shaped so the scanner is mode-agnostic) ────────
//
// A matcher maps a line to a packed match span: the 0-based start in
// the high 32 bits, the match length in the low 32 bits, or -1 when the
// line doesn't match. Packing keeps the closure type a plain `( @ i s )`
// while still carrying enough to highlight the exact substring.

@ pack_span i start i len → i { ^ + * start 4294967296 len }

@ span_start i packed → i { ^ / packed 4294967296 }

@ span_len i packed → i { ^ & packed 4294967295 }

// Literal matcher. `needles` are already lower-cased by the caller when
// `ci` is set; we then lower-case each line before searching so the
// match is case-insensitive. ASCII lower-casing preserves byte offsets,
// so the column found in the lowered copy is valid in the original.
@ make_literal_matcher ( Vec String ) needles b ci → ( @ i s ) {
    ^ \ s line → i {
        : ~ String hay ( string_from line )
        ? ci { : String low ( string_to_lower hay ) ( string_free hay ) = hay low } {}
        : s h ( string_data hay )
        : ~ i best -1
        : ~ i blen 0
        : i n ( vec_len [String] needles )
        : ~ i k 0
        ~ < k n {
            : ?String e ( vec_get [String] needles k )
            ?? e {
                T se → {
                    : s nd ( string_data se )
                    : i f ( nurl_str_find h nd )
                    ? >= f 0 { ? | < best 0 < f best { = best f = blen ( nurl_str_len nd ) } {} } {}
                }
                F → {}
            }
            = k + k 1
        }
        ( string_free hay )
        ^ ? < best 0 -1 ( pack_span best blen )
    }
}

@ make_regex_matcher ( Vec Regex ) rxs → ( @ i s ) {
    ^ \ s line → i {
        : ~ i best -1
        : ~ i blen 0
        : i n ( vec_len [Regex] rxs )
        : ~ i k 0
        ~ < k n {
            : ?Regex e ( vec_get [Regex] rxs k )
            ?? e {
                T rx → {
                    : ?Match m ( regex_find rx line )
                    ?? m {
                        T mm → { : i f . mm start : i ml . mm len ? | < best 0 < f best { = best f = blen ml } {} }
                        F → {}
                    }
                }
                F → {}
            }
            = k + k 1
        }
        ^ ? < best 0 -1 ( pack_span best blen )
    }
}

// ── Path utilities (OS-agnostic) ────────────────────────────────────

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
// once any file has printed at least one match, so we can emit the
// single blank-line separator before each subsequent matching file.

@ scan_file s path ( @ i s ) matcher b context b color ( Vec i ) flag → i {
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
                        : i packed ( matcher line )
                        ? >= packed 0 {
                            ? == hits 0 {
                                : ?i fp ( vec_get [i] flag 0 )
                                ?? fp { T fv → { ? > fv 0 { ( nurl_print `\n` ) } {} } F → {} }
                            } {}
                            : i lineno + i 1
                            : i col + ( span_start packed ) 1
                            : i mlen ( span_len packed )
                            ? & context > i 0 {
                                : ?String pe ( vec_get [String] lines - i 1 )
                                ?? pe { T ps → { ( print_ctx color path - lineno 1 ( string_data ps ) ) } F → {} }
                            } {}
                            ( print_match color path lineno col mlen line )
                            ? & context < + i 1 nlines {
                                : ?String ne ( vec_get [String] lines + i 1 )
                                ?? ne { T ns → { ( print_ctx color path + lineno 1 ( string_data ns ) ) } F → {} }
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

// ── Directory walk ──────────────────────────────────────────────────
//
// Lists `path`, scans each regular file, and descends into sub-dirs
// only when `recursive` is set. nurl_path_type: 0 missing, 1 file,
// 2 dir, 3 symlink, 4 other.

@ walk_dir s path ( @ i s ) matcher b context b recursive b color ( Vec i ) flag → i {
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
                            : i st ( nurl_path_type ( string_data sub ) )
                            ? == st 2 {
                                ? recursive { = hits + hits ( walk_dir ( string_data sub ) matcher context recursive color flag ) } {}
                            } {
                                = hits + hits ( scan_file ( string_data sub ) matcher context color flag )
                            }
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
        F err → ^ 0
    }
}

// Entry point for one search root: a directory is walked, anything else
// is treated as a single file.
@ walk s path ( @ i s ) matcher b context b recursive b color ( Vec i ) flag → i {
    ? == ( nurl_path_type path ) 2 {
        ^ ( walk_dir path matcher context recursive color flag )
    } {}
    ^ ( scan_file path matcher context color flag )
}

// ── CLI ─────────────────────────────────────────────────────────────

@ usage → v {
    ( nurl_eprint `Usage: find [OPTIONS] TERM [TERM ...]\n` )
    ( nurl_eprint `  -p, --path PATH   where to search (default: .)\n` )
    ( nurl_eprint `  -r, --recursive   descend into sub-directories\n` )
    ( nurl_eprint `  -e, --regex       treat each TERM as a regex (case-sensitive)\n` )
    ( nurl_eprint `  -s, --strict      case-sensitive literal match (default: insensitive)\n` )
    ( nurl_eprint `  -C, --context     print the line before and after each match\n` )
    ( nurl_eprint `      --color=WHEN  auto (default) | always | never\n` )
    ( nurl_eprint `  -h, --help        show this help\n` )
}

@ seq s a s b → b { ^ == ( nurl_str_eq a b ) 1 }

@ is_flag s a → b { ^ == 45 ( find_first_byte a ) }

@ main → i {
    : i argc ( nurl_argv_count )

    : ( Vec String ) terms ( vec_new [String] )
    : ~ String path ( string_from `.` )
    : ~ b use_regex F
    : ~ b strict F
    : ~ b recursive F
    : ~ b context F
    : ~ i color_mode 0  // 0 = auto, 1 = always, 2 = never
    : ~ b bad F
    : ~ b show_help F

    : ~ i ai 1
    ~ < ai argc {
        : s a ( nurl_argv_get ai )
        ? ( is_flag a ) {
            ? | ( seq a `-e` ) ( seq a `--regex` ) { = use_regex T } {
                ? | ( seq a `-s` ) ( seq a `--strict` ) { = strict T } {
                    ? | ( seq a `-r` ) ( seq a `--recursive` ) { = recursive T } {
                        ? | ( seq a `-C` ) ( seq a `--context` ) { = context T } {
                            ? | ( seq a `-h` ) ( seq a `--help` ) { = show_help T } {
                                ? | ( seq a `-p` ) ( seq a `--path` ) {
                                    = ai + ai 1
                                    ? < ai argc { ( string_free path ) = path ( string_from ( nurl_argv_get ai ) ) }
                                    { ( nurl_eprint `find: -p requires an argument\n` ) = bad T }
                                } {
                                    ? ( string_starts_with ( string_from a ) `--color=` ) {
                                        : String ca ( string_from a )
                                        : String cv ( string_substr ca 8 - ( string_len ca ) 8 )
                                        : s v ( string_data cv )
                                        ? ( seq v `always` ) { = color_mode 1 } {
                                            ? ( seq v `never` ) { = color_mode 2 } {
                                                ? ( seq v `auto` ) { = color_mode 0 } {
                                                    ( nurl_eprint `find: --color must be auto, always, or never\n` ) = bad T } } }
                                        ( string_free ca ) ( string_free cv )
                                    } {
                                        ( nurl_eprint `find: unknown option: ` ) ( nurl_eprint a ) ( nurl_eprint `\n` ) = bad T
                                    } } } } } } }
        } {
            ( vec_push [String] terms ( string_from a ) )
        }
        = ai + ai 1
    }

    ? show_help { ( usage ) ( vec_free_with [String] terms \ String s → v { ( string_free s ) } ) ( string_free path ) ^ 0 } {}
    ? bad { ( usage ) ( vec_free_with [String] terms \ String s → v { ( string_free s ) } ) ( string_free path ) ^ 2 } {}
    ? == ( vec_len [String] terms ) 0 {
        ( nurl_eprint `find: no search terms given\n` ) ( usage )
        ( vec_free_with [String] terms \ String s → v { ( string_free s ) } ) ( string_free path ) ^ 2
    } {}

    : ~ b use_color F
    ? == color_mode 1 { = use_color T } {
        ? == color_mode 2 { = use_color F } {
            = use_color == ( nurl_stdout_isatty ) 1 } }
    ? use_color { ( nurl_enable_vt ) } {}

    : ( Vec i ) flag ( vec_new [i] ) ( vec_push [i] flag 0 )
    : i nterms ( vec_len [String] terms )

    : ~ i hits 0
    : ~ i rc 0
    ? use_regex {
        : ( Vec Regex ) rxs ( vec_new [Regex] )
        : ~ b ok T
        : ~ i ti 0
        ~ & < ti nterms ok {
            : ?String te ( vec_get [String] terms ti )
            ?? te {
                T ts → {
                    : !Regex ParseErr c ( regex_compile ( string_data ts ) )
                    ?? c {
                        T rx → { ( vec_push [Regex] rxs rx ) }
                        F e → { ( nurl_eprint `find: invalid regex: ` ) ( nurl_eprint ( string_data ts ) ) ( nurl_eprint `\n` ) = ok F }
                    }
                }
                F → {}
            }
            = ti + ti 1
        }
        ? ok { = hits ( walk ( string_data path ) ( make_regex_matcher rxs ) context recursive use_color flag ) }
        { = rc 2 }
        ( vec_free_with [Regex] rxs \ Regex r → v { ( regex_free r ) } )
    } {
        : b ci ? strict F T
        : ( Vec String ) needles ( vec_new [String] )
        : ~ i ti 0
        ~ < ti nterms {
            : ?String te ( vec_get [String] terms ti )
            ?? te {
                T ts → {
                    ? ci { ( vec_push [String] needles ( string_to_lower ts ) ) }
                    { ( vec_push [String] needles ( string_from ( string_data ts ) ) ) }
                }
                F → {}
            }
            = ti + ti 1
        }
        = hits ( walk ( string_data path ) ( make_literal_matcher needles ci ) context recursive use_color flag )
        ( vec_free_with [String] needles \ String s → v { ( string_free s ) } )
    }

    ( vec_free [i] flag )
    ( vec_free_with [String] terms \ String s → v { ( string_free s ) } )
    ( string_free path )
    ? > rc 0 { ^ rc } {}
    ^ ? > hits 0 0 1
}
