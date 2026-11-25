// lean.nu — Lean as nurl-cert runs it: the checked tree of formal/, its
// hash, and one run of the kernel over a bundle's Program.lean and
// Claims.lean.

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
}

// Compile `bundle/Program.lean` to an olean under `work`, then check
// `bundle/Claims.lean` against it, both inside formal/ (`lake env`, so
// that `import C.Cert` is formal/'s). Every path is absolute; the working
// directory is formal/ for the run and restored after.
@ cert_lean_check s lake s formal s bundle s work → LeanRun {
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
            ^ @ LeanRun { F log }
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
    ? | ! . r1 started != . r1 code 0 {
        ?? ( env_chdir ( string_data back ) ) { T _ → {} F _ → {} }
        ^ @ LeanRun { F log }
    } {}
    ?? ( env_set `LEAN_PATH` work ) { T _ → {} F _ → {} }
    : ( Vec String ) a2 ( vec_new [String] )
    ( vec_push [String] a2 ( string_from `env` ) )
    ( vec_push [String] a2 ( string_from `lean` ) )
    ( vec_push [String] a2 ( string_clone claims ) )
    : Run r2 ( nc_run lake a2 )
    ?? ( env_unset `LEAN_PATH` ) { T _ → {} F _ → {} }
    ?? ( env_chdir ( string_data back ) ) { T _ → {} F _ → {} }
    ( string_push_str log ( string_data . r2 out ) )
    ( string_push_str log ( string_data . r2 err ) )
    ^ @ LeanRun { . r2 started log }
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
