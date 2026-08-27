// nurlbox/grep.nu — grep / egrep / fgrep.
//
// Three matchers behind one applet, because that is what the three
// names mean:
//
//   grep    POSIX BASIC regular expressions   (`\(`, `\|`, `\+`)
//   grep -E POSIX EXTENDED regular expressions (`(`, `|`, `+`)  = egrep
//   grep -F fixed strings, no metacharacters at all             = fgrep
//
// The engine is the stdlib's `ext/regex`, which speaks ERE. Basic
// regular expressions are therefore TRANSLATED to extended ones rather
// than approximated: in a BRE, `(` `)` `|` `+` `?` `{` `}` are literal
// characters and their backslashed forms are the operators, which is
// exactly the swap `_bre_to_ere` performs. A grep that quietly treated
// `a+` as "one or more a" would silently mis-answer every script that
// meant a literal plus.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bufio.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/ext/regex.nu`
$ `bx.nu`

: i GREP_INVERT 1
: i GREP_IGNORE 2
: i GREP_COUNT 4
: i GREP_LINENO 8
: i GREP_FILES 16
: i GREP_NOFILES 32
: i GREP_QUIET 64
: i GREP_WORD 128
: i GREP_LINE 256
: i GREP_ONLY 512
: i GREP_FIXED 1024
: i GREP_WITHNAME 2048
: i GREP_NOMATCH_FILES 4096
: i GREP_RECURSE 8192
: i GREP_SILENT 16384

// BRE → ERE. `\(` becomes `(` and a bare `(` becomes `\(`; same for
// `)`, `|`, `+`, `?`, `{`, `}`. Inside a bracket expression nothing is
// special, so the scan tracks that.
@ _bre_to_ere s pat → String {
    : String out ( string_new )
    : i n ( nurl_str_len pat )
    : ~ i i 0
    : ~ b in_class F
    ~ < i n {
        : i c ( nurl_str_get pat i )
        ? in_class {
            ( string_push_char out c )
            ? == c 93 { = in_class F } {}
            = i + i 1
        } {
            ? == c 91 {
                ( string_push_char out c )
                = in_class T
                = i + i 1
                // A `]` immediately after `[` or `[^` is a literal.
                ? & < i n == ( nurl_str_get pat i ) 94 {
                    ( string_push_char out 94 )
                    = i + i 1
                } {}
                ? & < i n == ( nurl_str_get pat i ) 93 {
                    ( string_push_char out 93 )
                    = i + i 1
                } {}
            } {
                ? & == c 92 < + i 1 n {
                    : i e ( nurl_str_get pat + i 1 )
                    ? | | | | | == e 40 == e 41 == e 124 == e 43 == e 63 | == e 123 == e 125 {
                        // The operator forms lose their backslash.
                        ( string_push_char out e )
                    } {
                        ( string_push_char out 92 )
                        ( string_push_char out e )
                    }
                    = i + i 2
                } {
                    ? | | | | | == c 40 == c 41 == c 124 == c 43 == c 63 | == c 123 == c 125 {
                        // …and the bare forms gain one: in a BRE they
                        // are ordinary characters.
                        ( string_push_char out 92 )
                        ( string_push_char out c )
                    } { ( string_push_char out c ) }
                    = i + i 1
                }
            }
        }
    }
    ^ out
}

@ __grep_is_word i c → b {
    ^ | | & >= c 97 <= c 122 & >= c 65 <= c 90 | & >= c 48 <= c 57 == c 95
}

// One pattern, compiled or literal.
: GrepPat {
    Regex rx
    String lit
    b fixed
}

@ __grep_pat_free GrepPat p → v {
    ? . p fixed { ( string_free . p lit ) } { ( regex_free . p rx ) ( string_free . p lit ) }
}

// Case folding is done by lowering both the pattern and the line — the
// engine has no case-insensitive mode, and lowering the input is what
// every grep without one does.
@ _grep_lower s text → String {
    : String out ( string_new )
    : i n ( nurl_str_len text )
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get text i )
        ( string_push_char out ? & >= c 65 <= c 90 + c 32 c )
        = i + i 1
    }
    ^ out
}

// Does `line` contain a match of pattern `p`? `start`/`len` receive the
// leftmost match when there is one.
@ __grep_find GrepPat p s line i flags inout i mstart inout i mlen → b {
    = mstart -1
    = mlen 0
    ? . p fixed {
        : i at ( nurl_str_find line ( string_data . p lit ) )
        ? < at 0 { ^ F } {}
        = mstart at
        = mlen ( string_len . p lit )
        ^ T
    } {}
    ?? ( regex_find . p rx line ) {
        T m → {
            = mstart . m start
            = mlen . m len
            ^ T
        }
        F _ → { ^ F }
    }
}

// -w and -x turn a match into a match WITH BOUNDARIES; a plain find is
// not enough, because the leftmost match may fail the boundary test
// while a later one passes.
@ __grep_line_matches GrepPat p s line i flags inout i mstart inout i mlen → b {
    : i n ( nurl_str_len line )
    : ~ i from 0
    : ~ b found F
    ~ & ! found <= from n {
        : s tail ( nurl_str_slice line from - n from )
        : ~ i s0 -1
        : ~ i l0 0
        ? ( __grep_find p tail flags s0 l0 ) {
            : i abs_start + from s0
            : i abs_end + abs_start l0
            : ~ b ok T
            ? != 0 & flags GREP_LINE {
                = ok & == abs_start 0 == abs_end n
            } {}
            ? != 0 & flags GREP_WORD {
                ? > abs_start 0 {
                    ? ( __grep_is_word ( nurl_str_get line - abs_start 1 ) ) { = ok F } {}
                } {}
                ? < abs_end n {
                    ? ( __grep_is_word ( nurl_str_get line abs_end ) ) { = ok F } {}
                } {}
            } {}
            ? ok {
                = mstart abs_start
                = mlen l0
                = found T
            } {
                // Step past this match's first byte and look again.
                = from + abs_start ? > l0 0 1 1
            }
        } { = from + n 1 }
    }
    ^ found
}

@ __grep_emit String out s name s line i lineno i flags b with_name b only i mstart i mlen → v {
    ? with_name {
        ( string_push_str out name )
        ( string_push_char out 58 )
    } {}
    ? != 0 & flags GREP_LINENO {
        ( string_push_int out lineno )
        ( string_push_char out 58 )
    } {}
    ? only {
        : ~ i k 0
        ~ < k mlen {
            ( string_push_char out ( nurl_str_get line + mstart k ) )
            = k + k 1
        }
    } {
        ( string_push_str out line )
    }
    ( string_push_char out 10 )
}

// Returns 0 when the file had at least one selected line, 1 when it had
// none, 2 on an I/O error — grep's own exit-code alphabet.
@ __grep_file ( Vec GrepPat ) pats s path s label i flags b with_name i maxcount inout i total → i {
    ?? ( bx_reader path ) {
        F _ → { ^ 2 }
        T br → {
            : String line ( string_new )
            : String lower ( string_new )
            : String out ( string_new )
            : ~ i lineno 0
            : ~ i hits 0
            : ~ b more T
            : i np ( vec_len [GrepPat] pats )
            ~ more {
                ? ( bufreader_read_line_into br line ) {
                    = lineno + lineno 1
                    : ~ s probe ( string_data line )
                    ? != 0 & flags GREP_IGNORE {
                        ( string_clear lower )
                        : String lo ( _grep_lower ( string_data line ) )
                        ( string_push_bytes lower # *u ( string_data lo ) ( string_len lo ) )
                        ( string_free lo )
                        = probe ( string_data lower )
                    } {}
                    : ~ b hit F
                    : ~ i mstart -1
                    : ~ i mlen 0
                    : ~ i pi 0
                    ~ & ! hit < pi np {
                        ?? ( vec_get [GrepPat] pats pi ) {
                            T p → {
                                ? ( __grep_line_matches p probe flags mstart mlen ) { = hit T } {}
                            }
                            F _ → {}
                        }
                        = pi + pi 1
                    }
                    ? != 0 & flags GREP_INVERT { = hit ! hit } {}
                    ? hit {
                        = hits + hits 1
                        = total + total 1
                        ? == 0 & flags | | GREP_COUNT GREP_QUIET | GREP_FILES GREP_NOMATCH_FILES {
                            ( __grep_emit out label ( string_data line ) lineno flags with_name
                            & != 0 & flags GREP_ONLY == 0 & flags GREP_INVERT mstart mlen )
                            ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
                        } {}
                        ? & > maxcount 0 >= hits maxcount { = more F } {}
                        ? != 0 & flags GREP_QUIET { = more F } {}
                    } {}
                } { = more F }
            }
            ? != 0 & flags GREP_COUNT {
                ( string_clear out )
                ? with_name {
                    ( string_push_str out label )
                    ( string_push_char out 58 )
                } {}
                ( string_push_int out hits )
                ( string_push_char out 10 )
            } {}
            ? & != 0 & flags GREP_FILES > hits 0 {
                ( string_clear out )
                ( string_push_str out label )
                ( string_push_char out 10 )
            } {}
            ? & != 0 & flags GREP_NOMATCH_FILES == hits 0 {
                ( string_clear out )
                ( string_push_str out label )
                ( string_push_char out 10 )
            } {}
            ? == 0 & flags GREP_QUIET { ( bx_write out ) } {}
            ( string_free out )
            ( string_free line )
            ( string_free lower )
            ( bufreader_close br )
            ^ ? > hits 0 0 1
        }
    }
}

@ __grep_walk ( Vec GrepPat ) pats s path i flags b with_name i maxcount inout i total inout i rc → v {
    ?? ( fs_lstat path ) {
        F e → {
            ? == 0 & flags GREP_SILENT { ( bx_err_at path ( bx_ioerr e ) ) } {}
            = rc 2
        }
        T st → {
            ? ( stat_is_dir st ) {
                ?? ( dir_list path ) {
                    T names → {
                        ( sort_by [String] names \ String a String b → i { ^ ( cmp_string a b ) } )
                        : i n ( vec_len [String] names )
                        : ~ i k 0
                        ~ < k n {
                            : String sub ( path_join path ( bx_at names k ) )
                            ( __grep_walk pats ( string_data sub ) flags with_name maxcount total rc )
                            ( string_free sub )
                            = k + k 1
                        }
                        ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
                    }
                    F e2 → {
                        ? == 0 & flags GREP_SILENT { ( bx_err_at path ( bx_ioerr e2 ) ) } {}
                        = rc 2
                    }
                }
            } {
                ? ( stat_is_symlink st ) {} {
                    : i one ( __grep_file pats path path flags with_name maxcount total )
                    ? & == one 2 != rc 0 {} {}
                    ? == one 2 { = rc 2 } {}
                }
            }
        }
    }
}

@ ap_grep ( Vec String ) argv → i {
    // egrep / fgrep are grep with a matcher preselected.
    : s me ( bx_name )
    : BxOpts o ( bx_getopt argv 1 `EFivnce:lLqwxohHrRsm:f:` `extended-regexp=E,fixed-strings=F,ignore-case=i,invert-match=v,line-number=n,count=c,files-with-matches=l,files-without-match=L,quiet=q,silent=q,word-regexp=w,line-regexp=x,only-matching=o,no-filename=h,with-filename=H,recursive=r,regexp=e,file=f,max-count=m` )
    : ~ i rc 1
    ? ! ( bx_ok o ) { = rc 2 } {
        : ~ i flags 0
        : ~ b extended | ( bx_has o `E` ) ( bx_streq me `egrep` )
        ? | ( bx_has o `F` ) ( bx_streq me `fgrep` ) { = flags | flags GREP_FIXED } {}
        ? ( bx_has o `i` ) { = flags | flags GREP_IGNORE } {}
        ? ( bx_has o `v` ) { = flags | flags GREP_INVERT } {}
        ? ( bx_has o `n` ) { = flags | flags GREP_LINENO } {}
        ? ( bx_has o `c` ) { = flags | flags GREP_COUNT } {}
        ? ( bx_has o `l` ) { = flags | flags GREP_FILES } {}
        ? ( bx_has o `L` ) { = flags | flags GREP_NOMATCH_FILES } {}
        ? ( bx_has o `q` ) { = flags | flags GREP_QUIET } {}
        ? ( bx_has o `w` ) { = flags | flags GREP_WORD } {}
        ? ( bx_has o `x` ) { = flags | flags GREP_LINE } {}
        ? ( bx_has o `o` ) { = flags | flags GREP_ONLY } {}
        ? | ( bx_has o `r` ) ( bx_has o `R` ) { = flags | flags GREP_RECURSE } {}
        ? ( bx_has o `s` ) { = flags | flags GREP_SILENT } {}
        : i maxcount ? ( bx_has o `m` ) ( nurl_str_to_int ( bx_val o `m` ) ) 0
        // Pattern sources: -e, -f, or the first operand.
        : ( Vec String ) rawpats ( vec_new [String] )
        ? ( bx_has o `e` ) { ( bx_vals o `e` rawpats ) } {}
        ? ( bx_has o `f` ) {
            ( bx_read_lines ( bx_val o `f` ) rawpats )
        } {}
        : i nops ( bx_operand_count o )
        : ~ i first_file 0
        ? == ( vec_len [String] rawpats ) 0 {
            ? > nops 0 {
                ( vec_push [String] rawpats ( string_from ( bx_operand o 0 ) ) )
                = first_file 1
            } {}
        } {}
        ? == ( vec_len [String] rawpats ) 0 {
            ( bx_err `usage: grep [-EFivncl] PATTERN [FILE]...` )
            = rc 2
        } {
            : ( Vec GrepPat ) pats ( vec_new [GrepPat] )
            : ~ b compiled T
            : i npat ( vec_len [String] rawpats )
            : ~ i pi 0
            ~ < pi npat {
                : s raw ( bx_at rawpats pi )
                : String src ? != 0 & flags GREP_IGNORE ( _grep_lower raw ) ( string_from raw )
                ? != 0 & flags GREP_FIXED {
                    ( vec_push [GrepPat] pats @ GrepPat { @ Regex { # s 0 } src T } )
                } {
                    : String ere ? extended ( string_clone src ) ( _bre_to_ere ( string_data src ) )
                    ?? ( regex_compile ( string_data ere ) ) {
                        T r → { ( vec_push [GrepPat] pats @ GrepPat { r src F } ) }
                        F _ → {
                            ( bx_err_at ( string_data src ) `invalid regular expression` )
                            = compiled F
                            ( string_free src )
                        }
                    }
                    ( string_free ere )
                }
                = pi + pi 1
            }
            ? ! compiled { = rc 2 } {
                : i nfiles - nops first_file
                : b with_name & == 0 & flags GREP_NOFILES | ( bx_has o `H` ) | > nfiles 1 != 0 & flags GREP_RECURSE
                : ~ i total 0
                : ~ i walkrc 0
                ? == nfiles 0 {
                    : i one ( __grep_file pats `-` `(standard input)` flags F maxcount total )
                    ? == one 2 { = walkrc 2 } {}
                } {
                    : ~ i i first_file
                    ~ < i nops {
                        : s p ( bx_operand o i )
                        ? != 0 & flags GREP_RECURSE {
                            ( __grep_walk pats p flags with_name maxcount total walkrc )
                        } {
                            : i one ( __grep_file pats p p flags with_name maxcount total )
                            ? == one 2 {
                                ? == 0 & flags GREP_SILENT {} {}
                                = walkrc 2
                            } {}
                        }
                        = i + i 1
                    }
                }
                = rc ? == walkrc 2 2 ? > total 0 0 1
            }
            ( vec_free_with [GrepPat] pats \ GrepPat p → v { ( __grep_pat_free p ) } )
        }
        ( bx_free_lines rawpats )
    }
    ( bx_opts_free o )
    ^ rc
}
