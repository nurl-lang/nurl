// lean.nu — Lean as nurl-cert runs it: the checked tree of formal/, its
// hash, and one run of the kernel over a bundle's Program.lean and
// Claims.lean (and, for a program in C.Elab's subset, Elab.lean).

$ `util.nu`
$ `claims.nu`

// ── formal/'s tree ───────────────────────────────────────────────────
//
// What a certificate is checked against: every Lean source of formal/ and
// the files that pin how it is built (lakefile.toml, lean-toolchain,
// lake-manifest.json); `.lake/` (build output) is not part of it. The
// tree's hash is the sha256 of `sha256sum`-style lines, one per file in
// byte order of the relative paths, so `sha256sum` reproduces it.

@ __lt_wanted String name → b {
    ? ( string_ends_with name `.lean` ) { ^ T } {}
    : s n ( string_data name )
    ^ | | != 0 ( nurl_str_eq n `lakefile.toml` ) != 0 ( nurl_str_eq n `lean-toolchain` )
    != 0 ( nurl_str_eq n `lake-manifest.json` )
}

@ __lt_walk s root s rel ( Vec String ) out → v {
    : String dir ? == 0 ( nurl_str_len rel ) ( string_from root ) ( nc_join root rel )
    ?? ( dir_list ( string_data dir ) ) {
        T names → {
            : i n ( vec_len [String] names )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] names k ) {
                    T e → {
                        : s es ( string_data e )
                        ? & & == 0 ( nurl_str_eq es `.lake` ) == 0 ( nurl_str_eq es `.` ) == 0 ( nurl_str_eq es `..` ) {
                            : String r ? == 0 ( nurl_str_len rel ) ( string_from es ) ( nc_join rel es )
                            : String full ( nc_join root ( string_data r ) )
                            ?? ( fs_stat ( string_data full ) ) {
                                T st → {
                                    ? ( stat_is_dir st ) {
                                        ( __lt_walk root ( string_data r ) out )
                                    } {
                                        ? ( __lt_wanted e ) { ( vec_push [String] out ( string_clone r ) ) } {}
                                    }
                                }
                                F _ → {}
                            }
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
        }
        F _ → {}
    }
}

// The listing (`<sha256>  <path>\n` per file) and, from it, the hash.
@ cert_formal_listing s root → String {
    : ( Vec String ) files ( vec_new [String] )
    ( __lt_walk root `` files )
    ( nc_sort files )
    : String o ( string_new )
    : i n ( vec_len [String] files )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] files k ) {
            T f → {
                : String full ( nc_join root ( string_data f ) )
                ?? ( nc_sha256_file ( string_data full ) ) {
                    T h → ( string_push_str o ( string_data h ) )
                    F → ( string_push_str o `unreadable` )
                }
                ( string_push_str o `  ` )
                ( string_push_str o ( string_data f ) )
                ( string_push_char o 10 )
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ o
}

@ cert_formal_hash s root → String {
    : String l ( cert_formal_listing root )
    ^ ( nc_sha256_text ( string_data l ) )
}

// ── One check ────────────────────────────────────────────────────────

: LeanRun {
    b ran
    String log
    // `elab`: Elab.lean checked too, beside Claims.lean, and its log
    b elab_ran
    String elab_log
}

// `lake env lean <file>`, started in the background (inside formal/, with
// the environment as it is, LEAN_PATH included), its output into `log`.
// (Through `sh`, so that the output goes to a file: a pipe nobody reads
// could fill and stop it.)
@ __lt_spawn s lake s file s log → ?ProcChild {
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `-c` )
    ( vec_push [s] args `exec "$0" env lean "$1" > "$2" 2>&1` )
    ( vec_push [s] args lake )
    ( vec_push [s] args file )
    ( vec_push [s] args log )
    ^ ?? ( process_spawn `sh` args ) {
        T c → @ ?ProcChild { T c }
        F _ → @ ?ProcChild { F }
    }
}

// Compile `bundle/Program.lean` to an olean under `work`, then check
// `bundle/Claims.lean` against it, both inside formal/ (`lake env`, so
// that `import C.Cert` is formal/'s). With `elab`, `bundle/Elab.lean` is
// checked against the same olean at the same time, in a second Lean
// process. Every path is absolute; the working directory is formal/ for
// the run and restored after.
@ cert_lean_check s lake s formal s bundle s work b elab → LeanRun {
    : String log ( string_new )
    : String prog ( nc_join bundle `Program.lean` )
    : String claims ( nc_join bundle `Claims.lean` )
    : String olean ( nc_join work `Program.olean` )
    : String root_arg ( string_from `--root=` )
    ( string_push_str root_arg bundle )
    : String back ?? ( env_cwd ) { T c → c F _ → ( string_from `/` ) }
    ?? ( env_chdir formal ) {
        T _ → {}
        F _ → {
            ( string_push_str log `cannot enter the formal tree ` )
            ( string_push_str log formal )
            ^ @ LeanRun { F log F ( string_new ) }
        }
    }
    : ( Vec String ) a1 ( vec_new [String] )
    ( vec_push [String] a1 ( string_from `env` ) )
    ( vec_push [String] a1 ( string_from `lean` ) )
    ( vec_push [String] a1 root_arg )
    ( vec_push [String] a1 ( string_from `-o` ) )
    ( vec_push [String] a1 ( string_clone olean ) )
    ( vec_push [String] a1 ( string_clone prog ) )
    : Run r1 ( nc_run lake a1 )
    ( string_push_str log ( string_data . r1 out ) )
    ( string_push_str log ( string_data . r1 err ) )
    : ~ b ran & . r1 started == . r1 code 0
    : ~ b eran F
    : ~ String elog ( string_new )
    ? ran {
        ?? ( env_set `LEAN_PATH` work ) { T _ → {} F _ → {} }
        : String elab_file ( nc_join bundle `Elab.lean` )
        : String elab_logf ( nc_join work `elab.log` )
        : ~ ? ProcChild ec @ ?ProcChild { F }
        ? elab { = ec ( __lt_spawn lake ( string_data elab_file ) ( string_data elab_logf ) ) } {}
        : ( Vec String ) a2 ( vec_new [String] )
        ( vec_push [String] a2 ( string_from `env` ) )
        ( vec_push [String] a2 ( string_from `lean` ) )
        ( vec_push [String] a2 ( string_clone claims ) )
        : Run r2 ( nc_run lake a2 )
        ?? ( env_unset `LEAN_PATH` ) { T _ → {} F _ → {} }
        ( string_push_str log ( string_data . r2 out ) )
        ( string_push_str log ( string_data . r2 err ) )
        // A run counts only when Lean finished: one killed before it printed
        // the axioms reports nothing to read.
        = ran & . r2 started == . r2 code 0
        // Elab.lean's run, likewise: only an exit 0 counts.
        ?? ec {
            T c → {
                : i code ( proc_wait c )
                = eran == code 0
                = elog ?? ( nc_read ( string_data elab_logf ) ) { T x → x F → ( string_new ) }
            }
            F → {
                ? elab { = elog ( string_from `could not start Lean on Elab.lean` ) } {}
            }
        }
    } {}
    ?? ( env_chdir ( string_data back ) ) { T _ → {} F _ → {} }
    ^ @ LeanRun { ran log eran elog }
}

// Lean proved `Cert.elab` on the standard axioms alone: the run exited 0,
// reported no error, and `#print axioms` lists no other axiom.
@ cert_elab_proved LeanRun lr → b {
    ? | ! . lr elab_ran ( cert_lean_has_error . lr elab_log ) { ^ F } {}
    ^ ?? ( cert_lean_axioms . lr elab_log `Cert.elab` ) {
        T ax → ( cert_axioms_std ( cert_axiom_list ax ) )
        F → F
    }
}

// ── Reading the run ──────────────────────────────────────────────────

@ cert_lean_has_error String log → b { ^ ( string_contains log `: error` ) }

// The kernel (or compiled code) decided that the checker refuses.
@ cert_lean_refused String log → b {
    ^ & ( string_contains log `that the proposition` ) ( string_contains log `is false` )
}

// The axioms `#print axioms` lists for `name`, comma-separated as Lean
// prints them ("" for none), or none when the name is not reported.
@ cert_lean_axioms String log s name → ?String {
    : ( Vec String ) ls ( nc_lines ( string_data log ) )
    : String head ( string_from `'` )
    ( string_push_str head name )
    ( string_push_str head `' ` )
    : i n ( vec_len [String] ls )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] ls k ) {
            T l → {
                ? ( string_starts_with l ( string_data head ) ) {
                    ? ( string_contains l `does not depend on any axioms` ) { ^ @ ?String { T ( string_new ) } } {}
                    ?? ( string_index_of l `[` ) {
                        T a → {
                            : i z - ( string_len l ) 1
                            ? > z a { ^ @ ?String { T ( string_substr l + a 1 - - z a 1 ) } } {}
                        }
                        F → {}
                    }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ ?String { F }
}

// The axioms as a list.
@ cert_axiom_list String ax → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ? == 0 ( string_len ax ) { ^ out } {}
    : ( Vec String ) parts ( string_split ax `,` )
    : i n ( vec_len [String] parts )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] parts k ) {
            T p → ( vec_push [String] out ( string_trim p ) )
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

// Every axiom is one of the three standard ones.
@ cert_axioms_std ( Vec String ) axioms → b {
    : i n ( vec_len [String] axioms )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] axioms k ) {
            T a → { ? ! ( cert_std_axiom ( string_data a ) ) { ^ F } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ T
}

// A claim's status from its axioms: `proved` when it rests on the three
// standard axioms only; under `fast`, `validated` when the rest is the
// compiled-code axioms `native_decide` makes (and nothing else); otherwise
// `open` — never more than the axioms allow.
@ __la_native s a → b {
    ^ | != 0 ( nurl_str_eq a `Lean.ofReduceBool` ) ( string_contains ( string_from a ) `._native.native_decide.ax_` )
}

@ cert_status_of s prof ( Vec String ) axioms → s {
    : i n ( vec_len [String] axioms )
    : ~ b std T
    : ~ b nat T
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] axioms k ) {
            T a → {
                ? ! ( cert_std_axiom ( string_data a ) ) {
                    = std F
                    ? ! ( __la_native ( string_data a ) ) { = nat F } {}
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ? std { ? != 0 ( nurl_str_eq prof `kernel` ) { ^ `proved` } { ^ `validated` } } {}
    ? & nat != 0 ( nurl_str_eq prof `fast` ) { ^ `validated` } {}
    ^ `open`
}
