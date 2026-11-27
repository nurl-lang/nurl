// nurl-cert — memory-safety certificates for NURL programs (AGORA-1019).
//
//   nurl-cert certify prog.nu [--out prog.cert] [--profile kernel|fast]
//                             [--binary prog]
//   nurl-cert verify prog.cert [--binary prog]
//   nurl-cert translate prog.core
//   nurl-cert coverage DIR
//
// `certify` turns a program into a bundle whose Claims.lean states, about
// the program's own term, that it never gets stuck (M.safe) and that it
// releases everything it allocates, a panic's unwinding included
// (M.leak), each proved from formal/'s theorems with the checker's verdict
// decided by the Lean kernel. `verify` checks a bundle again without
// nurlc. `translate` prints the Lean term of a core IR (`nurlc
// --emit-core`), as tools/ncore/tolean.py prints it. `coverage` prints the
// coverage table (Markdown) of the bundles DIR/*.cert: programs by verdict,
// own functions by status, and why the unsupported ones are (AGORA-1015).
// docs/dev/CERTIFICATE.md describes the bundle.
//
// Exit codes: certify 0 every claim proved (or, under fast, validated) ·
// 1 an error · 2 unsupported by the translation · 3 refused by the
// checker; verify 0 verified · 1 a check failed · 2 usage or no bundle;
// translate 0 translated · 1 a core IR it cannot read · 2 unsupported;
// coverage 0 printed · 1 DIR cannot be listed.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/args.nu`
$ `stdlib/ext/env.nu`
$ `util.nu`
$ `certify.nu`
$ `verify.nu`
$ `words.nu`
$ `coverage.nu`

@ __usage → v {
    ( nurl_print `nurl-cert — memory-safety certificates for NURL programs\n\n` )
    ( nurl_print `Usage:\n` )
    ( nurl_print `  nurl-cert certify <prog.nu> [options]   write the certificate bundle\n` )
    ( nurl_print `  nurl-cert verify <prog.cert> [options]  check a bundle again (no nurlc needed)\n` )
    ( nurl_print `  nurl-cert translate <prog.core>         print the Lean term of a core IR (nurlc --emit-core)\n` )
    ( nurl_print `  nurl-cert words <prog.core>             print the core IR as Lean data (C.Elab.IR)\n` )
    ( nurl_print `  nurl-cert coverage <dir>                the coverage table of the bundles dir/*.cert (Markdown)\n\n` )
    ( nurl_print `Options:\n` )
    ( nurl_print `  --out DIR        the bundle (default <prog>.cert)\n` )
    ( nurl_print `  --profile P      kernel (default: the Lean kernel decides, standard axioms only)\n` )
    ( nurl_print `                   or fast (compiled code decides; claims are 'validated')\n` )
    ( nurl_print `  --binary FILE    certify: record its hash; verify: check it is that binary\n` )
    ( nurl_print `  --rebuild        verify: make Program.core and Program.lean from the sources\n` )
    ( nurl_print `                   again with nurlc and the translator, and compare them\n` )
    ( nurl_print `  --formal DIR     the formal/ tree (default $NURL_FORMAL, else ./formal)\n` )
    ( nurl_print `  --nurlc PATH     the compiler (default $NURLC, else nurlc)\n` )
    ( nurl_print `  --lean PATH      Lean (default $LEAN, else lean: elan's picks formal/'s toolchain)\n` )
    ( nurl_print `  --stdlib DIR     the standard library's root (default $NURL_STDLIB, else <formal>/..)\n` )
    ( nurl_print `  --version        print the version and exit\n` )
}

@ __mkparser → ArgParser {
    : ArgParser p ( args_new `nurl-cert` `memory-safety certificates for NURL programs` )
    ( args_flag p `help` 104 `show this help` )
    ( args_flag p `version` 118 `print the version and exit` )
    ( args_flag p `rebuild` 0 `verify: make the core IR and the term again (needs nurlc)` )
    ( args_opt p `out` 111 `DIR` `the bundle` )
    ( args_opt p `profile` 0 `P` `kernel or fast` )
    ( args_opt p `binary` 0 `FILE` `the built program` )
    ( args_opt p `formal` 0 `DIR` `the formal/ tree` )
    ( args_opt p `nurlc` 0 `PATH` `the compiler` )
    ( args_opt p `lean` 0 `PATH` `Lean` )
    ( args_opt p `stdlib` 0 `DIR` `the standard library's root` )
    ^ p
}

@ __argv → ( Vec String ) {
    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i i 1
    ~ < i ac { ( vec_push [String] argv ( env_arg i ) ) = i + i 1 }
    ^ argv
}

// An option's value, else an environment variable's, else `dflt`.
@ __opt ArgParser p s name s env s dflt → String {
    ^ ?? ( args_value p name ) {
        T v → ( string_clone v )
        F _ → {
            ? == 0 ( nurl_str_len env ) { ( string_from dflt ) } {
                ?? ( env_get env ) {
                    T e → e
                    F → ( string_from dflt )
                }
            }
        }
    }
}

// A path option, made absolute: the run changes directory into formal/.
@ __opt_abs ArgParser p s name s env s dflt → String {
    : String v ( __opt p name env dflt )
    ? == 0 ( string_len v ) { ^ v } {}
    ^ ( nc_abs ( string_data v ) )
}

// A command found on PATH stays a bare name; one with a slash (or, on
// Windows, a backslash) is a path.
@ __opt_cmd ArgParser p s name s env s dflt → String {
    : String v ( __opt p name env dflt )
    : b bs & ( nc_backslash_sep ) ( string_contains v `\\` )
    ? | ( string_contains v `/` ) bs { ^ ( nc_abs ( string_data v ) ) } {}
    ^ v
}

@ __cmd_certify ArgParser p String target → i {
    : String src ( nc_abs ( string_data target ) )
    : ~ String dflt_out ( string_clone src )
    ? ( string_ends_with dflt_out `.nu` ) { = dflt_out ( string_substr src 0 - ( string_len src ) 3 ) } {}
    ( string_push_str dflt_out `.cert` )
    : String out ( __opt_abs p `out` `` ( string_data dflt_out ) )
    : String prof ( __opt p `profile` `` `kernel` )
    ? ! ( cert_profile_ok ( string_data prof ) ) {
        ( nurl_eprintln `nurl-cert: --profile is kernel or fast` )
        ^ 2
    } {}
    : String formal ( __opt_abs p `formal` `NURL_FORMAL` `formal` )
    : String nurlc ( __opt_cmd p `nurlc` `NURLC` `nurlc` )
    : String lean ( __opt_cmd p `lean` `LEAN` `lean` )
    : String binary ( __opt_abs p `binary` `` `` )
    : String sl_dflt ( nc_join ( string_data formal ) `..` )
    : String stdlib ( __opt_abs p `stdlib` `NURL_STDLIB` ( string_data sl_dflt ) )
    : CertOpts o @ CertOpts { src out prof nurlc formal lean binary stdlib }
    ^ ( cert_certify o )
}

@ __cmd_verify ArgParser p String target → i {
    : String bundle ( nc_abs ( string_data target ) )
    : String binary ( __opt_abs p `binary` `` `` )
    : String formal ( __opt_abs p `formal` `NURL_FORMAL` `formal` )
    : String lean ( __opt_cmd p `lean` `LEAN` `lean` )
    : b rebuild ( args_present p `rebuild` )
    : String nurlc ( __opt_cmd p `nurlc` `NURLC` `nurlc` )
    : String sl_dflt ( nc_join ( string_data formal ) `..` )
    : String stdlib ( __opt_abs p `stdlib` `NURL_STDLIB` ( string_data sl_dflt ) )
    : VerOpts o @ VerOpts { bundle binary formal lean rebuild nurlc stdlib }
    ^ ( cert_verify o )
}

// `words`: the core IR as Lean data (`def ir : C.Elab.IR`, AGORA-1029).
@ __cmd_words String target → i {
    : String text ?? ( nc_read ( string_data target ) ) {
        T x → x
        F → {
            ( nc_eprint2 `nurl-cert: cannot read ` ( string_data target ) )
            ^ 1
        }
    }
    // (the words are made from the text up to its first NUL)
    ? ! ( cert_words_ok text ) {
        ( nc_eprint2 `nurl-cert: the core IR holds a NUL byte: ` ( string_data target ) )
        ^ 1
    } {}
    : String w ( cert_words ( string_data text ) )
    ( nurl_print ( string_data w ) )
    ^ 0
}

// `translate`: the term on stdout, or `unsupported: <why>` on stderr and
// exit 2 (tolean.py's output and exit code); a core IR it cannot read is
// exit 1.
@ __cmd_translate String target → i {
    : String text ?? ( nc_read ( string_data target ) ) {
        T x → x
        F → {
            ( nc_eprint2 `nurl-cert: cannot read ` ( string_data target ) )
            ^ 1
        }
    }
    ^ ?? ( tolean_translate ( string_data text ) ) {
        T lean → {
            ( nurl_print ( string_data lean ) )
            0
        }
        F why → {
            ? ( string_starts_with why `internal: ` ) {
                ( nc_eprint2 `nurl-cert: ` ( string_data why ) )
                1
            } {
                ( nc_eprint2 `unsupported: ` ( string_data why ) )
                2
            }
        }
    }
}

// `coverage`: the table of the bundles under `dir` on stdout.
@ __cmd_coverage String dir → i {
    ^ ?? ( cov_table ( string_data dir ) ( string_data dir ) ) {
        T t → {
            ( nurl_print ( string_data t ) )
            0
        }
        F → {
            ( nc_eprint2 `nurl-cert: cannot list ` ( string_data dir ) )
            1
        }
    }
}

@ main → i {
    : ArgParser p ( __mkparser )
    : ( Vec String ) argv ( __argv )
    : ~ i rc 0
    ? ( args_parse p argv ) {
        ? ( args_present p `version` ) {
            ( nurl_print `nurl-cert ` )
            ( nurl_print NURLCERT_VERSION )
            ( nurl_print `\n` )
        } {
            : i np ( args_positional_count p )
            ? | ( args_present p `help` ) < np 2 {
                ( __usage )
                ? ! ( args_present p `help` ) { = rc 2 } {}
            } {
                : ( Vec String ) pos ( args_positionals p )
                : String cmd ?? ( vec_get [String] pos 0 ) { T s → ( string_clone s ) F _ → ( string_new ) }
                : String arg ?? ( vec_get [String] pos 1 ) { T s → ( string_clone s ) F _ → ( string_new ) }
                ? ( nc_is cmd `certify` ) { = rc ( __cmd_certify p arg ) } {
                    ? ( nc_is cmd `verify` ) { = rc ( __cmd_verify p arg ) } {
                        ? ( nc_is cmd `words` ) { = rc ( __cmd_words arg ) } {
                            ? ( nc_is cmd `translate` ) { = rc ( __cmd_translate arg ) } {
                                ? ( nc_is cmd `coverage` ) { = rc ( __cmd_coverage arg ) } {
                                    ( nurl_eprint `nurl-cert: unknown command: ` )
                                    ( nurl_eprintln ( string_data cmd ) )
                                    = rc 2
                                }
                            }
                        }
                    }
                }
            }
        }
    } {
        ( nurl_eprint `nurl-cert: ` )
        ( nurl_eprintln ( args_error p ) )
        ( nurl_eprintln `try 'nurl-cert --help'` )
        = rc 2
    }
    ^ rc
}
