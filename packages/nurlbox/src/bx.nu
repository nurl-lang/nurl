// nurlbox/bx.nu — the plumbing every applet shares.
//
// busybox's own glue is three things: a diagnostic prefix that names
// the applet rather than the binary, one option scanner (`getopt32`)
// that every applet drives from a short spec string, and a handful of
// byte-level output helpers. This file is that, in NURL.
//
// Option scanning follows busybox's model deliberately:
//
//     : BxOpts o ( bx_getopt argv 1 `ln:` `number=n,lines=n` )
//     ? ( bx_has o `l` ) { ... } {}
//     : s v ( bx_val o `n` )          // `` when the option was absent
//     : ( Vec String ) rest ( bx_operands o )
//
// The spec is a run of option letters; a letter followed by `:` takes a
// value. `longs` maps long names onto those letters, `name=letter`
// comma-separated, so `--lines 5` and `-n5` land in the same slot.
// Clustered shorts (`-la`), an attached value (`-n5`), a detached value
// (`-n 5`), `--name=value`, `--` and a bare `-` (an operand, by
// universal convention stdin) all behave as POSIX describes.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bufio.nu`

// The name diagnostics carry. Set once by the dispatcher, so every
// message reads `rm: cannot remove 'x'` and not `nurlbox: ...`.
: ~ s g_bx_name `nurlbox`

@ bx_name → s { ^ g_bx_name }

@ bx_set_name s n → v { = g_bx_name n }

// ── Diagnostics ───────────────────────────────────────────────────

@ bx_err s msg → v {
    ( nurl_eprint g_bx_name )
    ( nurl_eprint `: ` )
    ( nurl_eprint msg )
    ( nurl_eprint `\n` )
}

// `applet: subject: msg` — the shape every coreutils error takes.
@ bx_err_at s subject s msg → v {
    ( nurl_eprint g_bx_name )
    ( nurl_eprint `: ` )
    ( nurl_eprint subject )
    ( nurl_eprint `: ` )
    ( nurl_eprint msg )
    ( nurl_eprint `\n` )
}

// ── Output ────────────────────────────────────────────────────────

// Write a String's bytes verbatim — NULs and all — through stdout's
// ordinary buffer, so it never reorders against `nurl_print`.
@ bx_write String buf → v {
    : i n ( string_len buf )
    ? > n 0 { ( nurl_print_bytes ( string_data buf ) n ) } {}
}

@ bx_write_bytes ( Vec u ) buf → v {
    : i n ( vec_len [u] buf )
    ? > n 0 { ( nurl_print_bytes # s ( vec_data [u] buf ) n ) } {}
}

// ── Small string helpers ──────────────────────────────────────────

@ bx_streq s a s b → b { ^ != 0 ( nurl_str_eq a b ) }

// Borrowed view of argv[idx]; the empty string past the end. Callers
// treat it as read-only — the Vec still owns the bytes.
@ bx_at ( Vec String ) v i idx → s {
    ? | < idx 0 >= idx ( vec_len [String] v ) { ^ `` } {}
    ?? ( vec_get [String] v idx ) {
        T x → { ^ ( string_data x ) }
        F _ → { ^ `` }
    }
}

// ── Option scanning ───────────────────────────────────────────────

: BxOpts {
    s spec
    i flags  // bit k set = the k-th option letter of `spec` was given
    ( Vec String ) vals  // one slot per option letter, `` when unset
    ( Vec String ) allvals  // every value-bearing occurrence, in order
    ( Vec i ) allords  // the option ordinal each `allvals` entry belongs to
    ( Vec String ) args  // the operands, in order
    b ok
}

// Ordinal of `letter` among the option letters of `spec`, or -1.
@ __bx_ord s spec i lc → i {
    : i n ( nurl_str_len spec )
    : ~ i i 0
    : ~ i k 0
    : ~ i found -1
    ~ < i n {
        : i c ( nurl_str_get spec i )
        ? != c 58 {
            ? & < found 0 == c lc { = found k } {}
            = k + k 1
        } {}
        = i + i 1
    }
    ^ found
}

@ __bx_letters s spec → i {
    : i n ( nurl_str_len spec )
    : ~ i i 0
    : ~ i k 0
    ~ < i n {
        ? != ( nurl_str_get spec i ) 58 { = k + k 1 } {}
        = i + i 1
    }
    ^ k
}

// Does the ordinal-`ord` option letter take a value?
@ __bx_takes_val s spec i ord → b {
    : i n ( nurl_str_len spec )
    : ~ i i 0
    : ~ i k 0
    : ~ b ans F
    ~ < i n {
        : i c ( nurl_str_get spec i )
        ? != c 58 {
            ? == k ord {
                ? < + i 1 n { ? == ( nurl_str_get spec + i 1 ) 58 { = ans T } {} } {}
            } {}
            = k + k 1
        } {}
        = i + i 1
    }
    ^ ans
}

// Resolve a long option name against the `name=letter,…` table.
// Returns the letter's character code, or -1 when unknown.
@ __bx_long_letter s longs s name → i {
    : i ln ( nurl_str_len longs )
    : i nn ( nurl_str_len name )
    : ~ i i 0
    : ~ i ans -1
    ~ < i ln {
        // one entry: up to the next ','
        : ~ i e i
        ~ & < e ln != ( nurl_str_get longs e ) 44 { = e + e 1 }
        // split it at '='
        : ~ i eq i
        ~ & < eq e != ( nurl_str_get longs eq ) 61 { = eq + eq 1 }
        ? & < ans 0 == - eq i nn {
            : ~ b same T
            : ~ i k 0
            ~ < k nn {
                ? != ( nurl_str_get longs + i k ) ( nurl_str_get name k ) { = same F } {}
                = k + k 1
            }
            ? & same < + eq 1 e { = ans ( nurl_str_get longs + eq 1 ) } {}
        } {}
        = i + e 1
    }
    ^ ans
}

// The last value wins for `bx_val`, and EVERY value is kept for
// `bx_vals` — `grep -e a -e b` and `tar -f x -f y` mean different things
// and a scanner that only remembered the last could not tell them apart.
@ __bx_set_val ( Vec String ) vals ( Vec String ) allvals ( Vec i ) allords i ord s value → v {
    ?? ( vec_get [String] vals ord ) {
        T slot → { ( string_clear slot ) ( string_push_str slot value ) }
        F _ → {}
    }
    ( vec_push [String] allvals ( string_from value ) )
    ( vec_push [i] allords ord )
}

// Scan `argv` from `start`. See the file header for the spec grammar.
@ bx_getopt ( Vec String ) argv i start s spec s longs → BxOpts {
    : i nletters ( __bx_letters spec )
    : ( Vec String ) vals ( vec_new [String] )
    : ~ i j 0
    ~ < j nletters {
        ( vec_push [String] vals ( string_new ) )
        = j + j 1
    }
    : ( Vec String ) allvals ( vec_new [String] )
    : ( Vec i ) allords ( vec_new [i] )
    : ( Vec String ) args ( vec_new [String] )
    : ~ i flags 0
    : ~ b ok T
    : ~ b endopts F
    : i n ( vec_len [String] argv )
    : ~ i i start
    ~ < i n {
        : s tok ( bx_at argv i )
        : i tl ( nurl_str_len tok )
        // `-2` and `-.5` are operands, not options, for a tool whose
        // spec has no digit letters — `seq 10 -2 2` counts down, it does
        // not ask for an option named `2`.
        : b numeric & & > tl 1 == ( nurl_str_get tok 0 ) 45
        & | ( bx_is_digit ( nurl_str_get tok 1 ) ) == ( nurl_str_get tok 1 ) 46
        < ( __bx_ord spec ( nurl_str_get tok 1 ) ) 0
        ? | endopts | numeric | < tl 2 != ( nurl_str_get tok 0 ) 45 {
            ( vec_push [String] args ( string_from tok ) )
        } {
            ? & == ( nurl_str_get tok 1 ) 45 == tl 2 {
                = endopts T
            } {
                ? == ( nurl_str_get tok 1 ) 45 {
                    // --name  or  --name=value
                    : ~ i eq 2
                    ~ & < eq tl != ( nurl_str_get tok eq ) 61 { = eq + eq 1 }
                    : s nm ( nurl_str_slice tok 2 - eq 2 )
                    : i lc ( __bx_long_letter longs nm )
                    ? < lc 0 {
                        ( nurl_eprint g_bx_name )
                        ( nurl_eprint `: unrecognized option '` )
                        ( nurl_eprint tok )
                        ( nurl_eprint `'\n` )
                        = ok F
                        = i n
                    } {
                        : i ord ( __bx_ord spec lc )
                        = flags | flags << 1 ord
                        ? ( __bx_takes_val spec ord ) {
                            ? < eq tl {
                                : s v ( nurl_str_slice tok + eq 1 - tl + eq 1 )
                                ( __bx_set_val vals allvals allords ord v )
                            } {
                                ? < + i 1 n {
                                    = i + i 1
                                    ( __bx_set_val vals allvals allords ord ( bx_at argv i ) )
                                } {
                                    ( nurl_eprint g_bx_name )
                                    ( nurl_eprint `: option '` )
                                    ( nurl_eprint tok )
                                    ( nurl_eprint `' requires an argument\n` )
                                    = ok F
                                    = i n
                                }
                            }
                        } {}
                    }
                } {
                    // a cluster of shorts: -la, -n5, -n 5
                    : ~ i k 1
                    ~ < k tl {
                        : i c ( nurl_str_get tok k )
                        : i ord ( __bx_ord spec c )
                        ? < ord 0 {
                            ( nurl_eprint g_bx_name )
                            ( nurl_eprint `: invalid option -- '` )
                            : s bad ( nurl_str_slice tok k 1 )
                            ( nurl_eprint bad )
                            ( nurl_eprint `'\n` )
                            = ok F
                            = k tl
                            = i n
                        } {
                            = flags | flags << 1 ord
                            ? ( __bx_takes_val spec ord ) {
                                ? < + k 1 tl {
                                    : s v ( nurl_str_slice tok + k 1 - tl + k 1 )
                                    ( __bx_set_val vals allvals allords ord v )
                                } {
                                    ? < + i 1 n {
                                        = i + i 1
                                        ( __bx_set_val vals allvals allords ord ( bx_at argv i ) )
                                    } {
                                        ( nurl_eprint g_bx_name )
                                        ( nurl_eprint `: option requires an argument -- '` )
                                        : s bad2 ( nurl_str_slice tok k 1 )
                                        ( nurl_eprint bad2 )
                                        ( nurl_eprint `'\n` )
                                        = ok F
                                        = i n
                                    }
                                }
                                = k tl
                            } {
                                = k + k 1
                            }
                        }
                    }
                }
            }
        }
        = i + i 1
    }
    ^ @ BxOpts { spec flags vals allvals allords args ok }
}

@ bx_has BxOpts o s letter → b {
    : i ord ( __bx_ord . o spec ( nurl_str_get letter 0 ) )
    ? < ord 0 { ^ F } {}
    ^ != 0 & . o flags << 1 ord
}

// The value given for an option, or `` when it was never supplied.
@ bx_val BxOpts o s letter → s {
    : i ord ( __bx_ord . o spec ( nurl_str_get letter 0 ) )
    ? < ord 0 { ^ `` } {}
    ^ ( bx_at . o vals ord )
}

// Every value given for an option, in command-line order. Appends to
// `out`; the caller owns the Strings it receives.
@ bx_vals BxOpts o s letter ( Vec String ) out → v {
    : i ord ( __bx_ord . o spec ( nurl_str_get letter 0 ) )
    ? < ord 0 { ^ } {}
    : i n ( vec_len [i] . o allords )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [i] . o allords i ) {
            T k → {
                ? == k ord { ( vec_push [String] out ( string_from ( bx_at . o allvals i ) ) ) } {}
            }
            F _ → {}
        }
        = i + i 1
    }
}

@ bx_operand_count BxOpts o → i { ^ ( vec_len [String] . o args ) }

@ bx_operand BxOpts o i idx → s { ^ ( bx_at . o args idx ) }

@ bx_ok BxOpts o → b { ^ . o ok }

@ bx_opts_free sink BxOpts o → v {
    ( vec_free_with [String] . o vals \ String x → v { ( string_free x ) } )
    ( vec_free_with [String] . o allvals \ String x → v { ( string_free x ) } )
    ( vec_free [i] . o allords )
    ( vec_free_with [String] . o args \ String x → v { ( string_free x ) } )
}

// ── Inputs ────────────────────────────────────────────────────────
//
// Every filter takes the same shape of operand list: paths, where `-`
// (and, for a tool given none at all, the empty list) means stdin.

@ bx_is_stdin s path → b {
    ^ | == ( nurl_str_len path ) 0 ( bx_streq path `-` )
}

// The POSIX spelling of an I/O failure — `No such file or directory`,
// not the stdlib enum's terser `not found`. Utilities are read by people
// and by scripts that grep their stderr, so the wording matters.
@ bx_ioerr IoErr e → s {
    ^ ?? e {
        NotFound → `No such file or directory`
        PermissionDenied → `Permission denied`
        AlreadyExists → `File exists`
        Interrupted → `Interrupted system call`
        UnexpectedEof → `Unexpected end of file`
        WriteFailed → `Write error`
        ReadFailed → `Read error`
        Other → `Input/output error`
    }
}

// Open `path` (or stdin for `-`) as a buffered line reader. On failure
// the error is reported here — the caller only needs the option.
@ bx_reader s path → ?BufReader {
    ? ( bx_is_stdin path ) { ^ @ ?BufReader { T ( bufreader_stdin ) } } {}
    ?? ( bufreader_open path ) {
        T br → { ^ @ ?BufReader { T br } }
        F e → {
            ( bx_err_at path ( bx_ioerr e ) )
            ^ @ ?BufReader { F # BufReader 0 }
        }
    }
}

// Whole input as bytes, diagnostics included. `ok` says whether the
// returned Vec means anything.
@ bx_slurp s path inout b ok → ( Vec u ) {
    = ok T
    ? ( bx_is_stdin path ) { ^ ( read_all_stdin_bytes ) } {}
    ?? ( read_file_bytes path ) {
        T v → { ^ v }
        F e → {
            ( bx_err_at path ( bx_ioerr e ) )
            = ok F
            ^ ( vec_new [u] )
        }
    }
}

// ── Numbers ───────────────────────────────────────────────────────
//
// A count with the size suffixes every utility accepts: `b` (512),
// `k`/`K` (1024), `M`, `G`, and the decimal `kB`/`MB`/`GB`. Returns -1
// when the text is not a count at all, so a caller can diagnose it.
@ bx_count s text → i {
    : i n ( nurl_str_len text )
    ? == n 0 { ^ -1 } {}
    : ~ i i 0
    : ~ i val 0
    : ~ b any F
    ~ & < i n ( bx_is_digit ( nurl_str_get text i ) ) {
        = val + * val 10 - ( nurl_str_get text i ) 48
        = any T
        = i + i 1
    }
    ? ! any { ^ -1 } {}
    ? == i n { ^ val } {}
    : i c ( nurl_str_get text i )
    : b kb & < + i 1 n == ( nurl_str_get text + i 1 ) 66
    : i rest ? kb - n + i 2 - n + i 1
    ? != rest 0 { ^ -1 } {}
    ? == c 98 { ^ * val 512 } {}
    ? | == c 107 == c 75 { ^ * val ? kb 1000 1024 } {}
    ? == c 77 { ^ * val ? kb 1000000 1048576 } {}
    ? == c 71 { ^ * val ? kb 1000000000 1073741824 } {}
    ^ -1
}

@ bx_is_digit i c → b { ^ & >= c 48 <= c 57 }

@ bx_is_hex i c → b {
    ^ | ( bx_is_digit c ) | & >= c 97 <= c 102 & >= c 65 <= c 70
}

@ bx_hex_val i c → i {
    ? ( bx_is_digit c ) { ^ - c 48 } {}
    ? & >= c 97 <= c 102 { ^ + 10 - c 97 } {}
    ^ + 10 - c 65
}

// ── running one applet from another ──────────────────────────────────
//
// `bx_run_applet` is the dispatch table, and it lives in main.nu because it
// names every applet there is. The shell applet needs to call it, and a
// library module that imports the entry point is a circle — the publish gate
// compiles every module ALONE and would not resolve it. So main.nu hands the
// table over as a value at startup and sh.nu calls what it was given.
//
// A closure is a fat value and cannot sit in an `i` global, so one struct on
// the heap holds it and the pointer to that fits.

: BxDispatch { ( @ i s ( Vec String ) ) run }

: ~ i g_bx_dispatch 0

@ bx_dispatch_set ( @ i s ( Vec String ) ) f → v {
    ? == g_bx_dispatch 0 { = g_bx_dispatch # i ( nurl_alloc Z BxDispatch ) } {}
    : *BxDispatch d # *BxDispatch g_bx_dispatch
    = . d run f
}

// -1 when nobody installed one, which is every caller that is not the
// multiplexer — a library used on its own has no applet table.
@ bx_dispatch s name ( Vec String ) argv → i {
    ? == g_bx_dispatch 0 { ^ -1 } {}
    : *BxDispatch d # *BxDispatch g_bx_dispatch
    : ( @ i s ( Vec String ) ) f . d run
    ^ ( f name argv )
}

// Which applet names this binary answers to, and whether a given name is one
// of them. They live here rather than in main.nu because the shell applet
// asks the same question.
// Every applet, in the order `nurlbox` lists them.
@ _applet_names → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `[` ) )
    ( vec_push [String] v ( string_from `arch` ) )
    ( vec_push [String] v ( string_from `ash` ) )
    ( vec_push [String] v ( string_from `base64` ) )
    ( vec_push [String] v ( string_from `basename` ) )
    ( vec_push [String] v ( string_from `cat` ) )
    ( vec_push [String] v ( string_from `chmod` ) )
    ( vec_push [String] v ( string_from `cksum` ) )
    ( vec_push [String] v ( string_from `clear` ) )
    ( vec_push [String] v ( string_from `cmp` ) )
    ( vec_push [String] v ( string_from `comm` ) )
    ( vec_push [String] v ( string_from `cp` ) )
    ( vec_push [String] v ( string_from `crc32` ) )
    ( vec_push [String] v ( string_from `cut` ) )
    ( vec_push [String] v ( string_from `date` ) )
    ( vec_push [String] v ( string_from `dd` ) )
    ( vec_push [String] v ( string_from `df` ) )
    ( vec_push [String] v ( string_from `dirname` ) )
    ( vec_push [String] v ( string_from `dos2unix` ) )
    ( vec_push [String] v ( string_from `du` ) )
    ( vec_push [String] v ( string_from `echo` ) )
    ( vec_push [String] v ( string_from `egrep` ) )
    ( vec_push [String] v ( string_from `env` ) )
    ( vec_push [String] v ( string_from `expand` ) )
    ( vec_push [String] v ( string_from `expr` ) )
    ( vec_push [String] v ( string_from `factor` ) )
    ( vec_push [String] v ( string_from `false` ) )
    ( vec_push [String] v ( string_from `fgrep` ) )
    ( vec_push [String] v ( string_from `find` ) )
    ( vec_push [String] v ( string_from `fold` ) )
    ( vec_push [String] v ( string_from `free` ) )
    ( vec_push [String] v ( string_from `grep` ) )
    ( vec_push [String] v ( string_from `groups` ) )
    ( vec_push [String] v ( string_from `gunzip` ) )
    ( vec_push [String] v ( string_from `gzip` ) )
    ( vec_push [String] v ( string_from `head` ) )
    ( vec_push [String] v ( string_from `hexdump` ) )
    ( vec_push [String] v ( string_from `hostname` ) )
    ( vec_push [String] v ( string_from `id` ) )
    ( vec_push [String] v ( string_from `kill` ) )
    ( vec_push [String] v ( string_from `killall` ) )
    ( vec_push [String] v ( string_from `ln` ) )
    ( vec_push [String] v ( string_from `logname` ) )
    ( vec_push [String] v ( string_from `ls` ) )
    ( vec_push [String] v ( string_from `md5sum` ) )
    ( vec_push [String] v ( string_from `mkdir` ) )
    ( vec_push [String] v ( string_from `mktemp` ) )
    ( vec_push [String] v ( string_from `mount` ) )
    ( vec_push [String] v ( string_from `mv` ) )
    ( vec_push [String] v ( string_from `nl` ) )
    ( vec_push [String] v ( string_from `nproc` ) )
    ( vec_push [String] v ( string_from `od` ) )
    ( vec_push [String] v ( string_from `paste` ) )
    ( vec_push [String] v ( string_from `pidof` ) )
    ( vec_push [String] v ( string_from `printenv` ) )
    ( vec_push [String] v ( string_from `printf` ) )
    ( vec_push [String] v ( string_from `ps` ) )
    ( vec_push [String] v ( string_from `pwd` ) )
    ( vec_push [String] v ( string_from `readlink` ) )
    ( vec_push [String] v ( string_from `realpath` ) )
    ( vec_push [String] v ( string_from `rev` ) )
    ( vec_push [String] v ( string_from `rm` ) )
    ( vec_push [String] v ( string_from `rmdir` ) )
    ( vec_push [String] v ( string_from `sed` ) )
    ( vec_push [String] v ( string_from `seq` ) )
    ( vec_push [String] v ( string_from `sh` ) )
    ( vec_push [String] v ( string_from `sha1sum` ) )
    ( vec_push [String] v ( string_from `sha256sum` ) )
    ( vec_push [String] v ( string_from `sha512sum` ) )
    ( vec_push [String] v ( string_from `shuf` ) )
    ( vec_push [String] v ( string_from `sleep` ) )
    ( vec_push [String] v ( string_from `sort` ) )
    ( vec_push [String] v ( string_from `split` ) )
    ( vec_push [String] v ( string_from `stat` ) )
    ( vec_push [String] v ( string_from `strings` ) )
    ( vec_push [String] v ( string_from `sum` ) )
    ( vec_push [String] v ( string_from `sync` ) )
    ( vec_push [String] v ( string_from `tac` ) )
    ( vec_push [String] v ( string_from `tail` ) )
    ( vec_push [String] v ( string_from `tar` ) )
    ( vec_push [String] v ( string_from `tee` ) )
    ( vec_push [String] v ( string_from `test` ) )
    ( vec_push [String] v ( string_from `touch` ) )
    ( vec_push [String] v ( string_from `tr` ) )
    ( vec_push [String] v ( string_from `true` ) )
    ( vec_push [String] v ( string_from `truncate` ) )
    ( vec_push [String] v ( string_from `tty` ) )
    ( vec_push [String] v ( string_from `uname` ) )
    ( vec_push [String] v ( string_from `unexpand` ) )
    ( vec_push [String] v ( string_from `uniq` ) )
    ( vec_push [String] v ( string_from `unix2dos` ) )
    ( vec_push [String] v ( string_from `uptime` ) )
    ( vec_push [String] v ( string_from `usleep` ) )
    ( vec_push [String] v ( string_from `wc` ) )
    ( vec_push [String] v ( string_from `which` ) )
    ( vec_push [String] v ( string_from `whoami` ) )
    ( vec_push [String] v ( string_from `xargs` ) )
    ( vec_push [String] v ( string_from `xxd` ) )
    ( vec_push [String] v ( string_from `yes` ) )
    ( vec_push [String] v ( string_from `zcat` ) )
    ^ v
}

// Is `name` one of ours? A binary invoked under a name it does not
// implement is the MULTIPLEXER — that is how `nurlbox` behaves when the
// unikernel's loader calls it `main`, and how a copy named anything else
// still works.
@ bx_is_applet s name → b {
    : ( Vec String ) names ( _applet_names )
    : i n ( vec_len [String] names )
    : ~ b found F
    : ~ i i 0
    ~ < i n {
        ? ( bx_streq ( bx_at names i ) name ) { = found T } {}
        = i + i 1
    }
    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
    ^ found
}
