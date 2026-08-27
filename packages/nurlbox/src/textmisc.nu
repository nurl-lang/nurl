// nurlbox/textmisc.nu — the smaller text utilities.
//
// comm / paste / fold / expand / unexpand / shuf / dos2unix / unix2dos
// / factor / sum.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bufio.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/rng.nu`
$ `bx.nu`
$ `filter.nu`

// ── comm ──────────────────────────────────────────────────────────

@ ap_comm ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `123` `` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        ? != ( bx_operand_count o ) 2 {
            ( bx_err `usage: comm [-123] FILE1 FILE2` )
            = rc 1
        } {
            : b hide1 ( bx_has o `1` )
            : b hide2 ( bx_has o `2` )
            : b hide3 ( bx_has o `3` )
            : ( Vec String ) a ( vec_new [String] )
            : ( Vec String ) b ( vec_new [String] )
            ? & ( bx_read_lines ( bx_operand o 0 ) a ) ( bx_read_lines ( bx_operand o 1 ) b ) {
                : i na ( vec_len [String] a )
                : i nb ( vec_len [String] b )
                : String out ( string_new )
                : ~ i i 0
                : ~ i j 0
                // comm's merge is only correct on sorted input, so it
                // says so instead of quietly producing nonsense — the
                // warning is the whole reason the exit status is 1.
                : ~ b warned1 F
                : ~ b warned2 F
                // Both inputs are assumed sorted; the merge is the
                // whole algorithm, and it is why comm is O(n) where
                // `sort | uniq` over the pair is not.
                ~ | < i na < j nb {
                    : ~ i cmp 0
                    ? >= i na { = cmp 1 } {
                        ? >= j nb { = cmp -1 } {
                            = cmp ( nurl_str_cmp ( bx_at a i ) ( bx_at b j ) )
                        }
                    }
                    ? & & > i 0 < i na < ( nurl_str_cmp ( bx_at a i ) ( bx_at a - i 1 ) ) 0 {
                        ? ! warned1 {
                            ( bx_err `file 1 is not in sorted order` )
                            = warned1 T
                            = rc 1
                        } {}
                    } {}
                    ? & & > j 0 < j nb < ( nurl_str_cmp ( bx_at b j ) ( bx_at b - j 1 ) ) 0 {
                        ? ! warned2 {
                            ( bx_err `file 2 is not in sorted order` )
                            = warned2 T
                            = rc 1
                        } {}
                    } {}
                    ? < cmp 0 {
                        ? ! hide1 {
                            ( string_push_str out ( bx_at a i ) )
                            ( string_push_char out 10 )
                        } {}
                        = i + i 1
                    } {
                        ? > cmp 0 {
                            ? ! hide2 {
                                ? ! hide1 { ( string_push_char out 9 ) } {}
                                ( string_push_str out ( bx_at b j ) )
                                ( string_push_char out 10 )
                            } {}
                            = j + j 1
                        } {
                            ? ! hide3 {
                                ? ! hide1 { ( string_push_char out 9 ) } {}
                                ? ! hide2 { ( string_push_char out 9 ) } {}
                                ( string_push_str out ( bx_at a i ) )
                                ( string_push_char out 10 )
                            } {}
                            = i + i 1
                            = j + j 1
                        }
                    }
                    ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
                }
                ( bx_write out )
                ( string_free out )
            } { = rc 1 }
            ( bx_free_lines a )
            ( bx_free_lines b )
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── paste ─────────────────────────────────────────────────────────

@ __paste_delim s list i idx → i {
    : i n ( nurl_str_len list )
    ? == n 0 { ^ -1 } {}
    : i c ( nurl_str_get list ( __i_wrap idx n ) )
    ? == c 92 { ^ 9 } {}
    ^ c
}

@ __i_wrap i v i n → i { ^ - v * n / v n }

@ ap_paste ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `d:s` `delimiters=d,serial=s` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : s delims ? ( bx_has o `d` ) ( bx_val o `d` ) `\t`
        : ( Vec String ) ins ( vec_new [String] )
        ( bx_inputs o ins )
        : i ni ( vec_len [String] ins )
        : String out ( string_new )
        ? ( bx_has o `s` ) {
            // -s puts each FILE on one line instead of merging columns.
            : ~ i k 0
            ~ < k ni {
                : ( Vec String ) lines ( vec_new [String] )
                ? ( bx_read_lines ( bx_at ins k ) lines ) {
                    : i n ( vec_len [String] lines )
                    : ~ i j 0
                    ~ < j n {
                        ? > j 0 { ( string_push_char out ( __paste_delim delims - j 1 ) ) } {}
                        ( string_push_str out ( bx_at lines j ) )
                        = j + j 1
                    }
                    ( string_push_char out 10 )
                } { = rc 1 }
                ( bx_free_lines lines )
                = k + k 1
            }
        } {
            // Column form: one line taken from each file per output
            // line, until every file is drained.
            : ( Vec BufReader ) rs ( vec_new [BufReader] )
            : ( Vec i ) alive ( vec_new [i] )
            : ~ i k 0
            ~ < k ni {
                ?? ( bx_reader ( bx_at ins k ) ) {
                    T br → {
                        ( vec_push [BufReader] rs br )
                        ( vec_push [i] alive 1 )
                    }
                    F _ → {
                        ( vec_push [BufReader] rs ( bufreader_stdin ) )
                        ( vec_push [i] alive 0 )
                        = rc 1
                    }
                }
                = k + k 1
            }
            : String line ( string_new )
            : String row ( string_new )
            : ~ b more T
            ~ more {
                // The row is assembled aside and only committed once
                // some file actually yielded a line — otherwise the
                // round that discovers end-of-input emits a line of
                // bare delimiters.
                ( string_clear row )
                : ~ b any F
                : ~ i j 0
                ~ < j ni {
                    ? > j 0 { ( string_push_char row ( __paste_delim delims - j 1 ) ) } {}
                    : ~ i live 0
                    ?? ( vec_get [i] alive j ) { T x → { = live x } F _ → {} }
                    ? != live 0 {
                        ?? ( vec_get [BufReader] rs j ) {
                            T br → {
                                ? ( bufreader_read_line_into br line ) {
                                    ( string_push_bytes row # *u ( string_data line ) ( string_len line ) )
                                    = any T
                                } { : b _s ( vec_set [i] alive j 0 ) }
                            }
                            F _ → {}
                        }
                    } {}
                    = j + j 1
                }
                ? any {
                    ( string_push_bytes out # *u ( string_data row ) ( string_len row ) )
                    ( string_push_char out 10 )
                } { = more F }
                ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
            }
            ( string_free row )
            ( string_free line )
            : ~ i q 0
            ~ < q ni {
                ?? ( vec_get [BufReader] rs q ) {
                    T br → { ( bufreader_close br ) }
                    F _ → {}
                }
                = q + q 1
            }
            ( vec_free [BufReader] rs )
            ( vec_free [i] alive )
        }
        ( bx_write out )
        ( string_free out )
        ( bx_free_lines ins )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── fold ──────────────────────────────────────────────────────────

@ ap_fold ( Vec String ) argv → i {
    // `fold -20` is the historical spelling.
    : ( Vec String ) av ( vec_new [String] )
    : i argn ( vec_len [String] argv )
    : ~ i ai 0
    ~ < ai argn {
        : s tok ( bx_at argv ai )
        : i tl ( nurl_str_len tok )
        ? & & > ai 0 > tl 1 & == ( nurl_str_get tok 0 ) 45 ( bx_is_digit ( nurl_str_get tok 1 ) ) {
            ( vec_push [String] av ( string_from `-w` ) )
            ( vec_push [String] av ( string_from ( nurl_str_slice tok 1 - tl 1 ) ) )
        } { ( vec_push [String] av ( string_from tok ) ) }
        = ai + ai 1
    }
    : BxOpts o ( bx_getopt av 1 `w:bs` `width=w,bytes=b,spaces=s` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i width ? ( bx_has o `w` ) ( nurl_str_to_int ( bx_val o `w` ) ) 80
        : b at_spaces ( bx_has o `s` )
        ? <= width 0 {
            ( bx_err `width must be positive` )
            = rc 1
        } {
            : ( Vec String ) ins ( vec_new [String] )
            ( bx_inputs o ins )
            : i ni ( vec_len [String] ins )
            : String out ( string_new )
            : ~ i k 0
            ~ < k ni {
                ?? ( bx_reader ( bx_at ins k ) ) {
                    F _ → { = rc 1 }
                    T br → {
                        : String line ( string_new )
                        : ~ b more T
                        ~ more {
                            ? ( bufreader_read_line_into br line ) {
                                : i n ( string_len line )
                                : ~ i from 0
                                ~ < from n {
                                    : ~ i to ? < + from width n + from width n
                                    ? & at_spaces < to n {
                                        // Break at the last blank in the
                                        // window, so a word survives the
                                        // fold whole.
                                        : ~ i b - to 1
                                        : ~ b found F
                                        ~ & ! found > b from {
                                            ? ( bx_is_blank ( string_get line b ) ) {
                                                = to + b 1
                                                = found T
                                            } { = b - b 1 }
                                        }
                                    } {}
                                    ( string_push_bytes out # *u + # i ( string_data line ) from - to from )
                                    ( string_push_char out 10 )
                                    = from to
                                }
                                ? == n 0 { ( string_push_char out 10 ) } {}
                                ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
                            } { = more F }
                        }
                        ( string_free line )
                        ( bufreader_close br )
                    }
                }
                = k + k 1
            }
            ( bx_write out )
            ( string_free out )
            ( bx_free_lines ins )
        }
    }
    ( bx_opts_free o )
    ( vec_free_with [String] av \ String x → v { ( string_free x ) } )
    ^ rc
}

// ── expand / unexpand ─────────────────────────────────────────────

// A tab-stop list: a single number means "every N columns", a list
// means "at these columns, then every 8".
@ __tab_next s spec i col → i {
    : i n ( nurl_str_len spec )
    ? == n 0 { ^ + col - 8 ( __i_wrap col 8 ) } {}
    : ~ i i 0
    : ~ i last 0
    : ~ i count 0
    ~ < i n {
        : ~ i v 0
        : ~ b any F
        ~ & < i n ( bx_is_digit ( nurl_str_get spec i ) ) {
            = v + * v 10 - ( nurl_str_get spec i ) 48
            = any T
            = i + i 1
        }
        ? any {
            = count + count 1
            ? > v col { ^ v } {}
            = last v
        } {}
        ~ & < i n ! ( bx_is_digit ( nurl_str_get spec i ) ) { = i + i 1 }
    }
    // Past the last stop: a single stop repeats, a list falls back to
    // one column at a time, which is what coreutils does.
    ? == count 1 { ^ + col - last ( __i_wrap col last ) } {}
    ^ + col 1
}

@ ap_expand ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `t:i` `tabs=t,initial=i` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : s tabs ? ( bx_has o `t` ) ( bx_val o `t` ) `8`
        : b only_leading ( bx_has o `i` )
        : ( Vec String ) ins ( vec_new [String] )
        ( bx_inputs o ins )
        : i ni ( vec_len [String] ins )
        : String out ( string_new )
        : ~ i k 0
        ~ < k ni {
            ?? ( bx_reader ( bx_at ins k ) ) {
                F _ → { = rc 1 }
                T br → {
                    : String line ( string_new )
                    : ~ b more T
                    ~ more {
                        ? ( bufreader_read_line_into br line ) {
                            : i n ( string_len line )
                            : ~ i col 0
                            : ~ b leading T
                            : ~ i i 0
                            ~ < i n {
                                : i c ( string_get line i )
                                ? & == c 9 | ! only_leading leading {
                                    : i stop ( __tab_next tabs col )
                                    ~ < col stop { ( string_push_char out 32 ) = col + col 1 }
                                } {
                                    ? ! ( bx_is_blank c ) { = leading F } {}
                                    ( string_push_char out c )
                                    = col + col 1
                                }
                                = i + i 1
                            }
                            ( string_push_char out 10 )
                            ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
                        } { = more F }
                    }
                    ( string_free line )
                    ( bufreader_close br )
                }
            }
            = k + k 1
        }
        ( bx_write out )
        ( string_free out )
        ( bx_free_lines ins )
    }
    ( bx_opts_free o )
    ^ rc
}

@ ap_unexpand ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `t:a` `tabs=t,all=a` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : s tabs ? ( bx_has o `t` ) ( bx_val o `t` ) `8`
        : b all ( bx_has o `a` )
        : ( Vec String ) ins ( vec_new [String] )
        ( bx_inputs o ins )
        : i ni ( vec_len [String] ins )
        : String out ( string_new )
        : ~ i k 0
        ~ < k ni {
            ?? ( bx_reader ( bx_at ins k ) ) {
                F _ → { = rc 1 }
                T br → {
                    : String line ( string_new )
                    : ~ b more T
                    ~ more {
                        ? ( bufreader_read_line_into br line ) {
                            : i n ( string_len line )
                            : ~ i col 0
                            : ~ i pending 0  // blanks held back, waiting for a stop
                            : ~ i pend_col 0
                            : ~ b leading T
                            : ~ i i 0
                            ~ < i n {
                                : i c ( string_get line i )
                                : b blank ( bx_is_blank c )
                                ? & blank | all leading {
                                    ? == pending 0 { = pend_col col } {}
                                    = pending + pending ? == c 9 - ( __tab_next tabs col ) col 1
                                    = col ? == c 9 ( __tab_next tabs col ) + col 1
                                    // A run of blanks that crosses a tab
                                    // stop collapses into one tab.
                                    : i stop ( __tab_next tabs pend_col )
                                    ? >= col stop {
                                        ( string_push_char out 9 )
                                        = pend_col stop
                                        = pending - col stop
                                        ? < pending 0 { = pending 0 } {}
                                    } {}
                                } {
                                    ~ > pending 0 { ( string_push_char out 32 ) = pending - pending 1 }
                                    ? ! blank { = leading F } {}
                                    ( string_push_char out c )
                                    = col + col 1
                                }
                                = i + i 1
                            }
                            ~ > pending 0 { ( string_push_char out 32 ) = pending - pending 1 }
                            ( string_push_char out 10 )
                            ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
                        } { = more F }
                    }
                    ( string_free line )
                    ( bufreader_close br )
                }
            }
            = k + k 1
        }
        ( bx_write out )
        ( string_free out )
        ( bx_free_lines ins )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── shuf ──────────────────────────────────────────────────────────

@ ap_shuf ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `n:ei:zr` `head-count=n,echo=e,input-range=i,zero-terminated=z,repeat=r` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ( Vec String ) items ( vec_new [String] )
        ? ( bx_has o `e` ) {
            : i n ( bx_operand_count o )
            : ~ i k 0
            ~ < k n {
                ( vec_push [String] items ( string_from ( bx_operand o k ) ) )
                = k + k 1
            }
        } {
            ? ( bx_has o `i` ) {
                : s spec ( bx_val o `i` )
                : i dash ( nurl_str_find spec `-` )
                ? < dash 0 {
                    ( bx_err_at spec `invalid input range` )
                    = rc 1
                } {
                    : i lo ( nurl_str_to_int ( nurl_str_slice spec 0 dash ) )
                    : i hi ( nurl_str_to_int ( nurl_str_slice spec + dash 1 - ( nurl_str_len spec ) + dash 1 ) )
                    : ~ i v lo
                    ~ <= v hi {
                        ( vec_push [String] items ( string_from ( nurl_str_int v ) ) )
                        = v + v 1
                    }
                }
            } {
                : s p ? > ( bx_operand_count o ) 0 ( bx_operand o 0 ) `-`
                ? ( bx_read_lines p items ) {} { = rc 1 }
            }
        }
        ? == rc 0 {
            : i n ( vec_len [String] items )
            // The clock is the seed: two runs in the same millisecond
            // would otherwise shuffle identically, which `shuf` exists
            // not to do.
            : Rng g ( rng_seed ^^ ( now_ms ) * ( monotonic_ns ) 2654435761 )
            // Fisher-Yates, back to front.
            : ~ i i - n 1
            ~ > i 0 {
                : i j ( rng_below g + i 1 )
                : b _s ( vec_swap [String] items i j )
                = i - i 1
            }
            : i take ? ( bx_has o `n` ) ( nurl_str_to_int ( bx_val o `n` ) ) n
            : String out ( string_new )
            : ~ i k 0
            ~ & < k n < k take {
                ( string_push_str out ( bx_at items k ) )
                ( string_push_char out ? ( bx_has o `z` ) 0 10 )
                = k + k 1
            }
            ( bx_write out )
            ( string_free out )
            ( rng_free g )
        } {}
        ( bx_free_lines items )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── dos2unix / unix2dos ───────────────────────────────────────────

@ __crlf_convert s path b to_dos b in_place → i {
    : ~ b ok T
    : ( Vec u ) data ( bx_slurp path ok )
    ? ! ok {
        ( vec_free [u] data )
        ^ 1
    } {}
    : String out ( string_new )
    : i n ( vec_len [u] data )
    : *u p ( vec_data [u] data )
    : ~ i i 0
    ~ < i n {
        : i c & 255 # i . p i
        ? == c 13 {
            // A lone CR is data; a CR before LF is a line ending.
            ? & < + i 1 n == 10 & 255 # i . p + i 1 {} { ( string_push_char out 13 ) }
        } {
            ? == c 10 {
                ? to_dos { ( string_push_char out 13 ) } {}
                ( string_push_char out 10 )
            } { ( string_push_char out c ) }
        }
        = i + i 1
    }
    : ~ i rc 0
    ? in_place {
        : ( Vec u ) bytes ( vec_new [u] )
        : i on ( string_len out )
        : ~ i k 0
        ~ < k on { ( vec_push [u] bytes # u ( string_get out k ) ) = k + k 1 }
        ?? ( write_file_bytes path bytes ) {
            T _ → {}
            F e → {
                ( bx_err_at path ( bx_ioerr e ) )
                = rc 1
            }
        }
        ( vec_free [u] bytes )
    } { ( bx_write out ) }
    ( string_free out )
    ( vec_free [u] data )
    ^ rc
}

@ ap_dos2unix ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `ud` `` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        // -u forces unix endings, -d forces dos ones, whichever name
        // the binary was invoked under.
        : ~ b to_dos ( bx_streq ( bx_name ) `unix2dos` )
        ? ( bx_has o `u` ) { = to_dos F } {}
        ? ( bx_has o `d` ) { = to_dos T } {}
        : i nops ( bx_operand_count o )
        ? == nops 0 {
            = rc ( __crlf_convert `-` to_dos F )
        } {
            : ~ i i 0
            ~ < i nops {
                : i one ( __crlf_convert ( bx_operand o i ) to_dos T )
                ? != one 0 { = rc 1 } {}
                = i + i 1
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── factor ────────────────────────────────────────────────────────

@ __factor_one String out i n → v {
    ( string_push_int out n )
    ( string_push_char out 58 )
    : ~ i v n
    ? < v 2 {
        ( string_push_char out 10 )
        ^
    } {}
    ~ == 0 - v * 2 / v 2 {
        ( string_push_str out ` 2` )
        = v / v 2
    }
    : ~ i d 3
    // Trial division to sqrt(v): d*d > v is the stop, written as a
    // multiply so it never needs a square root.
    ~ <= * d d v {
        ~ == 0 - v * d / v d {
            ( string_push_char out 32 )
            ( string_push_int out d )
            = v / v d
        }
        = d + d 2
    }
    ? > v 1 {
        ( string_push_char out 32 )
        ( string_push_int out v )
    } {}
    ( string_push_char out 10 )
}

@ ap_factor ( Vec String ) argv → i {
    : i n ( vec_len [String] argv )
    : String out ( string_new )
    : ~ i rc 0
    ? <= n 1 {
        // No operands: numbers come from stdin, one per line.
        ?? ( bx_reader `-` ) {
            F _ → { = rc 1 }
            T br → {
                : String line ( string_new )
                : ~ b more T
                ~ more {
                    ? ( bufreader_read_line_into br line ) {
                        ? > ( string_len line ) 0 {
                            ( __factor_one out ( nurl_str_to_int ( string_data line ) ) )
                        } {}
                    } { = more F }
                }
                ( string_free line )
                ( bufreader_close br )
            }
        }
    } {
        : ~ i i 1
        ~ < i n {
            ( __factor_one out ( nurl_str_to_int ( bx_at argv i ) ) )
            = i + i 1
        }
    }
    ( bx_write out )
    ( string_free out )
    ^ rc
}

// ── sum ───────────────────────────────────────────────────────────

// Two historical checksums, neither of them a hash: the BSD one is a
// 16-bit rotate-and-add, the System V one a byte sum folded twice.
@ __sum_bsd ( Vec u ) data → i {
    : i n ( vec_len [u] data )
    : *u p ( vec_data [u] data )
    : ~ i s 0
    : ~ i i 0
    ~ < i n {
        = s | >> s 1 << & s 1 15
        = s & + s & 255 # i . p i 65535
        = i + i 1
    }
    ^ s
}

@ __sum_sysv ( Vec u ) data → i {
    : i n ( vec_len [u] data )
    : *u p ( vec_data [u] data )
    : ~ i s 0
    : ~ i i 0
    ~ < i n {
        = s + s & 255 # i . p i
        = i + i 1
    }
    : i r + & s 65535 >> s 16
    ^ & + & r 65535 >> r 16 65535
}

@ ap_sum ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `rs` `` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : b sysv ( bx_has o `s` )
        : i nops ( bx_operand_count o )
        : ~ i i 0
        ~ < i ? > nops 0 nops 1 {
            : s p ? > nops 0 ( bx_operand o i ) `-`
            : ~ b ok T
            : ( Vec u ) data ( bx_slurp p ok )
            ? ok {
                : String out ( string_new )
                : i n ( vec_len [u] data )
                ? sysv {
                    ( string_push_int out ( __sum_sysv data ) )
                    ( string_push_char out 32 )
                    ( string_push_int out / + n 511 512 )
                } {
                    : s d ( nurl_str_int ( __sum_bsd data ) )
                    : ~ i pad - 5 ( nurl_str_len d )
                    ~ > pad 0 { ( string_push_char out 32 ) = pad - pad 1 }
                    ( string_push_str out d )
                    ( string_push_char out 32 )
                    : s blocks ( nurl_str_int / + n 1023 1024 )
                    : ~ i pad2 - 5 ( nurl_str_len blocks )
                    ~ > pad2 0 { ( string_push_char out 32 ) = pad2 - pad2 1 }
                    ( string_push_str out blocks )
                }
                ? > nops 0 {
                    ( string_push_char out 32 )
                    ( string_push_str out p )
                } {}
                ( string_push_char out 10 )
                ( bx_write out )
                ( string_free out )
            } { = rc 1 }
            ( vec_free [u] data )
            = i + i 1
        }
    }
    ( bx_opts_free o )
    ^ rc
}
