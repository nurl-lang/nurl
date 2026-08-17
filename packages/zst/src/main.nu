// zst — Zstandard on the command line, with no Zstandard underneath.
//
//   zst c FILE                compress   → FILE.zst
//   zst d FILE.zst            decompress → FILE
//   zst t FILE.zst…           verify: checksum, structure, exact sizes
//   zst i FILE.zst            inspect: every frame and block, and why
//   zst b FILE                bench: compression and decompression here
//
// With no FILE (or `-`) it is a filter: stdin to stdout, bytes in, bytes
// out. Frames it writes are ordinary Zstandard frames — `unzstd` reads
// them — and frames the `zstd` CLI writes are read here, both directions
// checked against that CLI by tools/zstd_gate.sh in the compiler repo.
//
// `zst` never deletes an input file. The reference CLI removes the
// source on success unless you pass -k; here the safe thing is the only
// thing, and `rm` is right there.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/zstd.nu`
$ `stdlib/ext/env.nu`
$ `inspect.nu`

@ __die s msg → v {
    ( nurl_eprint `zst: ` )
    ( nurl_eprint msg )
    ( nurl_eprint `\n` )
}

@ __pos ( Vec String ) ps i k → s {
    ^ ?? ( vec_get [String] ps k ) { T s → ( string_data s ) F _ → `` }
}

@ __free_strvec ( Vec String ) v → v {
    ( vec_free_with [String] v \ String s → v { ( string_free s ) } )
}

@ __opt_int ArgParser p s name i dflt → i {
    ?? ( args_value p name ) {
        T v → { : i n ( nurl_str_to_int ( string_data v ) ) ( string_free v ) ^ n }
        F _ → { ^ dflt }
    }
}

@ __is_stdin s path → b {
    ^ | == 0 ( nurl_str_len path ) != 0 ( nurl_str_eq path `-` )
}

// The one-slot flag a helper reports success through: NURL returns one
// value, and `__read_input` has to return the bytes AND whether the read
// happened (an empty file is a legal, successful read).
@ __slot ( Vec i ) v → i {
    ^ ?? ( vec_get [i] v 0 ) { T x → x F _ → 0 }
}

// Read a whole input: a file, or all of stdin when the path is empty.
@ __read_input s path ( Vec i ) okslot → ( Vec u ) {
    : *i op ( vec_data [i] okslot )
    = . op 0 1
    ? ( __is_stdin path ) { ^ ( read_all_stdin_bytes ) } {}
    ?? ( read_file_bytes path ) {
        T v → { ^ v }
        F _e → {
            = . op 0 0
            ( __die ( nurl_str_cat3 `cannot read '` path `'` ) )
            ^ ( vec_new [u] )
        }
    }
}

@ __write_output s path ( Vec u ) data b force → b {
    ? ( __is_stdin path ) {
        ( write_bytes data )
        ( flush )
        ^ T
    } {}
    ? & ! force ( file_exists path ) {
        ( __die ( nurl_str_cat3 `'` path `' exists (use -f to overwrite)` ) )
        ^ F
    } {}
    ?? ( write_file_bytes path data ) {
        T _ok → { ^ T }
        F _e → { ( __die ( nurl_str_cat3 `cannot write '` path `'` ) ) ^ F }
    }
}

// FILE → FILE.zst, FILE.zst → FILE.
@ __out_name s inp b compressing → String {
    ? compressing { ^ ( string_from ( nurl_str_cat inp `.zst` ) ) } {}
    : i n ( nurl_str_len inp )
    ? & > n 4 != 0 ( nurl_str_eq ( nurl_str_slice inp - n 4 4 ) `.zst` ) {
        ^ ( string_from ( nurl_str_slice inp 0 - n 4 ) )
    } {}
    ^ ( string_from ( nurl_str_cat inp `.out` ) )
}

// "100000 → 29974 bytes  (30.0% of original, 3.34x)" — both numbers,
// because a ratio alone hides the scale and a size alone hides the win.
@ __ratio String out i from i to → v {
    ( string_push_int out from )
    ( string_push_str out ` → ` )
    ( string_push_int out to )
    ( string_push_str out ` bytes` )
    ? & > to 0 > from 0 {
        : i pct / * to 1000 from
        : i x / * from 100 to
        ( string_push_str out `  (` )
        ( string_push_int out / pct 10 )
        ( string_push_char out 46 )
        ( string_push_int out % pct 10 )
        ( string_push_str out `% of original, ` )
        ( string_push_int out / x 100 )
        ( string_push_char out 46 )
        : i frac % x 100
        ? < frac 10 { ( string_push_char out 48 ) } {}
        ( string_push_int out frac )
        ( string_push_str out `x)` )
    } {}
}

// ── commands ────────────────────────────────────────────────────────

@ __cmd_compress s inp s outp i level b force b quiet → i {
    : ( Vec i ) ok ( vec_new [i] )
    ( vec_push [i] ok 1 )
    : ( Vec u ) src ( __read_input inp ok )
    ? == 0 ( __slot ok ) { ( vec_free [u] src ) ( vec_free [i] ok ) ^ 1 } {}
    ( vec_free [i] ok )
    : ( Vec u ) out ( zstd_encode_at src level )
    : ~ i rc 0
    ? ( __write_output outp out force ) {} { = rc 1 }
    ? & == rc 0 & ! quiet ! ( __is_stdin outp ) {
        : String msg ( string_with_cap 96 )
        ( string_push_str msg outp )
        ( string_push_str msg `  ` )
        ( __ratio msg ( vec_len [u] src ) ( vec_len [u] out ) )
        ( string_push_char msg 10 )
        ( nurl_eprint ( string_data msg ) )
        ( string_free msg )
    } {}
    ( vec_free [u] out )
    ( vec_free [u] src )
    ^ rc
}

@ __cmd_decompress s inp s outp b force b quiet i limit → i {
    : ( Vec i ) ok ( vec_new [i] )
    ( vec_push [i] ok 1 )
    : ( Vec u ) src ( __read_input inp ok )
    ? == 0 ( __slot ok ) { ( vec_free [u] src ) ( vec_free [i] ok ) ^ 1 } {}
    ( vec_free [i] ok )
    : ~ i rc 0
    ?? ( zstd_decode_limit src limit ) {
        T out → {
            ? ( __write_output outp out force ) {} { = rc 1 }
            ? & == rc 0 & ! quiet ! ( __is_stdin outp ) {
                : String msg ( string_with_cap 96 )
                ( string_push_str msg outp )
                ( string_push_str msg `  ` )
                ( string_push_int msg ( vec_len [u] src ) )
                ( string_push_str msg ` → ` )
                ( string_push_int msg ( vec_len [u] out ) )
                ( string_push_str msg ` bytes\n` )
                ( nurl_eprint ( string_data msg ) )
                ( string_free msg )
            } {}
            ( vec_free [u] out )
        }
        F e → {
            ( __die ( nurl_str_cat3 `cannot decode: ` ( zstd_err_name e ) `` ) )
            = rc 1
        }
    }
    ( vec_free [u] src )
    ^ rc
}

@ __cmd_test s inp b quiet → i {
    : ( Vec i ) ok ( vec_new [i] )
    ( vec_push [i] ok 1 )
    : ( Vec u ) src ( __read_input inp ok )
    ? == 0 ( __slot ok ) { ( vec_free [u] src ) ( vec_free [i] ok ) ^ 1 } {}
    ( vec_free [i] ok )
    : ~ i rc 0
    ?? ( zstd_decode src ) {
        T out → {
            ? ! quiet {
                : String msg ( string_with_cap 96 )
                ( string_push_str msg ? ( __is_stdin inp ) `<stdin>` inp )
                ( string_push_str msg `: OK  ` )
                ( __ratio msg ( vec_len [u] out ) ( vec_len [u] src ) )
                ( string_push_char msg 10 )
                ( nurl_print ( string_data msg ) )
                ( string_free msg )
            } {}
            ( vec_free [u] out )
        }
        F e → {
            : String msg ( string_with_cap 64 )
            ( string_push_str msg ? ( __is_stdin inp ) `<stdin>` inp )
            ( string_push_str msg `: FAILED — ` )
            ( string_push_str msg ( zstd_err_name e ) )
            ( __die ( string_data msg ) )
            ( string_free msg )
            = rc 1
        }
    }
    ( vec_free [u] src )
    ^ rc
}

@ __cmd_inspect s inp → i {
    : ( Vec i ) ok ( vec_new [i] )
    ( vec_push [i] ok 1 )
    : ( Vec u ) src ( __read_input inp ok )
    ? == 0 ( __slot ok ) { ( vec_free [u] src ) ( vec_free [i] ok ) ^ 1 } {}
    ( vec_free [i] ok )
    : i rc ( zst_inspect src ? ( __is_stdin inp ) `<stdin>` inp )
    ( vec_free [u] src )
    ^ rc
}

@ __mbs String out i bytes i ns → v {
    ? <= ns 0 { ( string_push_str out `—` ) ^ v } {}
    // bytes/ns → MB/s, in integer arithmetic: bytes * 1000 / ns.
    ( string_push_int out / * bytes 1000 ns )
    ( string_push_str out ` MB/s` )
}

@ __cmd_bench s inp i level i reps → i {
    : ( Vec i ) ok ( vec_new [i] )
    ( vec_push [i] ok 1 )
    : ( Vec u ) src ( __read_input inp ok )
    ? == 0 ( __slot ok ) { ( vec_free [u] src ) ( vec_free [i] ok ) ^ 1 } {}
    ( vec_free [i] ok )
    : i n ( vec_len [u] src )
    ? == n 0 { ( __die `nothing to benchmark` ) ( vec_free [u] src ) ^ 1 } {}
    : ~ i best_c 0
    : ~ i best_d 0
    : ~ i csize 0
    : ~ i r 0
    ~ < r reps {
        : i t0 ( monotonic_ns )
        : ( Vec u ) enc ( zstd_encode_at src level )
        : i t1 ( monotonic_ns )
        = csize ( vec_len [u] enc )
        : i dc - t1 t0
        ? | == best_c 0 < dc best_c { = best_c dc } {}
        : i t2 ( monotonic_ns )
        ?? ( zstd_decode enc ) {
            T dec → {
                : i t3 ( monotonic_ns )
                : i dd - t3 t2
                ? | == best_d 0 < dd best_d { = best_d dd } {}
                ( vec_free [u] dec )
            }
            F e → { ( __die ( zstd_err_name e ) ) }
        }
        ( vec_free [u] enc )
        = r + r 1
    }
    : String out ( string_with_cap 160 )
    ( string_push_str out ? ( __is_stdin inp ) `<stdin>` inp )
    ( string_push_str out `  ` )
    ( __ratio out n csize )
    ( string_push_str out `\n  level ` )
    ( string_push_int out level )
    ( string_push_str out `   compress ` )
    ( __mbs out n best_c )
    ( string_push_str out `   decompress ` )
    ( __mbs out n best_d )
    ( string_push_str out `   (best of ` )
    ( string_push_int out reps )
    ( string_push_str out `)\n` )
    ( nurl_print ( string_data out ) )
    ( string_free out )
    ( vec_free [u] src )
    ^ 0
}

// ── entry point ─────────────────────────────────────────────────────

@ __usage ArgParser p → v {
    : String h ( args_usage p )
    ( nurl_print `zst — Zstandard, in pure NURL

Commands:
  c [FILE]      compress FILE to FILE.zst (or stdin to stdout)
  d [FILE]      decompress FILE.zst back to FILE (or stdin to stdout)
  t FILE...     verify: structure, sizes and content checksum
  i FILE        inspect: every frame and block, and how each was coded
  b FILE        bench: compression and decompression speed here

` )
    ( nurl_print ( string_data h ) )
    ( string_free h )
}

@ main → i {
    : ArgParser p ( args_new `zst` `Zstandard compression, in pure NURL` )
    ( args_flag p `help` 104 `show this help` )  // -h
    ( args_flag p `force` 102 `overwrite an existing output file` )  // -f
    ( args_flag p `stdout` 99 `write to stdout, whatever the input was` )  // -c
    ( args_flag p `quiet` 113 `no per-file report on stderr` )  // -q
    ( args_opt p `level` 108 `N` `level 1-19; 13+ = optimal parse, slow (default 3)` )  // -l
    ( args_opt p `out` 111 `FILE` `write here instead of the derived name` )  // -o
    ( args_opt p `reps` 110 `N` `bench: repetitions, best wins (default 3)` )  // -n
    ( args_opt p `max` 0 `BYTES` `d: refuse to produce more than this` )

    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i ai 1
    ~ < ai ac {
        ( vec_push [String] argv ( env_arg ai ) )
        = ai + ai 1
    }
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
    : i level ( __opt_int p `level` 3 )
    : i reps ( __opt_int p `reps` 3 )
    : i limit ( __opt_int p `max` 0x7FFFFFFFFFFFFFFF )
    : b force ( args_present p `force` )
    : b quiet ( args_present p `quiet` )
    : b to_stdout ( args_present p `stdout` )
    : i npos ( args_positional_count p )
    : s inp ? > npos 1 ( __pos ps 1 ) ``
    : ~ i rc 0

    ? | ( nurl_str_eq cmd `c` ) ( nurl_str_eq cmd `compress` ) {
        : ~ String outp ( string_new )
        ?? ( args_value p `out` ) {
            T v → { ( string_free outp ) = outp v }
            F _ → {
                ? | to_stdout ( __is_stdin inp ) {} {
                    ( string_free outp )
                    = outp ( __out_name inp T )
                }
            }
        }
        = rc ( __cmd_compress inp ( string_data outp ) level force quiet )
        ( string_free outp )
    } {
        ? | ( nurl_str_eq cmd `d` ) ( nurl_str_eq cmd `decompress` ) {
            : ~ String outp ( string_new )
            ?? ( args_value p `out` ) {
                T v → { ( string_free outp ) = outp v }
                F _ → {
                    ? | to_stdout ( __is_stdin inp ) {} {
                        ( string_free outp )
                        = outp ( __out_name inp F )
                    }
                }
            }
            = rc ( __cmd_decompress inp ( string_data outp ) force quiet limit )
            ( string_free outp )
        } {
            ? | ( nurl_str_eq cmd `t` ) ( nurl_str_eq cmd `test` ) {
                ? <= npos 1 {
                    = rc ( __cmd_test `` quiet )
                } {
                    : ~ i k 1
                    ~ < k npos {
                        : i one ( __cmd_test ( __pos ps k ) quiet )
                        ? != one 0 { = rc one } {}
                        = k + k 1
                    }
                }
            } {
                ? | ( nurl_str_eq cmd `i` ) ( nurl_str_eq cmd `inspect` ) {
                    = rc ( __cmd_inspect inp )
                } {
                    ? | ( nurl_str_eq cmd `b` ) ( nurl_str_eq cmd `bench` ) {
                        = rc ( __cmd_bench inp level reps )
                    } {
                        ( __die ( nurl_str_cat3 `unknown command '` cmd `' — try 'zst --help'` ) )
                        = rc 2
                    } } } } }

    ( args_free p )
    ( __free_strvec argv )
    ^ rc
}
