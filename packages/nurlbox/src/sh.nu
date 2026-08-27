// nurlbox/sh.nu — the shell.
//
// A POSIX-shaped `sh`: quoting, parameter and command substitution,
// arithmetic, globbing, pipelines, redirections, `&&` / `||`, `if`,
// `while`, `until`, `for`, `case`, functions, and the builtins a script
// cannot be written without.
//
// Two decisions shape the implementation.
//
// **Applets run in-process.** When a command names one of nurlbox's own
// applets, the shell calls it directly rather than exec'ing itself.
// That is busybox's standalone-shell trick, and here it is what makes
// the shell work on a machine with no `fork` at all — the unikernel runs
// one program in one address space, and a shell that could only work by
// spawning would be a shell that could not run there.
//
// **Quoting is tracked per byte.** Every word carries a mask parallel to
// its text saying how each byte was quoted: 0 unquoted, 1 single-quoted,
// 2 double-quoted. Expansion consults it, so `$x` expands inside `"` and
// not inside `'`, and the RESULT of an expansion is split into fields
// and globbed only where the `$` itself was unquoted. Anything less than
// a per-byte answer gets `"$@"` or `echo "a b"` wrong.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/bufio.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/ext/env.nu`
$ `bx.nu`

// ── Words ─────────────────────────────────────────────────────────

: ShWord {
    String text
    String mask  // one byte per text byte: 0 bare, 1 single, 2 double
}

@ __shw_new → ShWord { ^ @ ShWord { ( string_new ) ( string_new ) } }

@ __shw_free ShWord w → v {
    ( string_free . w text )
    ( string_free . w mask )
}

@ __shw_push ShWord w i c i q → v {
    ( string_push_char . w text c )
    ( string_push_char . w mask q )
}

@ __shw_push_str ShWord w s t i q → v {
    : i n ( nurl_str_len t )
    : ~ i i 0
    ~ < i n {
        ( __shw_push w ( nurl_str_get t i ) q )
        = i + i 1
    }
}

@ __shw_clone ShWord w → ShWord {
    ^ @ ShWord { ( string_clone . w text ) ( string_clone . w mask ) }
}

@ __shw_len ShWord w → i { ^ ( string_len . w text ) }

@ __shw_at ShWord w i k → i { ^ ( string_get . w text k ) }

@ __shw_q ShWord w i k → i { ^ ( string_get . w mask k ) }

@ __shw_free_vec ( Vec ShWord ) v → v {
    ( vec_free_with [ShWord] v \ ShWord w → v { ( __shw_free w ) } )
}

// ── Tokens ────────────────────────────────────────────────────────

: i SHT_WORD 0
: i SHT_OP 1
: i SHT_NEWLINE 2
: i SHT_EOF 3

: ShTok {
    i kind
    ShWord word  // for SHT_WORD
    String op  // for SHT_OP
}

@ __sht_free ShTok t → v {
    ( __shw_free . t word )
    ( string_free . t op )
}

@ __sht_free_vec ( Vec ShTok ) v → v {
    ( vec_free_with [ShTok] v \ ShTok t → v { ( __sht_free t ) } )
}

@ __sh_is_op_char i c → b {
    ^ | | | | | | | == c 124 == c 38 == c 59 == c 40 == c 41 == c 60 == c 62 == c 10
}

@ __sh_is_blank_c i c → b { ^ | == c 32 == c 9 }

// The lexer. Quoting is resolved here — the parser and the expander
// never see a quote character again, only the mask.
//
// Heredoc bodies are collected too, in the order their `<<` appeared,
// because a heredoc's text is NOT part of the token stream: it starts on
// the line after the operator and runs to its delimiter. Lexing it as
// words would turn `cat <<EOF` followed by `if false` into a parse
// error about an `if` nobody wrote.
@ __sh_lex s src ( Vec ShTok ) out ( Vec String ) bodies → b {
    : i n ( nurl_str_len src )
    : ~ i i 0
    : ~ b ok T
    // Delimiters awaiting their body, and whether `<<-` asked for the
    // leading tabs to be stripped.
    : ~ ( Vec String ) pending ( vec_new [String] )
    : ~ ( Vec i ) pending_strip ( vec_new [i] )
    : ~ b want_delim F
    : ~ b want_strip F
    ~ < i n {
        // Blanks between words, and comments to end of line.
        ~ & < i n ( __sh_is_blank_c ( nurl_str_get src i ) ) { = i + i 1 }
        ? & < i n == ( nurl_str_get src i ) 35 {
            ~ & < i n != ( nurl_str_get src i ) 10 { = i + i 1 }
        } {}
        ? >= i n { = i n } {
            : i c ( nurl_str_get src i )
            ? == c 10 {
                ( vec_push [ShTok] out @ ShTok { SHT_NEWLINE ( __shw_new ) ( string_from `\n` ) } )
                = i + i 1
                // Every heredoc opened on this line takes its body now.
                : i np ( vec_len [String] pending )
                : ~ i pi 0
                ~ < pi np {
                    : ~ i strip 0
                    ?? ( vec_get [i] pending_strip pi ) { T x → { = strip x } F _ → {} }
                    : String body ( string_new )
                    : ~ b closed F
                    ~ & ! closed < i n {
                        : ~ i e i
                        ~ & < e n != ( nurl_str_get src e ) 10 { = e + e 1 }
                        : ~ i ls i
                        ? != strip 0 {
                            ~ & < ls e == ( nurl_str_get src ls ) 9 { = ls + ls 1 }
                        } {}
                        : s line ( nurl_str_slice src ls - e ls )
                        ? ( bx_streq line ( bx_at pending pi ) ) {
                            = closed T
                        } {
                            ( string_push_str body line )
                            ( string_push_char body 10 )
                        }
                        = i ? < e n + e 1 e
                    }
                    ( vec_push [String] bodies body )
                    = pi + pi 1
                }
                ( vec_free_with [String] pending \ String x → v { ( string_free x ) } )
                ( vec_free [i] pending_strip )
                = pending ( vec_new [String] )
                = pending_strip ( vec_new [i] )
            } {
                // `2>file` / `1>&2`: a digit run touching a redirection
                // operator is that operator's descriptor, not a word.
                // Only adjacency distinguishes them — `echo 2 > f` is an
                // argument and a redirect, `echo 2> f` is a redirect.
                : ~ i digit_end i
                ~ & < digit_end n ( bx_is_digit ( nurl_str_get src digit_end ) ) { = digit_end + digit_end 1 }
                : b fd_prefix & > digit_end i & < digit_end n | == ( nurl_str_get src digit_end ) 60 == ( nurl_str_get src digit_end ) 62
                ? fd_prefix {
                    : String op ( string_from ( nurl_str_slice src i - digit_end i ) )
                    = i digit_end
                    : i oc ( nurl_str_get src i )
                    : i oc2 ? < + i 1 n ( nurl_str_get src + i 1 ) 0
                    ( string_push_char op oc )
                    = i + i 1
                    ? | & == oc 62 == oc2 62 & == oc 60 == oc2 60 {
                        ( string_push_char op oc2 )
                        = i + i 1
                    } {
                        ? == oc2 38 {
                            ( string_push_char op 38 )
                            = i + i 1
                        } {}
                    }
                    ( vec_push [ShTok] out @ ShTok { SHT_OP ( __shw_new ) op } )
                } {
                    ? ( __sh_is_op_char c ) {
                        // Longest operator first: `>>` before `>`, `&&`
                        // before `&`, `;;` before `;`.
                        : ~ String op ( string_new )
                        : i c2 ? < + i 1 n ( nurl_str_get src + i 1 ) 0
                        ? | | & == c 62 == c2 62 & == c 60 == c2 60 | & == c 38 == c2 38 | & == c 124 == c2 124 & == c 59 == c2 59 {
                            ( string_push_char op c )
                            ( string_push_char op c2 )
                            = i + i 2
                            // `<<-` is a heredoc that strips leading tabs.
                            ? & & == c 60 < i n == 45 ( nurl_str_get src i ) {
                                ( string_push_char op 45 )
                                = i + i 1
                            } {}
                        } {
                            ? & | == c 62 == c 60 & < + i 1 n == 38 c2 {
                                // `>&` / `<&` — a descriptor duplication.
                                ( string_push_char op c )
                                ( string_push_char op 38 )
                                = i + i 2
                            } {
                                ( string_push_char op c )
                                = i + i 1
                            }
                        }
                        ? ( nurl_str_starts ( string_data op ) `<<` ) {
                            ? ! ( bx_streq ( string_data op ) `<<&` ) {
                                = want_delim T
                                = want_strip ( bx_streq ( string_data op ) `<<-` )
                            } {}
                        } {}
                        ( vec_push [ShTok] out @ ShTok { SHT_OP ( __shw_new ) op } )
                    } {
                        // A word: everything up to an unquoted blank or
                        // operator, with quotes folded into the mask.
                        : ShWord w ( __shw_new )
                        : ~ b done F
                        ~ & ! done < i n {
                            : i ch ( nurl_str_get src i )
                            ? | ( __sh_is_blank_c ch ) ( __sh_is_op_char ch ) { = done T } {
                                ? == ch 39 {
                                    = i + i 1
                                    ~ & < i n != ( nurl_str_get src i ) 39 {
                                        ( __shw_push w ( nurl_str_get src i ) 1 )
                                        = i + i 1
                                    }
                                    ? >= i n {
                                        ( bx_err `unterminated '` )
                                        = ok F
                                        = done T
                                    } { = i + i 1 }
                                } {
                                    ? == ch 34 {
                                        = i + i 1
                                        ~ & < i n != ( nurl_str_get src i ) 34 {
                                            : i q ( nurl_str_get src i )
                                            ? & == q 92 < + i 1 n {
                                                : i e ( nurl_str_get src + i 1 )
                                                // Inside "…", a backslash
                                                // only escapes these five.
                                                ? | | | | == e 34 == e 92 == e 36 == e 96 == e 10 {
                                                    ? != e 10 { ( __shw_push w e 2 ) } {}
                                                    = i + i 2
                                                } {
                                                    ( __shw_push w 92 2 )
                                                    = i + i 1
                                                }
                                            } {
                                                ( __shw_push w q 2 )
                                                = i + i 1
                                            }
                                        }
                                        ? >= i n {
                                            ( bx_err `unterminated "` )
                                            = ok F
                                            = done T
                                        } { = i + i 1 }
                                    } {
                                        ? == ch 92 {
                                            ? < + i 1 n {
                                                : i e ( nurl_str_get src + i 1 )
                                                // A backslash-newline is a
                                                // line continuation and
                                                // disappears entirely.
                                                ? != e 10 { ( __shw_push w e 1 ) } {}
                                                = i + i 2
                                            } { = i + i 1 }
                                        } {
                                            // `$(` and backticks swallow a
                                            // nested run whole; the expander
                                            // parses it later.
                                            ? & == ch 36 & < + i 1 n == 40 ( nurl_str_get src + i 1 ) {
                                                : ~ i depth 0
                                                : i start i
                                                ~ & < i n | > depth 0 <= i + start 1 {
                                                    : i q ( nurl_str_get src i )
                                                    ? == q 40 { = depth + depth 1 } {}
                                                    ? == q 41 { = depth - depth 1 } {}
                                                    ( __shw_push w q 0 )
                                                    = i + i 1
                                                }
                                            } {
                                                ? == ch 96 {
                                                    ( __shw_push w ch 0 )
                                                    = i + i 1
                                                    ~ & < i n != ( nurl_str_get src i ) 96 {
                                                        ( __shw_push w ( nurl_str_get src i ) 0 )
                                                        = i + i 1
                                                    }
                                                    ? < i n {
                                                        ( __shw_push w 96 0 )
                                                        = i + i 1
                                                    } {}
                                                } {
                                                    ( __shw_push w ch 0 )
                                                    = i + i 1
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        ? want_delim {
                            // The delimiter is taken literally, quotes and
                            // all — `<<'EOF'` and `<<EOF` name the same one.
                            ( vec_push [String] pending ( string_clone . w text ) )
                            ( vec_push [i] pending_strip ? want_strip 1 0 )
                            = want_delim F
                            = want_strip F
                        } {}
                        ( vec_push [ShTok] out @ ShTok { SHT_WORD w ( string_new ) } )
                    }
                }
            }
        }
    }
    // A heredoc opened on the last line, with no newline after it.
    : i np2 ( vec_len [String] pending )
    : ~ i pj 0
    ~ < pj np2 {
        ( vec_push [String] bodies ( string_new ) )
        = pj + pj 1
    }
    ( vec_free_with [String] pending \ String x → v { ( string_free x ) } )
    ( vec_free [i] pending_strip )
    ( vec_push [ShTok] out @ ShTok { SHT_EOF ( __shw_new ) ( string_new ) } )
    ^ ok
}

// ── The syntax tree ───────────────────────────────────────────────
//
// A flat arena: every node is an index into one Vec, and a parent names
// its children by index. NURL has no cyclic ownership, and an arena is
// the shape that needs none — the whole tree is freed by walking the Vec
// once, in any order.

: i SH_SIMPLE 0
: i SH_PIPE 1
: i SH_AND 2
: i SH_OR 3
: i SH_SEQ 4
: i SH_IF 5
: i SH_WHILE 6
: i SH_UNTIL 7
: i SH_FOR 8
: i SH_CASE 9
: i SH_GROUP 10
: i SH_SUBSHELL 11
: i SH_FUNC 12
: i SH_BACKGROUND 13
: i SH_NOT 14

: i SHR_IN 0  // <
: i SHR_OUT 1  // >
: i SHR_APPEND 2  // >>
: i SHR_HEREDOC 3  // <<
: i SHR_DUP 4  // >&N / <&N

: ShRedir {
    i kind
    i fd  // the descriptor being redirected
    ShWord word  // filename, heredoc body, or target descriptor
}

: ShNode {
    i kind
    i a
    i b
    i c
    ( Vec i ) kids
    ( Vec ShWord ) words
    ( Vec ShRedir ) redirs
    String text
}

@ __shn_blank i kind → ShNode {
    ^ @ ShNode { kind -1 -1 -1 ( vec_new [i] ) ( vec_new [ShWord] ) ( vec_new [ShRedir] ) ( string_new ) }
}

@ __shn_free ShNode n → v {
    ( vec_free [i] . n kids )
    ( __shw_free_vec . n words )
    ( vec_free_with [ShRedir] . n redirs \ ShRedir r → v { ( __shw_free . r word ) } )
    ( string_free . n text )
}

@ __shn_free_arena ( Vec ShNode ) arena → v {
    ( vec_free_with [ShNode] arena \ ShNode n → v { ( __shn_free n ) } )
}

@ __shn_push ( Vec ShNode ) arena ShNode n → i {
    : i idx ( vec_len [ShNode] arena )
    ( vec_push [ShNode] arena n )
    ^ idx
}

// ── The parser ────────────────────────────────────────────────────

: ~ i g_sh_pos 0
: ~ i g_sh_here 0
: ~ b g_sh_perr F

@ __sh_kind ( Vec ShTok ) t i idx → i {
    ?? ( vec_get [ShTok] t idx ) {
        T x → { ^ . x kind }
        F _ → { ^ SHT_EOF }
    }
}

@ __sh_op ( Vec ShTok ) t i idx → s {
    ?? ( vec_get [ShTok] t idx ) {
        T x → { ^ ( string_data . x op ) }
        F _ → { ^ `` }
    }
}

@ __sh_word_at ( Vec ShTok ) t i idx → ShWord {
    ?? ( vec_get [ShTok] t idx ) {
        T x → { ^ . x word }
        F _ → { ^ ( __shw_new ) }
    }
}

// The literal text of a token, only meaningful for reserved-word tests.
@ __sh_text ( Vec ShTok ) t i idx → s {
    ?? ( vec_get [ShTok] t idx ) {
        T x → { ^ ( string_data . . x word text ) }
        F _ → { ^ `` }
    }
}

// A word is a RESERVED word only when nothing about it was quoted:
// `if` opens a conditional, `'if'` is the name of a command.
@ __sh_bare ( Vec ShTok ) t i idx → b {
    ?? ( vec_get [ShTok] t idx ) {
        T x → {
            : i n ( string_len . . x word mask )
            : ~ i k 0
            ~ < k n {
                ? != 0 ( string_get . . x word mask k ) { ^ F } {}
                = k + k 1
            }
            ^ T
        }
        F _ → { ^ F }
    }
}

@ __sh_is_word ( Vec ShTok ) t i idx s want → b {
    ? != ( __sh_kind t idx ) SHT_WORD { ^ F } {}
    ? ! ( __sh_bare t idx ) { ^ F } {}
    ^ ( bx_streq ( __sh_text t idx ) want )
}

@ __sh_is_op ( Vec ShTok ) t i idx s want → b {
    ? != ( __sh_kind t idx ) SHT_OP { ^ F } {}
    ^ ( bx_streq ( __sh_op t idx ) want )
}

@ __sh_reserved ( Vec ShTok ) t i idx → b {
    ? != ( __sh_kind t idx ) SHT_WORD { ^ F } {}
    ? ! ( __sh_bare t idx ) { ^ F } {}
    : s w ( __sh_text t idx )
    ^ | | | | | | | | | | | | | ( bx_streq w `if` ) ( bx_streq w `then` ) ( bx_streq w `elif` ) ( bx_streq w `else` ) ( bx_streq w `fi` ) ( bx_streq w `while` ) ( bx_streq w `until` ) ( bx_streq w `do` ) ( bx_streq w `done` ) ( bx_streq w `for` ) ( bx_streq w `in` ) ( bx_streq w `case` ) ( bx_streq w `esac` ) | ( bx_streq w `{` ) ( bx_streq w `}` )
}

@ __sh_skip_newlines ( Vec ShTok ) t → v {
    ~ == ( __sh_kind t g_sh_pos ) SHT_NEWLINE { = g_sh_pos + g_sh_pos 1 }
}

@ __sh_perr s msg → v {
    ? ! g_sh_perr {
        ( bx_err_at `syntax error` msg )
        = g_sh_perr T
    } {}
}

// `2>file`, `>>file`, `<<EOF`, `2>&1` — the fd may be glued to the left
// of the operator, which the lexer has already split off as its own
// word, so the check is "did a bare number end right where the operator
// begins".
@ __sh_redir ( Vec ShTok ) t ( Vec String ) bodies ( Vec ShRedir ) out → b {
    : i k ( __sh_kind t g_sh_pos )
    ? != k SHT_OP { ^ F } {}
    : s raw ( __sh_op t g_sh_pos )
    : ~ i explicit -1
    : ~ i skip 0
    ~ & < skip ( nurl_str_len raw ) ( bx_is_digit ( nurl_str_get raw skip ) ) { = skip + skip 1 }
    ? > skip 0 { = explicit ( nurl_str_to_int ( nurl_str_slice raw 0 skip ) ) } {}
    : s op ? > skip 0 ( nurl_str_slice raw skip - ( nurl_str_len raw ) skip ) raw
    : ~ i kind -1
    : ~ i fd -1
    ? ( bx_streq op `<` ) { = kind SHR_IN = fd 0 } {}
    ? ( bx_streq op `>` ) { = kind SHR_OUT = fd 1 } {}
    ? ( bx_streq op `>>` ) { = kind SHR_APPEND = fd 1 } {}
    ? | ( bx_streq op `<<` ) ( bx_streq op `<<-` ) { = kind SHR_HEREDOC = fd 0 } {}
    ? ( bx_streq op `>&` ) { = kind SHR_DUP = fd 1 } {}
    ? ( bx_streq op `<&` ) { = kind SHR_DUP = fd 0 } {}
    ? < kind 0 { ^ F } {}
    ? >= explicit 0 { = fd explicit } {}
    = g_sh_pos + g_sh_pos 1
    ? == kind SHR_HEREDOC {
        // The delimiter word was consumed by the lexer; the body is
        // waiting in `bodies`, in the order the operators appeared.
        ? == ( __sh_kind t g_sh_pos ) SHT_WORD { = g_sh_pos + g_sh_pos 1 } {}
        : ShWord w ( __shw_new )
        ? < g_sh_here ( vec_len [String] bodies ) {
            ( __shw_push_str w ( bx_at bodies g_sh_here ) 2 )
            = g_sh_here + g_sh_here 1
        } {}
        ( vec_push [ShRedir] out @ ShRedir { kind fd w } )
        ^ T
    } {}
    ? != ( __sh_kind t g_sh_pos ) SHT_WORD {
        ( __sh_perr `a redirection needs a target` )
        ^ T
    } {}
    ( vec_push [ShRedir] out @ ShRedir { kind fd ( __shw_clone ( __sh_word_at t g_sh_pos ) ) } )
    = g_sh_pos + g_sh_pos 1
    ^ T
}

// `name=value` at the head of a simple command, unquoted `=`.
@ __sh_is_assign ShWord w → b {
    : i n ( __shw_len w )
    ? == n 0 { ^ F } {}
    : i c0 ( __shw_at w 0 )
    ? ! | | & >= c0 65 <= c0 90 & >= c0 97 <= c0 122 == c0 95 { ^ F } {}
    : ~ i i 1
    ~ < i n {
        : i c ( __shw_at w i )
        ? & == c 61 == 0 ( __shw_q w i ) { ^ T } {}
        ? ! | | | & >= c 65 <= c 90 & >= c 97 <= c 122 & >= c 48 <= c 57 == c 95 { ^ F } {}
        = i + i 1
    }
    ^ F
}

@ __sh_parse_simple ( Vec ShNode ) arena ( Vec ShTok ) t ( Vec String ) bodies → i {
    : ShNode n ( __shn_blank SH_SIMPLE )
    : ~ b done F
    ~ ! done {
        ? ( __sh_redir t bodies . n redirs ) {} {
            ? == ( __sh_kind t g_sh_pos ) SHT_WORD {
                ( vec_push [ShWord] . n words ( __shw_clone ( __sh_word_at t g_sh_pos ) ) )
                = g_sh_pos + g_sh_pos 1
            } { = done T }
        }
        ? g_sh_perr { = done T } {}
    }
    ^ ( __shn_push arena n )
}

// `pattern) list ;;` arms, flattened into the node's kid list as
// alternating (pattern-word-index, body-node) — the words live in the
// node's word vector and the bodies in its kid vector, index for index.
@ __sh_parse_case ( Vec ShNode ) arena ( Vec ShTok ) t ( Vec String ) bodies → i {
    : ShNode n ( __shn_blank SH_CASE )
    ? != ( __sh_kind t g_sh_pos ) SHT_WORD {
        ( __sh_perr `case needs a word` )
        ^ ( __shn_push arena n )
    } {}
    ( vec_push [ShWord] . n words ( __shw_clone ( __sh_word_at t g_sh_pos ) ) )
    = g_sh_pos + g_sh_pos 1
    ( __sh_skip_newlines t )
    ? ! ( __sh_is_word t g_sh_pos `in` ) {
        ( __sh_perr `case needs 'in'` )
        ^ ( __shn_push arena n )
    } {}
    = g_sh_pos + g_sh_pos 1
    ( __sh_skip_newlines t )
    ~ & ! g_sh_perr ! ( __sh_is_word t g_sh_pos `esac` ) {
        ? == ( __sh_kind t g_sh_pos ) SHT_EOF {
            ( __sh_perr `case without esac` )
        } {
            // One arm: `(`? pat ( `|` pat )* `)` list `;;`
            ? ( __sh_is_op t g_sh_pos `(` ) { = g_sh_pos + g_sh_pos 1 } {}
            : ShWord pat ( __shw_new )
            : ~ b first T
            ~ & ! g_sh_perr == ( __sh_kind t g_sh_pos ) SHT_WORD {
                ? first { = first F } { ( __shw_push pat 124 1 ) }
                : ShWord w ( __sh_word_at t g_sh_pos )
                : i wn ( __shw_len w )
                : ~ i k 0
                ~ < k wn {
                    ( __shw_push pat ( __shw_at w k ) ( __shw_q w k ) )
                    = k + k 1
                }
                = g_sh_pos + g_sh_pos 1
                ? ( __sh_is_op t g_sh_pos `|` ) { = g_sh_pos + g_sh_pos 1 } { = k wn }
            }
            ? ! ( __sh_is_op t g_sh_pos `)` ) {
                ( __sh_perr `case pattern needs ')'` )
            } { = g_sh_pos + g_sh_pos 1 }
            : i body ( __sh_parse_list arena t bodies )
            ( vec_push [ShWord] . n words pat )
            ( vec_push [i] . n kids body )
            ( __sh_skip_newlines t )
            ? ( __sh_is_op t g_sh_pos `;;` ) {
                = g_sh_pos + g_sh_pos 1
                ( __sh_skip_newlines t )
            } {}
        }
    }
    ? ( __sh_is_word t g_sh_pos `esac` ) { = g_sh_pos + g_sh_pos 1 } {}
    ^ ( __shn_push arena n )
}

@ __sh_parse_command ( Vec ShNode ) arena ( Vec ShTok ) t ( Vec String ) bodies → i {
    ( __sh_skip_newlines t )
    ? ( __sh_is_op t g_sh_pos `!` ) {
        = g_sh_pos + g_sh_pos 1
        : i child ( __sh_parse_command arena t bodies )
        : ShNode n ( __shn_blank SH_NOT )
        = . n a child
        ^ ( __shn_push arena n )
    } {}
    ? ( __sh_is_word t g_sh_pos `if` ) {
        = g_sh_pos + g_sh_pos 1
        : i cond ( __sh_parse_list arena t bodies )
        ( __sh_skip_newlines t )
        ? ! ( __sh_is_word t g_sh_pos `then` ) { ( __sh_perr `if without then` ) } { = g_sh_pos + g_sh_pos 1 }
        : i thenb ( __sh_parse_list arena t bodies )
        ( __sh_skip_newlines t )
        : ~ i elseb -1
        ? ( __sh_is_word t g_sh_pos `elif` ) {
            // `elif` is `else if …fi`, and building it that way means
            // one code path instead of two.
            = g_sh_pos + g_sh_pos 1
            : i inner_cond ( __sh_parse_list arena t bodies )
            ( __sh_skip_newlines t )
            ? ! ( __sh_is_word t g_sh_pos `then` ) { ( __sh_perr `elif without then` ) } { = g_sh_pos + g_sh_pos 1 }
            : i inner_then ( __sh_parse_list arena t bodies )
            ( __sh_skip_newlines t )
            : ~ i inner_else -1
            ? ( __sh_is_word t g_sh_pos `else` ) {
                = g_sh_pos + g_sh_pos 1
                = inner_else ( __sh_parse_list arena t bodies )
                ( __sh_skip_newlines t )
            } {}
            : ShNode inner ( __shn_blank SH_IF )
            = . inner a inner_cond
            = . inner b inner_then
            = . inner c inner_else
            = elseb ( __shn_push arena inner )
        } {
            ? ( __sh_is_word t g_sh_pos `else` ) {
                = g_sh_pos + g_sh_pos 1
                = elseb ( __sh_parse_list arena t bodies )
                ( __sh_skip_newlines t )
            } {}
        }
        ? ( __sh_is_word t g_sh_pos `fi` ) { = g_sh_pos + g_sh_pos 1 } { ( __sh_perr `if without fi` ) }
        : ShNode n ( __shn_blank SH_IF )
        = . n a cond
        = . n b thenb
        = . n c elseb
        ^ ( __shn_push arena n )
    } {}
    ? | ( __sh_is_word t g_sh_pos `while` ) ( __sh_is_word t g_sh_pos `until` ) {
        : b until ( __sh_is_word t g_sh_pos `until` )
        = g_sh_pos + g_sh_pos 1
        : i cond ( __sh_parse_list arena t bodies )
        ( __sh_skip_newlines t )
        ? ! ( __sh_is_word t g_sh_pos `do` ) { ( __sh_perr `loop without do` ) } { = g_sh_pos + g_sh_pos 1 }
        : i body ( __sh_parse_list arena t bodies )
        ( __sh_skip_newlines t )
        ? ( __sh_is_word t g_sh_pos `done` ) { = g_sh_pos + g_sh_pos 1 } { ( __sh_perr `loop without done` ) }
        : ShNode n ( __shn_blank ? until SH_UNTIL SH_WHILE )
        = . n a cond
        = . n b body
        ^ ( __shn_push arena n )
    } {}
    ? ( __sh_is_word t g_sh_pos `for` ) {
        = g_sh_pos + g_sh_pos 1
        : ShNode n ( __shn_blank SH_FOR )
        ? != ( __sh_kind t g_sh_pos ) SHT_WORD {
            ( __sh_perr `for needs a variable name` )
            ^ ( __shn_push arena n )
        } {}
        ( string_push_str . n text ( __sh_text t g_sh_pos ) )
        = g_sh_pos + g_sh_pos 1
        : ~ b had_in F
        ? ( __sh_is_word t g_sh_pos `in` ) {
            = had_in T
            = g_sh_pos + g_sh_pos 1
            ~ == ( __sh_kind t g_sh_pos ) SHT_WORD {
                ? ( __sh_reserved t g_sh_pos ) { = g_sh_pos g_sh_pos } {}
                ( vec_push [ShWord] . n words ( __shw_clone ( __sh_word_at t g_sh_pos ) ) )
                = g_sh_pos + g_sh_pos 1
            }
        } {}
        // `for x; do` with no `in` iterates the positional parameters,
        // which is spelled by leaving the word list empty and saying so.
        = . n c ? had_in 1 0
        ? ( __sh_is_op t g_sh_pos `;` ) { = g_sh_pos + g_sh_pos 1 } {}
        ( __sh_skip_newlines t )
        ? ! ( __sh_is_word t g_sh_pos `do` ) { ( __sh_perr `for without do` ) } { = g_sh_pos + g_sh_pos 1 }
        = . n a ( __sh_parse_list arena t bodies )
        ( __sh_skip_newlines t )
        ? ( __sh_is_word t g_sh_pos `done` ) { = g_sh_pos + g_sh_pos 1 } { ( __sh_perr `for without done` ) }
        ^ ( __shn_push arena n )
    } {}
    ? ( __sh_is_word t g_sh_pos `case` ) {
        = g_sh_pos + g_sh_pos 1
        ^ ( __sh_parse_case arena t bodies )
    } {}
    ? ( __sh_is_word t g_sh_pos `{` ) {
        = g_sh_pos + g_sh_pos 1
        : i body ( __sh_parse_list arena t bodies )
        ( __sh_skip_newlines t )
        ? ( __sh_is_word t g_sh_pos `}` ) { = g_sh_pos + g_sh_pos 1 } { ( __sh_perr `{ without }` ) }
        : ShNode n ( __shn_blank SH_GROUP )
        = . n a body
        ^ ( __shn_push arena n )
    } {}
    ? ( __sh_is_op t g_sh_pos `(` ) {
        = g_sh_pos + g_sh_pos 1
        : i body ( __sh_parse_list arena t bodies )
        ( __sh_skip_newlines t )
        ? ( __sh_is_op t g_sh_pos `)` ) { = g_sh_pos + g_sh_pos 1 } { ( __sh_perr `( without )` ) }
        : ShNode n ( __shn_blank SH_SUBSHELL )
        = . n a body
        ^ ( __shn_push arena n )
    } {}
    // `name() { … }` — a function definition, recognised by the two
    // tokens after the name.
    ? & & == ( __sh_kind t g_sh_pos ) SHT_WORD ( __sh_is_op t + g_sh_pos 1 `(` ) ( __sh_is_op t + g_sh_pos 2 `)` ) {
        : ShNode n ( __shn_blank SH_FUNC )
        ( string_push_str . n text ( __sh_text t g_sh_pos ) )
        = g_sh_pos + g_sh_pos 3
        ( __sh_skip_newlines t )
        = . n a ( __sh_parse_command arena t bodies )
        ^ ( __shn_push arena n )
    } {}
    ^ ( __sh_parse_simple arena t bodies )
}

@ __sh_parse_pipeline ( Vec ShNode ) arena ( Vec ShTok ) t ( Vec String ) bodies → i {
    : i first ( __sh_parse_command arena t bodies )
    ? ! ( __sh_is_op t g_sh_pos `|` ) { ^ first } {}
    : ShNode n ( __shn_blank SH_PIPE )
    ( vec_push [i] . n kids first )
    ~ ( __sh_is_op t g_sh_pos `|` ) {
        = g_sh_pos + g_sh_pos 1
        ( __sh_skip_newlines t )
        ( vec_push [i] . n kids ( __sh_parse_command arena t bodies ) )
        ? g_sh_perr { = g_sh_pos g_sh_pos } {}
    }
    ^ ( __shn_push arena n )
}

@ __sh_parse_and_or ( Vec ShNode ) arena ( Vec ShTok ) t ( Vec String ) bodies → i {
    : ~ i left ( __sh_parse_pipeline arena t bodies )
    ~ & ! g_sh_perr | ( __sh_is_op t g_sh_pos `&&` ) ( __sh_is_op t g_sh_pos `||` ) {
        : b is_and ( __sh_is_op t g_sh_pos `&&` )
        = g_sh_pos + g_sh_pos 1
        ( __sh_skip_newlines t )
        : i right ( __sh_parse_pipeline arena t bodies )
        : ShNode n ( __shn_blank ? is_and SH_AND SH_OR )
        = . n a left
        = . n b right
        = left ( __shn_push arena n )
    }
    ^ left
}

// A list ends where its enclosing construct's keyword begins — `done`,
// `fi`, `esac`, `}`, `)`, or end of input.
@ __sh_list_ends ( Vec ShTok ) t → b {
    ? == ( __sh_kind t g_sh_pos ) SHT_EOF { ^ T } {}
    ? ( __sh_is_op t g_sh_pos `)` ) { ^ T } {}
    ? ( __sh_is_op t g_sh_pos `;;` ) { ^ T } {}
    ? != ( __sh_kind t g_sh_pos ) SHT_WORD { ^ F } {}
    ? ! ( __sh_bare t g_sh_pos ) { ^ F } {}
    : s w ( __sh_text t g_sh_pos )
    ^ | | | | | | | ( bx_streq w `then` ) ( bx_streq w `elif` ) ( bx_streq w `else` ) ( bx_streq w `fi` ) ( bx_streq w `do` ) ( bx_streq w `done` ) ( bx_streq w `esac` ) ( bx_streq w `}` )
}

@ __sh_parse_list ( Vec ShNode ) arena ( Vec ShTok ) t ( Vec String ) bodies → i {
    : ShNode n ( __shn_blank SH_SEQ )
    ( __sh_skip_newlines t )
    ~ & ! g_sh_perr ! ( __sh_list_ends t ) {
        : ~ i item ( __sh_parse_and_or arena t bodies )
        ? ( __sh_is_op t g_sh_pos `&` ) {
            = g_sh_pos + g_sh_pos 1
            : ShNode bg ( __shn_blank SH_BACKGROUND )
            = . bg a item
            = item ( __shn_push arena bg )
        } {
            ? ( __sh_is_op t g_sh_pos `;` ) { = g_sh_pos + g_sh_pos 1 } {}
        }
        ( vec_push [i] . n kids item )
        ( __sh_skip_newlines t )
    }
    ^ ( __shn_push arena n )
}

// ── Shell state ───────────────────────────────────────────────────
//
// One heap block reached through a global. The alternative — threading
// an `inout` parameter through every function — cannot work here: the
// evaluator is mutually recursive (a command substitution runs the
// evaluator again), and an `inout` callee must be defined before its
// caller, which no cycle can satisfy.

: ShState {
    ( Vec String ) names
    ( Vec String ) values
    ( Vec String ) fnames
    ( Vec i ) fnodes
    ( Vec String ) params
    String argv0
    i status
    i exiting  // 1 once `exit` has been run
    i exit_code
    i brk  // pending `break` levels
    i cont  // pending `continue` levels
    i returning
    i depth  // command-substitution nesting, for a sanity bound
}

: ~ i g_sh_state 0

@ __st → *ShState { ^ # *ShState g_sh_state }

@ __sh_state_new → v {
    : *ShState st # *ShState ( nurl_alloc Z ShState )
    = . st names ( vec_new [String] )
    = . st values ( vec_new [String] )
    = . st fnames ( vec_new [String] )
    = . st fnodes ( vec_new [i] )
    = . st params ( vec_new [String] )
    = . st argv0 ( string_from `sh` )
    = . st status 0
    = . st exiting 0
    = . st exit_code 0
    = . st brk 0
    = . st cont 0
    = . st returning 0
    = . st depth 0
    = g_sh_state # i st
}

@ __sh_state_free → v {
    : *ShState st ( __st )
    ( vec_free_with [String] . st names \ String x → v { ( string_free x ) } )
    ( vec_free_with [String] . st values \ String x → v { ( string_free x ) } )
    ( vec_free_with [String] . st fnames \ String x → v { ( string_free x ) } )
    ( vec_free [i] . st fnodes )
    ( vec_free_with [String] . st params \ String x → v { ( string_free x ) } )
    ( string_free . st argv0 )
    ( nurl_free # s st )
    = g_sh_state 0
}

@ __sh_var_index s name → i {
    : *ShState st ( __st )
    : i n ( vec_len [String] . st names )
    : ~ i i 0
    ~ < i n {
        ? ( bx_streq ( bx_at . st names i ) name ) { ^ i } {}
        = i + i 1
    }
    ^ -1
}

@ __sh_set s name s value → v {
    : *ShState st ( __st )
    : i idx ( __sh_var_index name )
    ? >= idx 0 {
        ?? ( vec_get [String] . st values idx ) {
            T slot → {
                ( string_clear slot )
                ( string_push_str slot value )
            }
            F _ → {}
        }
    } {
        ( vec_push [String] . st names ( string_from name ) )
        ( vec_push [String] . st values ( string_from value ) )
    }
}

// A shell variable, then the environment, then the empty string — the
// order every shell resolves in.
@ __sh_get s name → String {
    : *ShState st ( __st )
    : i idx ( __sh_var_index name )
    ? >= idx 0 { ^ ( string_from ( bx_at . st values idx ) ) } {}
    ?? ( env_get name ) {
        T v → { ^ v }
        F _ → { ^ ( string_new ) }
    }
}

@ __sh_unset s name → v {
    : *ShState st ( __st )
    : i idx ( __sh_var_index name )
    ? >= idx 0 {
        ?? ( vec_remove [String] . st names idx ) {
            T x → { ( string_free x ) }
            F _ → {}
        }
        ?? ( vec_remove [String] . st values idx ) {
            T x → { ( string_free x ) }
            F _ → {}
        }
    } {}
    ?? ( env_unset name ) { T _ → {} F _ → {} }
}

@ __sh_func_index s name → i {
    : *ShState st ( __st )
    : i n ( vec_len [String] . st fnames )
    : ~ i i 0
    ~ < i n {
        ? ( bx_streq ( bx_at . st fnames i ) name ) { ^ i } {}
        = i + i 1
    }
    ^ -1
}

// ── Expansion ─────────────────────────────────────────────────────

@ __sh_is_name_char i c b first → b {
    ? | | & >= c 65 <= c 90 & >= c 97 <= c 122 == c 95 { ^ T } {}
    ? first { ^ F } {}
    ^ & >= c 48 <= c 57
}

// `${VAR#pat}` and friends: strip a prefix or suffix matching `pat`.
// `greedy` picks the longest match, which is the difference between
// `#` and `##`.
@ __sh_strip s value s pat b suffix b greedy → String {
    : i n ( nurl_str_len value )
    : ~ i best -1
    : ~ i k 0
    ~ <= k n {
        : ~ b hit F
        ? suffix {
            : s tail ( nurl_str_slice value - n k k )
            = hit ( fs_match pat tail )
        } {
            : s head ( nurl_str_slice value 0 k )
            = hit ( fs_match pat head )
        }
        ? hit {
            ? | greedy < best 0 { = best k } {}
        } {}
        = k + k 1
    }
    ? < best 0 { ^ ( string_from value ) } {}
    ? suffix { ^ ( string_from ( nurl_str_slice value 0 - n best ) ) } {}
    ^ ( string_from ( nurl_str_slice value best - n best ) )
}

// Positional parameters joined with a space — `$*`, and `$@` outside
// quotes where the split puts them back apart anyway.
@ __sh_params_joined → String {
    : *ShState st ( __st )
    : String out ( string_new )
    : i n ( vec_len [String] . st params )
    : ~ i i 0
    ~ < i n {
        ? > i 0 { ( string_push_char out 32 ) } {}
        ( string_push_str out ( bx_at . st params i ) )
        = i + i 1
    }
    ^ out
}

// ── Arithmetic, for `$(( … ))` ────────────────────────────────────

: ~ i g_ari_pos 0

@ __ari_skip s src → v {
    : i n ( nurl_str_len src )
    ~ & < g_ari_pos n ( bx_is_blank ( nurl_str_get src g_ari_pos ) ) { = g_ari_pos + g_ari_pos 1 }
}

@ __ari_primary s src → i {
    : i n ( nurl_str_len src )
    ( __ari_skip src )
    ? >= g_ari_pos n { ^ 0 } {}
    : i c ( nurl_str_get src g_ari_pos )
    ? == c 40 {
        = g_ari_pos + g_ari_pos 1
        : i v ( __ari_or src )
        ( __ari_skip src )
        ? & < g_ari_pos n == ( nurl_str_get src g_ari_pos ) 41 { = g_ari_pos + g_ari_pos 1 } {}
        ^ v
    } {}
    ? == c 33 {
        = g_ari_pos + g_ari_pos 1
        ^ ? == ( __ari_primary src ) 0 1 0
    } {}
    ? == c 45 {
        = g_ari_pos + g_ari_pos 1
        ^ - 0 ( __ari_primary src )
    } {}
    ? == c 43 {
        = g_ari_pos + g_ari_pos 1
        ^ ( __ari_primary src )
    } {}
    ? ( bx_is_digit c ) {
        : ~ i v 0
        ~ & < g_ari_pos n ( bx_is_digit ( nurl_str_get src g_ari_pos ) ) {
            = v + * v 10 - ( nurl_str_get src g_ari_pos ) 48
            = g_ari_pos + g_ari_pos 1
        }
        ^ v
    } {}
    // A bare name is a variable, and an unset one is zero — the rule
    // that makes `i=$((i+1))` work without initialising `i`.
    ? ( __sh_is_name_char c T ) {
        : i start g_ari_pos
        ~ & < g_ari_pos n ( __sh_is_name_char ( nurl_str_get src g_ari_pos ) F ) { = g_ari_pos + g_ari_pos 1 }
        : String v ( __sh_get ( nurl_str_slice src start - g_ari_pos start ) )
        : i r ( nurl_str_to_int ( string_data v ) )
        ( string_free v )
        ^ r
    } {}
    = g_ari_pos + g_ari_pos 1
    ^ 0
}

@ __ari_mul s src → i {
    : i n ( nurl_str_len src )
    : ~ i acc ( __ari_primary src )
    ( __ari_skip src )
    ~ & < g_ari_pos n | | == ( nurl_str_get src g_ari_pos ) 42 == ( nurl_str_get src g_ari_pos ) 47 == ( nurl_str_get src g_ari_pos ) 37 {
        : i op ( nurl_str_get src g_ari_pos )
        = g_ari_pos + g_ari_pos 1
        : i rhs ( __ari_primary src )
        ? == op 42 { = acc * acc rhs } {
            ? == rhs 0 { = acc 0 } {
                ? == op 47 { = acc / acc rhs } { = acc - acc * rhs / acc rhs }
            }
        }
        ( __ari_skip src )
    }
    ^ acc
}

@ __ari_add s src → i {
    : i n ( nurl_str_len src )
    : ~ i acc ( __ari_mul src )
    ( __ari_skip src )
    ~ & < g_ari_pos n | == ( nurl_str_get src g_ari_pos ) 43 == ( nurl_str_get src g_ari_pos ) 45 {
        : i op ( nurl_str_get src g_ari_pos )
        = g_ari_pos + g_ari_pos 1
        : i rhs ( __ari_mul src )
        = acc ? == op 43 + acc rhs - acc rhs
        ( __ari_skip src )
    }
    ^ acc
}

@ __ari_cmp s src → i {
    : i n ( nurl_str_len src )
    : ~ i acc ( __ari_add src )
    ( __ari_skip src )
    ~ & < g_ari_pos n | | | == ( nurl_str_get src g_ari_pos ) 60 == ( nurl_str_get src g_ari_pos ) 62 & == ( nurl_str_get src g_ari_pos ) 61 == ( nurl_str_get src + g_ari_pos 1 ) 61 & == ( nurl_str_get src g_ari_pos ) 33 == ( nurl_str_get src + g_ari_pos 1 ) 61 {
        : i c1 ( nurl_str_get src g_ari_pos )
        : i c2 ? < + g_ari_pos 1 n ( nurl_str_get src + g_ari_pos 1 ) 0
        : ~ i op 0  // 0 <, 1 <=, 2 >, 3 >=, 4 ==, 5 !=
        ? == c1 60 { = op ? == c2 61 1 0 = g_ari_pos + g_ari_pos ? == c2 61 2 1 } {}
        ? == c1 62 { = op ? == c2 61 3 2 = g_ari_pos + g_ari_pos ? == c2 61 2 1 } {}
        ? == c1 61 { = op 4 = g_ari_pos + g_ari_pos 2 } {}
        ? == c1 33 { = op 5 = g_ari_pos + g_ari_pos 2 } {}
        : i rhs ( __ari_add src )
        : ~ b r F
        ? == op 0 { = r < acc rhs } {}
        ? == op 1 { = r <= acc rhs } {}
        ? == op 2 { = r > acc rhs } {}
        ? == op 3 { = r >= acc rhs } {}
        ? == op 4 { = r == acc rhs } {}
        ? == op 5 { = r != acc rhs } {}
        = acc ? r 1 0
        ( __ari_skip src )
    }
    ^ acc
}

@ __ari_and s src → i {
    : i n ( nurl_str_len src )
    : ~ i acc ( __ari_cmp src )
    ( __ari_skip src )
    ~ & < + g_ari_pos 1 n & == ( nurl_str_get src g_ari_pos ) 38 == ( nurl_str_get src + g_ari_pos 1 ) 38 {
        = g_ari_pos + g_ari_pos 2
        : i rhs ( __ari_cmp src )
        = acc ? & != acc 0 != rhs 0 1 0
        ( __ari_skip src )
    }
    ^ acc
}

@ __ari_or s src → i {
    : i n ( nurl_str_len src )
    : ~ i acc ( __ari_and src )
    ( __ari_skip src )
    ~ & < + g_ari_pos 1 n & == ( nurl_str_get src g_ari_pos ) 124 == ( nurl_str_get src + g_ari_pos 1 ) 124 {
        = g_ari_pos + g_ari_pos 2
        : i rhs ( __ari_and src )
        = acc ? | != acc 0 != rhs 0 1 0
        ( __ari_skip src )
    }
    ^ acc
}

@ __sh_arith s src → i {
    = g_ari_pos 0
    ^ ( __ari_or src )
}

// ── Expansion ─────────────────────────────────────────────────────

// Forward-declared shapes the expander calls back into; the evaluator
// is mutually recursive with it because `$(…)` runs a whole script.

@ __sh_default_ifs → s { ^ ` \t\n` }

@ __sh_ifs → String {
    : i idx ( __sh_var_index `IFS` )
    ? >= idx 0 {
        : *ShState st ( __st )
        ^ ( string_from ( bx_at . st values idx ) )
    } {}
    ^ ( string_from ( __sh_default_ifs ) )
}

@ __sh_in_ifs String ifs i c → b {
    : i n ( string_len ifs )
    : ~ i i 0
    ~ < i n {
        ? == ( string_get ifs i ) c { ^ T } {}
        = i + i 1
    }
    ^ F
}

@ __sh_has_glob ShWord w → b {
    : i n ( __shw_len w )
    : ~ i i 0
    ~ < i n {
        ? == 0 ( __shw_q w i ) {
            : i c ( __shw_at w i )
            ? | | == c 42 == c 63 == c 91 { ^ T } {}
        } {}
        = i + i 1
    }
    ^ F
}

// `${NAME<op>word}` — the braced form, cursor just past the `{`.
@ __sh_brace ShWord src i from i to ShWord acc i q → v {
    : ~ i i from
    // `${#NAME}` is the length of NAME.
    ? & < i to == ( __shw_at src i ) 35 {
        : String nm ( string_new )
        = i + i 1
        ~ < i to {
            ( string_push_char nm ( __shw_at src i ) )
            = i + i 1
        }
        : String v ? ( bx_streq ( string_data nm ) `@` ) ( __sh_params_joined ) ( __sh_get ( string_data nm ) )
        ( __shw_push_str acc ( nurl_str_int ( string_len v ) ) q )
        ( string_free v )
        ( string_free nm )
        ^
    } {}
    : String nm ( string_new )
    ~ & < i to ( __sh_is_name_char ( __shw_at src i ) == ( string_len nm ) 0 ) {
        ( string_push_char nm ( __shw_at src i ) )
        = i + i 1
    }
    // `$1` … `$9` and `$@` inside braces.
    ? == ( string_len nm ) 0 {
        ~ & < i to ! | | | | == ( __shw_at src i ) 58 == ( __shw_at src i ) 45 == ( __shw_at src i ) 61 == ( __shw_at src i ) 43 | == ( __shw_at src i ) 35 == ( __shw_at src i ) 37 {
            ( string_push_char nm ( __shw_at src i ) )
            = i + i 1
        }
    } {}
    : String value ( __sh_special ( string_data nm ) )
    : ~ b unset == ( string_len value ) 0
    ? >= i to {
        ( __shw_push_str acc ( string_data value ) q )
        ( string_free value )
        ( string_free nm )
        ^
    } {}
    // The operator, and the word it applies to.
    : ~ i op ( __shw_at src i )
    : ~ b colon F
    ? == op 58 {
        = colon T
        = i + i 1
        = op ? < i to ( __shw_at src i ) 0
    } {}
    : ~ b greedy F
    ? & | == op 35 == op 37 & < + i 1 to == ( __shw_at src + i 1 ) op {
        = greedy T
    } {}
    = i + i ? greedy 2 1
    : ShWord rest ( __shw_new )
    ~ < i to {
        ( __shw_push rest ( __shw_at src i ) ( __shw_q src i ) )
        = i + i 1
    }
    : String repl ( __sh_expand_to_string rest )
    ( __shw_free rest )
    ? | == op 45 == op 61 {
        ? unset {
            ( __shw_push_str acc ( string_data repl ) q )
            ? == op 61 { ( __sh_set ( string_data nm ) ( string_data repl ) ) } {}
        } { ( __shw_push_str acc ( string_data value ) q ) }
    } {
        ? == op 43 {
            ? unset {} { ( __shw_push_str acc ( string_data repl ) q ) }
        } {
            ? == op 63 {
                ? unset {
                    ( bx_err ? > ( string_len repl ) 0 ( string_data repl ) `parameter not set` )
                    : *ShState st ( __st )
                    = . st exiting 1
                    = . st exit_code 1
                } { ( __shw_push_str acc ( string_data value ) q ) }
            } {
                ? | == op 35 == op 37 {
                    : String cut ( __sh_strip ( string_data value ) ( string_data repl ) == op 37 greedy )
                    ( __shw_push_str acc ( string_data cut ) q )
                    ( string_free cut )
                } { ( __shw_push_str acc ( string_data value ) q ) }
            }
        }
    }
    ( string_free repl )
    ( string_free value )
    ( string_free nm )
}

// `$?`, `$#`, `$$`, `$0`…`$9`, `$*`, and ordinary names.
@ __sh_special s name → String {
    : *ShState st ( __st )
    ? ( bx_streq name `?` ) { ^ ( string_from ( nurl_str_int . st status ) ) } {}
    ? ( bx_streq name `#` ) { ^ ( string_from ( nurl_str_int ( vec_len [String] . st params ) ) ) } {}
    ? ( bx_streq name `$` ) { ^ ( string_from ( nurl_str_int # i ( getpid ) ) ) } {}
    ? | ( bx_streq name `*` ) ( bx_streq name `@` ) { ^ ( __sh_params_joined ) } {}
    ? ( bx_streq name `0` ) { ^ ( string_clone . st argv0 ) } {}
    : i n ( nurl_str_len name )
    ? > n 0 {
        : ~ b digits T
        : ~ i k 0
        ~ < k n {
            ? ! ( bx_is_digit ( nurl_str_get name k ) ) { = digits F } {}
            = k + k 1
        }
        ? digits {
            : i idx ( nurl_str_to_int name )
            ? & >= idx 1 <= idx ( vec_len [String] . st params ) {
                ^ ( string_from ( bx_at . st params - idx 1 ) )
            } {}
            ^ ( string_new )
        } {}
    } {}
    ^ ( __sh_get name )
}

// One word, expanded into `acc`; `$@` splits, so completed fields go to
// `fields` and `acc` restarts.
@ __sh_expand_into ShWord w ShWord acc ( Vec ShWord ) fields → v {
    : *ShState st ( __st )
    : i n ( __shw_len w )
    : ~ i i 0
    // A leading unquoted `~` is $HOME.
    ? & & > n 0 == ( __shw_at w 0 ) 126 == 0 ( __shw_q w 0 ) {
        ? | == n 1 == ( __shw_at w 1 ) 47 {
            : String home ( __sh_get `HOME` )
            ( __shw_push_str acc ( string_data home ) 2 )
            ( string_free home )
            = i 1
        } {}
    } {}
    ~ < i n {
        : i c ( __shw_at w i )
        : i q ( __shw_q w i )
        ? & == c 36 != q 1 {
            ? >= + i 1 n {
                ( __shw_push acc c q )
                = i + i 1
            } {
                : i c2 ( __shw_at w + i 1 )
                ? == c2 40 {
                    ? & < + i 2 n == ( __shw_at w + i 2 ) 40 {
                        // `$(( … ))` — arithmetic.
                        : ~ i depth 0
                        : ~ i k + i 1
                        : String expr ( string_new )
                        ~ < k n {
                            : i ch ( __shw_at w k )
                            ? == ch 40 { = depth + depth 1 } {}
                            ? == ch 41 { = depth - depth 1 } {}
                            ? == depth 0 { = k n } {
                                ? > k + i 2 { ( string_push_char expr ch ) } {}
                                = k + k 1
                            }
                        }
                        // Drop the inner `))`.
                        : i el ( string_len expr )
                        : String body ( string_substr expr 0 ? > el 1 - el 1 0 )
                        ( __shw_push_str acc ( nurl_str_int ( __sh_arith ( string_data body ) ) ) q )
                        ( string_free body )
                        ( string_free expr )
                        : ~ i skip + i 2
                        : ~ i d2 0
                        ~ < skip n {
                            : i ch ( __shw_at w skip )
                            ? == ch 40 { = d2 + d2 1 } {}
                            ? == ch 41 { = d2 - d2 1 } {}
                            = skip + skip 1
                            ? == d2 0 { = i skip = skip n } {}
                        }
                        ? >= skip n { = i n } {}
                    } {
                        // `$( … )` — command substitution.
                        : ~ i depth 0
                        : ~ i k + i 1
                        : String script ( string_new )
                        ~ < k n {
                            : i ch ( __shw_at w k )
                            ? == ch 40 { = depth + depth 1 } {}
                            ? == ch 41 { = depth - depth 1 } {}
                            ? == depth 0 {
                                = i + k 1
                                = k n
                            } {
                                ? > k + i 1 { ( string_push_char script ch ) } {}
                                = k + k 1
                            }
                        }
                        : String captured ( __sh_capture ( string_data script ) )
                        ( __shw_push_str acc ( string_data captured ) q )
                        ( string_free captured )
                        ( string_free script )
                    }
                } {
                    ? == c2 96 {
                        ( __shw_push acc c q )
                        = i + i 1
                    } {
                        ? == c2 123 {
                            : ~ i k + i 2
                            : ~ i close -1
                            ~ & < k n < close 0 {
                                ? == ( __shw_at w k ) 125 { = close k } { = k + k 1 }
                            }
                            ? < close 0 {
                                ( __shw_push acc c q )
                                = i + i 1
                            } {
                                ( __sh_brace w + i 2 close acc q )
                                = i + close 1
                            }
                        } {
                            // `$@` unquoted or quoted: each parameter is
                            // its own field either way when quoted.
                            ? & == c2 64 == q 2 {
                                : i np ( vec_len [String] . st params )
                                : ~ i pi 0
                                ~ < pi np {
                                    ? > pi 0 {
                                        ( vec_push [ShWord] fields ( __shw_clone acc ) )
                                        ( string_clear . acc text )
                                        ( string_clear . acc mask )
                                    } {}
                                    ( __shw_push_str acc ( bx_at . st params pi ) 2 )
                                    = pi + pi 1
                                }
                                = i + i 2
                            } {
                                ? ( __sh_is_name_char c2 T ) {
                                    : ~ i k + i 1
                                    : String nm ( string_new )
                                    ~ & < k n ( __sh_is_name_char ( __shw_at w k ) == ( string_len nm ) 0 ) {
                                        ( string_push_char nm ( __shw_at w k ) )
                                        = k + k 1
                                    }
                                    : String v ( __sh_special ( string_data nm ) )
                                    ( __shw_push_str acc ( string_data v ) q )
                                    ( string_free v )
                                    ( string_free nm )
                                    = i k
                                } {
                                    ? | | | ( bx_is_digit c2 ) == c2 63 == c2 35 | == c2 36 | == c2 42 == c2 64 {
                                        : String nm ( string_new )
                                        ( string_push_char nm c2 )
                                        : String v ( __sh_special ( string_data nm ) )
                                        ( __shw_push_str acc ( string_data v ) q )
                                        ( string_free v )
                                        ( string_free nm )
                                        = i + i 2
                                    } {
                                        ( __shw_push acc c q )
                                        = i + i 1
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } {
            ? & == c 96 != q 1 {
                : ~ i k + i 1
                : String script ( string_new )
                ~ & < k n != ( __shw_at w k ) 96 {
                    ( string_push_char script ( __shw_at w k ) )
                    = k + k 1
                }
                : String captured ( __sh_capture ( string_data script ) )
                ( __shw_push_str acc ( string_data captured ) q )
                ( string_free captured )
                ( string_free script )
                = i ? < k n + k 1 n
            } {
                ( __shw_push acc c q )
                = i + i 1
            }
        }
    }
}

// The whole word as one string, no splitting and no globbing — what a
// redirection target, a `${VAR:-word}` replacement and a case pattern
// all need.
@ __sh_expand_to_string ShWord w → String {
    : ShWord acc ( __shw_new )
    : ( Vec ShWord ) extra ( vec_new [ShWord] )
    ( __sh_expand_into w acc extra )
    : String out ( string_clone . acc text )
    ( __shw_free acc )
    ( __shw_free_vec extra )
    ^ out
}

// Full expansion: substitution, then field splitting on unquoted IFS
// bytes, then globbing. The mask is what keeps the three honest.
@ __sh_expand_word ShWord w ( Vec String ) out → v {
    : ShWord acc ( __shw_new )
    : ( Vec ShWord ) pre ( vec_new [ShWord] )
    ( __sh_expand_into w acc pre )
    ( vec_push [ShWord] pre ( __shw_clone acc ) )
    ( __shw_free acc )
    : String ifs ( __sh_ifs )
    : i np ( vec_len [ShWord] pre )
    : ~ i p 0
    ~ < p np {
        ?? ( vec_get [ShWord] pre p ) {
            T field → {
                : i n ( __shw_len field )
                : ShWord cur ( __shw_new )
                : ~ b started > np 1
                : ~ i i 0
                ~ < i n {
                    : i c ( __shw_at field i )
                    : i q ( __shw_q field i )
                    ? & == q 0 ( __sh_in_ifs ifs c ) {
                        ? > ( __shw_len cur ) 0 {
                            ( __sh_emit_field cur out )
                            ( string_clear . cur text )
                            ( string_clear . cur mask )
                        } {}
                        = started T
                    } {
                        ( __shw_push cur c q )
                        = started T
                    }
                    = i + i 1
                }
                ? | > ( __shw_len cur ) 0 & == n 0 == np 1 {
                    ( __sh_emit_field cur out )
                } {}
                ( __shw_free cur )
            }
            F _ → {}
        }
        = p + p 1
    }
    ( string_free ifs )
    ( __shw_free_vec pre )
}

// One field: globbed if it has unquoted metacharacters and matches
// something, literal otherwise — the shell's "no match, no change" rule.
@ __sh_emit_field ShWord w ( Vec String ) out → v {
    ? ( __sh_has_glob w ) {
        ?? ( fs_glob ( string_data . w text ) ) {
            T matches → {
                : i n ( vec_len [String] matches )
                ? > n 0 {
                    ( sort_by [String] matches \ String a String b → i { ^ ( cmp_string a b ) } )
                    : ~ i k 0
                    ~ < k n {
                        ( vec_push [String] out ( string_from ( bx_at matches k ) ) )
                        = k + k 1
                    }
                    ( vec_free_with [String] matches \ String x → v { ( string_free x ) } )
                    ^
                } {}
                ( vec_free_with [String] matches \ String x → v { ( string_free x ) } )
            }
            F _ → {}
        }
    } {}
    ( vec_push [String] out ( string_clone . w text ) )
}

// ── Execution ─────────────────────────────────────────────────────

& `c` @ dup i32 fd → i32

: i SH_O_RDONLY 0
: i SH_O_WRONLY 1
: i SH_O_CREAT 64
: i SH_O_TRUNC 512
: i SH_O_APPEND 1024

// Does this machine have processes at all? Asked once, because the
// answer changes what a pipeline and a `$(…)` can mean, and a unikernel
// says no.
: ~ i g_sh_have_fork -1

@ __sh_can_fork → b {
    ? < g_sh_have_fork 0 {
        : i32 pid ( fork )
        ? < # i pid 0 { = g_sh_have_fork 0 } {
            ? == # i pid 0 { ( _exit # i32 0 ) } {}
            : s buf ( nurl_zalloc 8 )
            : i32 _w ( waitpid pid # *u buf # i32 0 )
            ( nurl_free buf )
            = g_sh_have_fork 1
        }
    } {}
    ^ != g_sh_have_fork 0
}

@ __sh_no_processes s what → v {
    ( bx_err_at what `not available on a machine with no processes` )
}

// Save fd `fd` somewhere above 10 so the redirection can be undone.
// `fcntl(F_DUPFD)` rather than `dup`, because that is the call the
// freestanding target already carries.
@ __sh_save_fd i fd → i {
    : i32 r ( fcntl # i32 fd # i32 0 10 )
    ^ # i r
}

@ __sh_apply_redirs ( Vec ShRedir ) rs ( Vec i ) saved_fd ( Vec i ) saved_to → b {
    : i n ( vec_len [ShRedir] rs )
    : ~ i i 0
    : ~ b ok T
    ~ & ok < i n {
        ?? ( vec_get [ShRedir] rs i ) {
            T r → {
                : ~ i newfd -1
                ? == . r kind SHR_HEREDOC {
                    // The body has to live somewhere a descriptor can
                    // point at; a temporary file is that somewhere, and
                    // it is unlinked immediately so nothing outlives the
                    // command.
                    ?? ( fs_tempfile `` `sh-here.` ) {
                        T path → {
                            ?? ( write_file ( string_data path ) ( string_data . . r word text ) ) {
                                T _ → {}
                                F _ → { = ok F }
                            }
                            : i32 fd ( open ( string_data path ) # i32 SH_O_RDONLY )
                            = newfd # i fd
                            ?? ( file_delete ( string_data path ) ) { T _ → {} F _ → {} }
                            ( string_free path )
                        }
                        F _ → {
                            ( bx_err `cannot create a temporary file for the here-document` )
                            = ok F
                        }
                    }
                } {
                    : String target ( __sh_expand_to_string . r word )
                    ? == . r kind SHR_DUP {
                        : s t ( string_data target )
                        ? ( bx_streq t `-` ) {
                            : i32 _c ( close # i32 . r fd )
                            = newfd -2
                        } {
                            : i32 d ( fcntl # i32 ( nurl_str_to_int t ) # i32 0 10 )
                            = newfd # i d
                        }
                    } {
                        : ~ i flags SH_O_RDONLY
                        ? == . r kind SHR_OUT { = flags | | SH_O_WRONLY SH_O_CREAT SH_O_TRUNC } {}
                        ? == . r kind SHR_APPEND { = flags | | SH_O_WRONLY SH_O_CREAT SH_O_APPEND } {}
                        : i32 fd ( open ( string_data target ) # i32 flags 420 )
                        = newfd # i fd
                        ? < newfd 0 {
                            ( bx_err_at ( string_data target ) `cannot open` )
                            = ok F
                        } {}
                    }
                    ( string_free target )
                }
                ? & ok >= newfd 0 {
                    : i old ( __sh_save_fd . r fd )
                    ( vec_push [i] saved_fd . r fd )
                    ( vec_push [i] saved_to old )
                    ( flush )
                    : i32 d2 ( dup2 # i32 newfd # i32 . r fd )
                    ? < # i d2 0 {
                        ( __sh_no_processes `redirection` )
                        = ok F
                    } {}
                    : i32 _c ( close # i32 newfd )
                } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ ok
}

@ __sh_undo_redirs ( Vec i ) saved_fd ( Vec i ) saved_to → v {
    ( flush )
    : ~ i i ( vec_len [i] saved_fd )
    ~ > i 0 {
        : ~ i fd -1
        : ~ i old -1
        ?? ( vec_get [i] saved_fd - i 1 ) { T x → { = fd x } F _ → {} }
        ?? ( vec_get [i] saved_to - i 1 ) { T x → { = old x } F _ → {} }
        ? >= old 0 {
            : i32 _d ( dup2 # i32 old # i32 fd )
            : i32 _c ( close # i32 old )
        } {}
        = i - i 1
    }
}

// ── Builtins ──────────────────────────────────────────────────────

@ __sh_is_builtin s name → b {
    ^ | | | | | | | | | | | | | | | ( bx_streq name `cd` ) ( bx_streq name `exit` ) ( bx_streq name `export` ) ( bx_streq name `unset` ) ( bx_streq name `shift` ) ( bx_streq name `set` ) ( bx_streq name `read` ) ( bx_streq name `eval` ) ( bx_streq name `.` ) ( bx_streq name `source` ) ( bx_streq name `return` ) ( bx_streq name `break` ) ( bx_streq name `continue` ) ( bx_streq name `:` ) ( bx_streq name `local` ) ( bx_streq name `type` )
}

@ __sh_builtin ( Vec String ) argv → i {
    : *ShState st ( __st )
    : s name ( bx_at argv 0 )
    : i n ( vec_len [String] argv )
    ? ( bx_streq name `:` ) { ^ 0 } {}
    ? ( bx_streq name `cd` ) {
        : ~ String dest ( string_new )
        ? > n 1 { ( string_push_str dest ( bx_at argv 1 ) ) } {
            : String home ( __sh_get `HOME` )
            ( string_push_bytes dest # *u ( string_data home ) ( string_len home ) )
            ( string_free home )
        }
        ? == ( string_len dest ) 0 {
            ( string_free dest )
            ^ 0
        } {}
        // `cd -` returns to $OLDPWD, and says where it went.
        : ~ b announce F
        ? ( bx_streq ( string_data dest ) `-` ) {
            : String old ( __sh_get `OLDPWD` )
            ( string_clear dest )
            ( string_push_bytes dest # *u ( string_data old ) ( string_len old ) )
            ( string_free old )
            = announce T
        } {}
        : ~ String before ( string_new )
        ?? ( env_cwd ) {
            T c → {
                ( string_free before )
                = before c
            }
            F _ → {}
        }
        ?? ( env_chdir ( string_data dest ) ) {
            T _ → {
                ( __sh_set `OLDPWD` ( string_data before ) )
                ?? ( env_cwd ) {
                    T c2 → {
                        ( __sh_set `PWD` ( string_data c2 ) )
                        ? announce {
                            ( nurl_print ( string_data c2 ) )
                            ( nurl_print `\n` )
                        } {}
                        ( string_free c2 )
                    }
                    F _ → {}
                }
                ( string_free before )
                ( string_free dest )
                ^ 0
            }
            F e → {
                ( bx_err_at ( string_data dest ) ( bx_ioerr e ) )
                ( string_free before )
                ( string_free dest )
                ^ 1
            }
        }
    } {}
    ? ( bx_streq name `exit` ) {
        = . st exiting 1
        = . st exit_code ? > n 1 ( nurl_str_to_int ( bx_at argv 1 ) ) . st status
        ^ . st exit_code
    } {}
    ? ( bx_streq name `export` ) {
        : ~ i i 1
        ~ < i n {
            : s a ( bx_at argv i )
            : i eq ( nurl_str_find a `=` )
            ? > eq 0 {
                : s nm ( nurl_str_slice a 0 eq )
                : s val ( nurl_str_slice a + eq 1 - ( nurl_str_len a ) + eq 1 )
                ( __sh_set nm val )
                ?? ( env_set nm val ) { T _ → {} F _ → {} }
            } {
                : String v ( __sh_get a )
                ?? ( env_set a ( string_data v ) ) { T _ → {} F _ → {} }
                ( string_free v )
            }
            = i + i 1
        }
        ^ 0
    } {}
    ? ( bx_streq name `unset` ) {
        : ~ i i 1
        ~ < i n {
            ( __sh_unset ( bx_at argv i ) )
            = i + i 1
        }
        ^ 0
    } {}
    ? ( bx_streq name `shift` ) {
        : i by ? > n 1 ( nurl_str_to_int ( bx_at argv 1 ) ) 1
        : ~ i k 0
        ~ & < k by > ( vec_len [String] . st params ) 0 {
            ?? ( vec_remove [String] . st params 0 ) {
                T x → { ( string_free x ) }
                F _ → {}
            }
            = k + k 1
        }
        ^ 0
    } {}
    ? ( bx_streq name `set` ) {
        ? > n 1 {
            ( vec_free_with [String] . st params \ String x → v { ( string_free x ) } )
            = . st params ( vec_new [String] )
            : ~ i i 1
            // `set --` ends the option list; nothing here takes options.
            ? ( bx_streq ( bx_at argv 1 ) `--` ) { = i 2 } {}
            ~ < i n {
                ( vec_push [String] . st params ( string_from ( bx_at argv i ) ) )
                = i + i 1
            }
        } {
            : String out ( string_new )
            : i vn ( vec_len [String] . st names )
            : ~ i i 0
            ~ < i vn {
                ( string_push_str out ( bx_at . st names i ) )
                ( string_push_char out 61 )
                ( string_push_str out ( bx_at . st values i ) )
                ( string_push_char out 10 )
                = i + i 1
            }
            ( bx_write out )
            ( string_free out )
        }
        ^ 0
    } {}
    ? ( bx_streq name `read` ) {
        : String line ( read_line )
        : b eof & == ( string_len line ) 0 ( stdin_eof )
        ? > n 1 {
            // Fields go to the named variables, the last one taking
            // whatever is left — POSIX's rule.
            : ( Vec String ) fields ( string_split line ` ` )
            : i nf ( vec_len [String] fields )
            : ~ i vi 1
            ~ < vi n {
                : String val ( string_new )
                ? < - vi 1 nf {
                    ? == vi - n 1 {
                        : ~ i k - vi 1
                        ~ < k nf {
                            ? > k - vi 1 { ( string_push_char val 32 ) } {}
                            ( string_push_str val ( bx_at fields k ) )
                            = k + k 1
                        }
                    } { ( string_push_str val ( bx_at fields - vi 1 ) ) }
                } {}
                ( __sh_set ( bx_at argv vi ) ( string_data val ) )
                ( string_free val )
                = vi + vi 1
            }
            ( vec_free_with [String] fields \ String x → v { ( string_free x ) } )
        } { ( __sh_set `REPLY` ( string_data line ) ) }
        ( string_free line )
        ^ ? eof 1 0
    } {}
    ? ( bx_streq name `eval` ) {
        : String script ( string_new )
        : ~ i i 1
        ~ < i n {
            ? > i 1 { ( string_push_char script 32 ) } {}
            ( string_push_str script ( bx_at argv i ) )
            = i + i 1
        }
        : i r ( __sh_run_string ( string_data script ) )
        ( string_free script )
        ^ r
    } {}
    ? | ( bx_streq name `.` ) ( bx_streq name `source` ) {
        ? < n 2 {
            ( bx_err `. needs a file` )
            ^ 1
        } {}
        ?? ( read_file ( bx_at argv 1 ) ) {
            T text → {
                : i r ( __sh_run_string ( string_data text ) )
                ( string_free text )
                ^ r
            }
            F e → {
                ( bx_err_at ( bx_at argv 1 ) ( bx_ioerr e ) )
                ^ 1
            }
        }
    } {}
    ? ( bx_streq name `return` ) {
        = . st returning 1
        ^ ? > n 1 ( nurl_str_to_int ( bx_at argv 1 ) ) . st status
    } {}
    ? ( bx_streq name `break` ) {
        = . st brk ? > n 1 ( nurl_str_to_int ( bx_at argv 1 ) ) 1
        ^ 0
    } {}
    ? ( bx_streq name `continue` ) {
        = . st cont ? > n 1 ( nurl_str_to_int ( bx_at argv 1 ) ) 1
        ^ 0
    } {}
    ? ( bx_streq name `local` ) {
        // No scoping yet: `local x=1` sets it, which is the behaviour a
        // script depends on; the scope it does not get is documented
        // rather than faked.
        : ~ i i 1
        ~ < i n {
            : s a ( bx_at argv i )
            : i eq ( nurl_str_find a `=` )
            ? > eq 0 {
                ( __sh_set ( nurl_str_slice a 0 eq ) ( nurl_str_slice a + eq 1 - ( nurl_str_len a ) + eq 1 ) )
            } { ( __sh_set a `` ) }
            = i + i 1
        }
        ^ 0
    } {}
    ? ( bx_streq name `type` ) {
        : ~ i rc 0
        : ~ i i 1
        ~ < i n {
            : s a ( bx_at argv i )
            ( nurl_print a )
            ? >= ( __sh_func_index a ) 0 { ( nurl_print ` is a function\n` ) } {
                ? ( __sh_is_builtin a ) { ( nurl_print ` is a shell builtin\n` ) } {
                    ? ( bx_is_applet a ) { ( nurl_print ` is a nurlbox applet\n` ) } {
                        ( nurl_print ` not found\n` )
                        = rc 1
                    }
                }
            }
            = i + i 1
        }
        ^ rc
    } {}
    ^ 0
}

// ── Running commands ──────────────────────────────────────────────

// A function body, with `$1…` swapped for the call's arguments and put
// back afterwards.
@ __sh_call_func ( Vec ShNode ) arena i fidx ( Vec String ) argv → i {
    : *ShState st ( __st )
    : ( Vec String ) saved ( vec_new [String] )
    : i pn ( vec_len [String] . st params )
    : ~ i i 0
    ~ < i pn {
        ( vec_push [String] saved ( string_from ( bx_at . st params i ) ) )
        = i + i 1
    }
    ( vec_free_with [String] . st params \ String x → v { ( string_free x ) } )
    = . st params ( vec_new [String] )
    : i an ( vec_len [String] argv )
    : ~ i k 1
    ~ < k an {
        ( vec_push [String] . st params ( string_from ( bx_at argv k ) ) )
        = k + k 1
    }
    : ~ i body -1
    ?? ( vec_get [i] . st fnodes fidx ) { T x → { = body x } F _ → {} }
    : i rc ? >= body 0 ( __sh_exec arena body ) 0
    = . st returning 0
    ( vec_free_with [String] . st params \ String x → v { ( string_free x ) } )
    = . st params saved
    ^ rc
}

// An external program: fork, exec, wait. A machine with no processes
// says so rather than reporting "not found" about a program that is
// right there.
@ __sh_exec_external ( Vec String ) argv → i {
    ? ! ( __sh_can_fork ) {
        ( __sh_no_processes ( bx_at argv 0 ) )
        ^ 127
    } {}
    ( flush )
    : i32 pid ( fork )
    ? == # i pid 0 {
        : i n ( vec_len [String] argv )
        : s buf ( nurl_zalloc * 8 + n 1 )
        : ~ i k 0
        ~ < k n {
            ( nurl_poke buf k # i ( bx_at argv k ) )
            = k + k 1
        }
        : i32 _r ( execvp ( bx_at argv 0 ) # *u buf )
        ( nurl_eprint ( bx_at argv 0 ) )
        ( nurl_eprint `: not found\n` )
        ( _exit # i32 127 )
        ^ 127
    } {}
    ? < # i pid 0 { ^ 127 } {}
    : s statusbuf ( nurl_zalloc 8 )
    : i32 _w ( waitpid pid # *u statusbuf # i32 0 )
    : i raw ( nurl_peek statusbuf 0 )
    ( nurl_free statusbuf )
    ^ ( nurl_wait_exit_status & raw 65535 )
}

@ __sh_exec_simple ( Vec ShNode ) arena i idx → i {
    : *ShState st ( __st )
    : ~ i rc 0
    ?? ( vec_get [ShNode] arena idx ) {
        F _ → { ^ 0 }
        T n → {
            : ( Vec String ) argv ( vec_new [String] )
            : ( Vec String ) assigns ( vec_new [String] )
            : i wn ( vec_len [ShWord] . n words )
            : ~ b in_prefix T
            : ~ i i 0
            ~ < i wn {
                ?? ( vec_get [ShWord] . n words i ) {
                    T w → {
                        ? & in_prefix ( __sh_is_assign w ) {
                            : String flat ( __sh_expand_to_string w )
                            ( vec_push [String] assigns flat )
                        } {
                            = in_prefix F
                            ( __sh_expand_word w argv )
                        }
                    }
                    F _ → {}
                }
                = i + i 1
            }
            : i argc ( vec_len [String] argv )
            ? == argc 0 {
                // Assignments with no command set the shell's variables
                // for good; with a command they are that command's
                // environment only.
                : i an ( vec_len [String] assigns )
                : ~ i k 0
                ~ < k an {
                    : s a ( bx_at assigns k )
                    : i eq ( nurl_str_find a `=` )
                    ? > eq 0 {
                        ( __sh_set ( nurl_str_slice a 0 eq ) ( nurl_str_slice a + eq 1 - ( nurl_str_len a ) + eq 1 ) )
                    } {}
                    = k + k 1
                }
                ( vec_free_with [String] argv \ String x → v { ( string_free x ) } )
                ( vec_free_with [String] assigns \ String x → v { ( string_free x ) } )
                ^ 0
            } {}
            : ( Vec i ) saved_fd ( vec_new [i] )
            : ( Vec i ) saved_to ( vec_new [i] )
            ? ( __sh_apply_redirs . n redirs saved_fd saved_to ) {
                // A command's assignments go into the environment it
                // sees, and are undone after.
                : i an ( vec_len [String] assigns )
                : ~ i k 0
                ~ < k an {
                    : s a ( bx_at assigns k )
                    : i eq ( nurl_str_find a `=` )
                    ? > eq 0 {
                        ?? ( env_set ( nurl_str_slice a 0 eq ) ( nurl_str_slice a + eq 1 - ( nurl_str_len a ) + eq 1 ) ) {
                            T _ → {}
                            F _ → {}
                        }
                    } {}
                    = k + k 1
                }
                : s cmd ( bx_at argv 0 )
                : i fidx ( __sh_func_index cmd )
                ? >= fidx 0 {
                    = rc ( __sh_call_func arena fidx argv )
                } {
                    ? ( __sh_is_builtin cmd ) {
                        = rc ( __sh_builtin argv )
                    } {
                        ? ( bx_is_applet cmd ) {
                            // In-process: no fork needed, which is what
                            // makes this shell work on a unikernel.
                            = rc ( bx_run_applet cmd argv )
                            ( bx_set_name `sh` )
                        } { = rc ( __sh_exec_external argv ) }
                    }
                }
                ( flush )
            } { = rc 1 }
            ( __sh_undo_redirs saved_fd saved_to )
            ( vec_free [i] saved_fd )
            ( vec_free [i] saved_to )
            ( vec_free_with [String] argv \ String x → v { ( string_free x ) } )
            ( vec_free_with [String] assigns \ String x → v { ( string_free x ) } )
        }
    }
    = . st status rc
    ^ rc
}

// One pipeline stage in a child, with its ends already chosen.
@ __sh_stage ( Vec ShNode ) arena i idx i in_fd i out_fd → i32 {
    ( flush )
    : i32 pid ( fork )
    ? == # i pid 0 {
        ? >= in_fd 0 {
            : i32 _a ( dup2 # i32 in_fd # i32 0 )
            : i32 _b ( close # i32 in_fd )
        } {}
        ? >= out_fd 0 {
            : i32 _c ( dup2 # i32 out_fd # i32 1 )
            : i32 _d ( close # i32 out_fd )
        } {}
        : i rc ( __sh_exec arena idx )
        ( flush )
        ( _exit # i32 rc )
    } {}
    ^ pid
}

// A pipeline on a machine with no processes: each stage runs to
// completion with its output in a temporary file, and the next stage
// reads that file. It is NOT a pipeline — there is no concurrency and
// the buffering is unbounded — but it is what a shell without processes
// can honestly do, and it is what makes `seq 3 | wc -l` answer on a
// unikernel instead of refusing. A stage that never terminates will
// never hand anything on; a real pipeline would have streamed it.
@ __sh_pipe_sequential ( Vec ShNode ) arena i idx i stages → i {
    : ~ i rc 0
    ?? ( vec_get [ShNode] arena idx ) {
        F _ → { ^ 1 }
        T n → {
            : ~ String carry ( string_new )
            : ~ b have_carry F
            : ~ i s 0
            ~ < s stages {
                : ~ i node -1
                ?? ( vec_get [i] . n kids s ) { T k → { = node k } F _ → {} }
                : b last == s - stages 1
                : ~ i in_saved -1
                : ~ String in_path ( string_new )
                ? have_carry {
                    ?? ( fs_tempfile `` `sh-pipe-in.` ) {
                        T p → {
                            ?? ( write_file ( string_data p ) ( string_data carry ) ) { T _ → {} F _ → {} }
                            : i32 fd ( open ( string_data p ) # i32 SH_O_RDONLY )
                            ? >= # i fd 0 {
                                ( flush )
                                = in_saved ( __sh_save_fd 0 )
                                : i32 _d ( dup2 fd # i32 0 )
                                : i32 _c ( close fd )
                            } {}
                            ( string_clear in_path )
                            ( string_push_bytes in_path # *u ( string_data p ) ( string_len p ) )
                            ( string_free p )
                        }
                        F _ → {
                            ( bx_err `a pipeline needs somewhere writable, and this machine has nowhere` )
                            = rc 1
                            = s stages
                        }
                    }
                } {}
                ? == rc 0 {
                    ? last {
                        = rc ( __sh_exec arena node )
                    } {
                        : String captured ( string_new )
                        ?? ( fs_tempfile `` `sh-pipe-out.` ) {
                            T p → {
                                : i32 fd ( open ( string_data p ) # i32 | | SH_O_WRONLY SH_O_CREAT SH_O_TRUNC 420 )
                                ? >= # i fd 0 {
                                    ( flush )
                                    : i saved ( __sh_save_fd 1 )
                                    : i32 _d ( dup2 fd # i32 1 )
                                    : i32 _c ( close fd )
                                    = rc ( __sh_exec arena node )
                                    ( flush )
                                    ? >= saved 0 {
                                        : i32 _d2 ( dup2 # i32 saved # i32 1 )
                                        : i32 _c2 ( close # i32 saved )
                                    } {}
                                } { = rc ( __sh_exec arena node ) }
                                ?? ( read_file ( string_data p ) ) {
                                    T text → {
                                        ( string_push_bytes captured # *u ( string_data text ) ( string_len text ) )
                                        ( string_free text )
                                    }
                                    F _ → {}
                                }
                                ?? ( file_delete ( string_data p ) ) { T _ → {} F _ → {} }
                                ( string_free p )
                            }
                            F _ → {
                                ( bx_err `a pipeline needs somewhere writable, and this machine has nowhere` )
                                = rc 1
                                = s stages
                            }
                        }
                        ( string_free carry )
                        = carry captured
                        = have_carry T
                    }
                } {}
                ? >= in_saved 0 {
                    ( flush )
                    : i32 _r ( dup2 # i32 in_saved # i32 0 )
                    : i32 _rc ( close # i32 in_saved )
                } {}
                ? > ( string_len in_path ) 0 {
                    ?? ( file_delete ( string_data in_path ) ) { T _ → {} F _ → {} }
                } {}
                ( string_free in_path )
                = s + s 1
            }
            ( string_free carry )
        }
    }
    : *ShState st ( __st )
    = . st status rc
    ^ rc
}

@ __sh_exec_pipe ( Vec ShNode ) arena i idx → i {
    : ~ i rc 0
    ?? ( vec_get [ShNode] arena idx ) {
        F _ → { ^ 0 }
        T n → {
            : i stages ( vec_len [i] . n kids )
            ? <= stages 1 {
                ?? ( vec_get [i] . n kids 0 ) {
                    T k → { ^ ( __sh_exec arena k ) }
                    F _ → { ^ 0 }
                }
            } {}
            ? ! ( __sh_can_fork ) { ^ ( __sh_pipe_sequential arena idx stages ) } {}
            : s fdbuf ( nurl_zalloc 16 )
            : ( Vec i ) pids ( vec_new [i] )
            : ~ i prev_read -1
            : ~ i s 0
            ~ < s stages {
                : ~ i wfd -1
                : ~ i rfd -1
                ? < s - stages 1 {
                    : i32 pr ( pipe # *u fdbuf )
                    ? < # i pr 0 {
                        ( bx_err `cannot create a pipe` )
                        = s stages
                    } {
                        = rfd ( __le32_at fdbuf 0 )
                        = wfd ( __le32_at fdbuf 4 )
                    }
                } {}
                : ~ i node -1
                ?? ( vec_get [i] . n kids s ) { T k → { = node k } F _ → {} }
                ? >= node 0 {
                    : i32 pid ( __sh_stage arena node prev_read wfd )
                    ( vec_push [i] pids # i pid )
                } {}
                ? >= prev_read 0 { : i32 _c ( close # i32 prev_read ) } {}
                ? >= wfd 0 { : i32 _c2 ( close # i32 wfd ) } {}
                = prev_read rfd
                = s + s 1
            }
            ( nurl_free fdbuf )
            : s statusbuf ( nurl_zalloc 8 )
            : i np ( vec_len [i] pids )
            : ~ i k 0
            ~ < k np {
                ?? ( vec_get [i] pids k ) {
                    T pid → {
                        : i32 _w ( waitpid # i32 pid # *u statusbuf # i32 0 )
                        // A pipeline's status is its LAST stage's.
                        ? == k - np 1 {
                            = rc ( nurl_wait_exit_status & ( nurl_peek statusbuf 0 ) 65535 )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( nurl_free statusbuf )
            ( vec_free [i] pids )
        }
    }
    : *ShState st ( __st )
    = . st status rc
    ^ rc
}

// `pipe(2)` writes two ints; NURL reads them back a byte at a time
// because an int is 32 bits and `nurl_peek` steps in 64.
@ __le32_at s buf i off → i {
    : *u p # *u buf
    ^ | | | & 255 # i . p off << & 255 # i . p + off 1 8 << & 255 # i . p + off 2 16 << & 255 # i . p + off 3 24
}

@ __sh_exec ( Vec ShNode ) arena i idx → i {
    : *ShState st ( __st )
    ? < idx 0 { ^ 0 } {}
    ? != 0 . st exiting { ^ . st exit_code } {}
    : ~ i rc 0
    ?? ( vec_get [ShNode] arena idx ) {
        F _ → { ^ 0 }
        T n → {
            : i k . n kind
            ? == k SH_SIMPLE { = rc ( __sh_exec_simple arena idx ) } {
                ? == k SH_PIPE { = rc ( __sh_exec_pipe arena idx ) } {
                    ? == k SH_SEQ {
                        : i cnt ( vec_len [i] . n kids )
                        : ~ i i 0
                        ~ < i cnt {
                            ?? ( vec_get [i] . n kids i ) {
                                T child → { = rc ( __sh_exec arena child ) }
                                F _ → {}
                            }
                            ? | | != 0 . st exiting | != 0 . st brk != 0 . st cont != 0 . st returning { = i cnt } { = i + i 1 }
                        }
                    } {
                        ? == k SH_AND {
                            = rc ( __sh_exec arena . n a )
                            ? == rc 0 { = rc ( __sh_exec arena . n b ) } {}
                        } {
                            ? == k SH_OR {
                                = rc ( __sh_exec arena . n a )
                                ? != rc 0 { = rc ( __sh_exec arena . n b ) } {}
                            } {
                                ? == k SH_NOT {
                                    = rc ? == ( __sh_exec arena . n a ) 0 1 0
                                    = . st status rc
                                } {
                                    ? == k SH_IF {
                                        ? == ( __sh_exec arena . n a ) 0 {
                                            = rc ( __sh_exec arena . n b )
                                        } { = rc ? >= . n c 0 ( __sh_exec arena . n c ) 0 }
                                    } {
                                        ? | == k SH_WHILE == k SH_UNTIL {
                                            : ~ b go T
                                            ~ go {
                                                : i cond ( __sh_exec arena . n a )
                                                : b enter ? == k SH_WHILE == cond 0 != cond 0
                                                ? & enter == 0 . st exiting {
                                                    = rc ( __sh_exec arena . n b )
                                                    ? != 0 . st brk {
                                                        = . st brk - . st brk 1
                                                        = go F
                                                    } {}
                                                    ? != 0 . st cont { = . st cont - . st cont 1 } {}
                                                    ? != 0 . st returning { = go F } {}
                                                } { = go F }
                                            }
                                        } {
                                            ? == k SH_FOR {
                                                : ( Vec String ) items ( vec_new [String] )
                                                ? == . n c 0 {
                                                    : i pn ( vec_len [String] . st params )
                                                    : ~ i p 0
                                                    ~ < p pn {
                                                        ( vec_push [String] items ( string_from ( bx_at . st params p ) ) )
                                                        = p + p 1
                                                    }
                                                } {
                                                    : i wn ( vec_len [ShWord] . n words )
                                                    : ~ i w 0
                                                    ~ < w wn {
                                                        ?? ( vec_get [ShWord] . n words w ) {
                                                            T word → { ( __sh_expand_word word items ) }
                                                            F _ → {}
                                                        }
                                                        = w + w 1
                                                    }
                                                }
                                                : i cnt ( vec_len [String] items )
                                                : ~ i i 0
                                                ~ < i cnt {
                                                    ( __sh_set ( string_data . n text ) ( bx_at items i ) )
                                                    = rc ( __sh_exec arena . n a )
                                                    ? != 0 . st brk {
                                                        = . st brk - . st brk 1
                                                        = i cnt
                                                    } {
                                                        ? != 0 . st cont { = . st cont - . st cont 1 } {}
                                                        ? | != 0 . st returning != 0 . st exiting { = i cnt } { = i + i 1 }
                                                    }
                                                }
                                                ( vec_free_with [String] items \ String x → v { ( string_free x ) } )
                                            } {
                                                ? == k SH_CASE {
                                                    : ~ String subject ( string_new )
                                                    ?? ( vec_get [ShWord] . n words 0 ) {
                                                        T w → {
                                                            ( string_free subject )
                                                            = subject ( __sh_expand_to_string w )
                                                        }
                                                        F _ → {}
                                                    }
                                                    : i arms ( vec_len [i] . n kids )
                                                    : ~ i i 0
                                                    : ~ b matched F
                                                    ~ & ! matched < i arms {
                                                        ?? ( vec_get [ShWord] . n words + i 1 ) {
                                                            T pw → {
                                                                : String pat ( __sh_expand_to_string pw )
                                                                // The arm's alternatives are joined with a
                                                                // `|`; each is a glob pattern.
                                                                : ( Vec String ) alts ( string_split pat `|` )
                                                                : i na ( vec_len [String] alts )
                                                                : ~ i a 0
                                                                ~ & ! matched < a na {
                                                                    ? ( fs_match ( bx_at alts a ) ( string_data subject ) ) { = matched T } {}
                                                                    = a + a 1
                                                                }
                                                                ( vec_free_with [String] alts \ String x → v { ( string_free x ) } )
                                                                ( string_free pat )
                                                                ? matched {
                                                                    ?? ( vec_get [i] . n kids i ) {
                                                                        T body → { = rc ( __sh_exec arena body ) }
                                                                        F _ → {}
                                                                    }
                                                                } {}
                                                            }
                                                            F _ → {}
                                                        }
                                                        = i + i 1
                                                    }
                                                    ( string_free subject )
                                                } {
                                                    ? == k SH_GROUP { = rc ( __sh_exec arena . n a ) } {
                                                        ? == k SH_SUBSHELL {
                                                            // A subshell is a separate PROCESS — that is the whole
                                                            // difference between `( … )` and `{ … }`, and it is why
                                                            // an assignment inside one does not reach the parent.
                                                            // A machine with no processes cannot have one, so it
                                                            // runs the body here and says so rather than pretending
                                                            // the isolation happened.
                                                            ? ( __sh_can_fork ) {
                                                                ( flush )
                                                                : i32 pid ( fork )
                                                                ? == # i pid 0 {
                                                                    : i r2 ( __sh_exec arena . n a )
                                                                    ( flush )
                                                                    ( _exit # i32 r2 )
                                                                } {}
                                                                ? < # i pid 0 { = rc ( __sh_exec arena . n a ) } {
                                                                    : s statusbuf ( nurl_zalloc 8 )
                                                                    : i32 _w ( waitpid pid # *u statusbuf # i32 0 )
                                                                    = rc ( nurl_wait_exit_status & ( nurl_peek statusbuf 0 ) 65535 )
                                                                    ( nurl_free statusbuf )
                                                                }
                                                            } {
                                                                ( __sh_no_processes `a subshell` )
                                                                = rc ( __sh_exec arena . n a )
                                                            }
                                                        } {
                                                            ? == k SH_FUNC {
                                                                : i existing ( __sh_func_index ( string_data . n text ) )
                                                                ? >= existing 0 {
                                                                    : b _s ( vec_set [i] . st fnodes existing . n a )
                                                                } {
                                                                    ( vec_push [String] . st fnames ( string_clone . n text ) )
                                                                    ( vec_push [i] . st fnodes . n a )
                                                                }
                                                                = rc 0
                                                            } {
                                                                ? == k SH_BACKGROUND {
                                                                    ? ! ( __sh_can_fork ) {
                                                                        ( __sh_no_processes `a background job` )
                                                                        = rc 1
                                                                    } {
                                                                        ( flush )
                                                                        : i32 pid ( fork )
                                                                        ? == # i pid 0 {
                                                                            : i r2 ( __sh_exec arena . n a )
                                                                            ( flush )
                                                                            ( _exit # i32 r2 )
                                                                        } {}
                                                                        ( nurl_print `[1] ` )
                                                                        ( nurl_print ( nurl_str_int # i pid ) )
                                                                        ( nurl_print `\n` )
                                                                        = rc 0
                                                                    }
                                                                } { = rc 0 } } } } } } } } } } } } } }
        }
    }
    ? != ( __sh_node_kind arena idx ) SH_SIMPLE { = . st status rc } {}
    ^ rc
}

@ __sh_node_kind ( Vec ShNode ) arena i idx → i {
    ?? ( vec_get [ShNode] arena idx ) {
        T n → { ^ . n kind }
        F _ → { ^ -1 }
    }
}

// ── Driving a script ──────────────────────────────────────────────

@ __sh_run_string s script → i {
    : ( Vec ShTok ) toks ( vec_new [ShTok] )
    : ( Vec String ) bodies ( vec_new [String] )
    : ~ i rc 0
    ? ! ( __sh_lex script toks bodies ) { = rc 2 } {
        : ( Vec ShNode ) arena ( vec_new [ShNode] )
        : i saved_pos g_sh_pos
        : i saved_here g_sh_here
        : b saved_err g_sh_perr
        = g_sh_pos 0
        = g_sh_here 0
        = g_sh_perr F
        : i root ( __sh_parse_list arena toks bodies )
        ? g_sh_perr { = rc 2 } { = rc ( __sh_exec arena root ) }
        = g_sh_pos saved_pos
        = g_sh_here saved_here
        = g_sh_perr saved_err
        ( __shn_free_arena arena )
    }
    ( __sht_free_vec toks )
    ( vec_free_with [String] bodies \ String x → v { ( string_free x ) } )
    ^ rc
}

// `$(…)`: the script runs in a child with stdout on a pipe, and the
// trailing newlines come off the result — both of those are what makes
// `x=$(pwd)` behave.
@ __sh_capture s script → String {
    : String out ( string_new )
    ? ! ( __sh_can_fork ) {
        // No processes: run it HERE with stdout pointed at a temporary
        // file, then read the file back. That needs somewhere writable
        // to put the file, which a machine with only a read-only image
        // does not have — and then it says so rather than returning an
        // empty string that looks like a command producing no output.
        ?? ( fs_tempfile `` `sh-cap.` ) {
            F _ → {
                ( bx_err `command substitution needs somewhere writable, and this machine has nowhere` )
                ^ out
            }
            T path → {
                : i32 fd ( open ( string_data path ) # i32 | | SH_O_WRONLY SH_O_CREAT SH_O_TRUNC 420 )
                ? < # i fd 0 {
                    ( bx_err_at ( string_data path ) `cannot open` )
                    ( string_free path )
                    ^ out
                } {}
                ( flush )
                : i saved ( __sh_save_fd 1 )
                : i32 _d ( dup2 fd # i32 1 )
                : i32 _c ( close fd )
                : i rc ( __sh_run_string script )
                ( flush )
                ? >= saved 0 {
                    : i32 _d2 ( dup2 # i32 saved # i32 1 )
                    : i32 _c2 ( close # i32 saved )
                } {}
                : *ShState st0 ( __st )
                = . st0 status rc
                ?? ( read_file ( string_data path ) ) {
                    T text → {
                        ( string_push_bytes out # *u ( string_data text ) ( string_len text ) )
                        ( string_free text )
                    }
                    F _ → {}
                }
                ?? ( file_delete ( string_data path ) ) { T _ → {} F _ → {} }
                ( string_free path )
                : ~ i tn ( string_len out )
                ~ & > tn 0 == ( string_get out - tn 1 ) 10 { = tn - tn 1 }
                : String trimmed0 ( string_substr out 0 tn )
                ( string_free out )
                ^ trimmed0
            }
        }
    } {}
    : s fdbuf ( nurl_zalloc 16 )
    : i32 pr ( pipe # *u fdbuf )
    ? < # i pr 0 {
        ( nurl_free fdbuf )
        ^ out
    } {}
    : i rfd ( __le32_at fdbuf 0 )
    : i wfd ( __le32_at fdbuf 4 )
    ( nurl_free fdbuf )
    ( flush )
    : i32 pid ( fork )
    ? == # i pid 0 {
        : i32 _c ( close # i32 rfd )
        : i32 _d ( dup2 # i32 wfd # i32 1 )
        : i32 _e ( close # i32 wfd )
        : i rc ( __sh_run_string script )
        ( flush )
        ( _exit # i32 rc )
    } {}
    : i32 _c2 ( close # i32 wfd )
    : s buf ( nurl_alloc 4096 )
    : ~ b more T
    ~ more {
        : i got ( read # i32 rfd # *u buf 4096 )
        ? <= got 0 { = more F } { ( string_push_bytes out # *u buf got ) }
    }
    ( nurl_free buf )
    : i32 _c3 ( close # i32 rfd )
    : s statusbuf ( nurl_zalloc 8 )
    : i32 _w ( waitpid pid # *u statusbuf # i32 0 )
    : *ShState st ( __st )
    = . st status ( nurl_wait_exit_status & ( nurl_peek statusbuf 0 ) 65535 )
    ( nurl_free statusbuf )
    : ~ i n ( string_len out )
    ~ & > n 0 == ( string_get out - n 1 ) 10 { = n - n 1 }
    : String trimmed ( string_substr out 0 n )
    ( string_free out )
    ^ trimmed
}

// ── The applet ────────────────────────────────────────────────────

@ __sh_interactive → i {
    : *ShState st ( __st )
    : ~ String line ( string_new )
    ~ == 0 . st exiting {
        ( nurl_print `$ ` )
        ( flush )
        ( string_free line )
        = line ( read_line )
        ? & == ( string_len line ) 0 ( stdin_eof ) { = . st exiting 1 } {
            ? > ( string_len line ) 0 {
                : i _r ( __sh_run_string ( string_data line ) )
            } {}
        }
    }
    ( string_free line )
    ^ . st exit_code
}

@ ap_sh ( Vec String ) argv → i {
    ( __sh_state_new )
    : *ShState st ( __st )
    : i n ( vec_len [String] argv )
    : ~ i rc 0
    : ~ i i 1
    : ~ b did_something F
    : ~ b interactive F
    ~ & ! did_something < i n {
        : s a ( bx_at argv i )
        ? ( bx_streq a `-c` ) {
            ? < + i 1 n {
                ( string_clear . st argv0 )
                ( string_push_str . st argv0 `sh` )
                : ~ i k + i 2
                ~ < k n {
                    ( vec_push [String] . st params ( string_from ( bx_at argv k ) ) )
                    = k + k 1
                }
                = rc ( __sh_run_string ( bx_at argv + i 1 ) )
                = did_something T
            } {
                ( bx_err `-c needs a command` )
                = rc 2
                = did_something T
            }
        } {
            ? | ( bx_streq a `-s` ) ( bx_streq a `-i` ) { = i + i 1 } {
                ? & > ( nurl_str_len a ) 0 == 45 ( nurl_str_get a 0 ) { = i + i 1 } {
                    // A file operand: run it, with the rest as $1…
                    ?? ( read_file a ) {
                        T text → {
                            ( string_clear . st argv0 )
                            ( string_push_str . st argv0 a )
                            : ~ i k + i 1
                            ~ < k n {
                                ( vec_push [String] . st params ( string_from ( bx_at argv k ) ) )
                                = k + k 1
                            }
                            = rc ( __sh_run_string ( string_data text ) )
                            ( string_free text )
                        }
                        F e → {
                            ( bx_err_at a ( bx_ioerr e ) )
                            = rc 127
                        }
                    }
                    = did_something T
                }
            }
        }
    }
    ? ! did_something {
        // No script: read commands from stdin, prompting when it is a
        // terminal.
        = interactive T
        = rc ( __sh_interactive )
    } {}
    ? != 0 . st exiting { = rc . st exit_code } {}
    ( __sh_state_free )
    ^ rc
}
