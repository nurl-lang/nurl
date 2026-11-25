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

// The Lean source of `core` as words.
@ cert_words s core → String {
    : ( Slice u ) t ( slice_of_str core )
    : i n ( slice_len [u] t )
    : ~ String o ( string_with_cap + n / n 2 )
    ( string_push_str o `def ir : C.Elab.IR := [` )
    : ~ b first T
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
        ? ! blank {
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
