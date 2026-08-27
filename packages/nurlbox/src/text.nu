// nurlbox/text.nu — the stream utilities.
//
// cat / echo / head / tail / wc / seq / yes. Every one of them is a
// byte-exact filter: a line is copied with the terminator the input
// carried, so a CRLF file survives a `head` and a file with no final
// newline does not grow one.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bufio.nu`
$ `bx.nu`

// ── echo ──────────────────────────────────────────────────────────
//
// Options are only options while they form an unbroken leading run of
// -n / -e / -E; `echo -x` prints `-x`, as every shell's echo does.

@ __echo_is_opt s tok → b {
    : i n ( nurl_str_len tok )
    ? < n 2 { ^ F } {}
    ? != ( nurl_str_get tok 0 ) 45 { ^ F } {}
    : ~ i k 1
    : ~ b all T
    ~ < k n {
        : i c ( nurl_str_get tok k )
        ? ! | == c 110 | == c 101 == c 69 { = all F } {}
        = k + k 1
    }
    ^ all
}

// Expand the C escapes `echo -e` understands, in place into `out`.
@ __echo_escapes String out s text → v {
    : i n ( nurl_str_len text )
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get text i )
        ? & == c 92 < + i 1 n {
            : i e ( nurl_str_get text + i 1 )
            = i + i 2
            ? == e 110 { ( string_push_char out 10 ) } {
                ? == e 116 { ( string_push_char out 9 ) } {
                    ? == e 114 { ( string_push_char out 13 ) } {
                        ? == e 92 { ( string_push_char out 92 ) } {
                            ? == e 97 { ( string_push_char out 7 ) } {
                                ? == e 98 { ( string_push_char out 8 ) } {
                                    ? == e 102 { ( string_push_char out 12 ) } {
                                        ? == e 118 { ( string_push_char out 11 ) } {
                                            ? == e 48 {
                                                // \0NNN — up to three octal digits
                                                : ~ i val 0
                                                : ~ i k 0
                                                ~ & < k 3 & < i n & >= ( nurl_str_get text i ) 48 <= ( nurl_str_get text i ) 55 {
                                                    = val + * val 8 - ( nurl_str_get text i ) 48
                                                    = i + i 1
                                                    = k + k 1
                                                }
                                                ( string_push_char out & val 255 )
                                            } {
                                                ( string_push_char out 92 )
                                                ( string_push_char out e )
                                            } } } } } } } } }
        } {
            ( string_push_char out c )
            = i + i 1
        }
    }
}

@ ap_echo ( Vec String ) argv → i {
    : i n ( vec_len [String] argv )
    : ~ b newline T
    : ~ b escapes F
    : ~ i i 1
    : ~ b scanning T
    ~ & scanning < i n {
        : s tok ( bx_at argv i )
        ? ( __echo_is_opt tok ) {
            : i tn ( nurl_str_len tok )
            : ~ i k 1
            ~ < k tn {
                : i c ( nurl_str_get tok k )
                ? == c 110 { = newline F } {}
                ? == c 101 { = escapes T } {}
                ? == c 69 { = escapes F } {}
                = k + k 1
            }
            = i + i 1
        } { = scanning F }
    }
    : String out ( string_new )
    : ~ b first T
    ~ < i n {
        ? first { = first F } { ( string_push_char out 32 ) }
        ? escapes {
            ( __echo_escapes out ( bx_at argv i ) )
        } {
            ( string_push_str out ( bx_at argv i ) )
        }
        = i + i 1
    }
    ? newline { ( string_push_char out 10 ) } {}
    ( bx_write out )
    ( string_free out )
    ^ 0
}

// ── cat ───────────────────────────────────────────────────────────

: i CAT_NUMBER 1  // -n
: i CAT_NONBLANK 2  // -b
: i CAT_ENDS 4  // -E
: i CAT_TABS 8  // -T
: i CAT_NONPRINT 16  // -v
: i CAT_SQUEEZE 32  // -s

// Straight copy — no rewriting at all, so cat is a byte pipe.
@ __cat_raw s path → i {
    ? ( bx_is_stdin path ) {
        : ~ b more T
        ~ more {
            : ( Vec u ) chunk ( read_n_bytes 65536 )
            ? == ( vec_len [u] chunk ) 0 { = more F } { ( bx_write_bytes chunk ) }
            ( vec_free [u] chunk )
        }
        ^ 0
    } {}
    ?? ( file_open path ) {
        F e → {
            ( bx_err_at path ( bx_ioerr e ) )
            ^ 1
        }
        T f → {
            : ~ i rc 0
            : ~ b more T
            ~ more {
                ?? ( file_read_chunk f 65536 ) {
                    T chunk → {
                        ? == ( vec_len [u] chunk ) 0 { = more F } { ( bx_write_bytes chunk ) }
                        ( vec_free [u] chunk )
                    }
                    F e2 → {
                        ( bx_err_at path ( bx_ioerr e2 ) )
                        = rc 1
                        = more F
                    }
                }
            }
            ( file_close f )
            ^ rc
        }
    }
}

// `%6d\t` — the numbering coreutils emits.
@ __cat_number String out i lineno → v {
    : s digits ( nurl_str_int lineno )
    : i w ( nurl_str_len digits )
    : ~ i pad - 6 w
    ~ > pad 0 { ( string_push_char out 32 ) = pad - pad 1 }
    ( string_push_str out digits )
    ( string_push_char out 9 )
}

// One byte, rendered the way -v / -T / -E ask for.
@ __cat_byte String out i c i flags → v {
    ? & != 0 & flags CAT_TABS == c 9 {
        ( string_push_str out `^I` )
    } {
        ? & != 0 & flags CAT_NONPRINT ! | == c 9 == c 10 {
            : ~ i b c
            ? >= b 128 {
                ( string_push_str out `M-` )
                = b - b 128
            } {}
            ? < b 32 {
                ( string_push_char out 94 )
                ( string_push_char out + b 64 )
            } {
                ? == b 127 {
                    ( string_push_str out `^?` )
                } {
                    ( string_push_char out b )
                }
            }
        } {
            ( string_push_char out c )
        }
    }
}

@ __cat_cooked s path i flags inout i lineno inout i blanks → i {
    ?? ( bx_reader path ) {
        F _ → { ^ 1 }
        T br → {
            : String line ( string_new )
            : String out ( string_new )
            : ~ b more T
            ~ more {
                ? ( bufreader_read_line_raw br line ) {
                    : i ln ( string_len line )
                    // The payload is the line without its terminator.
                    : ~ i body ln
                    : ~ b had_nl F
                    ? & > body 0 == ( string_get line - body 1 ) 10 {
                        = body - body 1
                        = had_nl T
                        ? & > body 0 == ( string_get line - body 1 ) 13 { = body - body 1 } {}
                    } {}
                    : b blank == body 0
                    : ~ b skip F
                    ? & != 0 & flags CAT_SQUEEZE blank {
                        = blanks + blanks 1
                        ? > blanks 1 { = skip T } {}
                    } {}
                    ? ! blank { = blanks 0 } {}
                    ? ! skip {
                        ( string_clear out )
                        ? != 0 & flags CAT_NONBLANK {
                            ? ! blank {
                                = lineno + lineno 1
                                ( __cat_number out lineno )
                            } {}
                        } {
                            ? != 0 & flags CAT_NUMBER {
                                = lineno + lineno 1
                                ( __cat_number out lineno )
                            } {}
                        }
                        : ~ i k 0
                        ~ < k body {
                            ( __cat_byte out ( string_get line k ) flags )
                            = k + k 1
                        }
                        ? != 0 & flags CAT_ENDS { ( string_push_char out 36 ) } {}
                        // The terminator is copied verbatim: a CRLF file
                        // stays CRLF, a file with no final newline gains
                        // none.
                        : ~ i t body
                        ~ < t ln {
                            ( string_push_char out ( string_get line t ) )
                            = t + t 1
                        }
                        ( bx_write out )
                    } {}
                } { = more F }
            }
            ( string_free line )
            ( string_free out )
            ( bufreader_close br )
            ^ 0
        }
    }
}

@ ap_cat ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `nbeEtTvAsu` `number=n,number-nonblank=b,show-ends=E,show-tabs=T,show-nonprinting=v,show-all=A,squeeze-blank=s` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ~ i flags 0
        ? ( bx_has o `n` ) { = flags | flags CAT_NUMBER } {}
        ? ( bx_has o `b` ) { = flags | flags CAT_NONBLANK } {}
        ? ( bx_has o `E` ) { = flags | flags CAT_ENDS } {}
        ? ( bx_has o `T` ) { = flags | flags CAT_TABS } {}
        ? ( bx_has o `v` ) { = flags | flags CAT_NONPRINT } {}
        ? ( bx_has o `s` ) { = flags | flags CAT_SQUEEZE } {}
        ? ( bx_has o `e` ) { = flags | flags | CAT_NONPRINT CAT_ENDS } {}
        ? ( bx_has o `t` ) { = flags | flags | CAT_NONPRINT CAT_TABS } {}
        ? ( bx_has o `A` ) { = flags | flags | CAT_NONPRINT | CAT_ENDS CAT_TABS } {}
        : i nops ( bx_operand_count o )
        : ~ i lineno 0
        : ~ i blanks 0
        ? == nops 0 {
            ? == flags 0 {
                = rc ( __cat_raw `-` )
            } {
                = rc ( __cat_cooked `-` flags lineno blanks )
            }
        } {
            : ~ i i 0
            ~ < i nops {
                : s p ( bx_operand o i )
                : ~ i one 0
                ? == flags 0 {
                    = one ( __cat_raw p )
                } {
                    = one ( __cat_cooked p flags lineno blanks )
                }
                ? != one 0 { = rc 1 } {}
                = i + i 1
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── head ──────────────────────────────────────────────────────────

@ __head_banner b show s path b first → v {
    ? show {
        ? ! first { ( nurl_print `\n` ) } {}
        ( nurl_print `==> ` )
        ( nurl_print ? ( bx_is_stdin path ) `standard input` path )
        ( nurl_print ` <==\n` )
    } {}
}

@ __head_lines s path i count → i {
    ?? ( bx_reader path ) {
        F _ → { ^ 1 }
        T br → {
            : String line ( string_new )
            : ~ i seen 0
            : ~ b more T
            ~ & more < seen count {
                ? ( bufreader_read_line_raw br line ) {
                    ( bx_write line )
                    = seen + seen 1
                } { = more F }
            }
            ( string_free line )
            ( bufreader_close br )
            ^ 0
        }
    }
}

@ __head_bytes s path i count → i {
    : ~ b ok T
    : ( Vec u ) data ( bx_slurp path ok )
    : ~ i rc 0
    ? ok {
        : i n ( vec_len [u] data )
        : i take ? < count n count n
        ? > take 0 { ( nurl_print_bytes # s ( vec_data [u] data ) take ) } {}
    } { = rc 1 }
    ( vec_free [u] data )
    ^ rc
}

@ ap_head ( Vec String ) argv → i {
    // `head -5` is the historical spelling and still in every script.
    : ( Vec String ) av ( vec_new [String] )
    : i argn ( vec_len [String] argv )
    : ~ i ai 0
    ~ < ai argn {
        : s tok ( bx_at argv ai )
        : i tl ( nurl_str_len tok )
        ? & & > ai 0 > tl 1 & == ( nurl_str_get tok 0 ) 45 ( bx_is_digit ( nurl_str_get tok 1 ) ) {
            ( vec_push [String] av ( string_from `-n` ) )
            ( vec_push [String] av ( string_from ( nurl_str_slice tok 1 - tl 1 ) ) )
        } {
            ( vec_push [String] av ( string_from tok ) )
        }
        = ai + ai 1
    }
    : BxOpts o ( bx_getopt av 1 `c:n:qv` `bytes=c,lines=n,quiet=q,silent=q,verbose=v` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ~ i lines 10
        : ~ i bytes -1
        : ~ b bad F
        ? ( bx_has o `n` ) {
            : i v ( bx_count ( bx_val o `n` ) )
            ? < v 0 { ( bx_err_at ( bx_val o `n` ) `invalid number of lines` ) = bad T } { = lines v }
        } {}
        ? ( bx_has o `c` ) {
            : i v ( bx_count ( bx_val o `c` ) )
            ? < v 0 { ( bx_err_at ( bx_val o `c` ) `invalid number of bytes` ) = bad T } { = bytes v }
        } {}
        ? bad { = rc 1 } {
            : i nops ( bx_operand_count o )
            : b show & ! ( bx_has o `q` ) | ( bx_has o `v` ) > nops 1
            ? == nops 0 {
                = rc ? >= bytes 0 ( __head_bytes `-` bytes ) ( __head_lines `-` lines )
            } {
                : ~ i i 0
                ~ < i nops {
                    : s p ( bx_operand o i )
                    ( __head_banner show p == i 0 )
                    : i one ? >= bytes 0 ( __head_bytes p bytes ) ( __head_lines p lines )
                    ? != one 0 { = rc 1 } {}
                    = i + i 1
                }
            }
        }
    }
    ( bx_opts_free o )
    ( vec_free_with [String] av \ String x → v { ( string_free x ) } )
    ^ rc
}

// ── tail ──────────────────────────────────────────────────────────

// Keep the last `count` lines in a ring of Strings so an input far
// larger than memory still costs only the window.
@ __tail_lines s path i count b from_start → i {
    ?? ( bx_reader path ) {
        F _ → { ^ 1 }
        T br → {
            : String line ( string_new )
            ? from_start {
                : ~ i seen 0
                : ~ b more T
                ~ more {
                    ? ( bufreader_read_line_raw br line ) {
                        = seen + seen 1
                        ? >= seen count { ( bx_write line ) } {}
                    } { = more F }
                }
            } {
                : ( Vec String ) ring ( vec_new [String] )
                : ~ i head 0
                : ~ i held 0
                : ~ b more T
                ~ more {
                    ? ( bufreader_read_line_raw br line ) {
                        ? < held count {
                            ( vec_push [String] ring ( string_clone line ) )
                            = held + held 1
                        } {
                            ?? ( vec_get [String] ring head ) {
                                T slot → {
                                    ( string_clear slot )
                                    ( string_push_bytes slot # *u ( string_data line ) ( string_len line ) )
                                }
                                F _ → {}
                            }
                            = head + head 1
                            ? >= head count { = head 0 } {}
                        }
                    } { = more F }
                }
                : ~ i k 0
                ~ < k held {
                    : i idx ? >= held count % + head k count k
                    ?? ( vec_get [String] ring idx ) {
                        T slot → { ( bx_write slot ) }
                        F _ → {}
                    }
                    = k + k 1
                }
                ( vec_free_with [String] ring \ String x → v { ( string_free x ) } )
            }
            ( string_free line )
            ( bufreader_close br )
            ^ 0
        }
    }
}

@ __tail_bytes s path i count b from_start → i {
    : ~ b ok T
    : ( Vec u ) data ( bx_slurp path ok )
    : ~ i rc 0
    ? ok {
        : i n ( vec_len [u] data )
        : ~ i from 0
        ? from_start {
            = from ? > count 0 - count 1 0
            ? > from n { = from n } {}
        } {
            = from ? > - n count 0 - n count 0
        }
        : i take - n from
        ? > take 0 { ( nurl_print_bytes # s + # i ( vec_data [u] data ) from take ) } {}
    } { = rc 1 }
    ( vec_free [u] data )
    ^ rc
}

@ ap_tail ( Vec String ) argv → i {
    : ( Vec String ) av ( vec_new [String] )
    : i argn ( vec_len [String] argv )
    : ~ i ai 0
    ~ < ai argn {
        : s tok ( bx_at argv ai )
        : i tl ( nurl_str_len tok )
        ? & & > ai 0 > tl 1 & == ( nurl_str_get tok 0 ) 45 ( bx_is_digit ( nurl_str_get tok 1 ) ) {
            ( vec_push [String] av ( string_from `-n` ) )
            ( vec_push [String] av ( string_from ( nurl_str_slice tok 1 - tl 1 ) ) )
        } {
            ( vec_push [String] av ( string_from tok ) )
        }
        = ai + ai 1
    }
    : BxOpts o ( bx_getopt av 1 `c:n:qv` `bytes=c,lines=n,quiet=q,silent=q,verbose=v` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ~ i lines 10
        : ~ i bytes -1
        : ~ b from_start F
        : ~ b bad F
        ? ( bx_has o `n` ) {
            : s raw ( bx_val o `n` )
            : b plus == ( nurl_str_get raw 0 ) 43
            : i v ( bx_count ? plus ( nurl_str_slice raw 1 - ( nurl_str_len raw ) 1 ) raw )
            ? < v 0 { ( bx_err_at raw `invalid number of lines` ) = bad T } {
                = lines v
                = from_start plus
            }
        } {}
        ? ( bx_has o `c` ) {
            : s raw ( bx_val o `c` )
            : b plus == ( nurl_str_get raw 0 ) 43
            : i v ( bx_count ? plus ( nurl_str_slice raw 1 - ( nurl_str_len raw ) 1 ) raw )
            ? < v 0 { ( bx_err_at raw `invalid number of bytes` ) = bad T } {
                = bytes v
                = from_start plus
            }
        } {}
        ? bad { = rc 1 } {
            : i nops ( bx_operand_count o )
            : b show & ! ( bx_has o `q` ) | ( bx_has o `v` ) > nops 1
            ? == nops 0 {
                = rc ? >= bytes 0 ( __tail_bytes `-` bytes from_start ) ( __tail_lines `-` lines from_start )
            } {
                : ~ i i 0
                ~ < i nops {
                    : s p ( bx_operand o i )
                    ( __head_banner show p == i 0 )
                    : i one ? >= bytes 0 ( __tail_bytes p bytes from_start ) ( __tail_lines p lines from_start )
                    ? != one 0 { = rc 1 } {}
                    = i + i 1
                }
            }
        }
    }
    ( bx_opts_free o )
    ( vec_free_with [String] av \ String x → v { ( string_free x ) } )
    ^ rc
}

// ── wc ────────────────────────────────────────────────────────────

: WcCount {
    i lines
    i words
    i bytes
    i chars
    i longest
}

@ __wc_one s path inout i lines inout i words inout i bytes inout i chars inout i longest → i {
    ?? ( bx_reader path ) {
        F _ → { ^ 1 }
        T br → {
            : String line ( string_new )
            : ~ b more T
            ~ more {
                ? ( bufreader_read_line_raw br line ) {
                    : i n ( string_len line )
                    = bytes + bytes n
                    : ~ i body n
                    ? & > body 0 == ( string_get line - body 1 ) 10 {
                        = lines + lines 1
                        = body - body 1
                        ? & > body 0 == ( string_get line - body 1 ) 13 { = body - body 1 } {}
                    } {}
                    ? > body longest { = longest body } {}
                    : ~ b in_word F
                    : ~ i k 0
                    ~ < k n {
                        : i c ( string_get line k )
                        // A UTF-8 continuation byte is not a character.
                        ? != 128 & c 192 { = chars + chars 1 } {}
                        : b sp | | | == c 32 == c 9 == c 10 | == c 13 | == c 11 == c 12
                        ? sp { = in_word F } {
                            ? ! in_word { = words + words 1 = in_word T } {}
                        }
                        = k + k 1
                    }
                } { = more F }
            }
            ( string_free line )
            ( bufreader_close br )
            ^ 0
        }
    }
}

// busybox's column rule: a lone counter over at most one file prints
// bare, anything else pads every field to 9 columns.
@ __wc_field String out i val b pad → v {
    ? pad {
        : s d ( nurl_str_int val )
        : ~ i k - 9 ( nurl_str_len d )
        ~ > k 0 { ( string_push_char out 32 ) = k - k 1 }
        ( string_push_str out d )
    } {
        ( string_push_int out val )
    }
}

@ __wc_emit String out i flags b pad i lines i words i bytes i chars i longest s label → v {
    : ~ b first T
    ? != 0 & flags 1 {
        ( __wc_field out lines pad )
        = first F
    } {}
    ? != 0 & flags 2 {
        ? ! first { ( string_push_char out 32 ) } {}
        ( __wc_field out words pad )
        = first F
    } {}
    ? != 0 & flags 4 {
        ? ! first { ( string_push_char out 32 ) } {}
        ( __wc_field out bytes pad )
        = first F
    } {}
    ? != 0 & flags 8 {
        ? ! first { ( string_push_char out 32 ) } {}
        ( __wc_field out chars pad )
        = first F
    } {}
    ? != 0 & flags 16 {
        ? ! first { ( string_push_char out 32 ) } {}
        ( __wc_field out longest pad )
        = first F
    } {}
    ? > ( nurl_str_len label ) 0 {
        ( string_push_char out 32 )
        ( string_push_str out label )
    } {}
    ( string_push_char out 10 )
}

@ ap_wc ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `clwmL` `lines=l,bytes=c,words=w,chars=m,max-line-length=L` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ~ i flags 0
        ? ( bx_has o `l` ) { = flags | flags 1 } {}
        ? ( bx_has o `w` ) { = flags | flags 2 } {}
        ? ( bx_has o `c` ) { = flags | flags 4 } {}
        ? ( bx_has o `m` ) { = flags | flags 8 } {}
        ? ( bx_has o `L` ) { = flags | flags 16 } {}
        ? == flags 0 { = flags 7 } {}
        : i nfields ( nurl_popcnt flags )
        : i nops ( bx_operand_count o )
        : b pad ! & == nfields 1 <= nops 1
        : String out ( string_new )
        : ~ i tl 0
        : ~ i tw 0
        : ~ i tb 0
        : ~ i tc 0
        : ~ i tm 0
        ? == nops 0 {
            : ~ i l 0
            : ~ i w 0
            : ~ i b 0
            : ~ i c 0
            : ~ i m 0
            = rc ( __wc_one `-` l w b c m )
            ( string_clear out )
            ( __wc_emit out flags pad l w b c m `` )
            ( bx_write out )
        } {
            : ~ i i 0
            ~ < i nops {
                : s p ( bx_operand o i )
                : ~ i l 0
                : ~ i w 0
                : ~ i b 0
                : ~ i c 0
                : ~ i m 0
                : i one ( __wc_one p l w b c m )
                ? != one 0 { = rc 1 } {
                    ( string_clear out )
                    ( __wc_emit out flags pad l w b c m p )
                    ( bx_write out )
                    = tl + tl l
                    = tw + tw w
                    = tb + tb b
                    = tc + tc c
                    ? > m tm { = tm m } {}
                }
                = i + i 1
            }
            ? > nops 1 {
                ( string_clear out )
                ( __wc_emit out flags pad tl tw tb tc tm `total` )
                ( bx_write out )
            } {}
        }
        ( string_free out )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── seq ───────────────────────────────────────────────────────────

@ ap_seq ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `ws:` `separator=s,equal-width=w` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? | == nops 0 > nops 3 {
            ( bx_err `usage: seq [FIRST [INCREMENT]] LAST` )
            = rc 1
        } {
            : f first ? > nops 1 ( nurl_str_to_float ( bx_operand o 0 ) ) 1.0
            : f incr ? > nops 2 ( nurl_str_to_float ( bx_operand o 1 ) ) 1.0
            : f last ( nurl_str_to_float ( bx_operand o - nops 1 ) )
            : s sep ? ( bx_has o `s` ) ( bx_val o `s` ) `\n`
            ? == incr 0.0 {
                ( bx_err `increment may not be zero` )
                = rc 1
            } {
                : String out ( string_new )
                : ~ f x first
                : ~ b more T
                : ~ b any F
                ~ more {
                    ? > incr 0.0 { = more <= x last } { = more >= x last }
                    ? more {
                        // The separator goes BETWEEN the numbers; the
                        // line ends with a newline whatever -s said.
                        ? any { ( string_push_str out sep ) } {}
                        ( string_push_float out x )
                        = any T
                        = x + x incr
                    } {}
                    ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
                }
                ? any { ( string_push_char out 10 ) } {}
                ( bx_write out )
                ( string_free out )
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── yes ───────────────────────────────────────────────────────────

@ ap_yes ( Vec String ) argv → i {
    : String unit ( string_new )
    : i n ( vec_len [String] argv )
    ? <= n 1 {
        ( string_push_str unit `y` )
    } {
        : ~ i i 1
        ~ < i n {
            ? > i 1 { ( string_push_char unit 32 ) } {}
            ( string_push_str unit ( bx_at argv i ) )
            = i + i 1
        }
    }
    ( string_push_char unit 10 )
    // One large block per write beats one write per line by an order of
    // magnitude, and `yes` exists to saturate a pipe.
    : String block ( string_new )
    ~ < ( string_len block ) 8192 {
        ( string_push_bytes block # *u ( string_data unit ) ( string_len unit ) )
    }
    : ~ b more T
    ~ more { ( bx_write block ) }
    ( string_free block )
    ( string_free unit )
    ^ 0
}
