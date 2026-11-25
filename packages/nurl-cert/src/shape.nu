// shape.nu — Program.lean may only define the program.
//
// The claims in Claims.lean name `P` and `entry`, and Lean reads them in
// whatever Program.lean declared before. A Program.lean that declared an
// axiom, a notation, a macro, an instance or an `open … in` could change
// what the claims mean without a byte of Claims.lean changing. So the file
// is held to the translator's grammar, and nothing else passes:
//
//   import C.Cert
//   open A2 C
//   def fn<k> : Fn := <term>            (continuation lines indented)
//   def P : Prog := [fn0, fn1, …]
//   def entry : Stmt := .letcall 0 <k> [] .skip
//
// where a <term> is built from constructors written `.name`, numbers,
// `true`/`false`, the structure fields of `Fn`, the names `fn<k>`, and the
// punctuation `( ) [ ] { } , :=`. No other name, no comment, no string,
// no character outside ASCII. Whatever the translator emits is in that
// grammar (it is how the term is written); whatever is not, is refused.
//
// The check also reads off the slot count the claims are stated over: the
// entry is one call into slot 0, so it is 1.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: ShapeRes {
    b ok
    i nv
    String why
}

@ __sh_bad s why i line → ShapeRes {
    : String w ( string_from why )
    ( string_push_str w ` (line ` )
    ( string_push_int w line )
    ( string_push_str w `)` )
    ^ @ ShapeRes { F 0 w }
}

@ __sh_is_alpha i c → b { ^ | | & >= c 65 <= c 90 & >= c 97 <= c 122 == c 95 }

@ __sh_is_digit i c → b { ^ & >= c 48 <= c 57 }

// A bare name the grammar allows.
@ __sh_name_ok ( Slice u ) t i a i z → b {
    : i n - z a
    : String w ( string_new )
    ( string_push_window w t a n )
    : s ws ( string_data w )
    ? | | | != 0 ( nurl_str_eq ws `def` ) != 0 ( nurl_str_eq ws `Fn` ) != 0 ( nurl_str_eq ws `Prog` )
    != 0 ( nurl_str_eq ws `Stmt` ) { ^ T } {}
    ? | | | != 0 ( nurl_str_eq ws `P` ) != 0 ( nurl_str_eq ws `entry` ) != 0 ( nurl_str_eq ws `true` )
    != 0 ( nurl_str_eq ws `false` ) { ^ T } {}
    ? | | | != 0 ( nurl_str_eq ws `params` ) != 0 ( nurl_str_eq ws `resTy` ) != 0 ( nurl_str_eq ws `resOwn` )
    != 0 ( nurl_str_eq ws `lends` ) { ^ T } {}
    ? | | | != 0 ( nurl_str_eq ws `rholds` ) != 0 ( nurl_str_eq ws `outHolds` ) != 0 ( nurl_str_eq ws `body` )
    != 0 ( nurl_str_eq ws `nvars` ) { ^ T } {}
    // fn<digits>
    ? & > n 2 ( string_starts_with w `fn` ) {
        : ~ b all T
        : ~ i k + a 2
        ~ < k z {
            ? ! ( __sh_is_digit ( slice_byte t k ) ) { = all F } {}
            = k + k 1
        }
        ^ all
    } {}
    ^ F
}

// The tokens of lines [a, z) of the text: names, `.name`, numbers and the
// allowed punctuation.
@ __sh_tokens ( Slice u ) t i a i z i line → ShapeRes {
    : ~ i k a
    : ~ i prev 32
    ~ < k z {
        : i c ( slice_byte t k )
        ? ( __sh_is_alpha c ) {
            : ~ i e k
            ~ & < e z | ( __sh_is_alpha ( slice_byte t e ) ) ( __sh_is_digit ( slice_byte t e ) ) { = e + e 1 }
            // A name glued to the one before (`A.b`) is a qualified name.
            ? == prev 46 {
                // `.name`: a constructor; the character before the dot
                // must not end a name.
            } {
                ? ! ( __sh_name_ok t k e ) { ^ ( __sh_bad `a name the program grammar does not have` line ) } {}
            }
            = prev 97
            = k e
            continue
        } {}
        ? ( __sh_is_digit c ) {
            ? == prev 97 { ^ ( __sh_bad `a number glued to a name` line ) } {}
            : ~ e k
            ~ & < e z ( __sh_is_digit ( slice_byte t e ) ) { = e + e 1 }
            = prev 48
            = k e
            continue
        } {}
        ? == c 46 {
            // A dot may only start a constructor: after a separator, and
            // before a letter.
            ? | | == prev 97 == prev 48 == prev 46 { ^ ( __sh_bad `a qualified name` line ) } {}
            ? | >= + k 1 z ! ( __sh_is_alpha ( slice_byte t + k 1 ) ) { ^ ( __sh_bad `a dot not before a constructor` line ) } {}
            = prev 46
            = k + k 1
            continue
        } {}
        ? == c 58 {
            // `:` or `:=`
            = prev 58
            = k + k 1
            continue
        } {}
        ? == c 61 {
            ? != prev 58 { ^ ( __sh_bad `an '=' that is not ':='` line ) } {}
            = prev 61
            = k + k 1
            continue
        } {}
        ? | | | | | | | == c 40 == c 41 == c 91 == c 93 == c 123 == c 125 == c 44 == c 32 {
            = prev 32
            = k + k 1
            continue
        } {}
        ? == c 10 {
            = prev 32
            = k + k 1
            continue
        } {}
        ^ ( __sh_bad `a character the program grammar does not have` line )
    }
    ^ @ ShapeRes { T 0 ( string_new ) }
}

// Does line [a, z) start with `pre`?
@ __sh_starts ( Slice u ) t i a i z s pre → b {
    : ( Slice u ) pv ( slice_of_str pre )
    : i n ( slice_len [u] pv )
    ? > + a n z { ^ F } {}
    : ~ i k 0
    ~ < k n {
        ? != ( slice_byte t + a k ) ( slice_byte pv k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ __sh_line_is ( Slice u ) t i a i z s want → b {
    ^ & == - z a ( nurl_str_len want ) ( __sh_starts t a z want )
}

// The check. `text` is the whole of Program.lean.
@ cert_shape s text → ShapeRes {
    : ( Slice u ) t ( slice_of_str text )
    : i n ( slice_len [u] t )
    : ~ i a 0
    : ~ i line 1
    : ~ b have_p F
    : ~ b have_entry F
    : ~ b in_def F
    ~ < a n {
        : ~ i z a
        ~ & < z n != ( slice_byte t z ) 10 { = z + z 1 }
        ? == line 1 {
            ? ! ( __sh_line_is t a z `import C.Cert` ) { ^ ( __sh_bad `the first line is not 'import C.Cert'` line ) } {}
        } {
            ? == line 2 {
                ? ! ( __sh_line_is t a z `open A2 C` ) { ^ ( __sh_bad `the second line is not 'open A2 C'` line ) } {}
            } {
                ? == a z {
                    = in_def F
                } {
                    : i c0 ( slice_byte t a )
                    ? == c0 32 {
                        // A continuation of a `def fn<k>`.
                        ? ! in_def { ^ ( __sh_bad `an indented line outside a definition` line ) } {}
                    } {
                        ? ( __sh_starts t a z `def fn` ) {
                            ? | have_p have_entry { ^ ( __sh_bad `a function after P or entry` line ) } {}
                            = in_def T
                        } {
                            ? ( __sh_starts t a z `def P : Prog := [` ) {
                                ? have_p { ^ ( __sh_bad `P defined twice` line ) } {}
                                = have_p T
                                = in_def F
                            } {
                                ? ( __sh_starts t a z `def entry : Stmt := .letcall 0 ` ) {
                                    ? | have_entry ! have_p { ^ ( __sh_bad `entry not right after P` line ) } {}
                                    // the rest: <digits> [] .skip
                                    : ~ i k + a 31
                                    : i d0 k
                                    ~ & < k z ( __sh_is_digit ( slice_byte t k ) ) { = k + k 1 }
                                    ? | == k d0 ! ( __sh_line_is t k z ` [] .skip` ) {
                                        ^ ( __sh_bad `entry is not one call of a function with no arguments` line )
                                    } {}
                                    = have_entry T
                                    = in_def F
                                } {
                                    ^ ( __sh_bad `a line that defines something other than the program` line )
                                }
                            }
                        }
                    }
                    : ShapeRes r ( __sh_tokens t a z line )
                    ? ! . r ok { ^ r } {}
                }
            }
        }
        = a + z 1
        = line + line 1
    }
    ? ! & have_p have_entry { ^ ( __sh_bad `P or entry is missing` line ) } {}
    ^ @ ShapeRes { T 1 ( string_new ) }
}
