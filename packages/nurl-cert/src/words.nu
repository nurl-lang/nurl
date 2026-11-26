// words.nu — the core IR as Lean data (AGORA-1029, route (b) of
// docs/dev/TRANSLATION_TRUST.md).
//
// `def ir : C.Elab.IR := [ … ]`: one entry per line of the core IR, each a
// list of its words. A header line (`fn`, `v`, `ty`, `sum`) is split at its
// tabs, since a name or a type may hold spaces or be empty. A statement is
// split at spaces and tabs (`agg` writes its trailing type after a tab). Blank lines are dropped. This is the one step between the
// `.core` text and the term Lean builds (`C.Elab`) that runs outside the
// kernel. It makes no choice: `verify` splits Program.core again and
// compares.
//
// What it prints is Lean data and nothing else: the fixed text around the
// lists, and each word as a number (0.3.1): `nat_lit 0x1`, then the word's bytes
// from its last to its first, two hex digits each, so 256^k + Σ b_i·256^i
// for a word of k bytes b_0 … b_(k-1), and `0x1` for an empty word.
// `C.Elab.wordOf` reads it back into the bytes (`wordOf_encB`: for every
// list of bytes). A number cannot end the list, start a comment or hold a
// line break, and it means the same bytes whatever they are: no escaping,
// and no reading of the file as UTF-8 stands between the core IR and the
// words. The kernel holds such a number as one GMP integer; a string
// literal it builds by one `push` a byte, quadratic in its length
// (docs/dev/TRANSLATION_TRUST.md, "the words as numbers"). A core IR with a
// NUL byte has no words (`cert_words_ok`).
//
// A library function is left out whole (AGORA-1029 steps 4 and 5): the
// translator takes the functions whose file is the standard library's for
// A2's constructs, not bodies to check (tolean.nu's `__emit`), and
// `C.Elab.elabIR` drops them by the same test (`startsB file "stdlib/"`)
// before it reads anything of them but their records: what Lean's reader
// (`C.Elab.readFns`) needs to accept the IR at all. So such a function is
// left out only when the reader would accept its records: its `fn` line's
// count of parameters is a number (`natOf`) and each of its `v` lines is
// one `readVar` reads (`__wd_var_ok`). Otherwise its `fn`, `v` and
// `endfn` lines are printed (`__wd_records`), the reader refuses them as
// it would refuse the whole IR, and so does `elabIR`. A line is placed as
// the reader places it, by its words as printed: a line whose first word
// is `fn` opens a function, one whose first word is `endfn` closes it,
// and the function is the library's when its sixth word (the file) starts
// with `stdlib/` and no other function is open. So `elabIR` answers on
// the words as it would on every line (tools/ncore/elab_parity.sh
// compares the two over the corpus; the selftest over IRs the reader
// refuses).
//
// A `sum` line is left out when its name (its second word) is none of the
// words of the lines kept but the `sum` lines (0.3.1). `elabIR` looks a
// summary up only by a function's own name, a callee's name or the
// function a `let … call f` calls, each a word of a kept line that is not
// a `sum` line, and a name's summary is its last `sum` line, which stays.
// A `sum` line with no name is kept (`topOk` refuses it, as the reader
// does). So `elabIR` answers the same (tools/ncore/elab_parity.sh checks it
// over the corpus; translate_test 1c checks the rule against a Python
// reading of it).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/hashmap.nu`
$ `util.nu`

// A word as a number: `nat_lit 0x1`, then its bytes from the last to the
// first, two hex digits each (256^k + Σ b_i·256^i for its k bytes), which
// `C.Elab.wordOf` reads back into the bytes. (`nat_lit`: a raw literal,
// which Lean elaborates without an `OfNat` instance: a third of the cost.)
@ __wd_num ( Slice u ) t i a i z inout String o → v {
    ( string_push_str o `nat_lit 0x1` )
    : ( Slice u ) hx ( slice_of_str `0123456789abcdef` )
    : ~ i k - z 1
    ~ >= k a {
        : i c ( slice_byte t k )
        ( string_push_char o ( slice_byte hx / c 16 ) )
        ( string_push_char o ( slice_byte hx % c 16 ) )
        = k - k 1
    }
}

// A header line: `fn`, `v`, `ty` or `sum`, then a tab.
@ __wd_pre ( Slice u ) t i a i z s w → b {
    : ( Slice u ) wv ( slice_of_str w )
    : i n ( slice_len [u] wv )
    ? >= + a n z { ^ F } {}
    : ~ i k 0
    ~ < k n {
        ? != ( slice_byte t + a k ) ( slice_byte wv k ) { ^ F } {}
        = k + k 1
    }
    ^ == ( slice_byte t + a n ) 9
}

@ __wd_header ( Slice u ) t i a i z → b {
    ^ | | | ( __wd_pre t a z `fn` ) ( __wd_pre t a z `v` ) ( __wd_pre t a z `ty` ) ( __wd_pre t a z `sum` )
}

// Is t[a, e) the text `w`?
@ __wd_is ( Slice u ) t i a i e s w → b {
    : ( Slice u ) wv ( slice_of_str w )
    : i n ( slice_len [u] wv )
    ? != - e a n { ^ F } {}
    : ~ i k 0
    ~ < k n {
        ? != ( slice_byte t + a k ) ( slice_byte wv k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

// The word `j` of the line t[a, z) as it is printed (split as in
// `cert_words`), as its start and end; [-1, -1] past its last.
@ __wd_word ( Slice u ) t i a i z b header i j ( Vec i ) se → v {
    : ~ i k a
    : ~ i c 0
    ~ <= k z {
        : ~ i e k
        ? header {
            ~ & < e z != ( slice_byte t e ) 9 { = e + e 1 }
        } {
            ~ & & < e z != ( slice_byte t e ) 32 != ( slice_byte t e ) 9 { = e + e 1 }
        }
        ? | header > e k {
            ? == c j {
                ( vec_push [i] se k )
                ( vec_push [i] se e )
                ^
            } {}
            = c + c 1
        } {}
        = k + e 1
    }
    ( vec_push [i] se -1 )
    ( vec_push [i] se -1 )
}

// Is t[a, e) a number as `C.Elab.natOf` reads one: one digit at least,
// nothing else? (`small`: and at most 3, as `readVar` wants of a kind)
@ __wd_nat ( Slice u ) t i a i e b small → b {
    ? <= e a { ^ F } {}
    : ~ i k a
    ~ < k e {
        : i c ( slice_byte t k )
        ? | < c 48 > c 57 { ^ F } {}
        = k + k 1
    }
    ? ! small { ^ T } {}
    // the value, leading zeros aside, is one digit 0–3 or none
    : ~ i j a
    ~ & < j e == ( slice_byte t j ) 48 { = j + j 1 }
    ^ | == j e & == - e j 1 <= ( slice_byte t j ) 51
}

// Would `C.Elab.readVar` read the line t[a, z) (its words as printed)?
// `v id kind depth flags …`: id, kind and flags numbers, the kind at most
// 3, and one word at least after the flags.
@ __wd_var_ok ( Slice u ) t i a i z b header → b {
    : ( Vec i ) w ( vec_new [i] )
    : ~ i j 1
    ~ <= j 5 {
        ( __wd_word t a z header j w )
        = j + j 1
    }
    ? < ( vec_at [i] w 8 ) 0 { ^ F } {}
    ^ & & ( __wd_nat t ( vec_at [i] w 0 ) ( vec_at [i] w 1 ) F ) ( __wd_nat t ( vec_at [i] w 2 ) ( vec_at [i] w 3 ) T ) ( __wd_nat t ( vec_at [i] w 6 ) ( vec_at [i] w 7 ) F )
}

// The line t[a, z) as one entry of the list, its words as numbers.
@ __wd_line ( Slice u ) t i a i z b header inout String o inout b first → v {
    ( string_push_str o ? first `\n  [` `,\n  [` )
    = first F
    : ~ i k a
    : ~ b fw T
    ~ <= k z {
        // a word: up to the next separator (a tab in a header line, a
        // space or a tab in a statement); a statement's empty words are
        // dropped (runs of spaces), a header's are kept (an empty name)
        : ~ i e k
        ? header {
            ~ & < e z != ( slice_byte t e ) 9 { = e + e 1 }
        } {
            ~ & & < e z != ( slice_byte t e ) 32 != ( slice_byte t e ) 9 { = e + e 1 }
        }
        ? | header > e k {
            ? ! fw { ( string_push_str o `, ` ) } {}
            = fw F
            ( __wd_num t k e o )
        } {}
        = k + e 1
    }
    ( string_push_char o 93 )
}

// The end of the line that starts at `a`.
@ __wd_eol ( Slice u ) t i a i n → i {
    : ~ i z a
    ~ & < z n != ( slice_byte t z ) 10 { = z + z 1 }
    ^ z
}

// Is the line t[a, z) blank (spaces only)?
@ __wd_blank ( Slice u ) t i a i z → b {
    : ~ i q a
    ~ < q z {
        ? != ( slice_byte t q ) 32 { ^ F } {}
        = q + q 1
    }
    ^ T
}

// The first word of the line t[a, z) as printed: is it `w`?
@ __wd_first ( Slice u ) t i a i z b header s w → b {
    : ( Vec i ) w0 ( vec_new [i] )
    ( __wd_word t a z header 0 w0 )
    : i s0 ( vec_at [i] w0 0 )
    ^ & >= s0 0 ( __wd_is t s0 ( vec_at [i] w0 1 ) w )
}

// A line kept for the words: its start and end.
@ __wd_keep ( Vec i ) kept i a i z → v {
    ( vec_push [i] kept a )
    ( vec_push [i] kept z )
}

// The words of the line t[a, z) as printed, each put in `seen`.
@ __wd_see ( Slice u ) t i a i z b header ( HashMap String i ) seen → v {
    : ~ i j 0
    : ~ b more T
    ~ more {
        : ( Vec i ) w ( vec_new [i] )
        ( __wd_word t a z header j w )
        : i s ( vec_at [i] w 0 )
        ? < s 0 { = more F } {
            : String k ( string_new )
            ( string_push_window k t s - ( vec_at [i] w 1 ) s )
            : ?i _o ( map_set [String i] seen k 1 \ String x → i { ^ ( hash_string ( string_data x ) ) } \ String a String b → b { ^ ( eq_string ( string_data a ) ( string_data b ) ) } )
            = j + j 1
        }
    }
}

// Is t[s, e) a word in `seen`?
@ __wd_seen ( Slice u ) t i s i e ( HashMap String i ) seen → b {
    : String k ( string_new )
    ( string_push_window k t s - e s )
    ^ ?? ( map_get_with [String i s] seen ( string_data k ) \ s x → i { ^ ( hash_string x ) } \ String a s b → b { ^ ( eq_string ( string_data a ) b ) } ) {
        T _ → T
        F → F
    }
}

// A library function that Lean's reader would refuse, from its `fn` line
// at `a` to `b`: printed as step 4 printed it, its `fn`, `v` and `endfn`
// lines (the ones the reader reads as records), so that `elabIR` refuses
// it as it would on every line.
@ __wd_records ( Slice u ) t i a i b ( Vec i ) kept → v {
    : i n ( slice_len [u] t )
    : ~ i p a
    ~ < p b {
        : i q ( __wd_eol t p n )
        ? ! ( __wd_blank t p q ) {
            : b h ( __wd_header t p q )
            ? | | ( __wd_first t p q h `fn` ) ( __wd_first t p q h `v` ) ( __wd_first t p q h `endfn` ) { ( __wd_keep kept p q ) } {}
        } {}
        = p + q 1
    }
}

// The Lean source of `core` as words.
@ cert_words s core → String {
    : ( Slice u ) t ( slice_of_str core )
    : i n ( slice_len [u] t )
    : ~ String o ( string_with_cap + n / n 2 )
    ( string_push_str o `def ir : C.Elab.IR := [` )
    : ~ b first T
    // inside a function, as Lean's reader places the lines; inside one of
    // the library's (opened at `lib_a`, outside any other function): it is
    // left out whole, if the reader would read it (`lib_ok`)
    : ~ b in_fn F
    : ~ b in_lib F
    : ~ b lib_ok F
    : ~ i lib_a 0
    : ( Vec i ) kept ( vec_new [i] )
    : ~ i a 0
    ~ < a n {
        : i z ( __wd_eol t a n )
        ? ! ( __wd_blank t a z ) {
            : b header ( __wd_header t a z )
            : b is_fn ( __wd_first t a z header `fn` )
            : b is_end ( __wd_first t a z header `endfn` )
            : ~ b keep T
            ? & in_lib is_fn {
                // a function opened inside the library's: the reader refuses
                ( __wd_records t lib_a a kept )
                = in_lib F
            } {}
            ? in_lib {
                = keep F
                ? is_end {
                    ? ! lib_ok { ( __wd_records t lib_a + z 1 kept ) } {}
                    = in_fn F
                    = in_lib F
                } {
                    ? & ( __wd_first t a z header `v` ) ! ( __wd_var_ok t a z header ) { = lib_ok F } {}
                }
            } {
                ? is_fn {
                    : ( Vec i ) w5 ( vec_new [i] )
                    ( __wd_word t a z header 5 w5 )
                    : i s5 ( vec_at [i] w5 0 )
                    : i e5 ( vec_at [i] w5 1 )
                    ? & & ! in_fn >= s5 0 & >= - e5 s5 7 ( __wd_is t s5 + s5 7 `stdlib/` ) {
                        : ( Vec i ) w3 ( vec_new [i] )
                        ( __wd_word t a z header 3 w3 )
                        = in_lib T
                        = lib_ok ( __wd_nat t ( vec_at [i] w3 0 ) ( vec_at [i] w3 1 ) F )
                        = lib_a a
                        = keep F
                    } {}
                    = in_fn T
                } {
                    ? is_end { = in_fn F } {}
                }
            }
            ? keep { ( __wd_keep kept a z ) } {}
        } {}
        = a + z 1
    }
    // a library function left open: the reader refuses
    ? in_lib { ( __wd_records t lib_a n kept ) } {}
    // The words of every kept line but the `sum` lines: the only names
    // `elabIR` looks a summary up by (a function's own, its callees', a
    // `let`'s called one). A `sum` line whose name is none of them is left
    // out; one with no name is kept (`topOk` refuses it).
    : ( HashMap String i ) seen ( map_new [String i] )
    : i nk ( vec_len [i] kept )
    : ~ i r 0
    ~ < r nk {
        : i ka ( vec_at [i] kept r )
        : i kz ( vec_at [i] kept + r 1 )
        : b h ( __wd_header t ka kz )
        ? ! ( __wd_first t ka kz h `sum` ) { ( __wd_see t ka kz h seen ) } {}
        = r + r 2
    }
    = r 0
    ~ < r nk {
        : i ka ( vec_at [i] kept r )
        : i kz ( vec_at [i] kept + r 1 )
        : b h ( __wd_header t ka kz )
        : ~ b out T
        ? ( __wd_first t ka kz h `sum` ) {
            : ( Vec i ) w1 ( vec_new [i] )
            ( __wd_word t ka kz h 1 w1 )
            : i s1 ( vec_at [i] w1 0 )
            ? & >= s1 0 ! ( __wd_seen t s1 ( vec_at [i] w1 1 ) seen ) { = out F } {}
        } {}
        ? out { ( __wd_line t ka kz h o first ) } {}
        = r + r 2
    }
    ( string_push_str o `]\n` )
    ^ o
}

// Whether `core` has words: no NUL byte. The words are made from the text
// up to its first NUL (`string_data`), and the bundle hashes the whole
// file, so a NUL would leave the words short of Program.core; no core IR
// holds one. Any other byte is printed as its value: the words are numbers,
// which Lean reads as numbers whatever the bytes (before 0.3.1 they were
// string literals, and a byte that is not UTF-8 read back as U+FFFD, so
// such a core IR had no words).
@ cert_words_ok String core → b {
    : ( Slice u ) t ( string_bytes core )
    : i n ( slice_len [u] t )
    : ~ i k 0
    ~ < k n {
        ? == ( slice_byte t k ) 0 { ^ F } {}
        = k + k 1
    }
    ^ T
}
