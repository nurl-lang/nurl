// verify.nu — `nurl-cert verify prog.cert [--binary prog]`.
//
// Re-checks a bundle without nurlc: every hash again, Claims.lean written
// again from the template and compared byte for byte, Program.lean held to
// the program grammar, Elab.lean (when the manifest records it) made again
// from Program.core and compared byte for byte, the proofs checked again by Lean against formal/
// (whose tree must hash to what the manifest pins), `#print axioms` read
// again, and every claim's status recomputed and compared with the
// manifest's. Exit 0 only when all of it agrees; each disagreement is
// printed, so a tampered bundle says what was tampered with.

$ `util.nu`
$ `claims.nu`
$ `shape.nu`
$ `lean.nu`
$ `manifest.nu`
$ `certify.nu`
$ `caps.nu`

: VerOpts {
    String bundle
    String binary
    String formal
    String lean
    b rebuild
    String nurlc
    String stdlib
}

: Tally {
    i bad
}

@ __vf_ok s what → v {
    ( nurl_print `  ok    ` )
    ( nurl_println what )
}

@ __vf_bad inout Tally t s what s detail → v {
    ( nurl_print `  FAIL  ` )
    ( nurl_print what )
    ? > ( nurl_str_len detail ) 0 { ( nurl_print `: ` ) ( nurl_print detail ) } {}
    ( nurl_print `\n` )
    = . t bad + . t bad 1
}

@ __vf_check inout Tally t b good s what s detail → v {
    ? good { ( __vf_ok what ) } { ( __vf_bad t what detail ) }
}

@ __vf_path s pre i k s post → String {
    : String p ( string_from pre )
    ( string_push_int p k )
    ( string_push_str p post )
    ^ p
}

// A file in the bundle hashes to the manifest's `hashes.<key>`.
@ __vf_hash inout Tally t Json m s bundle s file s key → v {
    : String kp ( string_from `hashes.` )
    ( string_push_str kp key )
    : String want ( mj_get_str m ( string_data kp ) )
    : String path ( nc_join bundle file )
    : String what ( string_from file )
    ( string_push_str what ` hashes as recorded` )
    ?? ( nc_sha256_file ( string_data path ) ) {
        T h → ( __vf_check t ( string_eq h want ) ( string_data what ) `the file was changed` )
        F → ( __vf_bad t ( string_data what ) `missing` )
    }
}

@ cert_verify VerOpts o → i {
    : s bundle ( string_data . o bundle )
    : ~ Tally t @ Tally { 0 }
    : String mpath ( nc_join bundle `manifest.json` )
    : String mtext ?? ( nc_read ( string_data mpath ) ) {
        T x → x
        F → {
            ( nurl_eprint `nurl-cert: no manifest.json in ` )
            ( nurl_eprintln bundle )
            ^ 2
        }
    }
    : Json m ?? ( json_parse ( string_data mtext ) ) {
        T j → j
        F _ → {
            ( nurl_eprintln `nurl-cert: manifest.json is not JSON` )
            ^ 2
        }
    }
    ( nurl_print `verifying ` )
    ( nurl_println bundle )
    : String schema ( mj_get_str m `schema` )
    ( __vf_check t ( nc_is schema CERT_SCHEMA ) `the manifest's schema is nurl-cert/2` ( string_data schema ) )
    : String prof ( mj_get_str m `profile` )
    ( __vf_check t ( cert_profile_ok ( string_data prof ) ) `the profile is kernel or fast` ( string_data prof ) )
    // A threaded program's claims are A3's (one more, M.race): it is
    // threaded when its Program.lean, held to the grammar, names spawns.
    // A conditional certificate names assumed functions (C.Complete).
    : String ptext0 ?? ( nc_read ( string_data ( nc_join bundle `Program.lean` ) ) ) { T x → x F → ( string_new ) }
    : ShapeRes sh0 ( cert_shape ptext0 )
    : b threads & . sh0 ok . sh0 threads
    : b cond & . sh0 ok > ( vec_len [i] . sh0 assumed ) 0
    // The bundle's term is the kernel's (Elab.lean, Cert.elab) when the
    // manifest records Elab.lean's hash; the translation ledger row then
    // says so, and the files must be there. Otherwise there is no Elab.lean
    // and the row is the translator's.
    : b elab ( __vf_has m `hashes.elab_lean` )
    // (the encodings the kernel's term rests on, read off Program.lean as
    // certify reads them: their ledger rows and premises)
    : ~ ( Vec String ) enc ( vec_new [String] )
    ? elab { = enc ( cert_enc_ids ( string_data ptext0 ) ) } {}
    // For a conditional bundle, reconstruct each assumed function's ledger
    // row from Program.lean (stub signature, callees, hasThru), Program.core
    // (name, file:line) and coverage.functions (reason).
    : ( Vec AssumedRow ) assumed_rows ( vec_new [AssumedRow] )
    : ( Vec String ) assumed_ids ( vec_new [String] )
    : ~ b assumed_ok T
    ? cond {
        : String core0 ?? ( nc_read ( string_data ( nc_join bundle `Program.core` ) ) ) { T x → x F → ( string_new ) }
        : ( Vec FnRow ) fns0 ( cert_functions ( string_data core0 ) )
        : i nf0 ( vec_len [FnRow] fns0 )
        : i na0 ( vec_len [i] . sh0 assumed )
        : ~ i ai 0
        ~ < ai na0 {
            : i idx ( vec_at [i] . sh0 assumed ai )
            ? | < idx 0 >= idx nf0 {
                = assumed_ok F
            } {
                : FnRow fr ( vec_at [FnRow] fns0 idx )
                : StubRead sr ( cert_stub_read ptext0 idx )
                ? ! . sr ok {
                    = assumed_ok F
                } {
                    : String cstr ( string_new )
                    : i ncal ( vec_len [i] . sr callees )
                    : ~ i ci 0
                    ~ < ci ncal {
                        ? > ci 0 { ( string_push_str cstr `, ` ) } {}
                        : i g ( vec_at [i] . sr callees ci )
                        ? & >= g 0 < g nf0 {
                            ( string_push_str cstr ( string_data . ( vec_at [FnRow] fns0 g ) name ) )
                        } {
                            ( string_push_str cstr `fn` )
                            ( string_push_int cstr g )
                        }
                        = ci + ci 1
                    }
                    : String loc ( string_clone . fr file )
                    ( string_push_str loc `:` )
                    ( string_push_str loc ( string_data . fr line ) )
                    // Find this function's reason in coverage.functions (must be `unsupported`).
                    : ~ String why ( string_new )
                    : ~ b found_cov F
                    : ~ i fi 0
                    ~ ( __vf_has m ( string_data ( __vf_path `coverage.functions.` fi `` ) ) ) {
                        : String cn ( mj_get_str m ( string_data ( __vf_path `coverage.functions.` fi `.name` ) ) )
                        ? ( string_eq cn . fr name ) {
                            : String cst ( mj_get_str m ( string_data ( __vf_path `coverage.functions.` fi `.status` ) ) )
                            ? ( nc_is cst `unsupported` ) {
                                = why ( mj_get_str m ( string_data ( __vf_path `coverage.functions.` fi `.reason` ) ) )
                                = found_cov T
                            } {}
                            break
                        } {}
                        = fi + fi 1
                    }
                    ? ! found_cov { = assumed_ok F } {}
                    ( vec_push [AssumedRow] assumed_rows @ AssumedRow {
                        idx ( string_clone . fr name ) . sr sig cstr . sr has_thru why loc
                    } )
                    ( vec_push [String] assumed_ids ( cert_assumed_id ( string_data . fr name ) ) )
                }
            }
            = ai + ai 1
        }
        ( __vf_check t & assumed_ok ! elab `assumed functions in Program.lean match Program.core and coverage.functions` `` )
    } {}
    // N.cap is proved in the bundle when the manifest records Caps.lean's
    // hash (AGORA-1013): Caps.lean, caps.tsv and `capabilities` are there
    : b caps ( __vf_has m `hashes.caps_lean` )
    ( __vf_structure t m ( string_data prof ) threads cond elab enc assumed_ids assumed_rows caps )

    // The sources.
    : ~ i k 0
    : ~ b more T
    : ~ b srcs_ok T
    : ~ String src_detail ( string_new )
    ~ more {
        : String pk ( __vf_path `hashes.sources.` k `.path` )
        ?? ( json_get m ( string_data pk ) ) {
            T pj → {
                : String p ( string_from ( json_as_str pj ) )
                : String want ( mj_get_str m ( string_data ( __vf_path `hashes.sources.` k `.sha256` ) ) )
                ?? ( nc_sha256_file ( string_data p ) ) {
                    T h → {
                        ? ! ( string_eq h want ) {
                            = srcs_ok F
                            = src_detail ( string_clone p )
                            ( string_push_str src_detail ` changed` )
                        } {}
                    }
                    F → {
                        = srcs_ok F
                        = src_detail ( string_clone p )
                        ( string_push_str src_detail ` missing` )
                    }
                }
                = k + k 1
            }
            F → { = more F }
        }
    }
    : String srcs_what ( string_from `every source file hashes as recorded (` )
    ( string_push_int srcs_what k )
    ( string_push_str srcs_what `)` )
    ( __vf_check t & srcs_ok > k 0 ( string_data srcs_what ) ( string_data src_detail ) )

    ( __vf_hash t m bundle `Program.core` `core_ir` )

    // formal/ at the pinned tree.
    : String fwant ( mj_get_str m `versions.formal_tree` )
    : String fhave ( cert_formal_hash ( string_data . o formal ) )
    ( __vf_check t ( string_eq fwant fhave ) `formal/ is the tree the certificate was made against` ( string_data . o formal ) )

    // The binary.
    ? > ( string_len . o binary ) 0 {
        : String bwant ( mj_get_str m `hashes.binary.sha256` )
        ?? ( nc_sha256_file ( string_data . o binary ) ) {
            T h → ( __vf_check t & > ( string_len bwant ) 0 ( string_eq h bwant ) `the binary is the one certified` ( string_data . o binary ) )
            F → ( __vf_bad t `the binary is the one certified` `cannot read it` )
        }
    } {}

    // The claims.
    : String verdict ( mj_get_str m `program.verdict` )
    : i nclaims ( cert_claim_count threads )
    : String claims_path ( nc_join bundle `Claims.lean` )
    : String elab_path ( nc_join bundle `Elab.lean` )
    // The manifest's case and the files agree.
    : b has_e ( file_exists ( string_data elab_path ) )
    : b case_ok ? elab & ( nc_is verdict `accepted` ) has_e ! has_e
    ( __vf_check t case_ok ? elab `Elab.lean is there, as the manifest records (the term is the kernel's, Cert.elab)`
    `no Elab.lean, as the manifest records none (the term is the translator's)` `` )
    ? ( nc_is verdict `accepted` ) {
        ( __vf_hash t m bundle `Program.lean` `program_lean` )
        ( __vf_hash t m bundle `Claims.lean` `claims_lean` )
        : String ptext ?? ( nc_read ( string_data ( nc_join bundle `Program.lean` ) ) ) { T x → x F → ( string_new ) }
        : ShapeRes sh ( cert_shape ptext )
        ( __vf_check t . sh ok `Program.lean only defines the program` ( string_data . sh why ) )
        : i slots ?? ( json_get m `program.slots` ) { T j → ( json_as_int j ) F → -1 }
        ( __vf_check t == slots . sh nv `the claims are stated over the program's slots` `` )
        : String want ( cert_claims_lean ( string_data prof ) . sh nv threads cond )
        : String have ?? ( nc_read ( string_data claims_path ) ) { T x → x F → ( string_new ) }
        ( __vf_check t ( string_eq want have ) `Claims.lean is the claims' template, byte for byte` `its statements or proofs were edited` )
        ? elab {
            ( __vf_hash t m bundle `Elab.lean` `elab_lean` )
            : String core_text ?? ( nc_read ( string_data ( nc_join bundle `Program.core` ) ) ) { T x → x F → ( string_new ) }
            : String ehave ?? ( nc_read ( string_data elab_path ) ) { T x → x F → ( string_new ) }
            : b esame ?? ( cert_elab_lean core_text threads ) { T w → ( string_eq w ehave ) F → F }
            ( __vf_check t esame `Elab.lean is Program.core's words and the template, byte for byte`
            `its words, statement or proof are not what nurl-cert makes of Program.core` )
        } {}
        ? caps {
            // N.cap: the list, the classes and their chains made again from
            // the bundle's own Program.lean, Program.core and caps.tsv;
            // Caps.lean the template over that list, byte for byte
            ( __vf_hash t m bundle `Caps.lean` `caps_lean` )
            ( __vf_hash t m bundle `caps.tsv` `caps_tsv` )
            : String core_text2 ?? ( nc_read ( string_data ( nc_join bundle `Program.core` ) ) ) { T x → x F → ( string_new ) }
            : String tab_text ?? ( nc_read ( string_data ( nc_join bundle `caps.tsv` ) ) ) { T x → x F → ( string_new ) }
            ?? ( cert_caps_make ptext core_text2 tab_text ) {
                T cm → {
                    : String khave ?? ( nc_read ( string_data ( nc_join bundle `Caps.lean` ) ) ) { T x → x F → ( string_new ) }
                    ( __vf_check t ( string_eq ( cert_caps_lean . cm runs ( string_data prof ) threads ) khave )
                    `Caps.lean is the template over the functions the term can enter, byte for byte` `its list, statement or proof were edited` )
                    : String jwant ( json_stringify . cm json )
                    : String jhave ?? ( json_get m `capabilities` ) { T j → ( json_stringify j ) F → ( string_new ) }
                    ( __vf_check t ( string_eq jwant jhave )
                    `the capabilities are the ones the term, the core IR and caps.tsv give (list, classes, chains)` `` )
                    : i ncl ( cert_claim_count threads )
                    : String sen ( mj_get_str m ( string_data ( __vf_path `claims.` + ncl 1 `.sentence.en` ) ) )
                    : String sfi ( mj_get_str m ( string_data ( __vf_path `claims.` + ncl 1 `.sentence.fi` ) ) )
                    ( __vf_check t & ( string_eq sen ( cert_caps_sentence_en . . cm res doors ) ) ( string_eq sfi ( cert_caps_sentence_fi . . cm res doors ) )
                    `N.cap's sentences name exactly the classes it reaches` `` )
                }
                F e → ( __vf_bad t `the capabilities can be made again from the bundle` ( string_data e ) )
            }
        } {
            ( __vf_check t & ! ( file_exists ( string_data ( nc_join bundle `Caps.lean` ) ) ) ! ( __vf_has m `capabilities` )
            `no Caps.lean and no capabilities, as the manifest records no N.cap proof` `` )
        }
        // Lean, again, and only on files every check above passed: Lean runs
        // code while it elaborates a file (`#eval`, `run_cmd`), so a file
        // the grammar, the template or a hash refused is never handed to it.
        ? > . t bad 0 {
            ( __vf_bad t `Lean checks Program.lean and Claims.lean` `not run: the bundle failed the checks above` )
            ? elab { ( __vf_bad t `Lean proves Cert.elab (Elab.lean) on the standard axioms` `not run` ) } {}
            ? caps { ( __vf_bad t `Lean proves Cert.n_cap (Caps.lean)` `not run` ) } {}
            : ~ i c 0
            ~ < c nclaims {
                : String what ( string_from ( cert_claim_id c ) )
                ( string_push_str what `: the manifest's status is what Lean reports` )
                ( __vf_bad t ( string_data what ) `not checked` )
                = c + c 1
            }
            ^ ( __vf_end t )
        } {}
        : String work ( nc_join bundle `.build` )
        // A fresh directory for the one Lean file the check runs
        // (`cert_lean_check`: the bundle's modules, combined).
        ?? ( dir_remove_all ( string_data work ) ) { T _ → {} F _ → {} }
        ( nc_mkdirs ( string_data work ) )
        : LeanRun lr ( cert_lean_check2 ( string_data . o lean ) ( string_data . o formal ) bundle ( string_data work ) elab caps )
        : b clean & . lr ran ! ( cert_lean_has_error . lr log )
        ( __vf_check t clean `Lean checks Program.lean and Claims.lean` ( string_data ( __vf_first . lr log ) ) )
        // The term is the kernel's: Lean proves Cert.elab again, in the same
        // run as the claims (and only an exit 0 counts).
        ? elab {
            ( __vf_check t ( cert_elab_proved lr ) `Lean proves Cert.elab (Elab.lean) on the standard axioms`
            ( string_data ( __vf_first . lr elab_log ) ) )
        } {}
        // N.cap: Lean proves Cert.n_cap again, and its status and axioms are
        // the manifest's
        : String nst ( mj_get_str m ( string_data ( __vf_path `claims.` + nclaims 1 `.status` ) ) )
        ? caps {
            : b kp ( cert_caps_proved lr )
            ( __vf_check t kp `Lean proves Cert.n_cap (Caps.lean)` ( string_data ( __vf_first . lr caps_log ) ) )
            : ( Vec String ) kal ?? ( cert_lean_axioms . lr caps_log `Cert.n_cap` ) { T ax → ( cert_axiom_list ax ) F → ( vec_new [String] ) }
            : s kraw ? kp ( cert_status_of ( string_data prof ) kal ) `open`
            : String kst ( string_from ? & cond == 0 ( nurl_str_eq kraw `open` ) `assumed` kraw )
            ( __vf_check t ( string_eq kst nst ) `N.cap: the manifest's status is what Lean reports` ( string_data nst ) )
            : String kaxp ( __vf_path `claims.` + nclaims 1 `.axioms` )
            : ( Vec String ) mkal ?? ( json_get m ( string_data kaxp ) ) { T j → ( __vf_strs j ) F → ( vec_new [String] ) }
            ( __vf_check t ( string_eq ( string_join kal `, ` ) ( string_join mkal `, ` ) ) `N.cap: the manifest lists the axioms Lean lists` `` )
        } {
            ( __vf_check t ( nc_is nst `open` ) `N.cap is open, as the bundle holds no proof of it` ( string_data nst ) )
        }
        ?? ( dir_remove_all ( string_data work ) ) { T _ → {} F _ → {} }
        : ~ i c 0
        ~ < c nclaims {
            : String mid ( mj_get_str m ( string_data ( __vf_path `claims.` c `.id` ) ) )
            : String mst ( mj_get_str m ( string_data ( __vf_path `claims.` c `.status` ) ) )
            : String what ( string_from ( cert_claim_id c ) )
            ( string_push_str what `: the manifest's status is what Lean reports` )
            ? ! ( nc_is mid ( cert_claim_id c ) ) {
                ( __vf_bad t ( string_data what ) `the claims are not in the template's order` )
            } {
                ?? ( cert_lean_axioms . lr log ( cert_claim_lean c ) ) {
                    T ax → {
                        : ( Vec String ) al ( cert_axiom_list ax )
                        : s raw ? clean ( cert_status_of ( string_data prof ) al ) `open`
                        : String st ( string_from ? & cond == 0 ( nurl_str_eq raw `open` ) `assumed` raw )
                        : String detail ( string_from `Lean says ` )
                        ( string_push_str detail ( string_data st ) )
                        ( string_push_str detail ` (axioms: ` )
                        ( string_push_str detail ( string_data ax ) )
                        ( string_push_str detail `), the manifest says ` )
                        ( string_push_str detail ( string_data mst ) )
                        ( __vf_check t ( string_eq st mst ) ( string_data what ) ( string_data detail ) )
                        // and the axioms it lists are the ones Lean lists
                        : ( Vec String ) mal ( vec_new [String] )
                        : ~ i q 0
                        : ~ b qm T
                        ~ qm {
                            : String qs ( __vf_path `.axioms.` q `` )
                            : String qk ( __vf_path `claims.` c ( string_data qs ) )
                            ?? ( json_get m ( string_data qk ) ) {
                                T aj → { ( vec_push [String] mal ( string_from ( json_as_str aj ) ) ) = q + q 1 }
                                F → { = qm F }
                            }
                        }
                        : String wax ( string_join al `, ` )
                        : String hax ( string_join mal `, ` )
                        : String aw ( string_from ( cert_claim_id c ) )
                        ( string_push_str aw `: the manifest lists the axioms Lean lists` )
                        ( __vf_check t ( string_eq wax hax ) ( string_data aw ) ( string_data hax ) )
                    }
                    F → {
                        : String detail ( string_from `Lean reports no axioms for ` )
                        ( string_push_str detail ( cert_claim_lean c ) )
                        ( __vf_check t ( nc_is mst `open` ) ( string_data what ) ( string_data detail ) )
                    }
                }
            }
            = c + c 1
        }
    } {
        // Refused or unsupported: no proof may be in the bundle, and no
        // claim above `open`.
        : String plp ( nc_join bundle `Program.lean` )
        ? ( file_exists ( string_data plp ) ) { ( __vf_hash t m bundle `Program.lean` `program_lean` ) } {}
        ( __vf_check t ! ( file_exists ( string_data claims_path ) ) `no Claims.lean beside a program the checker did not accept` `` )
        : String nst0 ( mj_get_str m ( string_data ( __vf_path `claims.` + nclaims 1 `.status` ) ) )
        ( __vf_check t & & & ( nc_is nst0 `open` ) ! caps ! ( file_exists ( string_data ( nc_join bundle `Caps.lean` ) ) ) ! ( __vf_has m `capabilities` )
        `N.cap is open, with no Caps.lean, beside a program the checker did not accept` ( string_data nst0 ) )
        : ~ i c 0
        ~ < c nclaims {
            : String mst ( mj_get_str m ( string_data ( __vf_path `claims.` c `.status` ) ) )
            : String what ( string_from ( cert_claim_id c ) )
            ( string_push_str what ` is open` )
            ( __vf_check t ( nc_is mst `open` ) ( string_data what ) ( string_data mst ) )
            = c + c 1
        }
    }
    // --rebuild: the term is the source's. nurlc's core IR of the source
    // again, and the translation of it again, byte for byte: what a plain
    // verify takes from the translation ledger row, checked.
    ? . o rebuild {
        : String src ( mj_get_str m `program.source` )
        : String back ?? ( env_cwd ) { T c → c F _ → ( string_from `/` ) }
        ?? ( env_chdir ( string_data . o stdlib ) ) { T _ → {} F _ → {} }
        : ( Vec String ) a1 ( vec_new [String] )
        ( vec_push [String] a1 ( string_from `--emit-core` ) )
        : String tag ( rand_hex_str 16 )
        : String tag_arg ( string_from `--list-sources=` )
        ( string_push_str tag_arg ( string_data tag ) )
        ( vec_push [String] a1 tag_arg )
        ( vec_push [String] a1 ( string_clone src ) )
        : Run r1 ( nc_run ( string_data . o nurlc ) a1 )
        ?? ( env_chdir ( string_data back ) ) { T _ → {} F _ → {} }
        : String core_have ?? ( nc_read ( string_data ( nc_join bundle `Program.core` ) ) ) { T x → x F → ( string_new ) }
        ( __vf_check t & & . r1 started == . r1 code 0 ( string_eq . r1 out core_have )
        `--rebuild: nurlc makes Program.core from the sources again` `` )
        // and the bytes that compile read are the recorded ones: the hashes
        // of its own snapshots, in the same run, against the manifest's
        : ( Vec String ) rp ( vec_new [String] )
        : ( Vec String ) rs ( vec_new [String] )
        : ( Vec String ) rrest ( vec_new [String] )
        : b rec_ok ( cert_records . r1 err ( string_data tag ) rp rs rrest )
        : ( Vec String ) mp ( vec_new [String] )
        : ( Vec String ) ms ( vec_new [String] )
        : ~ i q 0
        ~ ( __vf_has m ( string_data ( __vf_path `hashes.sources.` q `` ) ) ) {
            ( vec_push [String] mp ( mj_get_str m ( string_data ( __vf_path `hashes.sources.` q `.path` ) ) ) )
            ( vec_push [String] ms ( mj_get_str m ( string_data ( __vf_path `hashes.sources.` q `.sha256` ) ) ) )
            = q + q 1
        }
        ( __vf_check t & & rec_ok ( cert_same rp mp ) ( cert_same rs ms )
        `--rebuild: the compile read exactly the recorded source bytes` `` )
        : String plp ( nc_join bundle `Program.lean` )
        ? ( file_exists ( string_data plp ) ) {
            : Translated tr ( cert_translate ( string_data ( nc_join bundle `Program.core` ) ) T )
            : String lean_have ?? ( nc_read ( string_data plp ) ) { T x → x F → ( string_new ) }
            ( __vf_check t & . tr ok ( string_eq . tr lean lean_have )
            `--rebuild: the translation makes Program.lean from Program.core again` `` )
        } {}
    } {}

    // M.unsafe is the report's, never more than assumed.
    : String uid ( mj_get_str m ( string_data ( __vf_path `claims.` nclaims `.id` ) ) )
    : String ust ( mj_get_str m ( string_data ( __vf_path `claims.` nclaims `.status` ) ) )
    : b has_ir ?? ( json_get m `hashes.llvm_ir` ) { T _ → T F → F }
    : s uwant ? has_ir `assumed` `open`
    ( __vf_check t & ( nc_is uid `M.unsafe` ) ( nc_is ust uwant ) `M.unsafe is assumed (nurlc's report, not a theorem), open without one` ( string_data ust ) )
    : String nid ( mj_get_str m ( string_data ( __vf_path `claims.` + nclaims 1 `.id` ) ) )
    ( __vf_check t ( nc_is nid `N.cap` ) `the claim after M.unsafe is N.cap` ( string_data nid ) )
    : String xk ( __vf_path `claims.` + nclaims 2 `.id` )
    : b extra ?? ( json_get m ( string_data xk ) ) { T _ → T F → F }
    ( __vf_check t ! extra `the manifest claims nothing beyond the template's claims` `` )

    ^ ( __vf_end t )
}

@ __vf_end Tally t → i {
    ? == . t bad 0 {
        ( nurl_println `verified` )
        ^ 0
    } {}
    ( nurl_print `NOT verified: ` )
    ( nurl_print_int . t bad )
    ( nurl_println ` check(s) failed` )
    ^ 1
}

// ── The manifest's shape ─────────────────────────────────────────────
//
// What docs/dev/certificate.schema.json requires, checked here (verify
// needs no Python): the top-level members and no others, every required
// field, the claims in the template's order with the template's ids,
// names, sentences and premises, and the trust ledger exactly as certify
// writes it for this profile and these unsafe rows. A manifest that drops
// or rewrites what the claims rest on does not verify.

@ __vf_has Json m s path → b { ^ ?? ( json_get m path ) { T _ → T F → F } }

@ __vf_structure inout Tally t Json m s prof b threads b cond b elab ( Vec String ) enc ( Vec String ) assumed_ids ( Vec AssumedRow ) assumed_rows b caps → v {
    // the top-level members, exactly
    : ( Vec String ) keys ( json_obj_keys m )
    : ( Vec String ) want ( string_split ( string_from ? caps `schema tool profile program claims coverage hashes versions ledger capabilities` `schema tool profile program claims coverage hashes versions ledger` ) ` ` )
    ( nc_sort keys )
    ( nc_sort want )
    ( __vf_check t ( cert_same keys want ) `the manifest has the schema's members and no others` ( string_data ( string_join keys ` ` ) ) )
    // every object: its required members, no others; the leaves' types and
    // the values the schema fixes
    : ~ String bad ( string_new )
    ( __vf_obj m `tool` `name version` `` bad )
    ( __vf_obj m `program` `source verdict reason slots` `` bad )
    ( __vf_obj m `hashes` `sources core_ir` `llvm_ir program_lean claims_lean elab_lean caps_lean caps_tsv binary` bad )
    ( __vf_obj m `versions` `nurlc formal_tree formal_commit lean_toolchain` `` bad )
    ? ! ( nc_is ( mj_get_str m `tool.name` ) `nurl-cert` ) { ( string_push_str bad `tool.name ` ) } {}
    ( __vf_strings m `tool.version program.source program.verdict program.reason hashes.core_ir versions.nurlc versions.formal_tree versions.formal_commit versions.lean_toolchain` bad )
    ? ! ( __vf_enum ( mj_get_str m `program.verdict` ) `accepted refused unsupported error` ) { ( string_push_str bad `program.verdict ` ) } {}
    ? ! ?? ( json_get m `program.slots` ) { T j → ( __vf_count j ) F → F } { ( string_push_str bad `program.slots ` ) } {}
    ( __vf_sha m `hashes.core_ir` T bad )
    ( __vf_sha m `hashes.llvm_ir` F bad )
    ( __vf_sha m `hashes.program_lean` F bad )
    ( __vf_sha m `hashes.claims_lean` F bad )
    ( __vf_sha m `hashes.elab_lean` F bad )
    ( __vf_sha m `hashes.caps_lean` F bad )
    ( __vf_sha m `hashes.caps_tsv` caps bad )
    ? caps {
        ( __vf_obj m `capabilities` `runs functions classes` `` bad )
        : ( Vec String ) carr ( string_split ( string_from `capabilities.runs capabilities.functions capabilities.classes` ) ` ` )
        : i nca ( vec_len [String] carr )
        : ~ i ca 0
        ~ < ca nca {
            : String cpth ( string_clone ( vec_at [String] carr ca ) )
            : b isa ?? ( json_get m ( string_data cpth ) ) { T j → ( json_is_arr j ) F → F }
            ? ! isa {
                ( string_push_str bad ( string_data cpth ) )
                ( string_push_str bad `(not an array) ` )
            } {}
            = ca + ca 1
        }
    } {}
    ( __vf_sha m `versions.formal_tree` T bad )
    ? ( __vf_has m `hashes.binary` ) {
        ( __vf_obj m `hashes.binary` `path sha256` `` bad )
        ( __vf_strings m `hashes.binary.path` bad )
        ( __vf_sha m `hashes.binary.sha256` T bad )
    } {}
    : ~ i q 0
    ~ ( __vf_has m ( string_data ( __vf_path `hashes.sources.` q `` ) ) ) {
        : String sp ( __vf_path `hashes.sources.` q `` )
        ( __vf_obj m ( string_data sp ) `path sha256` `` bad )
        : String spp ( __vf_path `hashes.sources.` q `.path` )
        ( __vf_strings m ( string_data spp ) bad )
        : String sps ( __vf_path `hashes.sources.` q `.sha256` )
        ( __vf_sha m ( string_data sps ) T bad )
        = q + q 1
    }
    ? == q 0 { ( string_push_str bad `hashes.sources ` ) } {}
    : i ncl + ( cert_claim_count threads ) 2
    : ~ i c 0
    ~ < c ncl {
        : String cp ( __vf_path `claims.` c `` )
        ( __vf_obj m ( string_data cp ) `id lean status sentence reason axioms premises` `` bad )
        : String csp ( __vf_path `claims.` c `.sentence` )
        ( __vf_obj m ( string_data csp ) `en fi` `` bad )
        : String cr ( __vf_path `claims.` c `.reason` )
        ( __vf_strings m ( string_data cr ) bad )
        : String cst ( __vf_path `claims.` c `.status` )
        ? ! ( __vf_enum ( mj_get_str m ( string_data cst ) ) `proved validated assumed open refuted not-claimed` ) {
            ( string_push_str bad ( string_data cst ) )
            ( string_push_str bad ` ` )
        } {}
        : String cax ( __vf_path `claims.` c `.axioms` )
        ( __vf_str_array m ( string_data cax ) bad )
        = c + c 1
    }
    // coverage: the functions, and counts beside them
    : ( Vec String ) ck ?? ( json_get m `coverage` ) { T j → ( json_obj_keys j ) F → ( vec_new [String] ) }
    : i nck ( vec_len [String] ck )
    : ~ b has_fns F
    : ~ i z 0
    ~ < z nck {
        ?? ( vec_get [String] ck z ) {
            T key → {
                ? ( nc_is key `functions` ) { = has_fns T } {
                    : String kp ( string_from `coverage.` )
                    ( string_push_str kp ( string_data key ) )
                    ? ! ?? ( json_get m ( string_data kp ) ) { T j → ( __vf_count j ) F → F } {
                        ( string_push_str bad ( string_data kp ) )
                        ( string_push_str bad ` ` )
                    } {}
                }
            }
            F _ → {}
        }
        = z + z 1
    }
    ? ! has_fns { ( string_push_str bad `coverage.functions ` ) } {}
    // the arrays are arrays: a null one would skip its rows' checks
    : ( Vec String ) arrs ( string_split ( string_from `coverage.functions claims ledger hashes.sources` ) ` ` )
    : i na ( vec_len [String] arrs )
    : ~ i y 0
    ~ < y na {
        ?? ( vec_get [String] arrs y ) {
            T ap → {
                : b is_arr ?? ( json_get m ( string_data ap ) ) { T j → ( json_is_arr j ) F → F }
                ? ! is_arr {
                    ( string_push_str bad ( string_data ap ) )
                    ( string_push_str bad `(not an array) ` )
                } {}
            }
            F _ → {}
        }
        = y + y 1
    }
    : ~ i f 0
    ~ ( __vf_has m ( string_data ( __vf_path `coverage.functions.` f `` ) ) ) {
        : String fp ( __vf_path `coverage.functions.` f `` )
        ( __vf_obj m ( string_data fp ) `name file line status reason` `` bad )
        : String fps ( string_from `` )
        ( string_push_str fps ( string_data ( __vf_path `coverage.functions.` f `.name ` ) ) )
        ( string_push_str fps ( string_data ( __vf_path `coverage.functions.` f `.file ` ) ) )
        ( string_push_str fps ( string_data ( __vf_path `coverage.functions.` f `.line ` ) ) )
        ( string_push_str fps ( string_data ( __vf_path `coverage.functions.` f `.reason` ) ) )
        ( __vf_strings m ( string_data fps ) bad )
        : String fs ( __vf_path `coverage.functions.` f `.status` )
        ? ! ( __vf_enum ( mj_get_str m ( string_data fs ) ) `proved validated open refused unsupported error` ) {
            ( string_push_str bad ( string_data fs ) )
            ( string_push_str bad ` ` )
        } {}
        = f + f 1
    }
    ( __vf_check t == 0 ( string_len bad ) `every member is the schema's, with its required fields and value types` ( string_data bad ) )
    // the claims: the template's, in its order
    : i nc ( cert_claim_count threads )
    : ~ b claims_ok T
    : ~ i c 0
    ~ <= c nc {
        : s id ? == c nc `M.unsafe` ( cert_claim_id c )
        : s lean ? == c nc `` ( cert_claim_lean c )
        : String prem_c ( cert_claim_premises prof c elab enc assumed_ids )
        : s prem ? == c nc `unsafe-report` ( string_data prem_c )
        ? ! ( nc_is ( mj_get_str m ( string_data ( __vf_path `claims.` c `.id` ) ) ) id ) { = claims_ok F } {}
        ? ! ( nc_is ( mj_get_str m ( string_data ( __vf_path `claims.` c `.lean` ) ) ) lean ) { = claims_ok F } {}
        ? == c nc {} {
            ? ! ( nc_is ( mj_get_str m ( string_data ( __vf_path `claims.` c `.sentence.en` ) ) ) ( cert_claim_sentence threads cond c ) ) { = claims_ok F } {}
            ? ! ( nc_is ( mj_get_str m ( string_data ( __vf_path `claims.` c `.sentence.fi` ) ) ) ( cert_claim_sentence_fi threads cond c ) ) { = claims_ok F } {}
        }
        : String pk ( __vf_path `claims.` c `.premises` )
        // element by element: one string that reads like the four
        // premises is one premise, which no ledger row is.
        : ( Vec String ) have ?? ( json_get m ( string_data pk ) ) { T j → ( __vf_strs j ) F → ( vec_new [String] ) }
        : ( Vec String ) wantp ( string_split ( string_from prem ) ` ` )
        ? ! ( cert_same have wantp ) { = claims_ok F } {}
        = c + c 1
    }
    // N.cap: its id, theorem and premises; an open one's sentences are the
    // open ones (a proved one's are checked against the classes made again)
    : i nk + nc 1
    ? ! ( nc_is ( mj_get_str m ( string_data ( __vf_path `claims.` nk `.id` ) ) ) `N.cap` ) { = claims_ok F } {}
    ? ! ( nc_is ( mj_get_str m ( string_data ( __vf_path `claims.` nk `.lean` ) ) ) `Cert.n_cap` ) { = claims_ok F } {}
    : ~ i nus 0
    : ~ i qu 0
    : ~ b moreu T
    ~ moreu {
        : String lik ( __vf_path `ledger.` qu `.id` )
        ?? ( json_get m ( string_data lik ) ) {
            T ij → {
                : String id ( string_from ( json_as_str ij ) )
                ? & ( string_starts_with id `unsafe-` ) ! ( nc_is id `unsafe-report` ) { = nus + nus 1 } {}
                = qu + qu 1
            }
            F → { = moreu F }
        }
    }
    : String kprem ( cert_caps_premises prof caps elab enc nus assumed_ids )
    : String kpk ( __vf_path `claims.` nk `.premises` )
    : ( Vec String ) khave ?? ( json_get m ( string_data kpk ) ) { T j → ( __vf_strs j ) F → ( vec_new [String] ) }
    ? ! ( cert_same khave ( string_split kprem ` ` ) ) { = claims_ok F } {}
    ? ! caps {
        ? ! ( nc_is ( mj_get_str m ( string_data ( __vf_path `claims.` nk `.sentence.en` ) ) ) ( cert_caps_open_en ) ) { = claims_ok F } {}
        ? ! ( nc_is ( mj_get_str m ( string_data ( __vf_path `claims.` nk `.sentence.fi` ) ) ) ( cert_caps_open_fi ) ) { = claims_ok F } {}
    } {}
    ( __vf_check t claims_ok `the claims are the template's: ids, theorems, sentences, premises` `` )
    // the ledger, as certify writes it
    : ( Vec String ) urows ( vec_new [String] )
    : ~ i q 0
    : ~ b more T
    ~ more {
        : String ik ( __vf_path `ledger.` q `.id` )
        ?? ( json_get m ( string_data ik ) ) {
            T ij → {
                : String id ( string_from ( json_as_str ij ) )
                ? & ( string_starts_with id `unsafe-` ) ! ( nc_is id `unsafe-report` ) {
                    ( vec_push [String] urows ( mj_get_str m ( string_data ( __vf_path `ledger.` q `.what` ) ) ) )
                } {}
                = q + q 1
            }
            F → { = more F }
        }
    }
    : Json lw ( cert_ledger prof urows threads elab enc assumed_rows caps )
    : String lws ( json_stringify lw )
    : String lhs ?? ( json_get m `ledger` ) { T j → ( json_stringify j ) F → ( string_new ) }
    ( __vf_check t ( string_eq lws lhs ) `the trust ledger is the one certify writes (no row dropped or reworded)` `` )
}

// A JSON array's elements, each as a String (`` for a non-string).
@ __vf_strs Json a → ( Vec String ) {
    : ( Vec String ) o ( vec_new [String] )
    : i n ( json_arr_len a )
    : ~ i k 0
    ~ < k n {
        ?? ( json_arr_get a k ) {
            T x → ( vec_push [String] o ( string_from ( json_as_str x ) ) )
            F → {}
        }
        = k + k 1
    }
    ^ o
}

@ __vf_first String log → String {
    : ( Vec String ) ls ( nc_lines ( string_data log ) )
    ^ ?? ( vec_get [String] ls 0 ) { T l → ( string_clone l ) F → ( string_new ) }
}

// The object at `path`: every member of `req` present, none outside `req`
// and `opt`. What is wrong is appended to `bad`.
@ __vf_obj Json m s path s req s opt inout String bad → v {
    : b is_obj ?? ( json_get m path ) { T j → ( json_is_obj j ) F → F }
    ? ! is_obj {
        ( string_push_str bad path )
        ( string_push_str bad ` ` )
        ^ v
    } {}
    : ( Vec String ) keys ?? ( json_get m path ) { T j → ( json_obj_keys j ) F → ( vec_new [String] ) }
    : String all ( string_from req )
    ( string_push_str all ` ` )
    ( string_push_str all opt )
    : ( Vec String ) rk ( string_split ( string_from req ) ` ` )
    : i nr ( vec_len [String] rk )
    : ~ i k 0
    ~ < k nr {
        ?? ( vec_get [String] rk k ) {
            T r → {
                ? & > ( string_len r ) 0 ! ( __vf_in r keys ) {
                    ( string_push_str bad path )
                    ( string_push_str bad `.` )
                    ( string_push_str bad ( string_data r ) )
                    ( string_push_str bad ` ` )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    : ( Vec String ) ak ( string_split all ` ` )
    : i nk ( vec_len [String] keys )
    : ~ i j 0
    ~ < j nk {
        ?? ( vec_get [String] keys j ) {
            T key → {
                ? ! ( __vf_in key ak ) {
                    ( string_push_str bad path )
                    ( string_push_str bad `.` )
                    ( string_push_str bad ( string_data key ) )
                    ( string_push_str bad `(extra) ` )
                } {}
            }
            F _ → {}
        }
        = j + j 1
    }
}

@ __vf_in String x ( Vec String ) v → b {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] v k ) { T y → { ? ( string_eq x y ) { ^ T } {} } F _ → {} }
        = k + k 1
    }
    ^ F
}

@ __vf_enum String x s alts → b {
    : ( Vec String ) v ( string_split ( string_from alts ) ` ` )
    ^ ( __vf_in x v )
}

// Each path (space-separated) is a string.
@ __vf_strings Json m s paths inout String bad → v {
    : ( Vec String ) ps ( string_split ( string_from paths ) ` ` )
    : i n ( vec_len [String] ps )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] ps k ) {
            T p → {
                : b ok ?? ( json_get m ( string_data p ) ) { T j → ( json_is_str j ) F → F }
                ? ! ok {
                    ( string_push_str bad ( string_data p ) )
                    ( string_push_str bad ` ` )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
}

// A sha256 in lowercase hex; `need`: it must be there.
@ __vf_sha Json m s path b need inout String bad → v {
    ? & ! need ! ( __vf_has m path ) { ^ v } {}
    : String h ( mj_get_str m path )
    : ~ b ok == ( string_len h ) 64
    : ( Slice u ) hv ( slice_of_str ( string_data h ) )
    : i n ( slice_len [u] hv )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte hv k )
        ? ! | & >= c 48 <= c 57 & >= c 97 <= c 102 { = ok F } {}
        = k + k 1
    }
    ? ! ok {
        ( string_push_str bad path )
        ( string_push_str bad ` ` )
    } {}
}

// An array of strings.
@ __vf_str_array Json m s path inout String bad → v {
    : b ok ?? ( json_get m path ) {
        T j → {
            : ~ b all ( json_is_arr j )
            : i n ( json_arr_len j )
            : ~ i k 0
            ~ < k n {
                ?? ( json_arr_get j k ) { T x → { ? ! ( json_is_str x ) { = all F } {} } F → {} }
                = k + k 1
            }
            all
        }
        F → F
    }
    ? ! ok {
        ( string_push_str bad path )
        ( string_push_str bad ` ` )
    } {}
}

// A count: a JSON number that is a nonnegative integer (digits only, as
// the schema's `integer, minimum 0`; no sign, fraction or exponent).
@ __vf_count Json j → b {
    ? ! ( json_is_num j ) { ^ F } {}
    : String txt ( json_stringify j )
    : ( Slice u ) tv ( slice_of_str ( string_data txt ) )
    : i n ( slice_len [u] tv )
    ? == n 0 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte tv k )
        ? | < c 48 > c 57 { ^ F } {}
        = k + k 1
    }
    ^ T
}
