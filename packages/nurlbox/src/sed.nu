// nurlbox/sed.nu — the stream editor.
//
// Addresses (`N`, `$`, `/re/`, ranges, `!`), the substitute command with
// its `g` / `p` / `i` / Nth-occurrence flags and `&` / `\1` back
// references, the hold space, transliteration, branches and labels, and
// `{ }` blocks.
//
// Back references are why `stdlib/ext/regex.nu` grew capture groups: a
// sed whose `s/\(a\)\(b\)/\2\1/` silently produced nothing would be a
// sed nobody could use, and the honest place to fix that was the engine,
// not this file.
//
// Regular expressions follow POSIX: `sed` is BASIC (so `\(` groups and a
// bare `+` is a literal plus), `sed -E` is EXTENDED. The translation is
// grep.nu's `_bre_to_ere`, shared rather than written twice.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bufio.nu`
$ `stdlib/ext/regex.nu`
$ `bx.nu`
$ `grep.nu`

: i SED_ADDR_NONE 0
: i SED_ADDR_LINE 1
: i SED_ADDR_LAST 2
: i SED_ADDR_RE 3

: SedCmd {
    i a1kind
    i a1line
    Regex a1re
    i a2kind
    i a2line
    Regex a2re
    b negate
    i cmd  // the command letter's byte
    Regex re  // s/// pattern
    b has_re
    String arg1  // s replacement / y source / a,i,c text / label / filename
    String arg2  // y destination
    i sflags  // 1 = g, 2 = p, 4 = i
    i soccur  // Nth occurrence (0 = first)
    i jump  // `{` → index just past the matching `}`
}

: i SED_S_GLOBAL 1
: i SED_S_PRINT 2
: i SED_S_ICASE 4

@ __sed_cmd_free SedCmd c → v {
    ? . c has_re { ( regex_free . c re ) } {}
    ? == . c a1kind SED_ADDR_RE { ( regex_free . c a1re ) } {}
    ? == . c a2kind SED_ADDR_RE { ( regex_free . c a2re ) } {}
    ( string_free . c arg1 )
    ( string_free . c arg2 )
}

// ── Script parsing ────────────────────────────────────────────────

: ~ i g_sed_pos 0
: ~ b g_sed_bad F
: ~ b g_sed_ere F

@ __sed_at s src i n → i { ^ ? < g_sed_pos n ( nurl_str_get src g_sed_pos ) 0 }

@ __sed_skip_ws s src i n → v {
    ~ & < g_sed_pos n | | == ( nurl_str_get src g_sed_pos ) 32 == ( nurl_str_get src g_sed_pos ) 9 == ( nurl_str_get src g_sed_pos ) 59 {
        = g_sed_pos + g_sed_pos 1
    }
}

// Read a delimited chunk starting just past the delimiter; `\<delim>`
// escapes it, and the delimiter itself ends the chunk.
@ __sed_chunk s src i n i delim String out → b {
    ( string_clear out )
    ~ < g_sed_pos n {
        : i c ( nurl_str_get src g_sed_pos )
        ? == c delim {
            = g_sed_pos + g_sed_pos 1
            ^ T
        } {}
        ? & == c 92 < + g_sed_pos 1 n {
            : i e ( nurl_str_get src + g_sed_pos 1 )
            ? == e delim {
                ( string_push_char out delim )
            } {
                ( string_push_char out 92 )
                ( string_push_char out e )
            }
            = g_sed_pos + g_sed_pos 2
        } {
            ( string_push_char out c )
            = g_sed_pos + g_sed_pos 1
        }
    }
    ^ F
}

@ __sed_compile_re String pat b icase → Regex {
    : String work ? icase ( _grep_lower ( string_data pat ) ) ( string_clone pat )
    : String ere ? g_sed_ere ( string_clone work ) ( _bre_to_ere ( string_data work ) )
    : ~ Regex out @ Regex { # s 0 }
    ?? ( regex_compile ( string_data ere ) ) {
        T r → { = out r }
        F _ → { = g_sed_bad T }
    }
    ( string_free ere )
    ( string_free work )
    ^ out
}

// One address, if there is one at the cursor.
@ __sed_addr s src i n inout i kind inout i line inout Regex re → v {
    = kind SED_ADDR_NONE
    = line 0
    : i c ( __sed_at src n )
    ? == c 36 {
        = kind SED_ADDR_LAST
        = g_sed_pos + g_sed_pos 1
        ^
    } {}
    ? ( bx_is_digit c ) {
        : ~ i v 0
        ~ & < g_sed_pos n ( bx_is_digit ( nurl_str_get src g_sed_pos ) ) {
            = v + * v 10 - ( nurl_str_get src g_sed_pos ) 48
            = g_sed_pos + g_sed_pos 1
        }
        = kind SED_ADDR_LINE
        = line v
        ^
    } {}
    ? == c 47 {
        = g_sed_pos + g_sed_pos 1
        : String pat ( string_new )
        ? ! ( __sed_chunk src n 47 pat ) { = g_sed_bad T } {}
        // A trailing `I` asks for a case-insensitive address.
        : ~ b icase F
        ? & < g_sed_pos n == ( nurl_str_get src g_sed_pos ) 73 {
            = icase T
            = g_sed_pos + g_sed_pos 1
        } {}
        = re ( __sed_compile_re pat icase )
        = kind SED_ADDR_RE
        ( string_free pat )
        ^
    } {}
}

// Text for `a` / `i` / `c`: either `a\` + newline + text, or the GNU
// one-liner `a text`.
@ __sed_text s src i n String out → v {
    ( string_clear out )
    ? & < g_sed_pos n == ( nurl_str_get src g_sed_pos ) 92 { = g_sed_pos + g_sed_pos 1 } {}
    ? & < g_sed_pos n == ( nurl_str_get src g_sed_pos ) 10 { = g_sed_pos + g_sed_pos 1 } {}
    ~ & < g_sed_pos n | == ( nurl_str_get src g_sed_pos ) 32 == ( nurl_str_get src g_sed_pos ) 9 {
        = g_sed_pos + g_sed_pos 1
    }
    ~ < g_sed_pos n {
        : i c ( nurl_str_get src g_sed_pos )
        ? == c 10 {
            = g_sed_pos + g_sed_pos 1
            ^
        } {}
        ? & == c 92 < + g_sed_pos 1 n {
            ( string_push_char out ( nurl_str_get src + g_sed_pos 1 ) )
            = g_sed_pos + g_sed_pos 2
        } {
            ( string_push_char out c )
            = g_sed_pos + g_sed_pos 1
        }
    }
}

@ __sed_word s src i n String out → v {
    ( string_clear out )
    ~ & < g_sed_pos n | == ( nurl_str_get src g_sed_pos ) 32 == ( nurl_str_get src g_sed_pos ) 9 {
        = g_sed_pos + g_sed_pos 1
    }
    ~ < g_sed_pos n {
        : i c ( nurl_str_get src g_sed_pos )
        ? | | | == c 10 == c 59 == c 32 == c 125 { ^ } {}
        ( string_push_char out c )
        = g_sed_pos + g_sed_pos 1
    }
}

@ __sed_parse s src ( Vec SedCmd ) out → v {
    : i n ( nurl_str_len src )
    = g_sed_pos 0
    ~ < g_sed_pos n {
        ( __sed_skip_ws src n )
        ~ & < g_sed_pos n == ( nurl_str_get src g_sed_pos ) 10 { = g_sed_pos + g_sed_pos 1 ( __sed_skip_ws src n ) }
        ? >= g_sed_pos n { ^ } {}
        // A comment runs to end of line.
        ? == ( nurl_str_get src g_sed_pos ) 35 {
            ~ & < g_sed_pos n != ( nurl_str_get src g_sed_pos ) 10 { = g_sed_pos + g_sed_pos 1 }
        } {
            : ~ i a1kind 0
            : ~ i a1line 0
            : ~ Regex a1re @ Regex { # s 0 }
            : ~ i a2kind 0
            : ~ i a2line 0
            : ~ Regex a2re @ Regex { # s 0 }
            ( __sed_addr src n a1kind a1line a1re )
            ? & != a1kind SED_ADDR_NONE == ( __sed_at src n ) 44 {
                = g_sed_pos + g_sed_pos 1
                ( __sed_addr src n a2kind a2line a2re )
            } {}
            : ~ b negate F
            ~ & < g_sed_pos n == ( nurl_str_get src g_sed_pos ) 33 {
                = negate ! negate
                = g_sed_pos + g_sed_pos 1
            }
            ( __sed_skip_ws src n )
            ? >= g_sed_pos n { ^ } {}
            : i cmd ( nurl_str_get src g_sed_pos )
            = g_sed_pos + g_sed_pos 1
            : String arg1 ( string_new )
            : String arg2 ( string_new )
            : ~ Regex re @ Regex { # s 0 }
            : ~ b has_re F
            : ~ i sflags 0
            : ~ i soccur 0
            ? == cmd 115 {  // s
                : i delim ( __sed_at src n )
                = g_sed_pos + g_sed_pos 1
                : String pat ( string_new )
                ? ! ( __sed_chunk src n delim pat ) { = g_sed_bad T } {}
                ? ! ( __sed_chunk src n delim arg1 ) { = g_sed_bad T } {}
                // Flags run until the command separator.
                : ~ b more T
                ~ & more < g_sed_pos n {
                    : i f ( nurl_str_get src g_sed_pos )
                    ? == f 103 { = sflags | sflags SED_S_GLOBAL = g_sed_pos + g_sed_pos 1 } {
                        ? == f 112 { = sflags | sflags SED_S_PRINT = g_sed_pos + g_sed_pos 1 } {
                            ? | == f 105 == f 73 { = sflags | sflags SED_S_ICASE = g_sed_pos + g_sed_pos 1 } {
                                ? ( bx_is_digit f ) {
                                    : ~ i v 0
                                    ~ & < g_sed_pos n ( bx_is_digit ( nurl_str_get src g_sed_pos ) ) {
                                        = v + * v 10 - ( nurl_str_get src g_sed_pos ) 48
                                        = g_sed_pos + g_sed_pos 1
                                    }
                                    = soccur ? > v 0 - v 1 0
                                } { = more F } } } }
                }
                = re ( __sed_compile_re pat != 0 & sflags SED_S_ICASE )
                = has_re T
                ( string_free pat )
            } {
                ? == cmd 121 {  // y
                    : i delim ( __sed_at src n )
                    = g_sed_pos + g_sed_pos 1
                    ? ! ( __sed_chunk src n delim arg1 ) { = g_sed_bad T } {}
                    ? ! ( __sed_chunk src n delim arg2 ) { = g_sed_bad T } {}
                } {
                    ? | | == cmd 97 == cmd 105 == cmd 99 {  // a i c
                        ( __sed_text src n arg1 )
                    } {
                        ? | | | | == cmd 98 == cmd 116 == cmd 58 == cmd 114 == cmd 119 {  // b t : r w
                            ( __sed_word src n arg1 )
                        } {}
                    }
                }
            }
            ( vec_push [SedCmd] out @ SedCmd {
                a1kind a1line a1re a2kind a2line a2re negate cmd re has_re arg1 arg2 sflags soccur -1
            } )
        }
    }
}

// Resolve every `{` to the index just past its `}`.
@ __sed_link ( Vec SedCmd ) cmds → v {
    : i n ( vec_len [SedCmd] cmds )
    : ( Vec i ) stack ( vec_new [i] )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [SedCmd] cmds i ) {
            T c → {
                ? == . c cmd 123 { ( vec_push [i] stack i ) } {}
                ? == . c cmd 125 {
                    ?? ( vec_pop [i] stack ) {
                        T open → {
                            ?? ( vec_get [SedCmd] cmds open ) {
                                T oc → {
                                    : b _ok ( vec_set [SedCmd] cmds open @ SedCmd {
                                        . oc a1kind . oc a1line . oc a1re . oc a2kind . oc a2line . oc a2re
                                        . oc negate . oc cmd . oc re . oc has_re . oc arg1 . oc arg2
                                        . oc sflags . oc soccur + i 1
                                    } )
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [i] stack )
}

// ── Execution ─────────────────────────────────────────────────────

@ __sed_re_hit Regex r b icase String line → b {
    ? icase {
        : String lo ( _grep_lower ( string_data line ) )
        : b h ( regex_test r ( string_data lo ) )
        ( string_free lo )
        ^ h
    } {}
    ^ ( regex_test r ( string_data line ) )
}

// Does this command apply to the current line? `ranges` carries each
// command's open/closed range state across lines.
@ __sed_selects SedCmd c ( Vec i ) ranges i idx i lineno b is_last String line → b {
    : ~ b hit F
    ? == . c a1kind SED_ADDR_NONE {
        = hit T
    } {
        : ~ i state 0
        ?? ( vec_get [i] ranges idx ) { T x → { = state x } F _ → {} }
        ? == . c a2kind SED_ADDR_NONE {
            ? == . c a1kind SED_ADDR_LINE { = hit == lineno . c a1line } {}
            ? == . c a1kind SED_ADDR_LAST { = hit is_last } {}
            ? == . c a1kind SED_ADDR_RE { = hit ( __sed_re_hit . c a1re F line ) } {}
        } {
            ? == state 0 {
                : ~ b starts F
                ? == . c a1kind SED_ADDR_LINE { = starts == lineno . c a1line } {}
                ? == . c a1kind SED_ADDR_LAST { = starts is_last } {}
                ? == . c a1kind SED_ADDR_RE { = starts ( __sed_re_hit . c a1re F line ) } {}
                ? starts {
                    = hit T
                    // A numeric end address already passed means the
                    // range covers exactly this one line.
                    : ~ b closes F
                    ? == . c a2kind SED_ADDR_LINE { = closes <= . c a2line lineno } {}
                    : b _s ( vec_set [i] ranges idx ? closes 0 1 )
                } {}
            } {
                = hit T
                : ~ b ends F
                ? == . c a2kind SED_ADDR_LINE { = ends >= lineno . c a2line } {}
                ? == . c a2kind SED_ADDR_LAST { = ends is_last } {}
                ? == . c a2kind SED_ADDR_RE { = ends ( __sed_re_hit . c a2re F line ) } {}
                ? ends { : b _s ( vec_set [i] ranges idx 0 ) } {}
            }
        }
    }
    ^ ? . c negate ! hit hit
}

// s/// over the pattern space. Returns T when anything changed.
@ __sed_subst SedCmd c String space → b {
    : b global != 0 & . c sflags SED_S_GLOBAL
    : b icase != 0 & . c sflags SED_S_ICASE
    : String probe ? icase ( _grep_lower ( string_data space ) ) ( string_clone space )
    : String out ( string_new )
    : ( Vec i ) slots ( vec_new [i] )
    : i n ( string_len space )
    : ~ i pos 0
    : ~ i seen 0
    : ~ b changed F
    : ~ b more T
    ~ & more <= pos n {
        : s tail ( nurl_str_slice ( string_data probe ) pos - n pos )
        ?? ( regex_find_caps . c re tail slots ) {
            T m → {
                : i abs + pos . m start
                : i len . m len
                // Copy the untouched run before the match.
                : ~ i k pos
                ~ < k abs {
                    ( string_push_char out ( string_get space k ) )
                    = k + k 1
                }
                : b use | global >= seen . c soccur
                ? & use | global == seen . c soccur {
                    // The slots are relative to `tail`; shift them onto
                    // the pattern space before expanding.
                    : i ns ( vec_len [i] slots )
                    : ~ i j 0
                    ~ < j ns {
                        ?? ( vec_get [i] slots j ) {
                            T v → { ? >= v 0 { : b _q ( vec_set [i] slots j + v pos ) } {} }
                            F _ → {}
                        }
                        = j + j 1
                    }
                    : String rep ( regex_expand ( string_data space ) slots ( string_data . c arg1 ) )
                    ( string_push_bytes out # *u ( string_data rep ) ( string_len rep ) )
                    ( string_free rep )
                    = changed T
                } {
                    : ~ i k2 abs
                    ~ < k2 + abs len {
                        ( string_push_char out ( string_get space k2 ) )
                        = k2 + k2 1
                    }
                }
                = seen + seen 1
                ? == len 0 {
                    ? < + abs 0 n { ( string_push_char out ( string_get space abs ) ) } {}
                    = pos + abs 1
                } { = pos + abs len }
                ? & changed ! global { = more F } {}
            }
            F _ → { = more F }
        }
    }
    : ~ i k3 pos
    ~ < k3 n {
        ( string_push_char out ( string_get space k3 ) )
        = k3 + k3 1
    }
    ? changed {
        ( string_clear space )
        ( string_push_bytes space # *u ( string_data out ) ( string_len out ) )
    } {}
    ( vec_free [i] slots )
    ( string_free out )
    ( string_free probe )
    ^ changed
}

@ __sed_translit SedCmd c String space → v {
    : s from ( string_data . c arg1 )
    : s to ( string_data . c arg2 )
    : i fn ( nurl_str_len from )
    : i tn ( nurl_str_len to )
    : i n ( string_len space )
    : String out ( string_new )
    : ~ i i 0
    ~ < i n {
        : i ch ( string_get space i )
        : ~ i outc ch
        : ~ i j 0
        ~ < j fn {
            ? == ( nurl_str_get from j ) ch {
                = outc ? < j tn ( nurl_str_get to j ) ch
                = j fn
            } { = j + j 1 }
        }
        ( string_push_char out outc )
        = i + i 1
    }
    ( string_clear space )
    ( string_push_bytes space # *u ( string_data out ) ( string_len out ) )
    ( string_free out )
}

// A file whose last line has no newline must not grow one — `sed` is a
// filter, and a filter that silently appends a byte breaks every
// checksum downstream of it. The missing terminator is therefore
// remembered rather than invented: if anything else is printed after
// such a line, the newline that separates them is emitted then.
: ~ b g_sed_nonl F

@ __sed_out_prep String out → v {
    ? g_sed_nonl {
        ( string_push_char out 10 )
        = g_sed_nonl F
    } {}
}

@ __sed_emit String out String line b had_nl → v {
    ( __sed_out_prep out )
    ( string_push_bytes out # *u ( string_data line ) ( string_len line ) )
    ? had_nl { ( string_push_char out 10 ) } { = g_sed_nonl T }
}

// Read one line, keeping whether it carried a terminator.
@ __sed_read BufReader br String raw String dst inout b had_nl → b {
    ? ! ( bufreader_read_line_raw br raw ) {
        = had_nl F
        ^ F
    } {}
    : i n ( string_len raw )
    : ~ i body n
    = had_nl F
    // Only '\n' is a terminator: a '\r' is DATA, and every sed keeps it
    // in the pattern space so `s/\r$//` has something to remove.
    ? & > body 0 == ( string_get raw - body 1 ) 10 {
        = body - body 1
        = had_nl T
    } {}
    ( string_clear dst )
    ( string_push_bytes dst # *u ( string_data raw ) body )
    ^ T
}

// Find the index of a label, or -1.
@ __sed_label ( Vec SedCmd ) cmds String name → i {
    : i n ( vec_len [SedCmd] cmds )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [SedCmd] cmds i ) {
            T c → {
                ? & == . c cmd 58 ( string_eq . c arg1 name ) { ^ i } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ -1
}

: ~ b g_sed_quit F
: ~ i g_sed_rc 0

@ __sed_stream ( Vec SedCmd ) cmds ( Vec i ) ranges s path b quiet String out → i {
    ?? ( bx_reader path ) {
        F _ → { ^ 1 }
        T br → {
            : String space ( string_new )
            : String ahead ( string_new )
            : String raw ( string_new )
            : ~ b space_nl T
            : ~ b ahead_nl T
            : String hold ( string_new )
            : String append ( string_new )
            : ~ b have_space F
            : ~ b have_ahead F
            : ~ i lineno 0
            : i ncmds ( vec_len [SedCmd] cmds )
            = g_sed_nonl F
            = have_space ( __sed_read br raw space space_nl )
            = have_ahead ( __sed_read br raw ahead ahead_nl )
            ~ & have_space ! g_sed_quit {
                = lineno + lineno 1
                : ~ b is_last ! have_ahead
                : ~ b deleted F
                : ~ b tflag F
                : ~ b restart T
                ~ restart {
                    = restart F
                    : ~ i pc 0
                    ~ & < pc ncmds ! deleted {
                        : ~ i next + pc 1
                        ?? ( vec_get [SedCmd] cmds pc ) {
                            T c → {
                                : b sel ( __sed_selects c ranges pc lineno is_last space )
                                : i k . c cmd
                                // A flat chain of guarded statements, not
                                // a nested ternary: the dispatch is two
                                // dozen arms deep and one mis-nested
                                // brace in a prefix-ternary tower is a
                                // bug you find by counting.
                                ? & == k 123 ! sel { = next . c jump } {}
                                ? & sel == k 115 {
                                    ? ( __sed_subst c space ) {
                                        = tflag T
                                        ? != 0 & . c sflags SED_S_PRINT { ( __sed_emit out space space_nl ) } {}
                                    } {}
                                } {}
                                ? & sel == k 112 { ( __sed_emit out space space_nl ) } {}
                                ? & sel == k 80 {
                                    : i pn ( string_len space )
                                    : ~ i e 0
                                    ~ & < e pn != ( string_get space e ) 10 { = e + e 1 }
                                    ( __sed_out_prep out )
                                    ( string_push_bytes out # *u ( string_data space ) e )
                                    ( string_push_char out 10 )
                                } {}
                                ? & sel == k 100 { = deleted T } {}
                                ? & sel == k 68 {
                                    : i pn ( string_len space )
                                    : ~ i e 0
                                    ~ & < e pn != ( string_get space e ) 10 { = e + e 1 }
                                    ? >= e pn { = deleted T } {
                                        : String rest ( string_substr space + e 1 - pn + e 1 )
                                        ( string_clear space )
                                        ( string_push_bytes space # *u ( string_data rest ) ( string_len rest ) )
                                        ( string_free rest )
                                        = restart T
                                        = next ncmds
                                    }
                                } {}
                                ? & sel == k 113 {
                                    ? ! quiet { ( __sed_emit out space space_nl ) } {}
                                    = g_sed_quit T
                                    = deleted T
                                } {}
                                ? & sel == k 110 {
                                    ? ! quiet { ( __sed_emit out space space_nl ) } {}
                                    ? have_ahead {
                                        ( string_clear space )
                                        ( string_push_bytes space # *u ( string_data ahead ) ( string_len ahead ) )
                                        = space_nl ahead_nl
                                        = lineno + lineno 1
                                        = have_ahead ( __sed_read br raw ahead ahead_nl )
                                        = is_last ! have_ahead
                                    } {
                                        = deleted T
                                        = have_space F
                                    }
                                } {}
                                ? & sel == k 78 {
                                    ? have_ahead {
                                        ( string_push_char space 10 )
                                        ( string_push_bytes space # *u ( string_data ahead ) ( string_len ahead ) )
                                        = space_nl ahead_nl
                                        = lineno + lineno 1
                                        = have_ahead ( __sed_read br raw ahead ahead_nl )
                                        = is_last ! have_ahead
                                    } { = next ncmds }
                                } {}
                                ? & sel == k 61 {
                                    ( __sed_out_prep out )
                                    ( string_push_int out lineno )
                                    ( string_push_char out 10 )
                                } {}
                                ? & sel == k 97 {
                                    ( string_push_bytes append # *u ( string_data . c arg1 ) ( string_len . c arg1 ) )
                                    ( string_push_char append 10 )
                                } {}
                                ? & sel == k 105 {
                                    ( __sed_out_prep out )
                                    ( string_push_bytes out # *u ( string_data . c arg1 ) ( string_len . c arg1 ) )
                                    ( string_push_char out 10 )
                                } {}
                                ? & sel == k 99 {
                                    ( __sed_out_prep out )
                                    ( string_push_bytes out # *u ( string_data . c arg1 ) ( string_len . c arg1 ) )
                                    ( string_push_char out 10 )
                                    = deleted T
                                } {}
                                ? & sel == k 121 { ( __sed_translit c space ) } {}
                                ? & sel == k 104 {
                                    ( string_clear hold )
                                    ( string_push_bytes hold # *u ( string_data space ) ( string_len space ) )
                                } {}
                                ? & sel == k 72 {
                                    ( string_push_char hold 10 )
                                    ( string_push_bytes hold # *u ( string_data space ) ( string_len space ) )
                                } {}
                                ? & sel == k 103 {
                                    ( string_clear space )
                                    ( string_push_bytes space # *u ( string_data hold ) ( string_len hold ) )
                                } {}
                                ? & sel == k 71 {
                                    ( string_push_char space 10 )
                                    ( string_push_bytes space # *u ( string_data hold ) ( string_len hold ) )
                                } {}
                                ? & sel == k 120 {
                                    : String tmp ( string_clone space )
                                    ( string_clear space )
                                    ( string_push_bytes space # *u ( string_data hold ) ( string_len hold ) )
                                    ( string_clear hold )
                                    ( string_push_bytes hold # *u ( string_data tmp ) ( string_len tmp ) )
                                    ( string_free tmp )
                                } {}
                                ? & sel == k 98 {
                                    ? == ( string_len . c arg1 ) 0 { = next ncmds } {
                                        : i t ( __sed_label cmds . c arg1 )
                                        = next ? >= t 0 t ncmds
                                    }
                                } {}
                                ? & sel == k 116 {
                                    ? tflag {
                                        = tflag F
                                        ? == ( string_len . c arg1 ) 0 { = next ncmds } {
                                            : i t ( __sed_label cmds . c arg1 )
                                            = next ? >= t 0 t ncmds
                                        }
                                    } {}
                                } {}
                                ? & sel == k 114 {
                                    ?? ( read_file ( string_data . c arg1 ) ) {
                                        T txt → {
                                            ( string_push_bytes append # *u ( string_data txt ) ( string_len txt ) )
                                            ( string_free txt )
                                        }
                                        F _ → {}
                                    }
                                } {}
                                ? & sel == k 119 {
                                    ?? ( file_append ( string_data . c arg1 ) ) {
                                        T f → {
                                            : ( Vec u ) bytes ( vec_new [u] )
                                            : i sn ( string_len space )
                                            : ~ i q 0
                                            ~ < q sn { ( vec_push [u] bytes # u ( string_get space q ) ) = q + q 1 }
                                            ( vec_push [u] bytes # u 10 )
                                            ?? ( file_write_chunk f bytes ) { T _ → {} F _ → {} }
                                            ( vec_free [u] bytes )
                                            ( file_close f )
                                        }
                                        F _ → {}
                                    }
                                } {}
                            }
                            F _ → {}
                        }
                        = pc next
                    }
                }
                ? & ! deleted ! quiet { ( __sed_emit out space space_nl ) } {}
                ? > ( string_len append ) 0 {
                    ( __sed_out_prep out )
                    ( string_push_bytes out # *u ( string_data append ) ( string_len append ) )
                    ( string_clear append )
                } {}
                ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
                ? & have_space ! g_sed_quit {
                    ? have_ahead {
                        ( string_clear space )
                        ( string_push_bytes space # *u ( string_data ahead ) ( string_len ahead ) )
                        = space_nl ahead_nl
                        = have_ahead ( __sed_read br raw ahead ahead_nl )
                    } { = have_space F }
                } {}
            }
            ( string_free space )
            ( string_free ahead )
            ( string_free raw )
            ( string_free hold )
            ( string_free append )
            ( bufreader_close br )
            ^ 0
        }
    }
}

@ ap_sed ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `ne:f:iErs` `quiet=n,silent=n,expression=e,file=f,in-place=i,regexp-extended=E,separate=s` )
    : ~ i rc 0
    = g_sed_quit F
    = g_sed_rc 0
    = g_sed_bad F
    = g_sed_ere | ( bx_has o `E` ) ( bx_has o `r` )
    ? ! ( bx_ok o ) { = rc 1 } {
        : String script ( string_new )
        : ( Vec String ) exprs ( vec_new [String] )
        ? ( bx_has o `e` ) { ( bx_vals o `e` exprs ) } {}
        ? ( bx_has o `f` ) {
            ?? ( read_file ( bx_val o `f` ) ) {
                T txt → {
                    ( vec_push [String] exprs txt )
                }
                F e → {
                    ( bx_err_at ( bx_val o `f` ) ( bx_ioerr e ) )
                    = rc 1
                }
            }
        } {}
        : i nops ( bx_operand_count o )
        : ~ i first_file 0
        ? == ( vec_len [String] exprs ) 0 {
            ? > nops 0 {
                ( vec_push [String] exprs ( string_from ( bx_operand o 0 ) ) )
                = first_file 1
            } {
                ( bx_err `no script` )
                = rc 1
            }
        } {}
        : i ne ( vec_len [String] exprs )
        : ~ i k 0
        ~ < k ne {
            ? > k 0 { ( string_push_char script 10 ) } {}
            ( string_push_str script ( bx_at exprs k ) )
            = k + k 1
        }
        ( bx_free_lines exprs )
        ? == rc 0 {
            : ( Vec SedCmd ) cmds ( vec_new [SedCmd] )
            ( __sed_parse ( string_data script ) cmds )
            ( __sed_link cmds )
            ? g_sed_bad {
                ( bx_err `invalid script` )
                = rc 1
            } {
                : ( Vec i ) ranges ( vec_new [i] )
                : ~ i q 0
                ~ < q ( vec_len [SedCmd] cmds ) { ( vec_push [i] ranges 0 ) = q + q 1 }
                : b quiet ( bx_has o `n` )
                : i nfiles - nops first_file
                : String out ( string_new )
                ? == nfiles 0 {
                    : i one ( __sed_stream cmds ranges `-` quiet out )
                    ? != one 0 { = rc 1 } {}
                    ( bx_write out )
                } {
                    : ~ i i first_file
                    ~ & < i nops ! g_sed_quit {
                        : s p ( bx_operand o i )
                        ( string_clear out )
                        : i one ( __sed_stream cmds ranges p quiet out )
                        ? != one 0 { = rc 1 } {}
                        ? ( bx_has o `i` ) {
                            // -i replaces the file with what the script
                            // produced. The write is a whole-file
                            // replacement, so a script that fails part
                            // way leaves the original untouched.
                            ?? ( write_file p ( string_data out ) ) {
                                T _ → {}
                                F e → {
                                    ( bx_err_at p ( bx_ioerr e ) )
                                    = rc 1
                                }
                            }
                        } { ( bx_write out ) }
                        = i + i 1
                    }
                }
                ( string_free out )
                ( vec_free [i] ranges )
            }
            ( vec_free_with [SedCmd] cmds \ SedCmd c → v { ( __sed_cmd_free c ) } )
        } {}
        ( string_free script )
    }
    ( bx_opts_free o )
    ^ ? != g_sed_rc 0 g_sed_rc rc
}
