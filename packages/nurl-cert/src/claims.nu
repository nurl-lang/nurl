// claims.nu — the claims of a memory-safety certificate, and the Lean file
// that states and proves them (Claims.lean).
//
// Claims.lean is a pure function of the profile and the program's slot
// count. `certify` writes it from here; `verify` writes it again from here
// and compares the bundle's copy byte for byte. A statement weakened, a
// proof replaced by `sorry`, or an axiom added in the bundle is therefore
// a difference, before Lean is even asked.
//
// The statements use A2's semantics only (`A2.Steps`, `A2.Stuck`,
// `A2.emptyMem`, `Mem.alloc`): what a reviewer reads in formal/CLAIM.md.
// The checker (`C.certOK2B`, formal/C/Cert.lean) is how they are proved,
// not what they say.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `util.nu`
$ `words.nu`

// The two profiles. `kernel`: the verdict is decided by the Lean kernel
// (`decide +kernel`), the three standard axioms only. `fast`: decided by
// compiled code (`native_decide`), whose claims are `validated`.
@ cert_profile_ok s prof → b {
    ^ | != 0 ( nurl_str_eq prof `kernel` ) != 0 ( nurl_str_eq prof `fast` )
}

@ __cl_tactic s prof → s {
    ? != 0 ( nurl_str_eq prof `fast` ) { ^ `native_decide` } {}
    ^ `decide +kernel`
}

// The memory-safety claims: id, Lean name, sentence. A single-threaded
// program gets M.safe and M.leak from A2's theorems; a threaded one
// (Program.lean names the functions it spawns) gets them, and M.race, from
// A3's claim, over every interleaving of its threads (formal/C/Cert3.lean).
// Module globals are not translated yet: such a program is unsupported.
@ cert_claim_count b threads → i { ^ ? threads 3 2 }

@ cert_claim_id i k → s {
    ? == k 0 { ^ `M.safe` } {}
    ? == k 1 { ^ `M.leak` } {}
    ^ `M.race`
}

@ cert_claim_lean i k → s {
    ? == k 0 { ^ `Cert.m_safe` } {}
    ? == k 1 { ^ `Cert.m_leak` } {}
    ^ `Cert.m_race`
}

// A claim's sentence. A threaded program's claims are A3's, over the runs
// in which every thread it spawns starts (the translation takes each
// `thread_spawn_owned` to succeed: a run where `pthread_create` fails, and
// the code that handles that, is outside the claim), and its M.leak is
// over runs in which every thread has finished (`cert3_leak`: A3's leak
// clause asks that of a run, and says nothing of one a panic ends).
@ cert_claim_sentence b threads b cond i k → s {
    ? threads {
        ? == k 0 { ^ `It never reads or writes memory it does not own, on any run in which every thread it spawns starts.` } {}
        ? == k 1 { ^ `On any run in which every thread it spawns starts, once every thread has finished, it has released everything it allocated.` } {}
        ^ `Its threads never race on shared memory, on any run in which every thread it spawns starts.`
    } {}
    ? cond {
        ? == k 0 { ^ `Assuming the listed functions follow their summaries, it never reads or writes memory it does not own, on any run.` } {}
        ^ `Assuming the listed functions follow their summaries, everything it allocates it releases, also when it stops with an error.`
    } {}
    ? == k 0 { ^ `It never reads or writes memory it does not own, on any run.` } {}
    ^ `Everything it allocates it releases, also when it stops with an error.`
}

@ cert_claim_sentence_fi b threads b cond i k → s {
    ? threads {
        ? == k 0 { ^ `Se ei koskaan lue eikä kirjoita muistia, jota se ei omista, millään ajolla, jolla jokainen sen käynnistämä säie käynnistyy.` } {}
        ? == k 1 { ^ `Millä tahansa ajolla, jolla jokainen sen käynnistämä säie käynnistyy, se on vapauttanut kaiken minkä varasi, kun jokainen säie on päättynyt.` } {}
        ^ `Sen säikeet eivät koskaan kilpaile jaetusta muistista millään ajolla, jolla jokainen sen käynnistämä säie käynnistyy.`
    } {}
    ? cond {
        ? == k 0 { ^ `Olettaen että luetellut funktiot noudattavat yhteenvetojaan, se ei koskaan lue eikä kirjoita muistia, jota se ei omista, millään ajolla.` } {}
        ^ `Olettaen että luetellut funktiot noudattavat yhteenvetojaan, kaiken minkä se varaa, se vapauttaa, myös kun se pysähtyy virheeseen.`
    } {}
    ? == k 0 { ^ `Se ei koskaan lue eikä kirjoita muistia, jota se ei omista, millään ajolla.` } {}
    ^ `Kaiken minkä se varaa, se vapauttaa, myös kun se pysähtyy virheeseen.`
}

// A claim's premises, the ledger rows it rests on: M.race also on the C11 /
// LLVM memory model's DRF-SC guarantee (the model's race freedom is the
// binary's sequential consistency), which is cited, not mechanized. With
// Elab.lean (`elab`), the translation is the core IR's words and the
// encodings the term uses (`enc`, cert_enc_ids), AGORA-1029; without it,
// the translator. Conditional certificates also rest on each `assumed-fn:*`
// ledger row (`assumed_ids`, AGORA-1033).
@ cert_claim_premises s prof i k b elab ( Vec String ) enc ( Vec String ) assumed_ids → String {
    : String p ( string_from `lean-kernel claim-definitions` )
    ? elab {
        ( string_push_str p ` core-ir-words` )
        : i ne ( vec_len [String] enc )
        : ~ i j 0
        ~ < j ne {
            ( string_push_char p 32 )
            ( string_push_str p ( string_data ( vec_at [String] enc j ) ) )
            = j + j 1
        }
    } { ( string_push_str p ` translation` ) }
    ( string_push_str p ` library-summaries` )
    ? != 0 ( nurl_str_eq prof `fast` ) { ( string_push_str p ` lean-compiler` ) } {}
    ? == k 2 { ( string_push_str p ` drf-sc` ) } {}
    : i na ( vec_len [String] assumed_ids )
    : ~ i aj 0
    ~ < aj na {
        ( string_push_char p 32 )
        ( string_push_str p ( string_data ( vec_at [String] assumed_ids aj ) ) )
        = aj + aj 1
    }
    ^ p
}

// The three axioms every Lean proof may rest on, and nothing else under
// `kernel`.
@ cert_std_axiom s name → b {
    ^ | | != 0 ( nurl_str_eq name `propext` ) != 0 ( nurl_str_eq name `Classical.choice` )
    != 0 ( nurl_str_eq name `Quot.sound` )
}

@ __cl_slots i nv → String {
    : String o ( string_new )
    ( string_push_int o nv )
    ^ o
}

// Claims.lean for a program over `nv` slots, under profile `prof`;
// `threads`: the A3 template; `cond`: the conditional template (C.Complete).
@ cert_claims_lean s prof i nv b threads b cond → String {
    ? threads { ^ ( __cl_claims3 prof nv ) } {}
    ? cond { ^ ( __cl_claims_cond prof nv ) } {}
    : String n ( __cl_slots nv )
    : s ns ( string_data n )
    : String o ( string_with_cap 2048 )
    ( string_push_str o `-- Generated by nurl-cert: the claims of this certificate. nurl-cert verify\n` )
    ( string_push_str o `-- writes this file again and compares it byte for byte; do not edit it.\n` )
    ( string_push_str o `-- Program.lean is the program as a term of formal/A2 (P, entry).\n` )
    ( string_push_str o `import Program\n\n` )
    ( string_push_str o `namespace Cert\n\n` )
    ( string_push_str o `/-- The verified checker accepts the program (formal/C/Cert.lean). -/\n` )
    ( string_push_str o `theorem verdict : C.certOK2B P entry ` )
    ( string_push_str o ns )
    ( string_push_str o ` = true := by ` )
    ( string_push_str o ( __cl_tactic prof ) )
    ( string_push_str o `\n\n` )
    ( string_push_str o `/-- M.safe: ` )
    ( string_push_str o ( cert_claim_sentence F F 0 ) )
    ( string_push_str o ` -/\n` )
    ( string_push_str o `theorem m_safe :\n    ∀ m' s', A2.Steps P (A2.emptyMem ` )
    ( string_push_str o ns )
    ( string_push_str o `) entry (.ok m' s') → ¬ A2.Stuck P m' s' :=\n  C.cert_safe verdict\n\n` )
    ( string_push_str o `/-- M.leak: ` )
    ( string_push_str o ( cert_claim_sentence F F 1 ) )
    ( string_push_str o ` -/\n` )
    ( string_push_str o `theorem m_leak :\n    (∀ m', A2.Steps P (A2.emptyMem ` )
    ( string_push_str o ns )
    ( string_push_str o `) entry (.ok m' .skip) → ∀ i, m'.alloc i = false) ∧\n` )
    ( string_push_str o `    (∀ m', A2.Steps P (A2.emptyMem ` )
    ( string_push_str o ns )
    ( string_push_str o `) entry (.panic m') → ∀ i, m'.alloc i = false) :=\n` )
    ( string_push_str o `  ⟨C.cert_leak_end verdict, C.cert_leak_panic verdict⟩\n\n` )
    ( string_push_str o `end Cert\n\n` )
    : i k0 0
    : ~ i k k0
    ~ < k ( cert_claim_count F ) {
        ( string_push_str o `#print axioms ` )
        ( string_push_str o ( cert_claim_lean k ) )
        ( string_push_str o `\n` )
        = k + k 1
    }
    ^ o
}

// The conditional template (formal/C/Complete.lean, AGORA-1033): the verdict
// over `assumed`, and M.safe / M.leak for every completion `P'` where the
// assumed functions satisfy `AssumedOK`.
@ __cl_claims_cond s prof i nv → String {
    : String n ( __cl_slots nv )
    : s ns ( string_data n )
    : String o ( string_with_cap 2048 )
    ( string_push_str o `-- Generated by nurl-cert: the claims of this certificate. nurl-cert verify\n` )
    ( string_push_str o `-- writes this file again and compares it byte for byte; do not edit it.\n` )
    ( string_push_str o `-- Program.lean is the program as a term of formal/A2 (P, entry) and the\n` )
    ( string_push_str o `-- indices of its assumed functions (assumed); the claims are conditional\n` )
    ( string_push_str o `-- over every completion of P at assumed (formal/C/Complete.lean).\n` )
    ( string_push_str o `import C.Complete\nimport Program\n\n` )
    ( string_push_str o `namespace Cert\n\n` )
    ( string_push_str o `/-- The verified checker accepts the program outside its assumed functions (formal/C/Complete.lean). -/\n` )
    ( string_push_str o `theorem verdict : C.certOK2BA P assumed entry ` )
    ( string_push_str o ns )
    ( string_push_str o ` = true := by ` )
    ( string_push_str o ( __cl_tactic prof ) )
    ( string_push_str o `\n\n` )
    ( string_push_str o `/-- M.safe: ` )
    ( string_push_str o ( cert_claim_sentence F T 0 ) )
    ( string_push_str o ` -/\n` )
    ( string_push_str o `theorem m_safe :\n    ∀ P', C.Completes assumed P P' → C.AssumedOK assumed P' →\n` )
    ( string_push_str o `      ∀ m' s', A2.Steps P' (A2.emptyMem ` )
    ( string_push_str o ns )
    ( string_push_str o `) entry (.ok m' s') → ¬ A2.Stuck P' m' s' :=\n  C.cert_safe_cond verdict\n\n` )
    ( string_push_str o `/-- M.leak: ` )
    ( string_push_str o ( cert_claim_sentence F T 1 ) )
    ( string_push_str o ` -/\n` )
    ( string_push_str o `theorem m_leak :\n    (∀ P', C.Completes assumed P P' → C.AssumedOK assumed P' →\n` )
    ( string_push_str o `      ∀ m', A2.Steps P' (A2.emptyMem ` )
    ( string_push_str o ns )
    ( string_push_str o `) entry (.ok m' .skip) → ∀ i, m'.alloc i = false) ∧\n` )
    ( string_push_str o `    (∀ P', C.Completes assumed P P' → C.AssumedOK assumed P' →\n` )
    ( string_push_str o `      ∀ m', A2.Steps P' (A2.emptyMem ` )
    ( string_push_str o ns )
    ( string_push_str o `) entry (.panic m') → ∀ i, m'.alloc i = false) :=\n` )
    ( string_push_str o `  ⟨C.cert_leak_end_cond verdict, C.cert_leak_panic_cond verdict⟩\n\n` )
    ( string_push_str o `end Cert\n\n` )
    : ~ i k 0
    ~ < k ( cert_claim_count F ) {
        ( string_push_str o `#print axioms ` )
        ( string_push_str o ( cert_claim_lean k ) )
        ( string_push_str o `\n` )
        = k + k 1
    }
    ^ o
}

// The A3 template: the verdict over the spawned functions `spawns`, and
// the three claims on every interleaving from the entry's start.
@ __cl_claims3 s prof i nv → String {
    : String n ( __cl_slots nv )
    : s ns ( string_data n )
    : String reach ( string_from `∀ C, A3.Reach P (fun f => decide (f ∈ spawns)) (A3.Cfg.init entry ` )
    ( string_push_str reach ns )
    ( string_push_str reach `) C →` )
    : s rs ( string_data reach )
    : String o ( string_with_cap 2048 )
    ( string_push_str o `-- Generated by nurl-cert: the claims of this certificate. nurl-cert verify\n` )
    ( string_push_str o `-- writes this file again and compares it byte for byte; do not edit it.\n` )
    ( string_push_str o `-- Program.lean is the program as a term of formal/A2 (P, entry) and the\n` )
    ( string_push_str o `-- functions it spawns (spawns); the claims are A3's, over its threads.\n` )
    ( string_push_str o `import C.Cert3\nimport Program\n\n` )
    ( string_push_str o `namespace Cert\n\n` )
    ( string_push_str o `/-- The verified checker accepts the program and its spawns (formal/C/Cert3.lean). -/\n` )
    ( string_push_str o `theorem verdict : C.certOK3B P spawns entry ` )
    ( string_push_str o ns )
    ( string_push_str o ` = true := by ` )
    ( string_push_str o ( __cl_tactic prof ) )
    ( string_push_str o `\n\n` )
    ( string_push_str o `/-- M.safe: ` )
    ( string_push_str o ( cert_claim_sentence T F 0 ) )
    ( string_push_str o ` -/\n` )
    ( string_push_str o `theorem m_safe :\n    ` )
    ( string_push_str o rs )
    ( string_push_str o ` ∀ (i : Nat) (t : A3.Thread), C.ths[i]? = some t → ¬ A2.Stuck P (C.view t) t.s :=\n  C.cert3_safe verdict\n\n` )
    ( string_push_str o `/-- M.leak: ` )
    ( string_push_str o ( cert_claim_sentence T F 1 ) )
    ( string_push_str o ` -/\n` )
    ( string_push_str o `theorem m_leak :\n    ` )
    ( string_push_str o rs )
    ( string_push_str o ` (∀ t ∈ C.ths, t.s = .skip) → ∀ i, C.alloc i = false :=\n  C.cert3_leak verdict\n\n` )
    ( string_push_str o `/-- M.race: ` )
    ( string_push_str o ( cert_claim_sentence T F 2 ) )
    ( string_push_str o ` -/\n` )
    ( string_push_str o `theorem m_race :\n    ` )
    ( string_push_str o rs )
    ( string_push_str o ` ¬ A3.Race P C :=\n  C.cert3_race verdict\n\n` )
    ( string_push_str o `end Cert\n\n` )
    : ~ i k 0
    ~ < k ( cert_claim_count T ) {
        ( string_push_str o `#print axioms ` )
        ( string_push_str o ( cert_claim_lean k ) )
        ( string_push_str o `\n` )
        = k + k 1
    }
    ^ o
}

// ── Elab.lean: the term checked by the kernel (AGORA-1029) ────────────
//
// Elab.lean holds Program.core's words (`cert_words`, words.nu) and the
// theorem that Program.lean's term is the one `C.Elab.elabIR` builds from
// them (formal/C/Elab.lean). It is a pure function of Program.core: `verify`
// writes it again and compares the bundle's copy byte for byte. The words
// are `noncomputable` (only the kernel runs them; compiling a literal of a
// few thousand words costs a quarter of a second), and `elabIs_sound` turns
// the kernel's `true` into the equation, on the standard axioms. The words
// are numbers (0x1, then a word's bytes last to first), which
// `C.Elab.elabIR` reads back into the bytes. None when the core IR holds a
// NUL byte (`cert_words_ok`). (`elab` is
// a keyword of Lean, hence `«elab»`; Lean prints the name `Cert.elab`.)
// A threaded program's (`threads`: Program.lean names its spawns) is
// about `C.Elab.elabIR3`, which builds the spawn wrappers too (step 10).
@ cert_elab_lean String core b threads → ?String {
    ? ! ( cert_words_ok core ) { ^ @ ?String { F } } {}
    : String w ( cert_words ( string_data core ) )
    : String o ( string_with_cap + ( string_len w ) 1024 )
    ( string_push_str o `-- Generated by nurl-cert: Program.lean's term is the one C.Elab.elabIR builds\n` )
    ( string_push_str o `-- from the words of Program.core, checked by the kernel. nurl-cert verify\n` )
    ( string_push_str o `-- writes this file again from Program.core and compares it byte for byte;\n` )
    ( string_push_str o `-- do not edit it.\n` )
    ( string_push_str o `import Program\nimport C.Elab\n\n` )
    ( string_push_str o `namespace Cert\n\n` )
    ( string_push_str o `/-- Program.core as words (nurl-cert words). -/\n` )
    ( string_push_str o `noncomputable ` )
    ( string_push_str o ( string_data w ) )
    ? threads {
        ( string_push_str o `\n/-- The term (P, spawns, entry) is C.Elab.elabIR3's of those words (formal/C/Elab.lean). -/\n` )
        ( string_push_str o `theorem «elab» : C.Elab.elabIR3 ir = some (P, spawns, entry) :=\n` )
        ( string_push_str o `  C.Elab.elabIs3_sound _ _ _ _ (by decide +kernel)\n\n` )
    } {
        ( string_push_str o `\n/-- The term (P, entry) is C.Elab.elabIR's of those words (formal/C/Elab.lean). -/\n` )
        ( string_push_str o `theorem «elab» : C.Elab.elabIR ir = some (P, entry) :=\n` )
        ( string_push_str o `  C.Elab.elabIs_sound _ _ _ (by decide +kernel)\n\n` )
    }
    ( string_push_str o `end Cert\n\n` )
    ( string_push_str o `#print axioms Cert.«elab»\n` )
    ^ @ ?String { T o }
}

// The constructors `C.Elab.elabIR` builds terms from (formal/C/Elab.lean:
// `go`, `rhsS`, `intrP`, `editS`, `callAny`, `letcallS`, `readP`,
// `operandE`, `operandP`, `fieldTemp`, `retR`, `modeOf`, `fnElab`, `elabIR`;
// step 6's `callindS`, `cloLitS`, `pairUp`, `capBinds`, `cloFnElab`,
// `envTy`, `ifaceFn`; step 7's `tyR`, `sndChain`; step 8's `dtorU`, `tyOf`
// and `go`'s `.letd`), as the translator writes them:
//   Stmt  .skip .seq .letv .letcall .assign .ite .exit .block .loop .push .free .edit .callc .letd
//   Rhs   .expr .new .var .borrow .at .view .sat .pack .pair .fst .snd .inl .inr .getr
//         .lockNew .lockClone .chanSend .chanRecv .chanClose (step 9, `intrP`)
//         .getl (step 10, a result's error)
//   Expr  .any .lit .var .add .lt .len .slen .isl
//   Edit  .push .trunc
//   PMode .inp .sink .inout
//   Eff   .replace .drop .realloc .dropIn
//   Ty    .int .vec .slice .prod .sum .fn .dtor .lk
//   Cross .any .send (a closure's class, `.any` the same word as Expr's; `.send` a
//         spawned one's, step 10)
// and the Bools of `resOwn := false` / `true` (a buffer, a struct or an
// option handed back) and of `.edit true` (a change through a borrow). A
// new constructor elabIR emits goes into this list too (Elab.lean says so
// above `elabIR`); the selftest's sweep fails if a certify program in the
// subset loses its Elab.lean.
// (Step 8 adds `.letd` and `.dtor`, which elabIR builds for a value of a
// destructor type of the program's own, and its type.)
// Of those, the ones elabIR builds for closures alone (step 6; step 7's
// structs build `.prod .pair .fst .snd` too).
: s ELAB_CLO_CTORS `callc pack`
: s ELAB_CTORS `skip seq letv letcall assign ite exit block loop push free edit callc letd expr new var borrow at view sat pack pair fst snd inl inr getr any lit add lt len slen isl trunc inp sink inout replace drop realloc dropIn int vec slice prod sum fn dtor lockNew lockClone chanSend chanRecv chanClose lk getl send`

// Can Program.lean's term be `elabIR`'s at all? F when it holds a
// constructor outside ELAB_CTORS: `elabIs` compares the two terms
// constructor by constructor, so `elabIR ir = some (P, entry)` is then
// impossible whatever the core IR, and skipping Lean on it is exact. T
// decides nothing: Lean does. (`text` has passed shape.nu's grammar: ASCII,
// constructors written `.name`; the `import`/`open` lines are skipped. A
// `true` is no constructor: the translator writes it in `resOwn` and in
// constructors outside the list, `.edit true`, `.chanRecv true`.)
// Also F when it holds one of ELAB_CLO_CTORS but no `.fn`: elabIR builds
// `.callc` and `.pack` only for a call through, or a literal of, a variable
// of a closure type, and every closure type has an interface whose first
// parameter is a `.fn` (formal/C/Elab.lean says so above `elabIR`), so this
// skip is exact as well.
@ cert_elab_candidate s text → b {
    : ( Vec String ) ok ( string_split ( string_from ELAB_CTORS ) ` ` )
    : ( Vec String ) clo ( string_split ( string_from ELAB_CLO_CTORS ) ` ` )
    : ~ b has_clo F
    : ~ b has_fn F
    : ( Vec String ) ls ( nc_lines text )
    : i nl ( vec_len [String] ls )
    : ~ i q 0
    ~ < q nl {
        ?? ( vec_get [String] ls q ) {
            T l → {
                ? | ( string_starts_with l `import ` ) ( string_starts_with l `open ` ) {} {
                    : ( Slice u ) t ( slice_of_str ( string_data l ) )
                    : i n ( slice_len [u] t )
                    : ~ i k 0
                    ~ < k n {
                        : i c ( slice_byte t k )
                        ? ( __cl_word c ) {
                            // a word: a constructor when a `.` with no word
                            // character before it starts it
                            : ~ i e k
                            ~ & < e n ( __cl_word ( slice_byte t e ) ) { = e + e 1 }
                            : ~ b dotted F
                            ? > k 0 { ? == ( slice_byte t - k 1 ) 46 { = dotted T } {} } {}
                            ? & dotted > k 1 { ? ( __cl_word ( slice_byte t - k 2 ) ) { = dotted F } {} } {}
                            : String w ( string_new )
                            ( string_push_window w t k - e k )
                            ? dotted {
                                ? ! ( __cl_in w ok ) { ^ F } {}
                                ? ( __cl_in w clo ) { = has_clo T } {}
                                ? != 0 ( nurl_str_eq ( string_data w ) `fn` ) { = has_fn T } {}
                            } {}
                            = k e
                        } { = k + k 1 }
                    }
                }
            }
            F _ → {}
        }
        = q + q 1
    }
    ^ | ! has_clo has_fn
}

// The constructors a term holds (`.name` words, as cert_elab_candidate
// reads them), each once, in the order first met.
@ cert_ctors s text → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ( Vec String ) ls ( nc_lines text )
    : i nl ( vec_len [String] ls )
    : ~ i q 0
    ~ < q nl {
        : String l ( string_clone ( vec_at [String] ls q ) )
        ? | ( string_starts_with l `import ` ) ( string_starts_with l `open ` ) {} {
            : ( Slice u ) t ( slice_of_str ( string_data l ) )
            : i n ( slice_len [u] t )
            : ~ i k 0
            ~ < k n {
                : i c ( slice_byte t k )
                ? ( __cl_word c ) {
                    : ~ i e k
                    ~ & < e n ( __cl_word ( slice_byte t e ) ) { = e + e 1 }
                    : ~ b dotted F
                    ? > k 0 { ? == ( slice_byte t - k 1 ) 46 { = dotted T } {} } {}
                    ? & dotted > k 1 { ? ( __cl_word ( slice_byte t - k 2 ) ) { = dotted F } {} } {}
                    ? dotted {
                        : String w ( string_new )
                        ( string_push_window w t k - e k )
                        ? ! ( __cl_in w out ) { ( vec_push [String] out w ) } {}
                    } {}
                    = k e
                } { = k + k 1 }
            }
        }
        = q + q 1
    }
    ^ out
}

// Does the term hold any of the constructors `names`?
@ __enc_any ( Vec String ) cs s names → b {
    : ( Vec String ) want ( string_split ( string_from names ) ` ` )
    : i n ( vec_len [String] want )
    : ~ i k 0
    ~ < k n {
        ? ( __cl_in ( vec_at [String] want k ) cs ) { ^ T } {}
        = k + k 1
    }
    ^ F
}

// The encodings of C.Elab.elabIR's (docs/dev/TRANSLATION_TRUST.md, "The
// encodings") a term of the kernel's rests on, each a ledger row: the ones
// whose constructors it holds (generously: a row is named where it may
// apply; one named for nothing is only more to read). Numbers always.
@ cert_enc_ids s text → ( Vec String ) {
    : ( Vec String ) cs ( cert_ctors text )
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out ( string_from `enc-numbers` ) )
    ? ( __enc_any cs `slice view new` ) { ( vec_push [String] out ( string_from `enc-raw-text` ) ) } {}
    ? ( __enc_any cs `sum prod pair fst snd inl inr isl getr getl` ) { ( vec_push [String] out ( string_from `enc-shapes` ) ) } {}
    ? ( __enc_any cs `dtor letd` ) { ( vec_push [String] out ( string_from `enc-destructors` ) ) } {}
    ? ( __enc_any cs `fn pack callc` ) { ( vec_push [String] out ( string_from `enc-closures` ) ) } {}
    ? ( __enc_any cs `send` ) { ( vec_push [String] out ( string_from `enc-threads` ) ) } {}
    ? ( __enc_any cs `lk lockNew lockClone chanSend chanRecv chanClose` ) { ( vec_push [String] out ( string_from `enc-channels` ) ) } {}
    // (the walk's summaries read into the term: a `sink` or `inout`
    // parameter, a change through a borrow, a cursor; elabIR's results lend
    // nothing, `lends := []`)
    ? ( __enc_any cs `sink inout borrow sat edit` ) { ( vec_push [String] out ( string_from `enc-summaries` ) ) } {}
    ^ out
}

@ __cl_word i c → b { ^ | | | & >= c 65 <= c 90 & >= c 97 <= c 122 & >= c 48 <= c 57 == c 95 }

@ __cl_in String x ( Vec String ) v → b {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] v k ) { T y → { ? ( string_eq x y ) { ^ T } {} } F _ → {} }
        = k + k 1
    }
    ^ F
}
