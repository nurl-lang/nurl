// lean.nu — Lean as nurl-cert runs it: the checked tree of formal/, its
// hash, and one run of the kernel over a bundle's Program.lean and
// Claims.lean (and, for a program in C.Elab's subset, Elab.lean).

$ `util.nu`
$ `claims.nu`
$ `stdlib/ext/json.nu`

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
    // `elab`: Elab.lean checked too, and its part of the output
    b elab_ran
    String elab_log
    // `caps`: Caps.lean (N.cap, AGORA-1013) checked too, and its part
    b caps_ran
    String caps_log
}

// A blank line, or a comment line (`--`).
@ __lt_quiet String l → b {
    ^ | == 0 ( string_len ( string_trim l ) ) ( string_starts_with l `--` )
}

// `text` without its import lines, which must be exactly `want`, in order,
// one after the other, with nothing but blank and comment lines before them
// and no other line of the text starting `import `; none otherwise.
@ __lt_unimport String text ( Vec String ) want → ?String {
    : ( Vec String ) ls ( nc_lines ( string_data text ) )
    : String o ( string_with_cap + ( string_len text ) 1 )
    : i n ( vec_len [String] ls )
    : i nw ( vec_len [String] want )
    : ~ i seen 0
    : ~ b before T
    : ~ i k 0
    ~ < k n {
        : String l ( string_clone ( vec_at [String] ls k ) )
        ? ( string_starts_with l `import ` ) {
            ? | ! before >= seen nw { ^ @ ?String { F } } {}
            ? ! ( string_eq l ( vec_at [String] want seen ) ) { ^ @ ?String { F } } {}
            = seen + seen 1
        } {
            ? > seen 0 { = before F } {
                ? ! ( __lt_quiet l ) { = before F } {}
            }
            ( string_push_str o ( string_data l ) )
            ( string_push_char o 10 )
        }
        = k + k 1
    }
    ? != seen nw { ^ @ ?String { F } } {}
    ^ @ ?String { T o }
}

@ __lt_v1 s a → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from a ) )
    ^ v
}

@ __lt_v2 s a s b → ( Vec String ) {
    : ( Vec String ) v ( __lt_v1 a )
    ( vec_push [String] v ( string_from b ) )
    ^ v
}

// One Lean file that checks the bundle's three modules as Lean would check
// them one by one (`lake build`, the module way: Program.lean, then Claims.lean
// and Elab.lean against its olean):
//   import C.Cert                  (Program.lean's first line)
//   import C.Cert3                 (a threaded Claims.lean's own import)
//   import C.Elab                  (Elab.lean's own import)
//   section
//   open A2 C                      (Program.lean's second line)
//   <the rest of Program.lean>
//   end
//   <Claims.lean, its imports left out>
//   <Elab.lean, its imports left out>     (from line `estart` on)
// It means what the modules mean: Program.lean's grammar (shape.nu) allows
// no option, notation, instance, namespace or attribute, so its definitions
// read the same inline as imported; the `section` ends its `open` before
// the claims, as the end of its module does; Claims.lean and Elab.lean are
// the templates byte for byte (certify writes them, verify compares them
// before Lean runs). Only lines checked to be exactly the expected ones are
// left out; anything else is none (`why`). No `.olean` passes from one
// process to the next any more.
@ __lt_combined String prog String claims ? String elab ? String caps inout String why inout i estart inout i cstart → ?String {
    : s head `import C.Cert\nopen A2 C\n`
    ? ! ( string_starts_with prog head ) {
        = why ( string_from `Program.lean does not start with its two lines 'import C.Cert' and 'open A2 C'` )
        ^ @ ?String { F }
    } {}
    : String pbody ( string_substr prog ( nurl_str_len head ) - ( string_len prog ) ( nurl_str_len head ) )
    : ~ b threads F
    : ~ String cbody ( string_new )
    ?? ( __lt_unimport claims ( __lt_v1 `import Program` ) ) {
        T c → { = cbody c }
        F → {
            ?? ( __lt_unimport claims ( __lt_v2 `import C.Cert3` `import Program` ) ) {
                T c → {
                    = cbody c
                    = threads T
                }
                F → {
                    = why ( string_from `Claims.lean's imports are not the template's` )
                    ^ @ ?String { F }
                }
            }
        }
    }
    : ~ String ebody ( string_new )
    : ~ b has_elab F
    ?? elab {
        T e → {
            ?? ( __lt_unimport e ( __lt_v2 `import Program` `import C.Elab` ) ) {
                T x → {
                    = ebody x
                    = has_elab T
                }
                F → {
                    = why ( string_from `Elab.lean's imports are not the template's` )
                    ^ @ ?String { F }
                }
            }
        }
        F → {}
    }
    : ~ String kbody ( string_new )
    : ~ b has_caps F
    // (a threaded program's Caps.lean imports C.Caps3, another's C.Caps)
    : ~ b caps3 F
    ?? caps {
        T c → {
            ?? ( __lt_unimport c ( __lt_v2 `import Program` `import C.Caps` ) ) {
                T x → {
                    = kbody x
                    = has_caps T
                }
                F → {
                    ?? ( __lt_unimport c ( __lt_v2 `import Program` `import C.Caps3` ) ) {
                        T x → {
                            = kbody x
                            = has_caps T
                            = caps3 T
                        }
                        F → {
                            = why ( string_from `Caps.lean's imports are not the template's` )
                            ^ @ ?String { F }
                        }
                    }
                }
            }
        }
        F → {}
    }
    : String o ( string_with_cap + + + + ( string_len prog ) ( string_len cbody ) ( string_len ebody ) ( string_len kbody ) 256 )
    ( string_push_str o `import C.Cert\n` )
    ? threads { ( string_push_str o `import C.Cert3\n` ) } {}
    ? has_elab { ( string_push_str o `import C.Elab\n` ) } {}
    ? has_caps { ( string_push_str o ? caps3 `import C.Caps3\n` `import C.Caps\n` ) } {}
    ( string_push_str o `section\nopen A2 C\n` )
    ( string_push_str o ( string_data pbody ) )
    ( string_push_str o `\nend\n\n` )
    ( string_push_str o ( string_data cbody ) )
    ? has_elab {
        ( string_push_str o `\n` )
        // (the line the Elab.lean part starts at: the lines so far, plus one)
        : ( Slice u ) t ( slice_of_str ( string_data o ) )
        : i n ( slice_len [u] t )
        : ~ i nl 0
        : ~ i k 0
        ~ < k n { ? == ( slice_byte t k ) 10 { = nl + nl 1 } {} = k + k 1 }
        = estart + nl 1
        ( string_push_str o ( string_data ebody ) )
    } {}
    ? has_caps {
        ( string_push_str o `\n` )
        // (the line the Caps.lean part starts at)
        : ( Slice u ) t ( slice_of_str ( string_data o ) )
        : i n ( slice_len [u] t )
        : ~ i nl 0
        : ~ i k 0
        ~ < k n { ? == ( slice_byte t k ) 10 { = nl + nl 1 } {} = k + k 1 }
        = cstart + nl 1
        ( string_push_str o ( string_data kbody ) )
    } {}
    ^ @ ?String { T o }
}

// One of Lean's messages (`lean --json`: one object a line) as the text
// the readers below take: an error or a warning as `<file>:<line>:<col>:
// <severity>: <text>`, the rest (`#print axioms`) as its text.
@ __lt_msg_text s file i line i col s sev s data → String {
    : String o ( string_new )
    ? | ( nc_is_s sev `error` ) ( nc_is_s sev `warning` ) {
        ( string_push_str o file )
        ( string_push_str o `:` )
        ( string_push_int o line )
        ( string_push_str o `:` )
        ( string_push_int o col )
        ( string_push_str o `: ` )
        ( string_push_str o sev )
        ( string_push_str o `: ` )
    } {}
    ( string_push_str o data )
    ( string_push_char o 10 )
    ^ o
}

@ nc_is_s s a s b → b { ^ != 0 ( nurl_str_eq a b ) }

// Check `bundle/Program.lean` and `bundle/Claims.lean` (and with `elab`,
// `bundle/Elab.lean`) in one Lean process: the file `__lt_combined` makes,
// in `work`, run by `lean --json` inside formal/ with formal/'s build on
// `LEAN_PATH` (`<formal>/.lake/build/lib/lean`, set in the environment, so
// that `import C.Cert` is formal/'s). Each message is the claims' (`log`) or Elab.lean's
// (`elab_log`) by its own position, not by where it comes in the output: a
// message of the file from the Elab.lean part's first line on is Elab.lean's,
// any other the claims'. Fail closed: output that cannot be placed (a line
// that is not one of Lean's messages, a message of another file or without
// a line, anything on stderr) is the claims', as an error. The claims' run
// finished when Lean exited 0, or exited 1 for errors of the Elab.lean part
// alone (they only mean that Cert.elab is not proved); Elab.lean's counts
// only on an exit 0.
@ cert_lean_check s lean s formal s bundle s work b elab → LeanRun {
    ^ ( cert_lean_check2 lean formal bundle work elab F )
}

// ... and with Caps.lean too (`caps`, N.cap): its messages, from line
// `cstart` on, are its own part (`caps_log`), as Elab.lean's are.
@ cert_lean_check2 s lean s formal s bundle s work b elab b caps → LeanRun {
    : ~ String log ( string_new )
    : String prog ( nc_join bundle `Program.lean` )
    : String claims ( nc_join bundle `Claims.lean` )
    : String all ( nc_join work `All.lean` )
    : String ptext ?? ( nc_read ( string_data prog ) ) { T x → x F → ( string_new ) }
    : String ctext ?? ( nc_read ( string_data claims ) ) { T x → x F → ( string_new ) }
    : ~ ? String etext @ ?String { F }
    ? elab {
        ?? ( nc_read ( string_data ( nc_join bundle `Elab.lean` ) ) ) {
            T x → { = etext @ ?String { T x } }
            F → {}
        }
    } {}
    : ~ ? String ktext @ ?String { F }
    ? caps {
        ?? ( nc_read ( string_data ( nc_join bundle `Caps.lean` ) ) ) {
            T x → { = ktext @ ?String { T x } }
            F → {}
        }
    } {}
    : ~ String why ( string_new )
    : ~ String text ( string_new )
    : ~ i estart 0
    : ~ i cstart 0
    ?? ( __lt_combined ptext ctext etext ktext why estart cstart ) {
        T t → { = text t }
        F → {
            ( string_push_str log ( string_data why ) )
            ^ @ LeanRun { F log F ( string_new ) F ( string_new ) }
        }
    }
    ? ! ( nc_write ( string_data all ) ( string_data text ) ) {
        ( string_push_str log `cannot write the combined Lean file ` )
        ( string_push_str log ( string_data all ) )
        ^ @ LeanRun { F log F ( string_new ) F ( string_new ) }
    } {}
    : String back ?? ( env_cwd ) { T c → c F _ → ( string_from `/` ) }
    ?? ( env_chdir formal ) {
        T _ → {}
        F _ → {
            ( string_push_str log `cannot enter the formal tree ` )
            ( string_push_str log formal )
            ^ @ LeanRun { F log F ( string_new ) F ( string_new ) }
        }
    }
    : ( Vec String ) a1 ( vec_new [String] )
    // (`lake env lean` set the same `LEAN_PATH` and cost ≈ 45 ms a run
    // before Lean started, AGORA-1029 step 9; `lean` adds its own library
    // itself. Run inside formal/, elan's `lean` picks formal/'s toolchain,
    // as its `lake` did; `LEAN_PATH` is set, not inherited: nurl-cert sets
    // it in its own environment, which Lean inherits, so no `env` program
    // stands between (there is none on a Windows PATH, AGORA-1031).)
    : String lp ( string_from formal )
    ( string_push_str lp `/.lake/build/lib/lean` )
    ?? ( env_set `LEAN_PATH` ( string_data lp ) ) {
        T _ → {}
        F _ → {
            ?? ( env_chdir ( string_data back ) ) { T _ → {} F _ → {} }
            ( string_push_str log `cannot set LEAN_PATH for Lean` )
            ^ @ LeanRun { F log F ( string_new ) F ( string_new ) }
        }
    }
    ( vec_push [String] a1 ( string_from `--json` ) )
    ( vec_push [String] a1 ( string_clone all ) )
    : Run r ( nc_run lean a1 )
    ?? ( env_chdir ( string_data back ) ) { T _ → {} F _ → {} }
    : b has_elab ?? etext { T _ → T F → F }
    : b has_caps ?? ktext { T _ → T F → F }
    : ~ String elog ( string_new )
    : ~ String klog ( string_new )
    : ( Vec String ) ls ( nc_lines ( string_data . r out ) )
    : i n ( vec_len [String] ls )
    : ~ i k 0
    // an error Lean itself placed in the claims' part
    : ~ b cerr F
    ~ < k n {
        : String l ( string_clone ( vec_at [String] ls k ) )
        ? > ( string_len ( string_trim l ) ) 0 {
            : ~ b placed F
            ?? ( json_parse ( string_data l ) ) {
                T j → {
                    : String file ?? ( json_get j `fileName` ) { T v → ( string_from ( json_as_str v ) ) F → ( string_new ) }
                    : String sev ?? ( json_get j `severity` ) { T v → ( string_from ( json_as_str v ) ) F → ( string_new ) }
                    : String data ?? ( json_get j `data` ) { T v → ( string_from ( json_as_str v ) ) F → ( string_new ) }
                    : ?i line ?? ( json_get j `pos.line` ) { T v → ( json_num_as_i v ) F → @ ?i { F 0 } }
                    : i col ?? ( json_get j `pos.column` ) { T v → ( json_as_int v ) F → 0 }
                    ?? line {
                        T ln → {
                            ? & ( string_eq file all ) | ( nc_is_s ( string_data sev ) `error` ) | ( nc_is_s ( string_data sev ) `warning` ) ( nc_is_s ( string_data sev ) `information` ) {
                                : String mt ( __lt_msg_text ( string_data file ) ln col ( string_data sev ) ( string_data data ) )
                                ? & has_caps >= ln cstart {
                                    ( string_push_str klog ( string_data mt ) )
                                } {
                                    ? & has_elab >= ln estart {
                                        ( string_push_str elog ( string_data mt ) )
                                    } {
                                        ( string_push_str log ( string_data mt ) )
                                        ? ( nc_is_s ( string_data sev ) `error` ) { = cerr T } {}
                                    }
                                }
                                = placed T
                            } {}
                        }
                        F → {}
                    }
                }
                F _ → {}
            }
            ? ! placed {
                // (fail closed: the claims', as an error)
                ( string_push_str log ( string_data all ) )
                ( string_push_str log `:0:0: error: Lean output nurl-cert cannot place: ` )
                ( string_push_str log ( string_data l ) )
                ( string_push_char log 10 )
            } {}
        } {}
        = k + k 1
    }
    ? > ( string_len ( string_trim . r err ) ) 0 {
        ( string_push_str log ( string_data all ) )
        ( string_push_str log `:0:0: error: Lean wrote to stderr: ` )
        ( string_push_str log ( string_data . r err ) )
        ( string_push_char log 10 )
    } {}
    : b ok0 & . r started == . r code 0
    // (an error in an optional part, Elab.lean's or Caps.lean's, and none in
    // the claims': the claims stand, the part is not proved)
    : b elab_failed & & & & | has_elab has_caps . r started == . r code 1 | ( cert_lean_has_error elog ) ( cert_lean_has_error klog ) ! ( cert_lean_has_error log )
    // A run that ended otherwise (killed, out of memory, an exit Lean does
    // not give for an error) with no error of Lean's in the claims' part
    // may have ended in the optional Elab.lean part: the claims are checked
    // again alone, once, and Elab.lean is not proved. (Without Elab.lean,
    // as in verify of a bundle that holds it, Cert.elab then fails.)
    ? & & | has_elab has_caps ! | ok0 elab_failed ! cerr {
        : LeanRun again ( cert_lean_check2 lean formal bundle work F F )
        : String note ( string_from `the Lean run ended abnormally (exit ` )
        ( string_push_int note . r code )
        ( string_push_str note `) before the Elab.lean part was checked; the claims were checked again alone` )
        ^ @ LeanRun { . again ran . again log F note F ( string_new ) }
    } {}
    // (each optional part ran when the run did and held no error of its
    // own: a failed Caps.lean part leaves Elab.lean's proof standing)
    : b ran_ok | ok0 elab_failed
    : b eran & & ran_ok has_elab ! ( cert_lean_has_error elog )
    : b kran & & ran_ok has_caps ! ( cert_lean_has_error klog )
    ^ @ LeanRun { ran_ok log eran elog kran klog }
}

// Lean proved `Cert.elab` on the standard axioms alone: the run exited 0,
// reported no error, and `#print axioms` lists no other axiom.
// Caps.lean (N.cap) proved: its part ran with no error, and Lean lists
// `Cert.n_cap`'s axioms (which the status is read off).
@ cert_caps_proved LeanRun lr → b {
    ? | ! . lr caps_ran ( cert_lean_has_error . lr caps_log ) { ^ F } {}
    ^ ?? ( cert_lean_axioms . lr caps_log `Cert.n_cap` ) { T _ → T F → F }
}

@ cert_elab_proved LeanRun lr → b {
    ? | ! . lr elab_ran ( cert_lean_has_error . lr elab_log ) { ^ F } {}
    ^ ?? ( cert_lean_axioms . lr elab_log `Cert.elab` ) {
        T ax → ( cert_axioms_std ( cert_axiom_list ax ) )
        F → F
    }
}

// ── Reading the run ──────────────────────────────────────────────────

@ cert_lean_has_error String log → b { ^ ( string_contains log `: error` ) }

// Does the kernel prove that the checker refuses the program in `bundle`
// (`C.certOK2B P entry 1 = false`, or A3's `C.certOK3B P spawns entry 1`)?
// Lean explains a failed `decide +kernel` by reducing the proposition again
// in the elaborator, and certify reads that explanation ("… is false"). On
// a term too deep for the elaborator the explanation fails too, and only
// the kernel's own mismatch is left, which would also be what a reduction
// that got stuck leaves (AGORA-1034). So a refusal is not read off that
// message: it is proved, in a run of its own, or the verdict stays an
// error. Program.lean has passed the grammar check (shape.nu) before.
@ cert_lean_refutes s lean s formal s bundle s work b threads → b {
    : String ptext ?? ( nc_read ( string_data ( nc_join bundle `Program.lean` ) ) ) { T x → x F → { ^ F } }
    : String o ( string_new )
    ? threads { ( string_push_str o `import C.Cert3
` ) } {}
    ( string_push_str o ( string_data ptext ) )
    ? threads {
        ( string_push_str o `
theorem refuted : C.certOK3B P spawns entry 1 = false := by decide +kernel
` )
    } {
        ( string_push_str o `
theorem refuted : C.certOK2B P entry 1 = false := by decide +kernel
` )
    }
    : String file ( nc_join work `Refute.lean` )
    ? ! ( nc_write ( string_data file ) ( string_data o ) ) { ^ F } {}
    : String back ?? ( env_cwd ) { T c → c F _ → ( string_from `/` ) }
    ?? ( env_chdir formal ) { T _ → {} F _ → { ^ F } }
    : String lp ( string_from formal )
    ( string_push_str lp `/.lake/build/lib/lean` )
    : b set ?? ( env_set `LEAN_PATH` ( string_data lp ) ) { T _ → T F _ → F }
    : ( Vec String ) a ( vec_new [String] )
    ( vec_push [String] a ( string_from `--json` ) )
    ( vec_push [String] a ( string_clone file ) )
    : Run r ? set ( nc_run lean a ) @ Run { F -1 ( string_new ) ( string_new ) }
    ?? ( env_chdir ( string_data back ) ) { T _ → {} F _ → {} }
    // proved: Lean exited 0, wrote no error and nothing on stderr
    ^ & & & . r started == . r code 0 ! ( string_contains . r out `\"severity\":\"error\"` ) == 0 ( string_len . r err )
}

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
