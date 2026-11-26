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
// lists, and each word as a string literal. Inside a literal `"` and `\`
// are escaped and every byte below 32 is written `\x..`, so a word cannot
// end its literal, start a comment, or hold a line break (a newline ends a
// core IR line, so no word has one anyway). A byte above 127 is written as
// it is: Lean reads the file as UTF-8, and well-formed UTF-8 reads back as
// the same bytes. Lean reads a byte that is not UTF-8 as U+FFFD, which is
// another word: such a core IR has no words (`cert_words_utf8`), and its
// bundle no Elab.lean.
//
// The statement lines of a library function are left out (AGORA-1029
// step 4): the translator takes the functions whose file is the standard
// library's for A2's constructs, not bodies to check (tolean.nu's
// `__emit`), and neither its reader (coreir.nu) nor any of its rules reads
// those lines; `C.Elab.elabIR` drops those functions by the same test
// (`startsB file "stdlib/"`). What is kept of such a function is what the
// Lean reader reads as its records: its `fn` line, its `v` lines (the
// reader checks them) and its `endfn`. A line is placed as Lean's reader
// (`C.Elab.readFns`) places it, by its words as printed: a line whose
// first word is `fn` opens a function, one whose first word is `endfn`
// closes it, and the function is the library's when its sixth word (the
// file) starts with `stdlib/`. So exactly the lines Lean would keep as a
// library function's body are left out, and `elabIR` answers as it would
// on every line (tools/ncore/elab_parity.sh compares the two).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `util.nu`

// A word as a Lean string literal: `"` and `\` escaped, a control
// character written `\x..`.
@ __wd_lit ( Slice u ) t i a i z inout String o → v {
    ( string_push_char o 34 )
    : ~ i k a
    ~ < k z {
        : i c ( slice_byte t k )
        ? | == c 34 == c 92 {
            ( string_push_char o 92 )
            ( string_push_char o c )
        } {
            ? < c 32 {
                ( string_push_str o `\x` )
                : ( Slice u ) hx ( slice_of_str `0123456789abcdef` )
                ( string_push_char o ( slice_byte hx / c 16 ) )
                ( string_push_char o ( slice_byte hx % c 16 ) )
            } { ( string_push_char o c ) }
        }
        = k + k 1
    }
    ( string_push_char o 34 )
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

// The Lean source of `core` as words.
@ cert_words s core → String {
    : ( Slice u ) t ( slice_of_str core )
    : i n ( slice_len [u] t )
    : ~ String o ( string_with_cap + n / n 2 )
    ( string_push_str o `def ir : C.Elab.IR := [` )
    : ~ b first T
    // inside a function, as Lean's reader places the lines; one of the
    // library's: its statement lines are left out
    : ~ b in_fn F
    : ~ b in_lib F
    : ~ i a 0
    ~ < a n {
        : ~ i z a
        ~ & < z n != ( slice_byte t z ) 10 { = z + z 1 }
        : b header ( __wd_header t a z )
        // a blank line (only spaces) is dropped
        : ~ b blank T
        : ~ i q a
        ~ < q z {
            ? != ( slice_byte t q ) 32 { = blank F } {}
            = q + q 1
        }
        : ~ b keep ! blank
        ? keep {
            : ( Vec i ) w0 ( vec_new [i] )
            ( __wd_word t a z header 0 w0 )
            : i s0 ( vec_at [i] w0 0 )
            : i e0 ( vec_at [i] w0 1 )
            : b is_fn & >= s0 0 ( __wd_is t s0 e0 `fn` )
            : b is_end & >= s0 0 ( __wd_is t s0 e0 `endfn` )
            : b is_v & >= s0 0 ( __wd_is t s0 e0 `v` )
            ? is_fn {
                = in_fn T
                : ( Vec i ) w5 ( vec_new [i] )
                ( __wd_word t a z header 5 w5 )
                : i s5 ( vec_at [i] w5 0 )
                : i e5 ( vec_at [i] w5 1 )
                = in_lib & >= s5 0 & >= - e5 s5 7 ( __wd_is t s5 + s5 7 `stdlib/` )
            } {
                ? is_end {
                    = in_fn F
                    = in_lib F
                } {
                    ? & & in_fn in_lib ! is_v { = keep F } {}
                }
            }
        } {}
        ? keep {
            ( string_push_str o ? first `\n  [` `,\n  [` )
            = first F
            : ~ i k a
            : ~ b fw T
            ~ <= k z {
                // a word: up to the next separator (a tab in a header line,
                // a space or a tab in a statement); a statement's empty words are
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
                    ( __wd_lit t k e o )
                } {}
                = k + e 1
            }
            ( string_push_char o 93 )
        } {}
        = a + z 1
    }
    ( string_push_str o `]\n` )
    ^ o
}

// Whether `core` is well-formed UTF-8 (RFC 3629: no overlong form, no
// surrogate, nothing past U+10FFFF). Lean reads each such sequence back as
// the same bytes; any other byte it reads as U+FFFD.
// (`core` read to its own length; a NUL byte is refused: no core IR holds
// one, and the words are made from the text up to the first NUL)
@ cert_words_utf8 String core → b {
    : ( Slice u ) t ( string_bytes core )
    : i n ( slice_len [u] t )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte t k )
        ? == c 0 { ^ F } {}
        ? < c 128 { = k + k 1 } {
            // the continuation bytes a lead byte takes, and the range of the first
            : ~ i len 0
            : ~ i lo 128
            : ~ i hi 191
            ? & >= c 194 <= c 223 { = len 1 } {}
            ? == c 224 { = len 2 = lo 160 } {}
            ? | & >= c 225 <= c 236 | == c 238 == c 239 { = len 2 } {}
            ? == c 237 { = len 2 = hi 159 } {}
            ? == c 240 { = len 3 = lo 144 } {}
            ? & >= c 241 <= c 243 { = len 3 } {}
            ? == c 244 { = len 3 = hi 143 } {}
            ? == len 0 { ^ F } {}
            ? >= + k len n { ^ F } {}
            : i b1 ( slice_byte t + k 1 )
            ? | < b1 lo > b1 hi { ^ F } {}
            : ~ i j 2
            ~ <= j len {
                : i bj ( slice_byte t + k j )
                ? | < bj 128 > bj 191 { ^ F } {}
                = j + j 1
            }
            = k + + k len 1
        }
    }
    ^ T
}
