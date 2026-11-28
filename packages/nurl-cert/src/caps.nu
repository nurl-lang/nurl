// caps.nu — N.cap, what a certified program can do outside its own memory
// (AGORA-1013).
//
// Two halves, kept apart in the bundle as they are in the proof:
//
// 1. Which of the program's functions a run can enter. `cert_runs` reads
//    the names Program.lean's term holds (a call's callee, a `recover`'s,
//    a destructor's, a closure's code) and closes them from the entry; Caps.lean
//    states that list and has the kernel check it closed
//    (`C.capsOKB`, formal/C/Caps.lean), so `Cert.n_cap` proves that no run
//    enters a function outside it: any program with the same functions there
//    has exactly the same runs. The scan here is generous (every `.dtor f`
//    of a block counts): a bigger closed list is still closed, and one the
//    kernel finds open is no claim.
//
// 2. What each of those functions may do. The term has no events: the
//    library's calls are A2's constructs, and a write to standard output is
//    no step of the model. So the classes are read off the core IR
//    (`cert_caps_fns`): every call a function makes, through the library's
//    bodies, down to the runtime's functions, each classed by the capability
//    table (stdlib/caps.tsv, copied into the bundle as caps.tsv). Two ledger
//    rows say what that rests on: the table (`caps-table`) and the reading
//    of the core IR's calls as the function's (`caps-attribution`).
//
// The claim's classes are the union over the functions in the list. Its
// sentence says what the program can do and what it never does, both from
// fixed phrases: nothing in it is free text.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `util.nu`
$ `coreir.nu`

// ── The classes ──────────────────────────────────────────────────────

// The classes a claim names, in the order a sentence lists them. `compute`
// and `mem` are not among them: they stay inside the process.
: s CAPS_DOORS `stdio.out stdio.err stdio.in fs.read fs.write fs.meta net.connect net.listen net.dns net.io fd proc.exec proc.signal sys.info env args clock random thread device exit panic ffi.unknown`

// The classes a row of the table may name.
: s CAPS_CLASSES `compute mem stdio.out stdio.err stdio.in fs.read fs.write fs.meta net.connect net.listen net.dns net.io fd proc.exec proc.signal sys.info env args clock random thread device exit panic`

@ cert_caps_door s c → b {
    : ( Vec String ) ds ( string_split ( string_from CAPS_DOORS ) ` ` )
    : i n ( vec_len [String] ds )
    : ~ i k 0
    ~ < k n {
        ? ( nc_is ( vec_at [String] ds k ) c ) { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ cert_caps_phrase_en s c → s {
    ? ( nc_is ( string_from c ) `stdio.out` ) { ^ `write to standard output` } {}
    ? ( nc_is ( string_from c ) `stdio.err` ) { ^ `write to standard error` } {}
    ? ( nc_is ( string_from c ) `stdio.in` ) { ^ `read standard input or control its terminal` } {}
    ? ( nc_is ( string_from c ) `fs.read` ) { ^ `read files` } {}
    ? ( nc_is ( string_from c ) `fs.write` ) { ^ `create, write or remove files` } {}
    ? ( nc_is ( string_from c ) `fs.meta` ) { ^ `list directories or read file metadata` } {}
    ? ( nc_is ( string_from c ) `net.connect` ) { ^ `open network connections` } {}
    ? ( nc_is ( string_from c ) `net.listen` ) { ^ `accept network connections` } {}
    ? ( nc_is ( string_from c ) `net.dns` ) { ^ `resolve host names` } {}
    ? ( nc_is ( string_from c ) `net.io` ) { ^ `use network connections it holds` } {}
    ? ( nc_is ( string_from c ) `fd` ) { ^ `read or write descriptors it holds` } {}
    ? ( nc_is ( string_from c ) `proc.exec` ) { ^ `start other programs` } {}
    ? ( nc_is ( string_from c ) `proc.signal` ) { ^ `send or handle signals` } {}
    ? ( nc_is ( string_from c ) `sys.info` ) { ^ `read facts about the host, its users or other processes` } {}
    ? ( nc_is ( string_from c ) `env` ) { ^ `read or change the environment` } {}
    ? ( nc_is ( string_from c ) `args` ) { ^ `read its command line` } {}
    ? ( nc_is ( string_from c ) `clock` ) { ^ `read the clock or sleep` } {}
    ? ( nc_is ( string_from c ) `random` ) { ^ `read the system's randomness` } {}
    ? ( nc_is ( string_from c ) `thread` ) { ^ `start threads` } {}
    ? ( nc_is ( string_from c ) `device` ) { ^ `use a device` } {}
    ? ( nc_is ( string_from c ) `exit` ) { ^ `end the process` } {}
    ? ( nc_is ( string_from c ) `panic` ) { ^ `stop with an error message` } {}
    ^ `call runtime functions the capability table does not class`
}

@ cert_caps_phrase_fi s c → s {
    ? ( nc_is ( string_from c ) `stdio.out` ) { ^ `kirjoittaa vakiotulosteeseen` } {}
    ? ( nc_is ( string_from c ) `stdio.err` ) { ^ `kirjoittaa vakiovirheeseen` } {}
    ? ( nc_is ( string_from c ) `stdio.in` ) { ^ `lukea vakiosyötettä tai ohjata päätettään` } {}
    ? ( nc_is ( string_from c ) `fs.read` ) { ^ `lukea tiedostoja` } {}
    ? ( nc_is ( string_from c ) `fs.write` ) { ^ `luoda, kirjoittaa tai poistaa tiedostoja` } {}
    ? ( nc_is ( string_from c ) `fs.meta` ) { ^ `listata hakemistoja tai lukea tiedostojen tietoja` } {}
    ? ( nc_is ( string_from c ) `net.connect` ) { ^ `avata verkkoyhteyksiä` } {}
    ? ( nc_is ( string_from c ) `net.listen` ) { ^ `ottaa vastaan verkkoyhteyksiä` } {}
    ? ( nc_is ( string_from c ) `net.dns` ) { ^ `selvittää nimiä` } {}
    ? ( nc_is ( string_from c ) `net.io` ) { ^ `käyttää hallussaan olevia verkkoyhteyksiä` } {}
    ? ( nc_is ( string_from c ) `fd` ) { ^ `lukea tai kirjoittaa hallussaan olevia kuvaajia` } {}
    ? ( nc_is ( string_from c ) `proc.exec` ) { ^ `käynnistää muita ohjelmia` } {}
    ? ( nc_is ( string_from c ) `proc.signal` ) { ^ `lähettää tai käsitellä signaaleja` } {}
    ? ( nc_is ( string_from c ) `sys.info` ) { ^ `lukea tietoja koneesta, sen käyttäjistä tai muista prosesseista` } {}
    ? ( nc_is ( string_from c ) `env` ) { ^ `lukea tai muuttaa ympäristöä` } {}
    ? ( nc_is ( string_from c ) `args` ) { ^ `lukea komentoriviään` } {}
    ? ( nc_is ( string_from c ) `clock` ) { ^ `lukea kelloa tai nukkua` } {}
    ? ( nc_is ( string_from c ) `random` ) { ^ `lukea järjestelmän satunnaisuutta` } {}
    ? ( nc_is ( string_from c ) `thread` ) { ^ `käynnistää säikeitä` } {}
    ? ( nc_is ( string_from c ) `device` ) { ^ `käyttää laitetta` } {}
    ? ( nc_is ( string_from c ) `exit` ) { ^ `lopettaa prosessin` } {}
    ? ( nc_is ( string_from c ) `panic` ) { ^ `pysähtyä virheilmoitukseen` } {}
    ^ `kutsua ajonaikaisia funktioita, joita kyvykkyystaulukko ei luokittele`
}

// The claim's sentence: what it can do, then what it never does, every
// class of CAPS_DOORS in one of the two (ffi.unknown, fd and net.io only in
// the first: their absence says nothing a reader needs).  A program that
// reaches an unclassed runtime function (ffi.unknown) gets no "never": that
// function could do anything, so the sentence says its effects outside its
// memory are not bounded.
@ __cp_never_listed s c → b {
    ^ ! | | ( nc_is ( string_from c ) `ffi.unknown` ) ( nc_is ( string_from c ) `fd` ) ( nc_is ( string_from c ) `net.io` )
}

@ __cp_in String x ( Vec String ) v → b {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        ? ( string_eq x ( vec_at [String] v k ) ) { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ __cp_sentence ( Vec String ) cls b fi → String {
    : ( Vec String ) ds ( string_split ( string_from CAPS_DOORS ) ` ` )
    : i n ( vec_len [String] ds )
    : String can ( string_new )
    : String never ( string_new )
    : ~ i k 0
    ~ < k n {
        : String d ( string_clone ( vec_at [String] ds k ) )
        : s ph ? fi ( cert_caps_phrase_fi ( string_data d ) ) ( cert_caps_phrase_en ( string_data d ) )
        ? ( __cp_in d cls ) {
            ? > ( string_len can ) 0 { ( string_push_str can `; ` ) } {}
            ( string_push_str can ph )
        } {
            ? ( __cp_never_listed ( string_data d ) ) {
                ? > ( string_len never ) 0 { ( string_push_str never `; ` ) } {}
                ( string_push_str never ph )
            } {}
        }
        = k + k 1
    }
    : String o ( string_new )
    : String unk ( string_from `ffi.unknown` )
    ? ( __cp_in unk cls ) {
        ? fi {
            ( string_push_str o `Oman muistinsa ulkopuolella se voi: ` )
            ( string_push_str o ( string_data can ) )
            ( string_push_str o `. Sen vaikutuksia oman muistinsa ulkopuolella ei ole rajattu.` )
        } {
            ( string_push_str o `Outside its own memory it can: ` )
            ( string_push_str o ( string_data can ) )
            ( string_push_str o `. Its effects outside its own memory are not bounded.` )
        }
        ^ o
    } {}
    ? fi {
        ? == 0 ( string_len can ) { ( string_push_str o `Se ei tee mitään oman muistinsa ulkopuolella.` ) } {
            ( string_push_str o `Oman muistinsa ulkopuolella se voi vain: ` )
            ( string_push_str o ( string_data can ) )
            ( string_push_str o `.` )
        }
        ( string_push_str o ` Se ei koskaan: ` )
    } {
        ? == 0 ( string_len can ) { ( string_push_str o `It does nothing outside its own memory.` ) } {
            ( string_push_str o `Outside its own memory it can only: ` )
            ( string_push_str o ( string_data can ) )
            ( string_push_str o `.` )
        }
        ( string_push_str o ` It never: ` )
    }
    ( string_push_str o ( string_data never ) )
    ( string_push_str o `.` )
    ^ o
}

@ cert_caps_sentence_en ( Vec String ) cls → String { ^ ( __cp_sentence cls F ) }

@ cert_caps_sentence_fi ( Vec String ) cls → String { ^ ( __cp_sentence cls T ) }

// The sentence of a claim that is not proved (the program is not accepted,
// or Lean did not check the list).
@ cert_caps_open_en → s { ^ `Not claimed: which runtime functions it can reach is not proved for this program.` }

@ cert_caps_open_fi → s { ^ `Ei väitetä: mitä ajonaikaisia funktioita se voi tavoittaa, ei ole todistettu tälle ohjelmalle.` }

// ── The table ────────────────────────────────────────────────────────

: CapRow {
    String sym
    String cls
}

// stdlib/caps.tsv: `symbol<TAB>class<TAB>note` lines, `#` comments. A
// symbol ending in `*` is a prefix (a family of the compiler's own
// built-ins). A row whose class is not one of CAPS_CLASSES is an error.
@ cert_caps_table String text → !( Vec CapRow ) String {
    : ( Vec CapRow ) out ( vec_new [CapRow] )
    : ( Vec String ) cs ( string_split ( string_from CAPS_CLASSES ) ` ` )
    : ( Vec String ) ls ( nc_lines ( string_data text ) )
    : i n ( vec_len [String] ls )
    : ~ i k 0
    ~ < k n {
        : String l ( string_clone ( vec_at [String] ls k ) )
        ? | == 0 ( string_len ( string_trim l ) ) ( string_starts_with l `#` ) {} {
            : ( Vec String ) f ( string_split l `	` )
            ? < ( vec_len [String] f ) 2 {
                : String e ( string_from `caps.tsv: a row with no class: ` )
                ( string_push_str e ( string_data l ) )
                ^ @ !( Vec CapRow ) String { F e }
            } {}
            : String sym ( string_clone ( vec_at [String] f 0 ) )
            : String cls ( string_clone ( vec_at [String] f 1 ) )
            ? ! ( __cp_in cls cs ) {
                : String e ( string_from `caps.tsv: an unknown class ` )
                ( string_push_str e ( string_data cls ) )
                ( string_push_str e ` for ` )
                ( string_push_str e ( string_data sym ) )
                ^ @ !( Vec CapRow ) String { F e }
            } {}
            ( vec_push [CapRow] out @ CapRow { sym cls } )
        }
        = k + k 1
    }
    ^ @ !( Vec CapRow ) String { T out }
}

// The class of runtime function `sym`: its row, else the longest prefix
// row that covers it, else `ffi.unknown`.
@ cert_caps_class_of ( Vec CapRow ) tab s sym → String {
    : String x ( string_from sym )
    : i n ( vec_len [CapRow] tab )
    : ~ i best -1
    : ~ i blen -1
    : ~ i k 0
    ~ < k n {
        : CapRow r ( vec_at [CapRow] tab k )
        ? ( string_eq . r sym x ) { ^ ( string_clone . r cls ) } {}
        : i sl ( string_len . r sym )
        ? & > sl 0 ( string_ends_with . r sym `*` ) {
            : String pre ( string_substr . r sym 0 - sl 1 )
            ? & ( string_starts_with x ( string_data pre ) ) > - sl 1 blen {
                = best k
                = blen - sl 1
            } {}
        } {}
        = k + k 1
    }
    ? >= best 0 { ^ ( string_clone . ( vec_at [CapRow] tab best ) cls ) } {}
    ^ ( string_from `ffi.unknown` )
}

// ── Which functions can run: the list Caps.lean states ───────────────

@ __cp_digit i c → b { ^ & >= c 48 <= c 57 }

// The number at `k` of `t` (after spaces), and where it ends; -1 if none.
@ __cp_num ( Slice u ) t inout i k → i {
    : i n ( slice_len [u] t )
    ~ & < k n == ( slice_byte t k ) 32 { = k + k 1 }
    ? | >= k n ! ( __cp_digit ( slice_byte t k ) ) { ^ -1 } {}
    : ~ i v 0
    ~ & < k n ( __cp_digit ( slice_byte t k ) ) {
        = v + * v 10 - ( slice_byte t k ) 48
        = k + k 1
    }
    ^ v
}

// Does `t` hold the word `w` at `k`?
@ __cp_at ( Slice u ) t i k s w → b {
    : ( Slice u ) wv ( slice_of_str w )
    : i m ( slice_len [u] wv )
    ? > + k m ( slice_len [u] t ) { ^ F } {}
    : ~ i j 0
    ~ < j m {
        ? != ( slice_byte t + k j ) ( slice_byte wv j ) { ^ F } {}
        = j + j 1
    }
    ^ T
}

@ __cp_add ( Vec i ) v i x → v {
    : i n ( vec_len [i] v )
    : ~ i k 0
    ~ < k n {
        ? == ( vec_at [i] v k ) x { ^ } {}
        = k + k 1
    }
    ( vec_push [i] v x )
}

@ __cp_has ( Vec i ) v i x → b {
    : i n ( vec_len [i] v )
    : ~ i k 0
    ~ < k n {
        ? == ( vec_at [i] v k ) x { ^ T } {}
        = k + k 1
    }
    ^ F
}

// The function indices one line of a term names: the callee of a call, of
// a `recover` and of a destructor frame (`.letcall x f`, `.letrec x f`,
// `.letd x f`, `.scopeD x f`), a closure literal's code (`.pack [f, …]`),
// and every destructor of a type (`.dtor f`).
@ __cp_line_names String l ( Vec i ) out → v {
    : ( Slice u ) t ( slice_of_str ( string_data l ) )
    : i n ( slice_len [u] t )
    : ~ i k 0
    ~ < k n {
        ? == ( slice_byte t k ) 46 {
            : ~ i skip -1
            ? ( __cp_at t k `.letcall ` ) { = skip + k 9 } {}
            ? ( __cp_at t k `.letrec ` ) { = skip + k 8 } {}
            ? ( __cp_at t k `.letd ` ) { = skip + k 6 } {}
            ? ( __cp_at t k `.scopeD ` ) { = skip + k 8 } {}
            ? >= skip 0 {
                : ~ i p skip
                : i x ( __cp_num t p )
                ? >= x 0 {
                    : i f ( __cp_num t p )
                    ? >= f 0 { ( __cp_add out f ) } {}
                } {}
                = k p
            } {
                ? ( __cp_at t k `.dtor ` ) {
                    : ~ i p + k 6
                    : i f ( __cp_num t p )
                    ? >= f 0 { ( __cp_add out f ) } {}
                    = k p
                } {
                    ? ( __cp_at t k `.pack [` ) {
                        : ~ i p + k 7
                        : ~ b go T
                        ~ go {
                            : i f ( __cp_num t p )
                            ? >= f 0 { ( __cp_add out f ) } {}
                            ? & < p n == ( slice_byte t p ) 44 { = p + p 1 } { = go F }
                        }
                        = k p
                    } { = k + k 1 }
                }
            }
        } { = k + k 1 }
    }
}

// The functions a run of the term in Program.lean `lean` can enter: the
// closure, from the entry statement, of the names each function's
// definition holds; sorted. None when the term has no entry, declares its
// functions out of order (fn0, fn1, …) or names one it does not declare.
@ __cp_all_below ( Vec i ) v i n → b {
    : i m ( vec_len [i] v )
    : ~ i j 0
    ~ < j m {
        : i x ( vec_at [i] v j )
        ? | < x 0 >= x n { ^ F } {}
        = j + j 1
    }
    ^ T
}

@ cert_runs String lean → ?( Vec i ) {
    : ( Vec ( Vec i ) ) names ( vec_new [( Vec i )] )
    : ( Vec i ) entry ( vec_new [i] )
    : ~ b has_entry F
    // the block the lines belong to: -1 entry, -2 none, else fn K
    : ~ i cur -2
    : ( Vec String ) ls ( nc_lines ( string_data lean ) )
    : i nl ( vec_len [String] ls )
    : ~ i q 0
    ~ < q nl {
        : String l ( string_clone ( vec_at [String] ls q ) )
        ? ( string_starts_with l `def ` ) {
            = cur -2
            ? ( string_starts_with l `def fn` ) {
                : ( Slice u ) t ( slice_of_str ( string_data l ) )
                : ~ i p 6
                : i kf ( __cp_num t p )
                ? & >= kf 0 & < p ( slice_len [u] t ) == ( slice_byte t p ) 32 {
                    // the functions are declared in order, fn0, fn1, …: an
                    // index is the one the next declaration has, so the work
                    // here grows with the declarations, not with an index
                    ? != kf ( vec_len [( Vec i )] names ) { ^ @ ?( Vec i ) { F } } {}
                    ( vec_push [( Vec i )] names ( vec_new [i] ) )
                    = cur kf
                } {}
            } {
                ? ( string_starts_with l `def entry ` ) {
                    = cur -1
                    = has_entry T
                } {}
            }
        } {}
        ? == cur -1 { ( __cp_line_names l entry ) } {
            ? >= cur 0 {
                : ( Vec i ) w ( vec_new [i] )
                ( __cp_line_names l w )
                ? > ( vec_len [i] w ) 0 {
                    : ( Vec i ) v ( vec_clone [i] ( vec_at [( Vec i )] names cur ) )
                    : i wn ( vec_len [i] w )
                    : ~ i j 0
                    ~ < j wn { ( vec_push [i] v ( vec_at [i] w j ) ) = j + j 1 }
                    : b _s ( vec_set [( Vec i )] names cur v )
                } {}
            } {}
        }
        = q + q 1
    }
    ? ! has_entry { ^ @ ?( Vec i ) { F } } {}
    // every name, in every definition and the entry, is a declared function
    // (the translator writes no other)
    : i nf ( vec_len [( Vec i )] names )
    ? ! ( __cp_all_below entry nf ) { ^ @ ?( Vec i ) { F } } {}
    : ~ i d 0
    ~ < d nf {
        ? ! ( __cp_all_below ( vec_at [( Vec i )] names d ) nf ) { ^ @ ?( Vec i ) { F } } {}
        = d + d 1
    }
    // the closure, from the entry's names
    : ( Vec b ) seen ( vec_new [b] )
    : ~ i z 0
    ~ < z nf { ( vec_push [b] seen F ) = z + z 1 }
    : ( Vec i ) work ( vec_clone [i] entry )
    ~ > ( vec_len [i] work ) 0 {
        ?? ( vec_pop [i] work ) {
            T f → {
                ? | < f 0 >= f nf { ^ @ ?( Vec i ) { F } } {}
                ? ! ( vec_at [b] seen f ) {
                    : b _s3 ( vec_set [b] seen f T )
                    : ( Vec i ) ns ( vec_at [( Vec i )] names f )
                    : i m ( vec_len [i] ns )
                    : ~ i j 0
                    ~ < j m {
                        ( vec_push [i] work ( vec_at [i] ns j ) )
                        = j + j 1
                    }
                } {}
            }
            F → {}
        }
    }
    // sorted: in index order
    : ( Vec i ) out ( vec_new [i] )
    : ~ i a 0
    ~ < a nf {
        ? ( vec_at [b] seen a ) { ( vec_push [i] out a ) } {}
        = a + a 1
    }
    ^ @ ?( Vec i ) { T out }
}

// The list as Lean writes it: `[0, 3, 4]`.
@ cert_runs_lean ( Vec i ) runs → String {
    : String o ( string_from `[` )
    : i n ( vec_len [i] runs )
    : ~ i k 0
    ~ < k n {
        ? > k 0 { ( string_push_str o `, ` ) } {}
        ( string_push_int o ( vec_at [i] runs k ) )
        = k + k 1
    }
    ( string_push_str o `]` )
    ^ o
}

// ── Caps.lean ────────────────────────────────────────────────────────
//
// A pure function of the list, the profile and whether the program
// spawns: `verify` writes it again from the manifest's list and compares
// it byte for byte. `Cert.runs_closed` is the kernel's check of the list;
// `Cert.n_cap` the theorem: a program with the same functions at the
// list's indices, whatever it has elsewhere, has the same runs (A2), or
// the same interleavings (A3, a program that spawns).
@ cert_caps_lean ( Vec i ) runs s prof b threads → String {
    : String o ( string_with_cap 2048 )
    ( string_push_str o `-- Generated by nurl-cert: which of the program's functions a run can enter\n` )
    ( string_push_str o `-- (N.cap). nurl-cert verify writes this file again from the manifest's list\n` )
    ( string_push_str o `-- and compares it byte for byte; do not edit it.\n` )
    // (a threaded program's from C.Caps3, so a single-threaded one's loads no A3)
    ( string_push_str o ? threads `import Program\nimport C.Caps3\n\n` `import Program\nimport C.Caps\n\n` )
    ( string_push_str o `namespace Cert\n\n` )
    ( string_push_str o `/-- The functions a run of the program can enter (the manifest's capabilities.runs). -/\n` )
    ( string_push_str o `def runs : List Nat := ` )
    ( string_push_str o ( string_data ( cert_runs_lean runs ) ) )
    ( string_push_str o `\n\n` )
    ( string_push_str o `/-- The entry and every function of runs name only functions of runs (formal/C/Caps.lean). -/\n` )
    ( string_push_str o `theorem runs_closed : C.capsOKB P entry runs = true := by ` )
    ( string_push_str o ? != 0 ( nurl_str_eq prof `fast` ) `native_decide` `decide +kernel` )
    ( string_push_str o `\n\n` )
    ? threads {
        ( string_push_str o `/-- N.cap: a function outside runs runs on no thread: a program with the same\n` )
        ( string_push_str o `    functions at the indices of runs has exactly this program's interleavings. -/\n` )
        ( string_push_str o `theorem n_cap : ∀ (P' : A2.Prog), (∀ f ∈ runs, P'[f]? = P[f]?) →\n` )
        ( string_push_str o `    ∀ (nv : Nat) (Cf : A3.Cfg), A3.Reach P (fun f => decide (f ∈ spawns)) (A3.Cfg.init entry nv) Cf ↔\n` )
        ( string_push_str o `      A3.Reach P' (fun f => decide (f ∈ spawns)) (A3.Cfg.init entry nv) Cf :=\n` )
        ( string_push_str o `  fun _ hag nv Cf => C.caps3_runs runs_closed hag _ nv Cf\n\n` )
    } {
        ( string_push_str o `/-- N.cap: a function outside runs never runs: a program with the same\n` )
        ( string_push_str o `    functions at the indices of runs has exactly this program's runs. -/\n` )
        ( string_push_str o `theorem n_cap : ∀ (P' : A2.Prog), (∀ f ∈ runs, P'[f]? = P[f]?) →\n` )
        ( string_push_str o `    ∀ (nv : Nat) (r : A2.Res), A2.Steps P (A2.emptyMem nv) entry r ↔ A2.Steps P' (A2.emptyMem nv) entry r :=\n` )
        ( string_push_str o `  fun _ hag nv r => C.caps_runs runs_closed hag nv r\n\n` )
    }
    ( string_push_str o `end Cert\n\n` )
    ( string_push_str o `#print axioms Cert.n_cap\n` )
    ^ o
}

// ── What each function may do: the core IR ───────────────────────────

: CapFn {
    // the classes this function may reach, sorted, each once
    ( Vec String ) cls
}

: CapWit {
    String cls
    // the chain: the function in the list it starts at, the calls down to
    // the runtime function, each `name (file:line)` of its call
    ( Vec String ) chain
}

: CapsRes {
    // per program function (in the core IR's order, the term's indices):
    // its name and classes
    ( Vec String ) names
    ( Vec ( Vec String ) ) cls
    // the union over `runs`, in CAPS_DOORS order
    ( Vec String ) doors
    ( Vec CapWit ) wits
}

// A library function: its file starts with `stdlib/`.  The translator's rule
// (tolean.nu, the `prog` it numbers), so the indices of `Cert.runs` name the
// same functions here.
@ __cp_is_lib String f → b {
    ^ ( string_starts_with f `stdlib/` )
}

// What N.cap reads of the core IR, and nothing more: each function's
// header (name, file, line, flags), the callees its statements name (a
// `call`'s and a `closure`'s, each with the `line` it is on) and the `virt`
// lines. A scan of the text in place, so certify does not parse the core IR
// a second time (the translation has its own reader, coreir.nu, which
// builds every record).
: CapIR {
    ( Vec String ) names
    ( Vec String ) files
    ( Vec i ) lines
    ( Vec i ) flags
    ( Vec ( Vec String ) ) callees
    ( Vec ( Vec i ) ) clines
    ( Vec String ) vcallee
    ( Vec ( Vec String ) ) vimpls
}

@ __cp_hash String x → i { ^ ( hash_string ( string_data x ) ) }

@ __cp_eqs String a String b → b { ^ ( eq_string ( string_data a ) ( string_data b ) ) }

@ __cp_mset ( HashMap String i ) m String k i v → v {
    : ?i _o ( map_set [String i] m k v \ String x → i { ^ ( __cp_hash x ) } \ String p String q → b { ^ ( __cp_eqs p q ) } )
}

@ __cp_mget ( HashMap String i ) m s k → i {
    ^ ?? ( map_get_with [String i s] m k \ s x → i { ^ ( hash_string x ) } \ String p s q → b { ^ ( eq_string ( string_data p ) q ) } ) {
        T v → v
        F → -1
    }
}

// The number of t[a, z) (digits only), or 0.
@ __cp_int ( Slice u ) t i a i z → i {
    : ~ i v 0
    : ~ i k a
    ~ & < k z ( __cp_digit ( slice_byte t k ) ) { = v + * v 10 - ( slice_byte t k ) 48 = k + k 1 }
    ^ v
}

// The tab-separated columns of t[a, z).
@ __cp_split_tabs ( Slice u ) t i a i z → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ~ i k a
    : ~ b more T
    ~ more {
        : ~ i e k
        ~ & < e z != ( slice_byte t e ) 9 { = e + e 1 }
        : String w ( string_new )
        ( string_push_window w t k - e k )
        ( vec_push [String] out w )
        ? < e z { = k + e 1 } { = more F }
    }
    ^ out
}

// A line break as the core IR's reader takes it (coreir.nu's __cr_is_nl:
// \n, \r, \v, \f, \x1c–\x1e).
@ __cp_is_nl i c → b { ^ | | | == c 10 == c 13 | == c 11 == c 12 & >= c 28 <= c 30 }

@ __cp_scan s text → CapIR {
    : ( Vec String ) names ( vec_new [String] )
    : ( Vec String ) files ( vec_new [String] )
    : ( Vec i ) lines ( vec_new [i] )
    : ( Vec i ) flags ( vec_new [i] )
    : ( Vec ( Vec String ) ) callees ( vec_new [( Vec String )] )
    : ( Vec ( Vec i ) ) clines ( vec_new [( Vec i )] )
    : ( Vec String ) vcallee ( vec_new [String] )
    : ( Vec ( Vec String ) ) vimpls ( vec_new [( Vec String )] )
    : ~ ( Vec String ) cc ( vec_new [String] )
    : ~ ( Vec i ) cl ( vec_new [i] )
    : ~ b in_fn F
    : ~ i cur_line 0
    : ( Slice u ) t ( slice_of_str text )
    : i n ( slice_len [u] t )
    : ~ i a 0
    ~ < a n {
        : ~ i z a
        ~ & < z n ! ( __cp_is_nl ( slice_byte t z ) ) { = z + z 1 }
        : ~ i sa a
        ~ & < sa z ( core_is_ws ( slice_byte t sa ) ) { = sa + sa 1 }
        ? < sa z {
            : i c0 ( slice_byte t sa )
            ? & & == c0 102 < + sa 2 z & == ( slice_byte t + sa 1 ) 110 == ( slice_byte t + sa 2 ) 9 {
                // `fn` header: name, return type, parameters, line, file, flags
                : ( Vec String ) f ( __cp_split_tabs t sa z )
                : String nm ?? ( vec_get [String] f 1 ) { T x → ( string_clone x ) F → ( string_new ) }
                : String ln ?? ( vec_get [String] f 4 ) { T x → ( string_clone x ) F → ( string_new ) }
                : String fl ?? ( vec_get [String] f 5 ) { T x → ( string_clone x ) F → ( string_new ) }
                : String fg ?? ( vec_get [String] f 6 ) { T x → ( string_clone x ) F → ( string_new ) }
                : ( Slice u ) lv ( slice_of_str ( string_data ln ) )
                : ( Slice u ) gv ( slice_of_str ( string_data fg ) )
                : i lnum ( __cp_int lv 0 ( slice_len [u] lv ) )
                ( vec_push [String] names nm )
                ( vec_push [String] files fl )
                ( vec_push [i] lines lnum )
                ( vec_push [i] flags ( __cp_int gv 0 ( slice_len [u] gv ) ) )
                = cc ( vec_new [String] )
                = cl ( vec_new [i] )
                = cur_line lnum
                = in_fn T
            } {
                ? & in_fn & == c0 101 & < + sa 4 z & == ( slice_byte t + sa 1 ) 110 & == ( slice_byte t + sa 2 ) 100 & == ( slice_byte t + sa 3 ) 102 == ( slice_byte t + sa 4 ) 110 {
                    // `endfn`
                    ( vec_push [( Vec String )] callees cc )
                    ( vec_push [( Vec i )] clines cl )
                    = cc ( vec_new [String] )
                    = cl ( vec_new [i] )
                    = in_fn F
                } {
                    ? & ! in_fn & == c0 118 & < + sa 4 z & == ( slice_byte t + sa 1 ) 105 & == ( slice_byte t + sa 2 ) 114 & == ( slice_byte t + sa 3 ) 116 == ( slice_byte t + sa 4 ) 9 {
                        // `virt` callee impl…
                        : ( Vec String ) f ( __cp_split_tabs t sa z )
                        : String cal ?? ( vec_get [String] f 1 ) { T x → ( string_clone x ) F → ( string_new ) }
                        : ( Vec String ) im ( vec_new [String] )
                        : i nfc ( vec_len [String] f )
                        : ~ i j 2
                        ~ < j nfc { ( vec_push [String] im ( string_clone ( vec_at [String] f j ) ) ) = j + j 1 }
                        ( vec_push [String] vcallee cal )
                        ( vec_push [( Vec String )] vimpls im )
                    } {
                        // (a variable's `v` line names no callee)
                        ? & in_fn ! & == c0 118 & < + sa 1 z == ( slice_byte t + sa 1 ) 9 {
                            ? & & == c0 108 < + sa 4 z & & == ( slice_byte t + sa 1 ) 105 == ( slice_byte t + sa 2 ) 110 & == ( slice_byte t + sa 3 ) 101 ( core_is_ws ( slice_byte t + sa 4 ) ) {
                                // `line N`
                                : ~ i ls + sa 5
                                ~ & < ls z ( core_is_ws ( slice_byte t ls ) ) { = ls + ls 1 }
                                = cur_line ( __cp_int t ls z )
                            } {
                                // a statement: every `call X` / `closure X`, its
                                // words split as the core IR's reader splits them
                                // (core_is_ws)
                                : ~ i k sa
                                ~ < k z {
                                    ~ & < k z ( core_is_ws ( slice_byte t k ) ) { = k + k 1 }
                                    : ~ i e k
                                    ~ & < e z ! ( core_is_ws ( slice_byte t e ) ) { = e + e 1 }
                                    : i wl - e k
                                    : b is_call & == wl 4 ( __cp_at t k `call` )
                                    : b is_clo & == wl 7 ( __cp_at t k `closure` )
                                    ? | is_call is_clo {
                                        : ~ i b2 e
                                        ~ & < b2 z ( core_is_ws ( slice_byte t b2 ) ) { = b2 + b2 1 }
                                        : ~ i e2 b2
                                        ~ & < e2 z ! ( core_is_ws ( slice_byte t e2 ) ) { = e2 + e2 1 }
                                        ? > e2 b2 {
                                            : String w ( string_new )
                                            ( string_push_window w t b2 - e2 b2 )
                                            ( vec_push [String] cc w )
                                            ( vec_push [i] cl cur_line )
                                        } {}
                                        = k e2
                                    } { = k e }
                                }
                            }
                        } {}
                    }
                }
            }
        } {}
        = a + z 1
    }
    ^ @ CapIR { names files lines flags callees clines vcallee vimpls }
}

@ __cp_add_s ( Vec String ) v String x → v {
    ? ! ( __cp_in x v ) { ( vec_push [String] v x ) } {}
}

// One function's direct edges: the functions it calls (or whose closure it
// makes, or, through a `dyn` call, every impl of the method), and the
// runtime functions it calls, each with the line of the call; and `panic`
// when it may start a panic inline (`fn` flag bit 3).
: CapEdges {
    ( Vec i ) fns
    ( Vec i ) flines
    ( Vec String ) syms
    ( Vec i ) slines
}

@ __cp_sort_doors ( Vec String ) v → ( Vec String ) {
    : ( Vec String ) ds ( string_split ( string_from CAPS_DOORS ) ` ` )
    : ( Vec String ) out ( vec_new [String] )
    : i n ( vec_len [String] ds )
    : ~ i k 0
    ~ < k n {
        : String d ( string_clone ( vec_at [String] ds k ) )
        ? ( __cp_in d v ) { ( vec_push [String] out d ) } {}
        = k + k 1
    }
    ^ out
}

@ __cp_step String name String file i line → String {
    : String o ( string_clone name )
    ( string_push_str o ` (` )
    ( string_push_str o ( string_data file ) )
    ( string_push_str o `:` )
    ( string_push_int o line )
    ( string_push_str o `)` )
    ^ o
}

// The classes every function of the core IR `text` may reach (its own
// calls, and its callees', the library's and the program's alike, as far
// as the calls go), the program's functions by their term index, and the
// union over `runs` with one shortest chain each.
@ cert_caps_fns String text ( Vec CapRow ) tab ( Vec i ) runs → !CapsRes String {
    : CapIR ir ( __cp_scan ( string_data text ) )
    : i nf ( vec_len [String] . ir names )
    // every `fn` closed by its `endfn`, or the core IR is refused
    ? | != ( vec_len [( Vec String )] . ir callees ) nf != ( vec_len [( Vec i )] . ir clines ) nf {
        ^ @ !CapsRes String { F ( string_from `the core IR has a fn with no endfn` ) }
    } {}
    // names → indices, once
    : ( HashMap String i ) fidx ( map_new [String i] )
    : ~ i k 0
    ~ < k nf { ( __cp_mset fidx ( string_clone ( vec_at [String] . ir names k ) ) k ) = k + k 1 }
    : ( HashMap String i ) vidx ( map_new [String i] )
    = k 0
    ~ < k ( vec_len [String] . ir vcallee ) { ( __cp_mset vidx ( string_clone ( vec_at [String] . ir vcallee k ) ) k ) = k + k 1 }
    // a runtime function's class, once each
    : ( HashMap String i ) cidx ( map_new [String i] )
    : ( Vec String ) ccls ( vec_new [String] )
    : ( Vec CapEdges ) es ( vec_new [CapEdges] )
    : ( Vec ( Vec String ) ) own ( vec_new [( Vec String )] )
    = k 0
    ~ < k nf {
        : ( Vec String ) cs ( vec_at [( Vec String )] . ir callees k )
        : ( Vec i ) ls ( vec_at [( Vec i )] . ir clines k )
        : ( Vec i ) fs ( vec_new [i] )
        : ( Vec i ) fl ( vec_new [i] )
        : ( Vec String ) ss ( vec_new [String] )
        : ( Vec i ) sl ( vec_new [i] )
        : ( Vec String ) mine ( vec_new [String] )
        : i nc ( vec_len [String] cs )
        : ~ i j 0
        ~ < j nc {
            : String c ( string_clone ( vec_at [String] cs j ) )
            : i ln ( vec_at [i] ls j )
            : i g ( __cp_mget fidx ( string_data c ) )
            ? >= g 0 {
                ( vec_push [i] fs g )
                ( vec_push [i] fl ln )
            } {
                : i vi ( __cp_mget vidx ( string_data c ) )
                ? >= vi 0 {
                    : ( Vec String ) im ( vec_at [( Vec String )] . ir vimpls vi )
                    : i ni ( vec_len [String] im )
                    : ~ i z 0
                    ~ < z ni {
                        : i h ( __cp_mget fidx ( string_data ( vec_at [String] im z ) ) )
                        ? >= h 0 {
                            ( vec_push [i] fs h )
                            ( vec_push [i] fl ln )
                        } {}
                        = z + z 1
                    }
                } {
                    : ~ i ci ( __cp_mget cidx ( string_data c ) )
                    ? < ci 0 {
                        = ci ( vec_len [String] ccls )
                        ( vec_push [String] ccls ( cert_caps_class_of tab ( string_data c ) ) )
                        ( __cp_mset cidx ( string_clone c ) ci )
                    } {}
                    ( __cp_add_s mine ( string_clone ( vec_at [String] ccls ci ) ) )
                    ( vec_push [String] ss c )
                    ( vec_push [i] sl ln )
                }
            }
            = j + j 1
        }
        ? != 0 & ( vec_at [i] . ir flags k ) 8 { ( __cp_add_s mine ( string_from `panic` ) ) } {}
        ( vec_push [CapEdges] es @ CapEdges { fs fl ss sl } )
        ( vec_push [( Vec String )] own mine )
        = k + k 1
    }
    // the transitive classes: a fixpoint over the call edges
    : ( Vec ( Vec String ) ) all ( vec_new [( Vec String )] )
    = k 0
    ~ < k nf { ( vec_push [( Vec String )] all ( vec_clone [String] ( vec_at [( Vec String )] own k ) ) ) = k + k 1 }
    : ~ b changed T
    ~ changed {
        = changed F
        = k 0
        ~ < k nf {
            : ( Vec String ) acc ( vec_clone [String] ( vec_at [( Vec String )] all k ) )
            : i before ( vec_len [String] acc )
            : ( Vec i ) cs . ( vec_at [CapEdges] es k ) fns
            : i nc ( vec_len [i] cs )
            : ~ i j 0
            ~ < j nc {
                : ( Vec String ) theirs ( vec_at [( Vec String )] all ( vec_at [i] cs j ) )
                : i nt ( vec_len [String] theirs )
                : ~ i z 0
                ~ < z nt { ( __cp_add_s acc ( string_clone ( vec_at [String] theirs z ) ) ) = z + z 1 }
                = j + j 1
            }
            ? > ( vec_len [String] acc ) before {
                = changed T
                : b _s ( vec_set [( Vec String )] all k acc )
            } {}
            = k + k 1
        }
    }
    // the program's functions, in order: the term's indices 0 …
    : ( Vec i ) prog ( vec_new [i] )
    : ( Vec String ) names ( vec_new [String] )
    : ( Vec ( Vec String ) ) pcls ( vec_new [( Vec String )] )
    = k 0
    ~ < k nf {
        ? ! ( __cp_is_lib ( vec_at [String] . ir files k ) ) {
            ( vec_push [i] prog k )
            ( vec_push [String] names ( string_clone ( vec_at [String] . ir names k ) ) )
            ( vec_push [( Vec String )] pcls ( __cp_sort_doors ( vec_at [( Vec String )] all k ) ) )
        } {}
        = k + k 1
    }
    // the union over runs (indices past the program's functions are the
    // closure interfaces and spawn wrappers, which call nothing of their own)
    : ( Vec String ) uni ( vec_new [String] )
    : ( Vec i ) roots ( vec_new [i] )
    : i nr ( vec_len [i] runs )
    : ~ i r 0
    ~ < r nr {
        : i x ( vec_at [i] runs r )
        ? < x ( vec_len [i] prog ) {
            ( vec_push [i] roots ( vec_at [i] prog x ) )
            : ( Vec String ) c ( vec_at [( Vec String )] all ( vec_at [i] prog x ) )
            : i nc ( vec_len [String] c )
            : ~ i z 0
            ~ < z nc { ( __cp_add_s uni ( string_clone ( vec_at [String] c z ) ) ) = z + z 1 }
        } {}
        = r + r 1
    }
    : ( Vec String ) doors ( __cp_sort_doors uni )
    // one shortest chain per class: breadth first from the roots, in their
    // order, over the call edges, to a function that reaches the class itself
    : ( Vec CapWit ) wits ( vec_new [CapWit] )
    : i nd ( vec_len [String] doors )
    : ~ i d 0
    ~ < d nd {
        : String want ( string_clone ( vec_at [String] doors d ) )
        : ( Vec i ) par ( vec_new [i] )
        : ( Vec i ) pline ( vec_new [i] )
        = k 0
        ~ < k nf { ( vec_push [i] par -2 ) ( vec_push [i] pline 0 ) = k + k 1 }
        : ( Vec i ) queue ( vec_new [i] )
        : i nro ( vec_len [i] roots )
        = k 0
        ~ < k nro {
            : i x ( vec_at [i] roots k )
            ? == ( vec_at [i] par x ) -2 {
                : b _s ( vec_set [i] par x -1 )
                ( vec_push [i] queue x )
            } {}
            = k + k 1
        }
        : ~ i head 0
        : ~ i found -1
        ~ & < head ( vec_len [i] queue ) < found 0 {
            : i x ( vec_at [i] queue head )
            = head + head 1
            ? ( __cp_in want ( vec_at [( Vec String )] own x ) ) { = found x } {
                : CapEdges e ( vec_at [CapEdges] es x )
                : i ne ( vec_len [i] . e fns )
                : ~ i j 0
                ~ < j ne {
                    : i y ( vec_at [i] . e fns j )
                    ? == ( vec_at [i] par y ) -2 {
                        : b _s1 ( vec_set [i] par y x )
                        : b _s2 ( vec_set [i] pline y ( vec_at [i] . e flines j ) )
                        ( vec_push [i] queue y )
                    } {}
                    = j + j 1
                }
            }
        }
        : ( Vec String ) chain ( vec_new [String] )
        ? >= found 0 {
            // the path, root first
            : ( Vec i ) path ( vec_new [i] )
            : ~ i x found
            ~ >= x 0 { ( vec_push [i] path x ) = x ( vec_at [i] par x ) }
            : ~ i z - ( vec_len [i] path ) 1
            ~ >= z 0 {
                : i f ( vec_at [i] path z )
                ? == ( vec_at [i] par f ) -1 {
                    ( vec_push [String] chain ( __cp_step ( vec_at [String] . ir names f ) ( vec_at [String] . ir files f ) ( vec_at [i] . ir lines f ) ) )
                } {
                    ( vec_push [String] chain ( __cp_step ( vec_at [String] . ir names f ) ( vec_at [String] . ir files ( vec_at [i] par f ) ) ( vec_at [i] pline f ) ) )
                }
                = z - z 1
            }
            // the runtime function, at its call
            : CapEdges e ( vec_at [CapEdges] es found )
            : i nsy ( vec_len [String] . e syms )
            : ~ b put F
            : ~ i j 0
            ~ & < j nsy ! put {
                : String sy ( string_clone ( vec_at [String] . e syms j ) )
                ? ( string_eq ( cert_caps_class_of tab ( string_data sy ) ) want ) {
                    ( vec_push [String] chain ( __cp_step sy ( vec_at [String] . ir files found ) ( vec_at [i] . e slines j ) ) )
                    = put T
                } {}
                = j + j 1
            }
            ? ! put {
                // (`panic` from an inline check: no call names it)
                ( vec_push [String] chain ( string_from `an inline check that may panic` ) )
            } {}
        } {}
        ( vec_push [CapWit] wits @ CapWit { want chain } )
        = d + d 1
    }
    ^ @ !CapsRes String { T @ CapsRes { names pcls doors wits } }
}

// ── The manifest's part ──────────────────────────────────────────────

$ `manifest.nu`

// N.cap's premises, the ledger rows it rests on: the kernel, the claims'
// definitions, the term's rows (as M.safe's: the kernel's words or the
// translator), the table, the reading of the core IR's calls, and the
// binary's link to the model (memory safety: a run that broke memory could
// call anything); under `fast` the Lean compiler; and every hand-vouched
// place (an `unsafe` function may call anything). A claim that is not
// proved rests on nothing but its definition.
@ cert_caps_premises s prof b proved b elab ( Vec String ) enc i nunsafe ( Vec String ) assumed_ids → String {
    ? ! proved { ^ ( string_from `claim-definitions` ) } {}
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
    ( string_push_str p ` caps-table caps-attribution caps-binary` )
    ? != 0 ( nurl_str_eq prof `fast` ) { ( string_push_str p ` lean-compiler` ) } {}
    : ~ i k 0
    ~ < k nunsafe {
        ( string_push_str p ` unsafe-` )
        ( string_push_int p + k 1 )
        = k + k 1
    }
    // (a conditional bundle, AGORA-1033: Cert.n_cap is about the program with
    // a stub at each assumed function, and an assumed function's row says
    // what its stub stands for: the functions it calls)
    : i na ( vec_len [String] assumed_ids )
    : ~ i aj 0
    ~ < aj na {
        ( string_push_char p 32 )
        ( string_push_str p ( string_data ( vec_at [String] assumed_ids aj ) ) )
        = aj + aj 1
    }
    ^ p
}

// The ledger rows N.cap adds (certify's ledger, after the common rows).
@ cert_caps_rows Json L → v {
    ( json_arr_push L ( mj_row `caps-table` `the capability table: the class of each runtime function the program's calls reach (stdlib/caps.tsv, copied into the bundle as caps.tsv)`
    `the claim's classes are the table's word for what each runtime function does; nothing proves that the C runtime or the operating system does only that (a policy the platform enforces is the remedy, AGORA-1025)`
    `stdlib/caps.tsv` `the NURL project (reviewed with the runtime)` `N.cap` ) )
    ( json_arr_push L ( mj_row `caps-attribution` `the core IR's calls as what a function does: the term has no events (the library's calls are A2's constructs), so each function's classes are read off its calls in the core IR, through the library's bodies, down to the runtime's functions`
    `Cert.n_cap proves which functions can run; that each does only what its calls in the core IR reach is the core IR's reading (nurlc --emit-core), checked again by verify, not a theorem`
    `packages/nurl-cert/src/caps.nu, compiler/nurlc.nu (--emit-core)` `nurlc and nurl-cert (re-made by verify)` `N.cap` ) )
    ( json_arr_push L ( mj_row `caps-binary` `the binary does only what its model does: a run that broke memory could call any function`
    `N.cap is about the program's model; that the binary's runs are the model's rests on M.safe and on the code generator (phase D validates its drops)`
    `formal/CLAIM.md, Claims.lean (M.safe)` `the NURL formal model (claude-formal)` `N.cap` ) )
}

// The manifest's `capabilities`: the list, each program function in it
// with its classes, and each class with its chain.
@ cert_caps_json ( Vec i ) runs CapsRes res → Json {
    : Json o ( json_obj_new )
    : Json ra ( json_arr_new )
    : i nr ( vec_len [i] runs )
    : ~ i k 0
    ~ < k nr { ( json_arr_push ra ( json_int ( vec_at [i] runs k ) ) ) = k + k 1 }
    ( mj_set o `runs` ra )
    : Json fa ( json_arr_new )
    = k 0
    ~ < k nr {
        : i x ( vec_at [i] runs k )
        ? < x ( vec_len [String] . res names ) {
            : Json fo ( json_obj_new )
            ( mj_int fo `index` x )
            ( mj_str fo `name` ( string_data ( vec_at [String] . res names x ) ) )
            ( mj_set fo `classes` ( mj_strs ( vec_at [( Vec String )] . res cls x ) ) )
            ( json_arr_push fa fo )
        } {}
        = k + k 1
    }
    ( mj_set o `functions` fa )
    : Json ca ( json_arr_new )
    : i nw ( vec_len [CapWit] . res wits )
    = k 0
    ~ < k nw {
        : CapWit w ( vec_at [CapWit] . res wits k )
        : Json co ( json_obj_new )
        ( mj_str co `class` ( string_data . w cls ) )
        ( mj_set co `chain` ( mj_strs . w chain ) )
        ( json_arr_push ca co )
        = k + k 1
    }
    ( mj_set o `classes` ca )
    ^ o
}

// Everything N.cap needs of a bundle, from the term, the core IR and the
// table (certify and verify both call it): the list, the classes and the
// manifest's part; or why there is none.
: CapsMade {
    ( Vec i ) runs
    CapsRes res
    Json json
}

@ cert_caps_make String lean String core String table → !CapsMade String {
    : ( Vec i ) runs ?? ( cert_runs lean ) { T r → r F → { ^ @ !CapsMade String { F ( string_from `the term has no entry statement, declares its functions out of order, or names one it does not declare` ) } } }
    : ( Vec CapRow ) tab \ ( cert_caps_table table )
    : CapsRes res \ ( cert_caps_fns core tab runs )
    : Json j ( cert_caps_json runs res )
    ^ @ !CapsMade String { T @ CapsMade { runs res j } }
}
