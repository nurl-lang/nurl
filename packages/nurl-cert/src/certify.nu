// certify.nu — `nurl-cert certify`: one program to a certificate bundle.
//
//   prog.cert/
//     Program.core    nurlc's core IR of the program (the translation's input)
//     Program.lean    the program as a term of formal/A2 (P, entry)
//     Claims.lean     the claims, stated and proved (only when the checker
//                     accepts; see claims.nu)
//     manifest.json   statuses, coverage, hashes, versions, trust ledger
//
// Fail closed: a program the translation does not cover is `unsupported`,
// one the checker refuses is `refused`, and neither gets a Claims.lean or
// a claim above `open`. A claim's status is read off what Lean reports for
// it (lean.nu), never assumed.

$ `util.nu`
$ `claims.nu`
$ `shape.nu`
$ `lean.nu`
$ `manifest.nu`

: s NURLCERT_VERSION ( pkg_version )

: CertOpts {
    String src
    String out
    String prof
    String nurlc
    String formal
    String tolean
    String lake
    String binary
    String stdlib
}

// ── The translation (one interface) ──────────────────────────────────
//
// `.core` text in, Program.lean out. Until the translator written in NURL
// lands (AGORA-1020), this calls the Python prototype tools/ncore/tolean.py
// unchanged and only rewrites its frame: the import (C.Cert, which has the
// claims' lemmas) and the `#eval` line (the claims replace it). The shape
// check in shape.nu then holds the result to the program grammar.

: Translated {
    b ok
    String lean
    String why
}

@ __ct_reframe s text → String {
    : ( Vec String ) ls ( nc_lines text )
    : String o ( string_with_cap + ( nurl_str_len text ) 16 )
    : i n ( vec_len [String] ls )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] ls k ) {
            T l → {
                ? ( string_starts_with l `#eval ` ) {} {
                    ? ( nc_is l `import C.A2Prog` ) {
                        ( string_push_str o `import C.Cert` )
                    } {
                        ( string_push_str o ( string_data l ) )
                    }
                    ( string_push_char o 10 )
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ o
}

@ cert_translate s tolean s core_path → Translated {
    : ( Vec String ) a ( vec_new [String] )
    ( vec_push [String] a ( string_from tolean ) )
    ( vec_push [String] a ( string_from core_path ) )
    : Run r ( nc_run `python3` a )
    ? ! . r started { ^ @ Translated { F ( string_new ) ( string_clone . r err ) } } {}
    ? != . r code 0 {
        : ~ String why ( string_trim . r err )
        ? ( string_starts_with why `unsupported: ` ) { = why ( string_substr why 13 - ( string_len why ) 13 ) } {}
        ? == 0 ( string_len why ) { ^ @ Translated { F ( string_new ) ( string_from `the translator failed` ) } } {}
        ^ @ Translated { F ( string_new ) why }
    } {}
    ^ @ Translated { T ( __ct_reframe ( string_data . r out ) ) ( string_new ) }
}

// ── What nurlc says ──────────────────────────────────────────────────

// `source <path>` lines of a `--list-sources` run.
@ __ct_sources String err → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ( Vec String ) ls ( nc_lines ( string_data err ) )
    : i n ( vec_len [String] ls )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] ls k ) {
            T l → {
                ? ( string_starts_with l `source ` ) {
                    ( vec_push [String] out ( string_substr l 7 - ( string_len l ) 7 ) )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

// `--unsafe-report` lines: `file:line what`, a colon and digits and then a
// space (a diagnostic has `file:line:col:`), or `unsafe: none …`.
@ __ct_is_report_line String l → b {
    : ( Slice u ) t ( slice_of_str ( string_data l ) )
    : i n ( slice_len [u] t )
    : ~ i k 0
    ~ < k n {
        ? == ( slice_byte t k ) 58 {
            : ~ i e + k 1
            ~ & < e n & >= ( slice_byte t e ) 48 <= ( slice_byte t e ) 57 { = e + e 1 }
            ? & > e + k 1 & < e n == ( slice_byte t e ) 32 { ^ T } {}
        } {}
        = k + k 1
    }
    ^ F
}

@ __ct_unsafe_rows String err → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ( Vec String ) ls ( nc_lines ( string_data err ) )
    : i n ( vec_len [String] ls )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] ls k ) {
            T l → { ? ( __ct_is_report_line l ) { ( vec_push [String] out ( string_clone l ) ) } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

// The program's own functions in the core IR (`fn` lines whose source is
// not the standard library's): name, file, line.
: FnRow {
    String name
    String file
    String line
}

@ __ct_is_lib String f → b {
    ^ | ( string_starts_with f `stdlib/` ) ( string_contains f `/stdlib/` )
}

@ __ct_functions s core → ( Vec FnRow ) {
    : ( Vec FnRow ) out ( vec_new [FnRow] )
    : ( Vec String ) ls ( nc_lines core )
    : i n ( vec_len [String] ls )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] ls k ) {
            T l → {
                ? ( string_starts_with l `fn	` ) {
                    : ( Vec String ) c ( string_split l `	` )
                    ? >= ( vec_len [String] c ) 6 {
                        : String name ?? ( vec_get [String] c 1 ) { T x → ( string_clone x ) F → ( string_new ) }
                        : String line ?? ( vec_get [String] c 4 ) { T x → ( string_clone x ) F → ( string_new ) }
                        : String file ?? ( vec_get [String] c 5 ) { T x → ( string_clone x ) F → ( string_new ) }
                        ? ! ( __ct_is_lib file ) { ( vec_push [FnRow] out @ FnRow { name file line } ) } {}
                    } {}
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

@ __ct_first_line String s → String {
    : ( Vec String ) ls ( nc_lines ( string_data s ) )
    ^ ?? ( vec_get [String] ls 0 ) { T l → ( string_trim l ) F → ( string_new ) }
}

// ── The ledger ───────────────────────────────────────────────────────

@ __ct_ledger s prof ( Vec String ) unsafe_rows → Json {
    : Json L ( json_arr_new )
    ( json_arr_push L ( mj_row `lean-kernel` `the Lean 4 kernel and the toolchain formal/lean-toolchain pins`
    `it checks every proof in Program.lean and Claims.lean` `formal/lean-toolchain` `the Lean developers` `M.safe M.leak` ) )
    ? != 0 ( nurl_str_eq prof `fast` ) {
        ( json_arr_push L ( mj_row `lean-compiler` `the Lean compiler and its runtime (native_decide)`
        `under the fast profile the checker's verdict is computed by compiled code, not by the kernel`
        `Claims.lean, theorem Cert.verdict` `the Lean developers` `M.safe M.leak` ) )
    } {}
    ( json_arr_push L ( mj_row `claim-definitions` `the claims' definitions: A2's semantics (A2.Steps, A2.Stuck, A2.emptyMem, Mem.alloc)`
    `a claim means what these definitions say; formal/CLAIM.md is their review document`
    `formal/CLAIM.md, formal/A2/Semantics.lean` `the NURL formal model (claude-formal)` `M.safe M.leak` ) )
    ( json_arr_push L ( mj_row `translation` `the translation from source to the Lean term: nurlc --emit-core, then tools/ncore/tolean.py`
    `nothing yet proves that P is the program the source describes (AGORA-1020 moves it inside the kernel's sight)`
    `compiler/nurlc.nu (--emit-core), tools/ncore/tolean.py` `nurl-cert's translator (untrusted, tested by tolean_selftest.sh)` `M.safe M.leak` ) )
    ( json_arr_push L ( mj_row `library-summaries` `the standard library as the term has it: its calls are A2 primitives and declared summaries`
    `the library's unsafe base follows formal/B's models by inspection, not by proof (AGORA-1014 ties each to its theorem)`
    `tools/ncore/tolean.py, tools/ncore/prims.py, formal/B` `the NURL formal model (claude-formal)` `M.safe M.leak` ) )
    ( json_arr_push L ( mj_row `llvm` `LLVM: the IR to machine code` `the claims are about the program's model; phase D validates the drops, nothing proves codegen`
    `the LLVM IR hash in this manifest` `the LLVM project` `M.safe M.leak` ) )
    ( json_arr_push L ( mj_row `linker` `the linker` `it joins the program with the C runtime` `the build` `the toolchain's linker` `M.safe M.leak` ) )
    ( json_arr_push L ( mj_row `os` `the operating system` `memory, threads and files are the kernel's` `the host` `the OS vendor` `M.safe M.leak` ) )
    ( json_arr_push L ( mj_row `c-runtime` `the C runtime the program links against` `allocation, I/O and panics go through it`
    `stdlib/runtime*.c` `the NURL project` `M.safe M.leak` ) )
    ( json_arr_push L ( mj_row `unsafe-report` `nurlc --unsafe-report: the program's own hand-vouched code`
    `M.unsafe is what this report says, not a theorem` `compiler/nurlc.nu (--unsafe-report)` `nurlc` `M.unsafe` ) )
    : i n ( vec_len [String] unsafe_rows )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] unsafe_rows k ) {
            T r → {
                : String id ( string_from `unsafe-` )
                ( string_push_int id + k 1 )
                ( json_arr_push L ( mj_row ( string_data id ) ( string_data r ) `the program vouches for this by hand (unsafe), no rule checks it`
                ( string_data r ) `the program's author` `M.unsafe M.safe M.leak` ) )
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ L
}

// ── Certify ──────────────────────────────────────────────────────────

@ __ct_claim s id s lean s status s en s fi s reason ( Vec String ) axioms s premises → Json {
    : Json c ( json_obj_new )
    ( mj_str c `id` id )
    ( mj_str c `lean` lean )
    ( mj_str c `status` status )
    : Json sen ( json_obj_new )
    ( mj_str sen `en` en )
    ( mj_str sen `fi` fi )
    ( mj_set c `sentence` sen )
    ( mj_str c `reason` reason )
    ( mj_set c `axioms` ( mj_strs axioms ) )
    : String ps ( string_from premises )
    ( mj_set c `premises` ( mj_strs ( string_split ps ` ` ) ) )
    ^ c
}

@ __ct_fail s msg → i {
    ( nurl_eprint `nurl-cert: ` )
    ( nurl_eprintln msg )
    ^ 1
}

@ cert_certify CertOpts o → i {
    : s out ( string_data . o out )
    : s src ( string_data . o src )
    : s prof ( string_data . o prof )
    ? ! ( nc_mkdirs out ) { ^ ( __ct_fail `cannot create the bundle directory` ) } {}
    // A bundle is written whole or not at all: an old Claims.lean must not
    // survive next to a manifest that says the program is now refused.
    ?? ( file_delete ( string_data ( nc_join out `Claims.lean` ) ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( string_data ( nc_join out `manifest.json` ) ) ) { T _ → {} F _ → {} }

    // nurlc runs from the standard library's root: the core IR then names
    // the library's files `stdlib/…`, which is how the translation tells
    // the library from the program (the source path is absolute).
    : String back ?? ( env_cwd ) { T c → c F _ → ( string_from `/` ) }
    ?? ( env_chdir ( string_data . o stdlib ) ) {
        T _ → {}
        F _ → { ^ ( __ct_fail `cannot enter the standard library's root (--stdlib / $NURL_STDLIB)` ) }
    }

    // 1. nurlc: the core IR and the files it read.
    : ( Vec String ) a1 ( vec_new [String] )
    ( vec_push [String] a1 ( string_from `--emit-core` ) )
    ( vec_push [String] a1 ( string_from `--list-sources` ) )
    ( vec_push [String] a1 ( string_from src ) )
    : Run r1 ( nc_run ( string_data . o nurlc ) a1 )
    ? | ! . r1 started != . r1 code 0 {
        ( nurl_eprint ( string_data . r1 err ) )
        ^ ( __ct_fail `nurlc did not compile the program; nothing to certify` )
    } {}
    : String core_path ( nc_join out `Program.core` )
    ? ! ( nc_write ( string_data core_path ) ( string_data . r1 out ) ) { ^ ( __ct_fail `cannot write Program.core` ) } {}
    : ( Vec String ) sources ( __ct_sources . r1 err )
    ( nc_sort sources )

    // 2. nurlc: the LLVM IR and the unsafe report.
    : ( Vec String ) a2 ( vec_new [String] )
    ( vec_push [String] a2 ( string_from `--unsafe-report` ) )
    ( vec_push [String] a2 ( string_from src ) )
    : Run r2 ( nc_run ( string_data . o nurlc ) a2 )
    ? ! . r2 started { ^ ( __ct_fail `nurlc did not start` ) } {}
    // nurlc's own borrow walk may refuse a program the core IR still
    // describes: it has no LLVM IR then, and its unsafe report is cut short.
    : b compiled == . r2 code 0
    : String llvm_sha ? compiled ( nc_sha256_text ( string_data . r2 out ) ) ( string_new )
    : ( Vec String ) unsafe_rows ( __ct_unsafe_rows . r2 err )

    : ( Vec String ) a3 ( vec_new [String] )
    ( vec_push [String] a3 ( string_from `--version` ) )
    : Run r3 ( nc_run ( string_data . o nurlc ) a3 )
    : String nurlc_ver ( __ct_first_line . r3 out )
    ?? ( env_chdir ( string_data back ) ) { T _ → {} F _ → {} }

    // 3. The translation, held to the program grammar.
    : ~ String verdict ( string_from `accepted` )
    : ~ String reason ( string_new )
    : Translated tr ( cert_translate ( string_data . o tolean ) ( string_data core_path ) )
    : String prog_path ( nc_join out `Program.lean` )
    : String claims_path ( nc_join out `Claims.lean` )
    : ~ i nv 0
    ? . tr ok {
        : ShapeRes sh ( cert_shape ( string_data . tr lean ) )
        ? . sh ok {
            = nv . sh nv
        } {
            = verdict ( string_from `unsupported` )
            = reason ( string_from `the translator's output is outside the program grammar: ` )
            ( string_push_str reason ( string_data . sh why ) )
        }
    } {
        = verdict ( string_from `unsupported` )
        = reason ( string_clone . tr why )
    }
    ?? ( file_delete ( string_data prog_path ) ) { T _ → {} F _ → {} }
    : b wrote_prog ( nc_is verdict `accepted` )
    ? wrote_prog {
        ? ! ( nc_write ( string_data prog_path ) ( string_data . tr lean ) ) { ^ ( __ct_fail `cannot write Program.lean` ) } {}
    } {}

    // 4. Lean: the claims, checked.
    : String formal ( string_clone . o formal )
    : ( Vec ( Vec String ) ) axioms ( vec_new [( Vec String )] )
    : ( Vec String ) statuses ( vec_new [String] )
    : i nclaims ( cert_claim_count )
    ? ( nc_is verdict `accepted` ) {
        : String claims ( cert_claims_lean prof nv )
        ? ! ( nc_write ( string_data claims_path ) ( string_data claims ) ) { ^ ( __ct_fail `cannot write Claims.lean` ) } {}
        : String work ( nc_join out `.build` )
        // A fresh directory: an .olean the bundle brought must not stand in
        // for the one compiled from its Program.lean.
        ?? ( dir_remove_all ( string_data work ) ) { T _ → {} F _ → {} }
        ( nc_mkdirs ( string_data work ) )
        : LeanRun lr ( cert_lean_check ( string_data . o lake ) ( string_data formal ) out ( string_data work ) )
        ?? ( dir_remove_all ( string_data work ) ) { T _ → {} F _ → {} }
        ? ( cert_lean_refused . lr log ) {
            = verdict ( string_from `refused` )
            = reason ( string_from `the verified checker refuses the program (C.certOK2B is false)` )
        } {
            ? | ! . lr ran ( cert_lean_has_error . lr log ) {
                = verdict ( string_from `error` )
                = reason ( string_from `Lean did not check the claims: ` )
                ( string_push_str reason ( string_data ( __ct_first_line . lr log ) ) )
                ( nurl_eprint ( string_data . lr log ) )
            } {}
        }
        : ~ i k 0
        ~ < k nclaims {
            ?? ( cert_lean_axioms . lr log ( cert_claim_lean k ) ) {
                T ax → {
                    : ( Vec String ) al ( cert_axiom_list ax )
                    ? ( nc_is verdict `accepted` ) {
                        ( vec_push [String] statuses ( string_from ( cert_status_of prof al ) ) )
                    } { ( vec_push [String] statuses ( string_from `open` ) ) }
                    ( vec_push [( Vec String )] axioms al )
                }
                F → {
                    ( vec_push [String] statuses ( string_from `open` ) )
                    ( vec_push [( Vec String )] axioms ( vec_new [String] ) )
                }
            }
            = k + k 1
        }
        ? ! ( nc_is verdict `accepted` ) {
            // No proved claim may stand next to a refusal.
            ?? ( file_delete ( string_data claims_path ) ) { T _ → {} F _ → {} }
        } {}
    } {
        : ~ i k 0
        ~ < k nclaims {
            ( vec_push [String] statuses ( string_from `open` ) )
            ( vec_push [( Vec String )] axioms ( vec_new [String] ) )
            = k + k 1
        }
    }

    // 5. The manifest.
    : Json m ( json_obj_new )
    ( mj_str m `schema` CERT_SCHEMA )
    : Json tool ( json_obj_new )
    ( mj_str tool `name` `nurl-cert` )
    ( mj_str tool `version` NURLCERT_VERSION )
    ( mj_set m `tool` tool )
    ( mj_str m `profile` prof )
    : Json pg ( json_obj_new )
    ( mj_str pg `source` src )
    ( mj_str pg `verdict` ( string_data verdict ) )
    ( mj_str pg `reason` ( string_data reason ) )
    ( mj_int pg `slots` nv )
    ( mj_set m `program` pg )

    : Json cl ( json_arr_new )
    : ~ i k 0
    ~ < k nclaims {
        : String st ?? ( vec_get [String] statuses k ) { T x → ( string_clone x ) F → ( string_from `open` ) }
        : ( Vec String ) ax ?? ( vec_get [( Vec String )] axioms k ) { T x → ( vec_clone [String] x ) F → ( vec_new [String] ) }
        : String why ? ( nc_is st `open` ) ( string_clone reason ) ( string_new )
        : String prem ( string_from `lean-kernel claim-definitions translation library-summaries` )
        ? != 0 ( nurl_str_eq prof `fast` ) { ( string_push_str prem ` lean-compiler` ) } {}
        ( json_arr_push cl ( __ct_claim ( cert_claim_id k ) ( cert_claim_lean k ) ( string_data st )
        ( cert_claim_sentence k ) ( cert_claim_sentence_fi k ) ( string_data why ) ax ( string_data prem ) ) )
        = k + k 1
    }
    // M.unsafe: what nurlc's report says.
    : i nu ( vec_len [String] unsafe_rows )
    : String uen ? == nu 0 ( string_from `It contains no hand-vouched (unsafe) code outside the standard library.` )
    ( string_from `It contains hand-vouched (unsafe) code outside the standard library: see the ledger rows unsafe-*.` )
    : String ufi ? == nu 0 ( string_from `Siinä ei ole käsin taattua (unsafe) koodia vakiokirjaston ulkopuolella.` )
    ( string_from `Siinä on käsin taattua (unsafe) koodia vakiokirjaston ulkopuolella: katso rivit unsafe-*.` )
    : s ust ? compiled `assumed` `open`
    : s uwhy ? compiled `nurlc --unsafe-report` `nurlc refuses to compile the program, so its unsafe report is incomplete`
    ( json_arr_push cl ( __ct_claim `M.unsafe` `` ust ( string_data uen ) ( string_data ufi )
    uwhy ( vec_new [String] ) `unsafe-report` ) )
    ( mj_set m `claims` cl )

    // Coverage: the program's own functions.
    : ( Vec FnRow ) fns ( __ct_functions ( string_data . r1 out ) )
    : Json cov ( json_obj_new )
    : Json fa ( json_arr_new )
    : i nf ( vec_len [FnRow] fns )
    : String fst ? ( nc_is verdict `accepted` ) ( string_from `proved` ) ( string_clone verdict )
    : ~ i j 0
    ~ < j nf {
        ?? ( vec_get [FnRow] fns j ) {
            T f → {
                : Json fo ( json_obj_new )
                ( mj_str fo `name` ( string_data . f name ) )
                ( mj_str fo `file` ( string_data . f file ) )
                ( mj_str fo `line` ( string_data . f line ) )
                ( mj_str fo `status` ( string_data fst ) )
                ( mj_str fo `reason` ( string_data reason ) )
                ( json_arr_push fa fo )
            }
            F _ → {}
        }
        = j + j 1
    }
    ( mj_set cov `functions` fa )
    ( mj_int cov ( string_data fst ) nf )
    ( mj_set m `coverage` cov )

    // Hashes.
    : Json hs ( json_obj_new )
    : Json sa ( json_arr_new )
    : i ns ( vec_len [String] sources )
    : ~ i q 0
    ~ < q ns {
        ?? ( vec_get [String] sources q ) {
            T p → {
                : Json so ( json_obj_new )
                ( mj_str so `path` ( string_data p ) )
                ?? ( nc_sha256_file ( string_data p ) ) {
                    T h → ( mj_str so `sha256` ( string_data h ) )
                    F → ( mj_str so `sha256` `unreadable` )
                }
                ( json_arr_push sa so )
            }
            F _ → {}
        }
        = q + q 1
    }
    ( mj_set hs `sources` sa )
    ( mj_str hs `core_ir` ( string_data ( nc_sha256_text ( string_data . r1 out ) ) ) )
    ? compiled { ( mj_str hs `llvm_ir` ( string_data llvm_sha ) ) } {}
    ? wrote_prog { ( mj_str hs `program_lean` ( string_data ( nc_sha256_text ( string_data . tr lean ) ) ) ) } {}
    ? ( nc_is verdict `accepted` ) {
        ?? ( nc_sha256_file ( string_data claims_path ) ) {
            T h → ( mj_str hs `claims_lean` ( string_data h ) )
            F → {}
        }
    } {}
    ? > ( string_len . o binary ) 0 {
        : Json bo ( json_obj_new )
        ( mj_str bo `path` ( string_data . o binary ) )
        ?? ( nc_sha256_file ( string_data . o binary ) ) {
            T h → ( mj_str bo `sha256` ( string_data h ) )
            F → { ^ ( __ct_fail `cannot read the binary given with --binary` ) }
        }
        ( mj_set hs `binary` bo )
    } {}
    ( mj_set m `hashes` hs )

    // Versions.
    : Json vs ( json_obj_new )
    ( mj_str vs `nurlc` ( string_data nurlc_ver ) )
    ( mj_str vs `formal_tree` ( string_data ( cert_formal_hash ( string_data formal ) ) ) )
    : ( Vec String ) ga ( vec_new [String] )
    ( vec_push [String] ga ( string_from `-C` ) )
    ( vec_push [String] ga ( string_clone formal ) )
    ( vec_push [String] ga ( string_from `rev-parse` ) )
    ( vec_push [String] ga ( string_from `HEAD` ) )
    : Run gr ( nc_run `git` ga )
    : String commit ? & . gr started == . gr code 0 ( __ct_first_line . gr out ) ( string_new )
    ( mj_str vs `formal_commit` ( string_data commit ) )
    : String tc_path ( nc_join ( string_data formal ) `lean-toolchain` )
    : String tc ?? ( nc_read ( string_data tc_path ) ) { T t → ( string_trim t ) F → ( string_new ) }
    ( mj_str vs `lean_toolchain` ( string_data tc ) )
    ( mj_set m `versions` vs )

    ( mj_set m `ledger` ( __ct_ledger prof unsafe_rows ) )

    : String text ( json_pretty m )
    ( string_push_char text 10 )
    ? ! ( nc_write ( string_data ( nc_join out `manifest.json` ) ) ( string_data text ) ) { ^ ( __ct_fail `cannot write manifest.json` ) } {}

    ( nurl_print ( string_data verdict ) )
    ? > ( string_len reason ) 0 { ( nurl_print `: ` ) ( nurl_print ( string_data reason ) ) } {}
    ( nurl_print `\n` )
    ? ( nc_is verdict `accepted` ) {
        : ~ b all T
        : ~ i z 0
        ~ < z nclaims {
            ?? ( vec_get [String] statuses z ) {
                T st → {
                    ( nurl_print `  ` )
                    ( nurl_print ( cert_claim_id z ) )
                    ( nurl_print ` ` )
                    ( nurl_println ( string_data st ) )
                    ? ( nc_is st `open` ) { = all F } {}
                }
                F _ → {}
            }
            = z + z 1
        }
        ^ ? all 0 1
    } {}
    ? ( nc_is verdict `refused` ) { ^ 3 } {}
    ? ( nc_is verdict `unsupported` ) { ^ 2 } {}
    ^ 1
}
