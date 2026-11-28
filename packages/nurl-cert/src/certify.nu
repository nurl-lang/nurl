// certify.nu — `nurl-cert certify`: one program to a certificate bundle.
//
//   prog.cert/
//     Program.core    nurlc's core IR of the program (the translation's input)
//     Program.lean    the program as a term of formal/A2 (P, entry)
//     Claims.lean     the claims, stated and proved (only when the checker
//                     accepts; see claims.nu)
//     Elab.lean       Program.core as words (words.nu), and the proof that
//                     Program.lean's term is the one the kernel builds from
//                     them (C.Elab.elabIR): only when the checker accepts
//                     and Lean proves Cert.elab
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
$ `tolean.nu`
$ `words.nu`
$ `caps.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`

: s NURLCERT_VERSION ( pkg_version )

: CertOpts {
    String src
    String out
    String prof
    String nurlc
    String formal
    String lean
    String binary
    String stdlib
}

// ── The translation (one interface) ──────────────────────────────────
//
// `.core` text in, Program.lean out. The translator is tolean.nu (the
// NURL port of the Python prototype tools/ncore/tolean.py, which it
// matches byte for byte: tools/ncore/tolean_parity.sh); only its frame is
// rewritten here: the import (C.Cert, which has the claims' lemmas) and
// the `#eval` line (the claims replace it). The shape check in shape.nu
// then holds the result to the program grammar.

: Translated {
    b ok
    String lean
    String why
    // the program's own functions the translation does not cover, each with
    // its reason (AGORA-1015); an empty name: the ones after the last were
    // not reached
    ( Vec TlMiss ) miss
    // stubs emitted for assumed functions (AGORA-1033)
    ( Vec TlStub ) stubs
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
                    // (a threaded program's frame imports C.Cert3; its Claims.lean
                    // imports that itself, so Program.lean stays the one grammar)
                    ? | ( nc_is l `import C.A2Prog` ) ( nc_is l `import C.Cert3` ) {
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

// With `all` T, every function the translation does not cover goes into
// `miss` (certify's coverage); with F it stops at the first (verify).
// The term's file with, for a deep term, the elaborator's bound it needs as
// its third line (`cert_rec_depth`, shape.nu; AGORA-1034).
@ __ct_depth String text → String {
    : i need ( cert_rec_depth text )
    ? == need 0 { ^ ( string_clone text ) } {}
    : s head `import C.Cert
open A2 C
`
    : i hn ( nurl_str_len head )
    : String o ( string_from head )
    ( string_push_str o `set_option maxRecDepth ` )
    ( string_push_int o need )
    ( string_push_char o 10 )
    ( string_push_str o ( string_data ( string_substr text hn - ( string_len text ) hn ) ) )
    ^ o
}

@ cert_translate s core_path b all → Translated {
    : String text ?? ( nc_read core_path ) {
        T x → x
        F → { ^ @ Translated { F ( string_new ) ( string_from `cannot read the core IR` ) ( vec_new [TlMiss] ) ( vec_new [TlStub] ) } }
    }
    : ( Vec TlMiss ) miss ( vec_new [TlMiss] )
    : ( Vec TlStub ) stubs ( vec_new [TlStub] )
    : !String String r ? all ( tolean_translate_fns ( string_data text ) miss stubs ) ( tolean_translate ( string_data text ) )
    ^ ?? r {
        T lean → @ Translated { T ( __ct_depth ( __ct_reframe ( string_data lean ) ) ) ( string_new ) miss stubs }
        F why → @ Translated { F ( string_new ) why miss stubs }
    }
}

// ── What nurlc says ──────────────────────────────────────────────────

// The records of a `--list-sources=TAG` run (nurlc prints them on stderr):
//   source:TAG <length> <path>\n<length bytes>\n
// each path into `paths` and the sha256 of the bytes nurlc compiled into
// `shas`, and every other line of stderr into `rest`. F when a record is
// cut short. A line a diagnostic quotes from a source cannot pass for a
// record: TAG is fresh and random per run.
@ cert_records String err s tag ( Vec String ) paths ( Vec String ) shas ( Vec String ) rest → b {
    : String head ( string_from `source:` )
    ( string_push_str head tag )
    ( string_push_str head ` ` )
    : ( Slice u ) hv ( slice_of_str ( string_data head ) )
    : i hn ( slice_len [u] hv )
    : ( Slice u ) t ( slice_of_str ( string_data err ) )
    : i n ( slice_len [u] t )
    : ~ i a 0
    ~ < a n {
        : ~ i z a
        ~ & < z n != ( slice_byte t z ) 10 { = z + z 1 }
        : ~ b is_head <= + a hn z
        : ~ i k 0
        ~ & is_head < k hn {
            ? != ( slice_byte t + a k ) ( slice_byte hv k ) { = is_head F } {}
            = k + k 1
        }
        ? is_head {
            : ~ i p + a hn
            : ~ i len 0
            : i d0 p
            ~ & < p z & >= ( slice_byte t p ) 48 <= ( slice_byte t p ) 57 {
                = len + * len 10 - ( slice_byte t p ) 48
                = p + p 1
            }
            ? | == p d0 | >= p z != ( slice_byte t p ) 32 { ^ F } {}
            : String path ( string_new )
            ( string_push_window path t + p 1 - - z p 1 )
            : i start + z 1
            ? > + start len n { ^ F } {}
            : ( Vec u ) bytes ( slice_to_vec [u] ( slice_window [u] t start len ) )
            ( vec_push [String] paths path )
            ( vec_push [String] shas ( bytes_to_hex ( sha256_pure bytes ) ) )
            = a + + start len 1
        } {
            : String l ( string_new )
            ( string_push_window l t a - z a )
            ( vec_push [String] rest l )
            = a + z 1
        }
    }
    ^ T
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

@ __ct_unsafe_rows ( Vec String ) ls → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
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

// The sha256 of each file, in order; shorter than `paths` when one
// cannot be read.
@ __ct_hash_all ( Vec String ) paths → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( vec_len [String] paths )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] paths k ) {
            T p → {
                ?? ( nc_sha256_file ( string_data p ) ) {
                    T h → ( vec_push [String] out h )
                    F → { ^ out }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

@ cert_same ( Vec String ) a ( Vec String ) b → b {
    : i n ( vec_len [String] a )
    ? != n ( vec_len [String] b ) { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : b eq ?? ( vec_get [String] a k ) {
            T x → ?? ( vec_get [String] b k ) { T y → ( string_eq x y ) F _ → F }
            F _ → F
        }
        ? ! eq { ^ F } {}
        = k + k 1
    }
    ^ T
}

// The program's own functions in the core IR (`fn` lines whose source is
// not the standard library's): name, file, line.
: FnRow {
    String name
    String file
    String line
}

@ __ct_is_lib String f → b {
    ^ ( string_starts_with f `stdlib/` )
}

@ cert_functions s core → ( Vec FnRow ) {
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

// The first line of `s` that is one of Lean's errors, else its first line.
@ __ct_first_err String s → String {
    : ( Vec String ) ls ( nc_lines ( string_data s ) )
    : i n ( vec_len [String] ls )
    : ~ i k 0
    ~ < k n {
        : String l ( string_clone ( vec_at [String] ls k ) )
        ? ( string_contains l `: error` ) { ^ ( string_trim l ) } {}
        = k + k 1
    }
    ^ ( __ct_first_line s )
}

@ __ct_cov_status String verdict ( Vec String ) statuses b cond s prof → String {
    ? ! ( nc_is verdict `accepted` ) { ^ ( string_clone verdict ) } {}
    ? cond {
        // In a conditional certificate, every M claim is `assumed` when Lean
        // proved the conditional theorem; each non-assumed function was
        // checked by fnOK2B/stmtCodesB itself, so it is `proved` (under
        // kernel) or `validated` (under fast).
        : i n ( vec_len [String] statuses )
        : ~ b all_ok > n 0
        : ~ i k 0
        ~ < k n {
            ?? ( vec_get [String] statuses k ) {
                T st → { ? ! ( nc_is st `assumed` ) { = all_ok F } {} }
                F _ → { = all_ok F }
            }
            = k + k 1
        }
        ? all_ok { ^ ( string_from ? != 0 ( nurl_str_eq prof `kernel` ) `proved` `validated` ) } {}
        ^ ( string_from `open` )
    } {}
    : ~ i rank 2
    : i n ( vec_len [String] statuses )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] statuses k ) {
            T st → {
                ? ( nc_is st `validated` ) { ? > rank 1 { = rank 1 } {} } {
                    ? ! ( nc_is st `proved` ) { = rank 0 } {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ? == rank 2 { ^ ( string_from `proved` ) } {}
    ? == rank 1 { ^ ( string_from `validated` ) } {}
    ^ ( string_from `open` )
}

// The index in `miss` of function `name`, -1 when the translation covers it.
@ __ct_miss_at ( Vec TlMiss ) miss s name → i {
    : i n ( vec_len [TlMiss] miss )
    : ~ i k 0
    ~ < k n {
        ? ( nc_is . ( vec_at [TlMiss] miss k ) name name ) { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// The index in `miss` of its entry with an empty name (the translation
// stopped, or never reached the functions), or -1.
@ __ct_stop_ix ( Vec TlMiss ) miss → i {
    : i n ( vec_len [TlMiss] miss )
    : ~ i k 0
    ~ < k n {
        ? == ( string_len . ( vec_at [TlMiss] miss k ) name ) 0 { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// One more of status `st`: its count in `counts`, beside `keys` in order of
// first use.
@ __ct_count ( Vec String ) keys ( Vec i ) counts s st → v {
    : i n ( vec_len [String] keys )
    : ~ i at -1
    : ~ i k 0
    ~ < k n {
        ? & < at 0 ( nc_is ( vec_at [String] keys k ) st ) { = at k } {}
        = k + k 1
    }
    ? < at 0 {
        ( vec_push [String] keys ( string_from st ) )
        ( vec_push [i] counts 1 )
    } {
        : b _s ( vec_set [i] counts at + ( vec_at [i] counts at ) 1 )
    }
}

// ── The ledger ───────────────────────────────────────────────────────

// An encoding's ledger row (docs/dev/TRANSLATION_TRUST.md, "The encodings,
// and where each is argued"): how C.Elab.elabIR reads a part of the core IR
// as the calculus, which no theorem ties to the core IR's meaning (it has
// none of its own yet), each argued by its design note.
@ __ct_enc_row s id s mc → Json {
    : s note `docs/dev/TRANSLATION_TRUST.md (the encodings), formal/C/Elab.lean`
    : s who `the NURL formal model (claude-formal)`
    ? != 0 ( nurl_str_eq id `enc-numbers` ) {
        ^ ( mj_row id `a number is A2's int; an untracked number (c) is any number, a computation over tracked operands any number with its operands still read`
        `a number's value is no part of the memory model, and the model's runs must include the program's whatever its numbers (C.ite_any_both: both arms of an if are runs)` note who mc )
    } {}
    ? != 0 ( nurl_str_eq id `enc-raw-text` ) {
        ^ ( mj_row id `raw text: bound from a literal or a fresh string it is owned text (.vec .int), held in a value or made by string_data a view (.slice .int)`
        `owned text against a view (MEMORY.md §1, §2.13); the core IR has no provenance flag to prove it from` note who mc )
    } {}
    ? != 0 ( nurl_str_eq id `enc-shapes` ) {
        ^ ( mj_row id `an option is sum int t (None the first variant), a struct its fields nested in pairs, a struct of one field its field`
        `layout-free shapes: no ownership choice is made in them` note who mc )
    } {}
    ? != 0 ( nurl_str_eq id `enc-destructors` ) {
        ^ ( mj_row id `a type with a % Drop of the program's own is .dtor f u (f its drop__, a struct of one field padded with a number), its values bound by .letd`
        `the destructor runs at the end of every value of the type (A2-drop's theorems)` note who mc )
    } {}
    ? != 0 ( nurl_str_eq id `enc-closures` ) {
        ^ ( mj_row id `a closure is .fn [σ] .any, σ its type's interface; a capture is by name or held in the environment (CORE_VF_ENVOWN), by name read only (inp) or changed (inout drop)`
        `a capture by name is a dependency on the binding (MEMORY.md §2.11); by name against by value is meaning, the mode precision` note who mc )
    } {}
    ? != 0 ( nurl_str_eq id `enc-threads` ) {
        ^ ( mj_row id `a spawned closure is of class send with an interface of its own; a spawn is A3's call of a wrapper that takes the closure over and calls it, a join a read; a thread's handle and error are numbers, a result sum E T`
        `a spawn moves the closure to a new thread, its captures held by value; thread_spawn_owned's failure is outside the model, and the closure is moved where nurlc copies its environment (a use after the spawn is refused)` note who mc )
    } {}
    ? != 0 ( nurl_str_eq id `enc-channels` ) {
        ^ ( mj_row id `a channel is lk (prod (vec A) int), its queue and its closed flag; Channel_share is lockClone; a channel bound from another binding is a move`
        `A3.4's channel; one owner per handle, as nurlc moves it (Ty.ChanOf)` note who mc )
    } {}
    ^ ( mj_row id `the walk's summaries read into the term: a parameter the walk infers taken over is sink, one a callee changes inout (AGORA-994), a cursor a borrow, a change of a Vec's elements an edit through one`
    `it reads nurlc's own borrow walk, which the certificate is meant not to need (the engine computing the summaries itself, AGORA-877, removes it)` note who mc )
}

// One assumed function's trust-ledger record (AGORA-1033).
: AssumedRow {
    i idx
    String name
    String sig
    String callees
    b has_thru
    String why
    String loc
}

@ cert_assumed_id s name → String {
    : String id ( string_from `assumed-fn:` )
    ( string_push_str id name )
    ^ id
}

// (`caps`: N.cap is proved, about the program with its stubs: the row backs
// it too)
@ cert_assumed_row AssumedRow a b threads b caps → Json {
    : String id ( cert_assumed_id ( string_data . a name ) )
    : String what ( string_from `function ` )
    ( string_push_str what ( string_data . a name ) )
    ( string_push_str what ` (fn` )
    ( string_push_int what . a idx )
    ( string_push_str what `): completion obligations (` )
    ( string_push_str what ( string_data . a sig ) )
    ( string_push_str what `; callees [` )
    ( string_push_str what ( string_data . a callees ) )
    ( string_push_str what `]; hasThru ` )
    ( string_push_str what ? . a has_thru `true` `false` )
    ( string_push_str what ? threads `) and proof obligations (FnOK, codesOK, globsAt)` `) and proof obligations (FnOK, codesOK)` )
    : s mc ? threads `M.safe M.leak M.race` `M.safe M.leak`
    ^ ( mj_row ( string_data id ) ( string_data what ) ( string_data . a why ) ( string_data . a loc )
    `assumed (not translated; checked only by signature and call summary)` ? caps ( string_data ( __ct_with_ncap mc ) ) mc )
}

// `elab`: the bundle has Elab.lean, so the term is the kernel's
// (`Cert.elab`): the translation is what is left of it, the core IR's
// words (`core-ir-words`), and the encodings the term uses (`enc`,
// cert_enc_ids), each a row (AGORA-1029). `assumed_rows`: one row per
// assumed function (AGORA-1033).
@ cert_ledger s prof ( Vec String ) unsafe_rows b threads b elab ( Vec String ) enc ( Vec AssumedRow ) assumed_rows b caps → Json {
    // the claims a shared row backs: M.race too, for a threaded program
    : s mc ? threads `M.safe M.leak M.race` `M.safe M.leak`
    : s muc ? threads `M.unsafe M.safe M.leak M.race` `M.unsafe M.safe M.leak`
    : Json L ( json_arr_new )
    ( json_arr_push L ( mj_row `lean-kernel` `the Lean 4 kernel and the toolchain formal/lean-toolchain pins`
    `it checks every proof in Program.lean and Claims.lean` `formal/lean-toolchain` `the Lean developers` mc ) )
    ? != 0 ( nurl_str_eq prof `fast` ) {
        ( json_arr_push L ( mj_row `lean-compiler` `the Lean compiler and its runtime (native_decide)`
        `under the fast profile the checker's verdict is computed by compiled code, not by the kernel`
        `Claims.lean, theorem Cert.verdict` `the Lean developers` mc ) )
    } {}
    : s defs ? threads `the claims' definitions: A3's semantics over A2's (A3.Reach, A3.Race, A3.Cfg.init, A2.Stuck, Cfg.alloc)` `the claims' definitions: A2's semantics (A2.Steps, A2.Stuck, A2.emptyMem, Mem.alloc)`
    ( json_arr_push L ( mj_row `claim-definitions` defs
    `a claim means what these definitions say; formal/CLAIM.md is their review document`
    `formal/CLAIM.md, formal/A2/Semantics.lean` `the NURL formal model (claude-formal)` mc ) )
    ? elab {
        // (a program that spawns: Cert.elab is about C.Elab.elabIR3 / elabIR3Cond;
        // a conditional program: C.Elab.elabIRCond / elabIR3Cond)
        : b has_a > ( vec_len [AssumedRow] assumed_rows ) 0
        : String what ( string_from `the core IR and its words, the part of the translation the kernel does not check: nurlc --emit-core, and the core IR as words (packages/nurl-cert/src/words.nu); the term is checked by the kernel (Elab.lean, theorem Cert.elab: ` )
        ( string_push_str what ? & threads has_a `C.Elab.elabIR3Cond builds P (with stubs at assumed), its spawn wrappers (spawns) and entry`
        ? threads `C.Elab.elabIR3 builds P, its spawn wrappers (spawns) and entry`
        ? has_a `C.Elab.elabIRCond builds P (with stubs at assumed) and entry`
        `C.Elab.elabIR builds P and entry` )
        ( string_push_str what ` from the words)` )
        ( json_arr_push L ( mj_row `core-ir-words` ( string_data what )
        `nothing proves that the core IR is the source's; verify makes Elab.lean, words and all, again from Program.core and compares it byte for byte`
        `compiler/nurlc.nu (--emit-core), packages/nurl-cert/src/words.nu` `nurlc (untrusted, tested by the hole corpus) and nurl-cert's words (re-made by verify)` mc ) )
        : i ne ( vec_len [String] enc )
        : ~ i j 0
        ~ < j ne {
            ( json_arr_push L ( __ct_enc_row ( string_data ( vec_at [String] enc j ) ) mc ) )
            = j + j 1
        }
    } {
        ( json_arr_push L ( mj_row `translation` `the translation from source to the Lean term: nurlc --emit-core, then nurl-cert's translator (packages/nurl-cert/src/tolean.nu)`
        `nothing yet proves that P is the program the source describes (AGORA-1020 moves it inside the kernel's sight)`
        `compiler/nurlc.nu (--emit-core), packages/nurl-cert/src/tolean.nu` `nurl-cert's translator (untrusted, tested by tests/translate_test.sh and tools/ncore/tolean_parity.sh)` mc ) )
    }
    ( json_arr_push L ( mj_row `library-summaries` `the standard library as the term has it: its calls are A2 primitives and declared summaries`
    `the library's unsafe base follows formal/B's models by inspection, not by proof (AGORA-1014 ties each to its theorem)`
    `packages/nurl-cert/src/tolean.nu, tools/ncore/prims.py, formal/B` `the NURL formal model (claude-formal)` mc ) )
    ( json_arr_push L ( mj_row `llvm` `LLVM: the IR to machine code` `the claims are about the program's model; phase D validates the drops, nothing proves codegen`
    `the LLVM IR hash in this manifest` `the LLVM project` mc ) )
    ( json_arr_push L ( mj_row `linker` `the linker` `it joins the program with the C runtime` `the build` `the toolchain's linker` mc ) )
    ( json_arr_push L ( mj_row `os` `the operating system` `memory, threads and files are the kernel's` `the host` `the OS vendor` mc ) )
    ( json_arr_push L ( mj_row `c-runtime` `the C runtime the program links against` `allocation, I/O and panics go through it`
    `stdlib/runtime*.c` `the NURL project` mc ) )
    ? threads {
        ( json_arr_push L ( mj_row `drf-sc` `the C11 / LLVM memory model's DRF-SC guarantee`
        `M.race is A3's race freedom of the program's model; that a race-free program behaves sequentially consistently in the binary is the memory model's theorem, cited, not mechanized`
        `formal/CLAIM.md (trusted base), A3/DESIGN.md` `the C11 and LLVM memory models (Batty et al.; LLVM LangRef)` `M.race` ) )
    } {}
    // N.cap's own rows, when it is proved (AGORA-1013)
    ? caps { ( cert_caps_rows L ) } {}
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
                ( string_data r ) `the program's author` ? caps ( string_data ( __ct_with_ncap muc ) ) muc ) )
            }
            F _ → {}
        }
        = k + k 1
    }
    : i na ( vec_len [AssumedRow] assumed_rows )
    : ~ i ak 0
    ~ < ak na {
        ( json_arr_push L ( cert_assumed_row ( vec_at [AssumedRow] assumed_rows ak ) threads caps ) )
        = ak + ak 1
    }
    ^ L
}

// The claims a hand-vouched place backs, and N.cap too.
@ __ct_with_ncap s c → String {
    : String o ( string_from c )
    ( string_push_str o ` N.cap` )
    ^ o
}

// ── formal/'s commit ─────────────────────────────────────────────────
//
// `versions.formal_commit` (informational: verify pins the tree's hash,
// not the commit). Read off the repository's files where they are the
// plain case, a `.git` directory or a worktree's `.git` file, `HEAD` a ref
// or a commit, the ref loose or in `packed-refs`: that costs a few small
// reads, where starting `git rev-parse HEAD` cost about 9 ms of every
// certify. Anything else asks git, as before.

@ __ct_hex40 String x → b {
    : ( Slice u ) t ( slice_of_str ( string_data x ) )
    : i n ( slice_len [u] t )
    ? != n 40 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte t k )
        ? ! | & >= c 48 <= c 57 & >= c 97 <= c 102 { ^ F } {}
        = k + k 1
    }
    ^ T
}

// The directory above `p` ("" at the root).
@ __ct_parent String p → String {
    : ( Slice u ) t ( slice_of_str ( string_data p ) )
    : ~ i k - ( slice_len [u] t ) 1
    ~ & > k 0 | == ( slice_byte t k ) 47 == ( slice_byte t k ) 92 { = k - k 1 }
    ~ & > k 0 & != ( slice_byte t k ) 47 != ( slice_byte t k ) 92 { = k - k 1 }
    ? <= k 0 { ^ ( string_new ) } {}
    ^ ( string_substr p 0 k )
}

@ __ct_git_commit_files s dir → String {
    // the repository's git directory, from `dir` up
    : ~ String d ( nc_abs dir )
    : ~ String gitdir ( string_new )
    : ~ i up 0
    ~ & == 0 ( string_len gitdir ) & > ( string_len d ) 0 < up 64 {
        : String g ( nc_join ( string_data d ) `.git` )
        ?? ( dir_list ( string_data g ) ) {
            T _ → { = gitdir ( string_clone g ) }
            F _ → {
                ?? ( nc_read ( string_data g ) ) {
                    T txt → {
                        : String l ( string_trim txt )
                        ? ( string_starts_with l `gitdir: ` ) {
                            : String rest ( string_substr l 8 - ( string_len l ) 8 )
                            = gitdir ? ( nc_is_abs ( string_data rest ) ) rest ( nc_join ( string_data d ) ( string_data rest ) )
                        } { ^ ( string_new ) }
                    }
                    F → {}
                }
            }
        }
        = d ( __ct_parent d )
        = up + up 1
    }
    ? == 0 ( string_len gitdir ) { ^ ( string_new ) } {}
    // a worktree's refs are its common directory's
    : ~ String common ( string_clone gitdir )
    ?? ( nc_read ( string_data ( nc_join ( string_data gitdir ) `commondir` ) ) ) {
        T c → {
            : String cd ( string_trim c )
            = common ? ( nc_is_abs ( string_data cd ) ) cd ( nc_join ( string_data gitdir ) ( string_data cd ) )
        }
        F → {}
    }
    : String head ?? ( nc_read ( string_data ( nc_join ( string_data gitdir ) `HEAD` ) ) ) { T h → ( string_trim h ) F → { ^ ( string_new ) } }
    ? ( __ct_hex40 head ) { ^ head } {}
    ? ! ( string_starts_with head `ref: ` ) { ^ ( string_new ) } {}
    : String ref ( string_substr head 5 - ( string_len head ) 5 )
    ?? ( nc_read ( string_data ( nc_join ( string_data common ) ( string_data ref ) ) ) ) {
        T x → {
            : String sha ( string_trim x )
            ? ( __ct_hex40 sha ) { ^ sha } {}
        }
        F → {}
    }
    ?? ( nc_read ( string_data ( nc_join ( string_data common ) `packed-refs` ) ) ) {
        T pr → {
            : ( Vec String ) ls ( nc_lines ( string_data pr ) )
            : i n ( vec_len [String] ls )
            : ~ i k 0
            ~ < k n {
                : String l ( string_clone ( vec_at [String] ls k ) )
                ? & > ( string_len l ) 41 ( string_ends_with l ( string_data ref ) ) {
                    : String sha ( string_substr l 0 40 )
                    : String tail ( string_substr l 41 - ( string_len l ) 41 )
                    ? & ( __ct_hex40 sha ) ( string_eq tail ref ) { ^ sha } {}
                } {}
                = k + k 1
            }
        }
        F → {}
    }
    ^ ( string_new )
}

@ __ct_formal_commit s formal → String {
    : String c ( __ct_git_commit_files formal )
    ? > ( string_len c ) 0 { ^ c } {}
    : ( Vec String ) ga ( vec_new [String] )
    ( vec_push [String] ga ( string_from `-C` ) )
    ( vec_push [String] ga ( string_from formal ) )
    ( vec_push [String] ga ( string_from `rev-parse` ) )
    ( vec_push [String] ga ( string_from `HEAD` ) )
    : Run gr ( nc_run `git` ga )
    ^ ? & . gr started == . gr code 0 ( __ct_first_line . gr out ) ( string_new )
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

// The second compile (the LLVM IR and the unsafe report) and nurlc's
// version, on a thread: a channel the two runs come back on, in that
// order. Where no thread starts, both run here first.
: Compile2 {
    ( Channel Run ) ch
    Thread th
}

@ __ct_compile2_run String nurlc ( Vec String ) a2 ( Channel Run ) tx → v {
    ( chan_send [Run] tx ( nc_run ( string_data nurlc ) a2 ) )
    : ( Vec String ) a3 ( vec_new [String] )
    ( vec_push [String] a3 ( string_from `--version` ) )
    ( chan_send [Run] tx ( nc_run ( string_data nurlc ) a3 ) )
}

@ __ct_compile2 String nurlc ( Vec String ) a2 → Compile2 {
    : ( Channel Run ) ch ( chan_new [Run] )
    : ( Channel Run ) tx ( Channel_share [Run] ch )
    : String n2 ( string_clone nurlc )
    : ( Vec String ) b2 ( vec_clone [String] a2 )
    : ( @ v ) job \ → v { ( __ct_compile2_run nurlc a2 tx ) }
    ^ ?? ( thread_spawn_owned job ) {
        T t → @ Compile2 { ch t }
        F _ → {
            ( __ct_compile2_run n2 b2 ch )
            @ Compile2 { ch ( thread_null ) }
        }
    }
}

// The next run back from the thread (none started: not started).
@ __ct_compile2_next Compile2 c → Run {
    ^ ?? ( chan_recv [Run] . c ch ) { T r → r F → @ Run { F -1 ( string_new ) ( string_new ) } }
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
    ?? ( file_delete ( string_data ( nc_join out `Elab.lean` ) ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( string_data ( nc_join out `Caps.lean` ) ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( string_data ( nc_join out `caps.tsv` ) ) ) { T _ → {} F _ → {} }

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
    : String tag ( rand_hex_str 16 )
    : String tag_arg ( string_from `--list-sources=` )
    ( string_push_str tag_arg ( string_data tag ) )
    ( vec_push [String] a1 tag_arg )
    ( vec_push [String] a1 ( string_from src ) )
    : Run r1 ( nc_run ( string_data . o nurlc ) a1 )
    ? | ! . r1 started != . r1 code 0 {
        ( nurl_eprint ( string_data . r1 err ) )
        ^ ( __ct_fail `nurlc did not compile the program; nothing to certify` )
    } {}
    : String core_path ( nc_join out `Program.core` )
    ? ! ( nc_write ( string_data core_path ) ( string_data . r1 out ) ) { ^ ( __ct_fail `cannot write Program.core` ) } {}
    // The hashes are of the bytes the core IR was made from: nurlc prints
    // each snapshot it compiled, and certify hashes those bytes. Each file
    // on disk must hold those bytes when certify checks it, so that
    // verify, which re-hashes the files, checks the bytes that were
    // compiled. A file that differs then (or one nurlc did not read whole)
    // certifies nothing; an edit undone before that check is not seen, and
    // need not be: the recorded hash is still of the compiled bytes.
    : ( Vec String ) sources ( vec_new [String] )
    : ( Vec String ) shas ( vec_new [String] )
    : ( Vec String ) rest1 ( vec_new [String] )
    ? ! ( cert_records . r1 err ( string_data tag ) sources shas rest1 ) { ^ ( __ct_fail `nurlc's list of sources is cut short` ) } {}
    ? == 0 ( vec_len [String] sources ) { ^ ( __ct_fail `nurlc listed no sources` ) } {}
    : ( Vec String ) disk ( __ct_hash_all sources )
    ? ! ( cert_same shas disk ) {
        ^ ( __ct_fail `a source file on disk is not the bytes nurlc compiled (changed during the run?); nothing is certified` )
    } {}

    // 2. nurlc: the LLVM IR and the unsafe report, and nurlc's version. They
    // go only into the manifest, so they run on a thread while the
    // translation and Lean run (`__ct_compile2`), and are read after Lean.
    // The thread starts them here, with the standard library's root the
    // working directory, which no step changes until they are read
    // (Lean's run sets its toolchain in the environment, `cert_lean_env`).
    : ( Vec String ) a2 ( vec_new [String] )
    ( vec_push [String] a2 ( string_from `--unsafe-report` ) )
    : String tag2 ( rand_hex_str 16 )
    : String tag2_arg ( string_from `--list-sources=` )
    ( string_push_str tag2_arg ( string_data tag2 ) )
    ( vec_push [String] a2 tag2_arg )
    ( vec_push [String] a2 ( string_from src ) )
    // (Lean's environment is set before the thread starts: `cert_lean_env`)
    ? ! ( cert_lean_env ( string_data . o formal ) ) { ^ ( __ct_fail `cannot set LEAN_PATH for Lean` ) } {}
    : Compile2 c2 ( __ct_compile2 ( string_clone . o nurlc ) a2 )

    // 3. The translation, held to the program grammar.
    : ~ String verdict ( string_from `accepted` )
    : ~ String reason ( string_new )
    : Translated tr ( cert_translate ( string_data core_path ) T )
    : String prog_path ( nc_join out `Program.lean` )
    : String claims_path ( nc_join out `Claims.lean` )
    : String elab_path ( nc_join out `Elab.lean` )
    : ~ i nv 0
    : ~ b threads F
    : ~ b cond F
    ? . tr ok {
        : ShapeRes sh ( cert_shape . tr lean )
        ? . sh ok {
            = nv . sh nv
            = threads . sh threads
            = cond > ( vec_len [i] . sh assumed ) 0
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
    : i nclaims ( cert_claim_count threads )
    : ~ b elab F
    // why a candidate the checker accepts has no Cert.elab (printed)
    : ~ String elab_why ( string_new )
    // N.cap: attempted, proved, why not, and what the manifest says of it
    : String caps_path ( nc_join out `Caps.lean` )
    : String ctab_path ( nc_join out `caps.tsv` )
    : ~ b try_caps F
    : ~ b caps F
    : ~ String caps_why ( string_from `the program is not accepted: nothing is claimed of it` )
    : ~ Json caps_json ( json_obj_new )
    : ~ ( Vec String ) caps_doors ( vec_new [String] )
    : ~ ( Vec String ) caps_axioms ( vec_new [String] )
    : ~ String caps_status ( string_from `open` )
    ? ( nc_is verdict `accepted` ) {
        : String claims ( cert_claims_lean prof nv threads cond )
        ? ! ( nc_write ( string_data claims_path ) ( string_data claims ) ) { ^ ( __ct_fail `cannot write Claims.lean` ) } {}
        // C.Elab: does the kernel build this very term from the core IR's
        // words? Lean decides, in the claims' run, for every term
        // that can be elabIR's at all (`cert_elab_candidate`: one with a
        // constructor elabIR never builds cannot, so Lean is not asked). A
        // core IR that is not UTF-8 has no words. Conditional bundles (with
        // stubs) get no Elab.lean in this step (AGORA-1033).
        : ~ b try_elab F
        ? ( cert_elab_candidate ( string_data . tr lean ) ) {
            ?? ( cert_elab_lean . r1 out threads cond ) {
                T el → { = try_elab ( nc_write ( string_data elab_path ) ( string_data el ) ) }
                F → {}
            }
        } {}
        // N.cap (AGORA-1013): the functions a run can enter, the classes
        // they reach (the core IR, through the capability table), and
        // Caps.lean, which Lean checks in the same run, as an optional part.
        : String ctab_src ( nc_join ( string_data . o stdlib ) `stdlib/caps.tsv` )
        ?? ( nc_read ( string_data ctab_src ) ) {
            T tab → {
                ?? ( cert_caps_make . tr lean . r1 out tab ) {
                    T cm → {
                        ? & ( nc_write ( string_data caps_path ) ( string_data ( cert_caps_lean . cm runs prof threads ) ) )
                        ( nc_write ( string_data ctab_path ) ( string_data tab ) ) {
                            = try_caps T
                            = caps_json . cm json
                            = caps_doors ( vec_clone [String] . . cm res doors )
                        } {}
                    }
                    F e → { = caps_why e }
                }
            }
            F → { = caps_why ( string_from `no capability table (stdlib/caps.tsv) under the standard library's root` ) }
        }
        : String work ( nc_join out `.build` )
        // A fresh directory for the one Lean file the check runs
        // (`cert_lean_check`: the bundle's modules, combined).
        ?? ( dir_remove_all ( string_data work ) ) { T _ → {} F _ → {} }
        ( nc_mkdirs ( string_data work ) )
        : LeanRun lr ( cert_lean_check2 ( string_data . o lean ) ( string_data formal ) out ( string_data work ) try_elab try_caps )
        ? ( cert_lean_refused . lr log ) {
            = verdict ( string_from `refused` )
            = reason ( string_from ? & threads cond `the verified checker refuses the program (C.certOK3BA is false)`
            ? threads `the verified checker refuses the program (C.certOK3B is false)`
            ? cond `the verified checker refuses the program (C.certOK2BA is false)`
            `the verified checker refuses the program (C.certOK2B is false)` )
        } {
            // (Lean's explanation of the failure may itself fail on a deep
            // term: the refusal is then proved in a run of its own)
            : b failed | ! . lr ran ( cert_lean_has_error . lr log )
            ? & failed ( cert_lean_refutes ( string_data . o lean ) ( string_data formal ) out ( string_data work ) threads cond ) {
                = verdict ( string_from `refused` )
                = reason ( string_from ? & threads cond `the verified checker refuses the program (C.certOK3BA is false, proved by the kernel)`
                ? threads `the verified checker refuses the program (C.certOK3B is false, proved by the kernel)`
                ? cond `the verified checker refuses the program (C.certOK2BA is false, proved by the kernel)`
                `the verified checker refuses the program (C.certOK2B is false, proved by the kernel)` )
            } {
                ? failed {
                    = verdict ( string_from `error` )
                    = reason ( string_from `Lean did not check the claims: ` )
                    ( string_push_str reason ( string_data ( __ct_first_line . lr log ) ) )
                    ( nurl_eprint ( string_data . lr log ) )
                } {}
            }
        }
        // The bundle keeps Elab.lean only for a program the checker accepts
        // and a run that proved Cert.elab on the standard axioms; otherwise
        // it is as before, its term the translator's (the translation row).
        = elab & & try_elab ( nc_is verdict `accepted` ) ( cert_elab_proved lr )
        ? & & try_elab ( nc_is verdict `accepted` ) ! elab {
            = elab_why ( __ct_first_err . lr elab_log )
            ? == 0 ( string_len elab_why ) { = elab_why ( string_from `Lean did not prove it on the standard axioms` ) } {}
        } {}
        ?? ( dir_remove_all ( string_data work ) ) { T _ → {} F _ → {} }
        ? ! elab { ?? ( file_delete ( string_data elab_path ) ) { T _ → {} F _ → {} } } {}
        = caps & & try_caps ( nc_is verdict `accepted` ) ( cert_caps_proved lr )
        ? caps {
            ?? ( cert_lean_axioms . lr caps_log `Cert.n_cap` ) {
                T ax → { = caps_axioms ( cert_axiom_list ax ) }
                F → {}
            }
            = caps_status ( string_from ( cert_status_of prof caps_axioms ) )
            = caps_why ( string_new )
            ? ( nc_is caps_status `open` ) {
                = caps F
                = caps_why ( string_from `Cert.n_cap rests on axioms beyond the profile's` )
            } {
                // a conditional bundle's N.cap is about the program with its
                // stubs: assumed, as its M claims are (AGORA-1033)
                ? cond { = caps_status ( string_from `assumed` ) } {}
            }
        } {
            ? & try_caps ( nc_is verdict `accepted` ) {
                = caps_why ( string_from `Lean did not check the list of functions a run can enter: ` )
                ( string_push_str caps_why ( string_data ( __ct_first_err . lr caps_log ) ) )
            } {}
        }
        ? ! caps {
            ?? ( file_delete ( string_data caps_path ) ) { T _ → {} F _ → {} }
            ?? ( file_delete ( string_data ctab_path ) ) { T _ → {} F _ → {} }
            = caps_status ( string_from `open` )
            = caps_axioms ( vec_new [String] )
        } {}
        : ~ i k 0
        ~ < k nclaims {
            ?? ( cert_lean_axioms . lr log ( cert_claim_lean k ) ) {
                T ax → {
                    : ( Vec String ) al ( cert_axiom_list ax )
                    ? ( nc_is verdict `accepted` ) {
                        : s raw ( cert_status_of prof al )
                        : s cst ? & cond == 0 ( nurl_str_eq raw `open` ) `assumed` raw
                        ( vec_push [String] statuses ( string_from cst ) )
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
    : ( Vec FnRow ) fns ( cert_functions ( string_data . r1 out ) )
    : i nf ( vec_len [FnRow] fns )
    // Assumed functions' ledger rows and premise ids (AGORA-1033).
    : ( Vec AssumedRow ) assumed_rows ( vec_new [AssumedRow] )
    : ( Vec String ) assumed_ids ( vec_new [String] )
    ? cond {
        : i nst ( vec_len [TlStub] . tr stubs )
        : ~ i si 0
        ~ < si nst {
            : TlStub sb ( vec_at [TlStub] . tr stubs si )
            : String loc ( string_new )
            ? & >= . sb idx 0 < . sb idx nf {
                : FnRow fr ( vec_at [FnRow] fns . sb idx )
                ( string_push_str loc ( string_data . fr file ) )
                ( string_push_str loc `:` )
                ( string_push_str loc ( string_data . fr line ) )
            } {}
            ( vec_push [AssumedRow] assumed_rows @ AssumedRow {
                . sb idx ( string_clone . sb name ) ( string_clone . sb sig )
                ( string_clone . sb callees ) . sb has_thru ( string_clone . sb why ) loc
            } )
            ( vec_push [String] assumed_ids ( cert_assumed_id ( string_data . sb name ) ) )
            = si + si 1
        }
    } {}
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

    // the encodings the kernel's term rests on, each a ledger row
    : ~ ( Vec String ) enc ( vec_new [String] )
    ? elab { = enc ( cert_enc_ids ( string_data . tr lean ) ) } {}
    : Json cl ( json_arr_new )
    : ~ i k 0
    ~ < k nclaims {
        : String st ?? ( vec_get [String] statuses k ) { T x → ( string_clone x ) F → ( string_from `open` ) }
        : ( Vec String ) ax ?? ( vec_get [( Vec String )] axioms k ) { T x → ( vec_clone [String] x ) F → ( vec_new [String] ) }
        : String why ? ( nc_is st `open` ) ( string_clone reason ) ( string_new )
        : String prem ( cert_claim_premises prof k elab enc assumed_ids )
        ( json_arr_push cl ( __ct_claim ( cert_claim_id k ) ( cert_claim_lean k ) ( string_data st )
        ( cert_claim_sentence threads cond k ) ( cert_claim_sentence_fi threads cond k ) ( string_data why ) ax ( string_data prem ) ) )
        = k + k 1
    }
    // M.unsafe: what nurlc's report says.
    // 2, read: the compile on the thread, and nurlc's version.
    : Run r2 ( __ct_compile2_next c2 )
    : Run r3 ( __ct_compile2_next c2 )
    ( thread_join . c2 th )
    ?? ( env_chdir ( string_data back ) ) { T _ → {} F _ → {} }
    ? ! . r2 started { ^ ( __ct_fail `nurlc did not start` ) } {}
    // This compile read the sources again: its LLVM IR and its unsafe
    // report count only when it read the very bytes the first run did.
    : ( Vec String ) sources2 ( vec_new [String] )
    : ( Vec String ) shas2 ( vec_new [String] )
    : ( Vec String ) rest2 ( vec_new [String] )
    : b rec2 ( cert_records . r2 err ( string_data tag2 ) sources2 shas2 rest2 )
    ? | | ! rec2 ! ( cert_same sources sources2 ) ! ( cert_same shas shas2 ) {
        ^ ( __ct_fail `the compile for the LLVM IR and the unsafe report read other source bytes than the first; nothing is certified` )
    } {}
    // nurlc's own borrow walk may refuse a program the core IR still
    // describes: it has no LLVM IR then, and its unsafe report is cut short.
    : b compiled == . r2 code 0
    : String llvm_sha ? compiled ( nc_sha256_text ( string_data . r2 out ) ) ( string_new )
    : ( Vec String ) unsafe_rows ( __ct_unsafe_rows rest2 )
    : String nurlc_ver ( __ct_first_line . r3 out )

    : i nu ( vec_len [String] unsafe_rows )
    : String uen ? == nu 0 ( string_from `It contains no hand-vouched (unsafe) code outside the standard library.` )
    ( string_from `It contains hand-vouched (unsafe) code outside the standard library: see the ledger rows unsafe-*.` )
    : String ufi ? == nu 0 ( string_from `Siinä ei ole käsin taattua (unsafe) koodia vakiokirjaston ulkopuolella.` )
    ( string_from `Siinä on käsin taattua (unsafe) koodia vakiokirjaston ulkopuolella: katso rivit unsafe-*.` )
    : s ust ? compiled `assumed` `open`
    : s uwhy ? compiled `nurlc --unsafe-report` `nurlc refuses to compile the program, so its unsafe report is incomplete`
    ( json_arr_push cl ( __ct_claim `M.unsafe` `` ust ( string_data uen ) ( string_data ufi )
    uwhy ( vec_new [String] ) `unsafe-report` ) )
    // N.cap: which functions a run can enter (Cert.n_cap), and the classes
    // they reach (AGORA-1013)
    : String cen ? caps ( cert_caps_sentence_en caps_doors ) ( string_from ( cert_caps_open_en ) )
    : String cfi ? caps ( cert_caps_sentence_fi caps_doors ) ( string_from ( cert_caps_open_fi ) )
    : String cprem ( cert_caps_premises prof caps elab enc nu assumed_ids )
    ( json_arr_push cl ( __ct_claim `N.cap` `Cert.n_cap` ( string_data caps_status ) ( string_data cen ) ( string_data cfi )
    ( string_data caps_why ) caps_axioms ( string_data cprem ) ) )
    ( mj_set m `claims` cl )
    ? caps { ( mj_set m `capabilities` caps_json ) } {}

    // Coverage: the program's own functions.
    : Json cov ( json_obj_new )
    : Json fa ( json_arr_new )
    // A function's status is the program's: its claims' weakest status
    // when accepted (`proved` only when every M claim is kernel-proved, or
    // in a conditional certificate when every M claim is `assumed` under
    // kernel), else the verdict.
    : String fst ( __ct_cov_status verdict statuses cond prof )
    // A function the translation does not cover is `unsupported` with its
    // own reason (`error` where the translation stopped on it), whatever the
    // others are (AGORA-1015). One it covers in a program that is not
    // translated whole is `open`: no claim is proved for it. The functions
    // after the one the translation stopped in are `error`, not reached; and
    // where it refused the program before it translated any function (no
    // `main`), every one is `unsupported`, with the program's reason.
    : i six ( __ct_stop_ix . tr miss )
    : ~ String stopped ( string_new )
    // (the function it stopped in: the entry before the mark)
    : ~ String stop_at ( string_new )
    ? >= six 0 { = stopped ( string_clone . ( vec_at [TlMiss] . tr miss six ) why ) } {}
    ? > six 0 { = stop_at ( string_clone . ( vec_at [TlMiss] . tr miss - six 1 ) name ) } {}
    : b none_reached == six 0
    : ~ b past F
    : ( Vec String ) cst ( vec_new [String] )
    : ( Vec i ) ccount ( vec_new [i] )
    : ~ i j 0
    ~ < j nf {
        ?? ( vec_get [FnRow] fns j ) {
            T f → {
                : ~ String st ( string_clone fst )
                : ~ String why ( string_clone reason )
                : i mi ( __ct_miss_at . tr miss ( string_data . f name ) )
                ? >= mi 0 {
                    = why ( string_clone . ( vec_at [TlMiss] . tr miss mi ) why )
                    = st ( string_from ? ( string_starts_with why `internal: ` ) `error` `unsupported` )
                    ? & > ( string_len stop_at ) 0 ( nc_is . f name ( string_data stop_at ) ) { = past T } {}
                } {
                    ? none_reached {
                        = st ( string_from `unsupported` )
                        = why ( string_from `not translated: the program is refused before its functions are: ` )
                        ( string_push_str why ( string_data stopped ) )
                    } {
                        ? past {
                            = st ( string_from `error` )
                            = why ( string_clone stopped )
                        } {
                            ? ( nc_is verdict `unsupported` ) {
                                = st ( string_from `open` )
                                = why ( string_from `translated; the program is not: ` )
                                ( string_push_str why ( string_data reason ) )
                            } {}
                        }
                    }
                }
                ( __ct_count cst ccount ( string_data st ) )
                : Json fo ( json_obj_new )
                ( mj_str fo `name` ( string_data . f name ) )
                ( mj_str fo `file` ( string_data . f file ) )
                ( mj_str fo `line` ( string_data . f line ) )
                ( mj_str fo `status` ( string_data st ) )
                ( mj_str fo `reason` ( string_data why ) )
                ( json_arr_push fa fo )
            }
            F _ → {}
        }
        = j + j 1
    }
    ( mj_set cov `functions` fa )
    : ~ i jc 0
    ~ < jc ( vec_len [String] cst ) {
        ( mj_int cov ( string_data ( vec_at [String] cst jc ) ) ( vec_at [i] ccount jc ) )
        = jc + jc 1
    }
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
                ?? ( vec_get [String] shas q ) {
                    T h → ( mj_str so `sha256` ( string_data h ) )
                    F _ → {}
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
    ? elab {
        ?? ( nc_sha256_file ( string_data elab_path ) ) { T h → ( mj_str hs `elab_lean` ( string_data h ) ) F → {} }
    } {}
    ? caps {
        ?? ( nc_sha256_file ( string_data caps_path ) ) { T h → ( mj_str hs `caps_lean` ( string_data h ) ) F → {} }
        ?? ( nc_sha256_file ( string_data ctab_path ) ) { T h → ( mj_str hs `caps_tsv` ( string_data h ) ) F → {} }
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
    ( mj_str vs `formal_commit` ( string_data ( __ct_formal_commit ( string_data formal ) ) ) )
    : String tc_path ( nc_join ( string_data formal ) `lean-toolchain` )
    : String tc ?? ( nc_read ( string_data tc_path ) ) { T t → ( string_trim t ) F → ( string_new ) }
    ( mj_str vs `lean_toolchain` ( string_data tc ) )
    ( mj_set m `versions` vs )

    ( mj_set m `ledger` ( cert_ledger prof unsafe_rows threads elab enc assumed_rows caps ) )

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
        ( nurl_print `  N.cap ` )
        ( nurl_println ( string_data caps_status ) )
        ? > ( string_len caps_why ) 0 {
            ( nurl_print `  N.cap not proved: ` )
            ( nurl_println ( string_data caps_why ) )
        } {}
        ? cond {
            ( nurl_print `  assumed: ` )
            ( nurl_print_int ( vec_len [AssumedRow] assumed_rows ) )
            ( nurl_println ` function(s)` )
        } {}
        ( nurl_println ? elab `  term: Cert.elab (the kernel built it from the core IR's words)` `  term: the translator's (the translation ledger row)` )
        ? > ( string_len elab_why ) 0 {
            ( nurl_print `  Cert.elab not proved: ` )
            ( nurl_println ( string_data elab_why ) )
        } {}
        ^ ? all 0 1
    } {}
    ? ( nc_is verdict `refused` ) { ^ 3 } {}
    ? ( nc_is verdict `unsupported` ) { ^ 2 } {}
    ^ 1
}
