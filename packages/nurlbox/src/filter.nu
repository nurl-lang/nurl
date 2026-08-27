// nurlbox/filter.nu — the line-shaped filters.
//
// tac / rev / nl / cut / tr / sort / uniq / tee / comm / paste / fold /
// expand / unexpand / split / cmp.
//
// Each reads its inputs through `bx_reader`, so `-` and a missing
// operand both mean stdin, and each writes through one String buffer so
// a long run costs one write per few thousand lines rather than one per
// line.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bufio.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `bx.nu`

// Collect every line of one input, terminators stripped.
@ bx_read_lines s path ( Vec String ) out → b {
    ?? ( bx_reader path ) {
        F _ → { ^ F }
        T br → {
            : String line ( string_new )
            : ~ b more T
            ~ more {
                ? ( bufreader_read_line_into br line ) {
                    ( vec_push [String] out ( string_clone line ) )
                } { = more F }
            }
            ( string_free line )
            ( bufreader_close br )
            ^ T
        }
    }
}

@ bx_free_lines ( Vec String ) v → v {
    ( vec_free_with [String] v \ String x → v { ( string_free x ) } )
}

// Every operand, or `-` when there are none.
@ bx_inputs BxOpts o ( Vec String ) out → v {
    : i n ( bx_operand_count o )
    ? == n 0 {
        ( vec_push [String] out ( string_from `-` ) )
    } {
        : ~ i i 0
        ~ < i n {
            ( vec_push [String] out ( string_from ( bx_operand o i ) ) )
            = i + i 1
        }
    }
}

// ── tac ───────────────────────────────────────────────────────────

@ ap_tac ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `` `` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ( Vec String ) ins ( vec_new [String] )
        ( bx_inputs o ins )
        : i ni ( vec_len [String] ins )
        : ~ i k 0
        ~ < k ni {
            : ( Vec String ) lines ( vec_new [String] )
            ? ( bx_read_lines ( bx_at ins k ) lines ) {
                : String out ( string_new )
                : ~ i j ( vec_len [String] lines )
                ~ > j 0 {
                    ?? ( vec_get [String] lines - j 1 ) {
                        T l → {
                            ( string_push_bytes out # *u ( string_data l ) ( string_len l ) )
                            ( string_push_char out 10 )
                        }
                        F _ → {}
                    }
                    = j - j 1
                }
                ( bx_write out )
                ( string_free out )
            } { = rc 1 }
            ( bx_free_lines lines )
            = k + k 1
        }
        ( bx_free_lines ins )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── rev ───────────────────────────────────────────────────────────

@ ap_rev ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `` `` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ( Vec String ) ins ( vec_new [String] )
        ( bx_inputs o ins )
        : i ni ( vec_len [String] ins )
        : ~ i k 0
        ~ < k ni {
            ?? ( bx_reader ( bx_at ins k ) ) {
                F _ → { = rc 1 }
                T br → {
                    : String line ( string_new )
                    : String out ( string_new )
                    : ~ b more T
                    ~ more {
                        ? ( bufreader_read_line_into br line ) {
                            : ~ i j ( string_len line )
                            ~ > j 0 {
                                ( string_push_char out ( string_get line - j 1 ) )
                                = j - j 1
                            }
                            ( string_push_char out 10 )
                            ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
                        } { = more F }
                    }
                    ( bx_write out )
                    ( string_free out )
                    ( string_free line )
                    ( bufreader_close br )
                }
            }
            = k + k 1
        }
        ( bx_free_lines ins )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── nl ────────────────────────────────────────────────────────────

@ ap_nl ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `b:n:s:w:v:i:` `body-numbering=b,number-format=n,number-separator=s,number-width=w,starting-line-number=v,line-increment=i` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : s style ? ( bx_has o `b` ) ( bx_val o `b` ) `t`
        : s fmt ? ( bx_has o `n` ) ( bx_val o `n` ) `rn`
        : s sep ? ( bx_has o `s` ) ( bx_val o `s` ) `\t`
        : i width ? ( bx_has o `w` ) ( nurl_str_to_int ( bx_val o `w` ) ) 6
        : i start ? ( bx_has o `v` ) ( nurl_str_to_int ( bx_val o `v` ) ) 1
        : i step ? ( bx_has o `i` ) ( nurl_str_to_int ( bx_val o `i` ) ) 1
        : ( Vec String ) ins ( vec_new [String] )
        ( bx_inputs o ins )
        : ~ i num start
        : i ni ( vec_len [String] ins )
        : ~ i k 0
        ~ < k ni {
            ?? ( bx_reader ( bx_at ins k ) ) {
                F _ → { = rc 1 }
                T br → {
                    : String line ( string_new )
                    : String out ( string_new )
                    : ~ b more T
                    ~ more {
                        ? ( bufreader_read_line_into br line ) {
                            : b blank == ( string_len line ) 0
                            : b numbered | ( bx_streq style `a` ) & ( bx_streq style `t` ) ! blank
                            ? numbered {
                                : s d ( nurl_str_int num )
                                : i pad - width ( nurl_str_len d )
                                ? ( bx_streq fmt `ln` ) {
                                    ( string_push_str out d )
                                    : ~ i q pad
                                    ~ > q 0 { ( string_push_char out 32 ) = q - q 1 }
                                } {
                                    : ~ i q pad
                                    ~ > q 0 { ( string_push_char out ? ( bx_streq fmt `rz` ) 48 32 ) = q - q 1 }
                                    ( string_push_str out d )
                                }
                                ( string_push_str out sep )
                                = num + num step
                            } {
                                : ~ i q width
                                ~ > q 0 { ( string_push_char out 32 ) = q - q 1 }
                                ( string_push_str out sep )
                            }
                            ( string_push_bytes out # *u ( string_data line ) ( string_len line ) )
                            ( string_push_char out 10 )
                        } { = more F }
                    }
                    ( bx_write out )
                    ( string_free out )
                    ( string_free line )
                    ( bufreader_close br )
                }
            }
            = k + k 1
        }
        ( bx_free_lines ins )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── cut ───────────────────────────────────────────────────────────

// A LIST like `1,3-5,7-` as a membership test. Ranges are 1-based and
// `N-` means "to the end", which is how every cut spells it.
: CutList {
    ( Vec i ) lo
    ( Vec i ) hi
    b ok
}

@ __cut_parse s spec → CutList {
    : ( Vec i ) lo ( vec_new [i] )
    : ( Vec i ) hi ( vec_new [i] )
    : ~ b ok T
    : i n ( nurl_str_len spec )
    : ~ i i 0
    ~ < i n {
        : ~ i a 0
        : ~ b any_a F
        ~ & < i n ( bx_is_digit ( nurl_str_get spec i ) ) {
            = a + * a 10 - ( nurl_str_get spec i ) 48
            = any_a T
            = i + i 1
        }
        : ~ i b a
        ? & < i n == ( nurl_str_get spec i ) 45 {
            = i + i 1
            : ~ i c 0
            : ~ b any_c F
            ~ & < i n ( bx_is_digit ( nurl_str_get spec i ) ) {
                = c + * c 10 - ( nurl_str_get spec i ) 48
                = any_c T
                = i + i 1
            }
            = b ? any_c c 1000000000
            ? ! any_a { = a 1 } {}
        } {
            ? ! any_a { = ok F } {}
        }
        ( vec_push [i] lo a )
        ( vec_push [i] hi b )
        ? & < i n == ( nurl_str_get spec i ) 44 { = i + i 1 } {
            ? < i n { = ok F = i n } {}
        }
    }
    ? == ( vec_len [i] lo ) 0 { = ok F } {}
    ^ @ CutList { lo hi ok }
}

@ __cut_has CutList c i k → b {
    : i n ( vec_len [i] . c lo )
    : ~ i i 0
    ~ < i n {
        : ~ i a 0
        : ~ i b 0
        ?? ( vec_get [i] . c lo i ) { T x → { = a x } F _ → {} }
        ?? ( vec_get [i] . c hi i ) { T x → { = b x } F _ → {} }
        ? & >= k a <= k b { ^ T } {}
        = i + i 1
    }
    ^ F
}

@ __cut_free CutList c → v {
    ( vec_free [i] . c lo )
    ( vec_free [i] . c hi )
}

@ ap_cut ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `b:c:f:d:sn` `bytes=b,characters=c,fields=f,delimiter=d,only-delimited=s` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ~ i mode 0  // 0 none, 1 bytes/chars, 2 fields
        : ~ s spec ``
        ? | ( bx_has o `b` ) ( bx_has o `c` ) {
            = mode 1
            = spec ? ( bx_has o `b` ) ( bx_val o `b` ) ( bx_val o `c` )
        } {}
        ? ( bx_has o `f` ) {
            = mode 2
            = spec ( bx_val o `f` )
        } {}
        ? == mode 0 {
            ( bx_err `you must specify a list of bytes, characters, or fields` )
            = rc 1
        } {
            : CutList list ( __cut_parse spec )
            ? ! . list ok {
                ( bx_err_at spec `invalid list` )
                = rc 1
            } {
                : i delim ? ( bx_has o `d` ) ( nurl_str_get ( bx_val o `d` ) 0 ) 9
                : b only ( bx_has o `s` )
                : ( Vec String ) ins ( vec_new [String] )
                ( bx_inputs o ins )
                : i ni ( vec_len [String] ins )
                : ~ i k 0
                ~ < k ni {
                    ?? ( bx_reader ( bx_at ins k ) ) {
                        F _ → { = rc 1 }
                        T br → {
                            : String line ( string_new )
                            : String out ( string_new )
                            : ~ b more T
                            ~ more {
                                ? ( bufreader_read_line_into br line ) {
                                    : i ln ( string_len line )
                                    ? == mode 1 {
                                        : ~ i j 0
                                        ~ < j ln {
                                            ? ( __cut_has list + j 1 ) {
                                                ( string_push_char out ( string_get line j ) )
                                            } {}
                                            = j + j 1
                                        }
                                        ( string_push_char out 10 )
                                    } {
                                        : ~ b has_delim F
                                        : ~ i j 0
                                        ~ < j ln {
                                            ? == ( string_get line j ) delim { = has_delim T = j ln } { = j + j 1 }
                                        }
                                        ? & only ! has_delim {} {
                                            ? ! has_delim {
                                                ( string_push_bytes out # *u ( string_data line ) ln )
                                                ( string_push_char out 10 )
                                            } {
                                                : ~ i field 1
                                                : ~ i from 0
                                                : ~ b first T
                                                : ~ i j 0
                                                ~ <= j ln {
                                                    ? | == j ln == ( string_get line j ) delim {
                                                        ? ( __cut_has list field ) {
                                                            ? first { = first F } { ( string_push_char out delim ) }
                                                            : ~ i q from
                                                            ~ < q j {
                                                                ( string_push_char out ( string_get line q ) )
                                                                = q + q 1
                                                            }
                                                        } {}
                                                        = field + field 1
                                                        = from + j 1
                                                    } {}
                                                    = j + j 1
                                                }
                                                ( string_push_char out 10 )
                                            }
                                        }
                                    }
                                    ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
                                } { = more F }
                            }
                            ( bx_write out )
                            ( string_free out )
                            ( string_free line )
                            ( bufreader_close br )
                        }
                    }
                    = k + k 1
                }
                ( bx_free_lines ins )
            }
            ( __cut_free list )
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── tr ────────────────────────────────────────────────────────────

// Expand `a-z`, `[:alpha:]`, `\n` and friends into a byte list.
@ __tr_expand s spec ( Vec u ) out → v {
    : i n ( nurl_str_len spec )
    : ~ i i 0
    ~ < i n {
        : ~ i c ( nurl_str_get spec i )
        ? & & == c 91 < + i 1 n == ( nurl_str_get spec + i 1 ) 58 {
            : ~ i e + i 2
            ~ & < e n != ( nurl_str_get spec e ) 58 { = e + e 1 }
            : s name ( nurl_str_slice spec + i 2 - e + i 2 )
            : ~ i b 0
            ~ < b 256 {
                : ~ b hit F
                ? ( bx_streq name `alpha` ) { = hit | & >= b 65 <= b 90 & >= b 97 <= b 122 } {}
                ? ( bx_streq name `digit` ) { = hit & >= b 48 <= b 57 } {}
                ? ( bx_streq name `alnum` ) { = hit | | & >= b 65 <= b 90 & >= b 97 <= b 122 & >= b 48 <= b 57 } {}
                ? ( bx_streq name `upper` ) { = hit & >= b 65 <= b 90 } {}
                ? ( bx_streq name `lower` ) { = hit & >= b 97 <= b 122 } {}
                ? ( bx_streq name `space` ) { = hit | == b 32 & >= b 9 <= b 13 } {}
                ? ( bx_streq name `blank` ) { = hit | == b 32 == b 9 } {}
                ? ( bx_streq name `punct` ) {
                    = hit & > b 32 & < b 127 ! | | & >= b 65 <= b 90 & >= b 97 <= b 122 & >= b 48 <= b 57
                } {}
                ? ( bx_streq name `print` ) { = hit & >= b 32 < b 127 } {}
                ? ( bx_streq name `graph` ) { = hit & > b 32 < b 127 } {}
                ? ( bx_streq name `cntrl` ) { = hit | < b 32 == b 127 } {}
                ? ( bx_streq name `xdigit` ) { = hit ( bx_is_hex b ) } {}
                ? hit { ( vec_push [u] out # u b ) } {}
                = b + b 1
            }
            = i ? < e n + e 2 n
        } {
            ? & == c 92 < + i 1 n {
                : i e ( nurl_str_get spec + i 1 )
                = i + i 2
                ? == e 110 { = c 10 } {
                    ? == e 116 { = c 9 } {
                        ? == e 114 { = c 13 } {
                            ? == e 92 { = c 92 } {
                                ? & >= e 48 <= e 55 {
                                    : ~ i val - e 48
                                    : ~ i got 1
                                    ~ & < got 3 & < i n & >= ( nurl_str_get spec i ) 48 <= ( nurl_str_get spec i ) 55 {
                                        = val + * val 8 - ( nurl_str_get spec i ) 48
                                        = i + i 1
                                        = got + got 1
                                    }
                                    = c & val 255
                                } { = c e } } } } }
            } { = i + i 1 }
            // A range `a-z`, but only when a real `-` sits between two
            // characters — a trailing `-` is a literal dash.
            ? & & < + i 1 ( nurl_str_len spec ) == ( nurl_str_get spec i ) 45 < + i 1 n {
                : i hi ( nurl_str_get spec + i 1 )
                : ~ i b c
                ~ <= b hi {
                    ( vec_push [u] out # u b )
                    = b + b 1
                }
                = i + i 2
            } {
                ( vec_push [u] out # u c )
            }
        }
    }
}

@ ap_tr ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `dsc` `delete=d,squeeze-repeats=s,complement=c` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        : b del ( bx_has o `d` )
        : b squeeze ( bx_has o `s` )
        : b comp ( bx_has o `c` )
        ? == nops 0 {
            ( bx_err `missing operand` )
            = rc 1
        } {
            : ( Vec u ) set1 ( vec_new [u] )
            : ( Vec u ) set2 ( vec_new [u] )
            ( __tr_expand ( bx_operand o 0 ) set1 )
            ? > nops 1 { ( __tr_expand ( bx_operand o 1 ) set2 ) } {}
            // A 256-entry table beats a search per byte, and makes -c a
            // single inversion pass instead of a special case everywhere.
            : s inset ( nurl_zalloc 256 )
            : ~ i j 0
            ~ < j ( vec_len [u] set1 ) {
                ?? ( vec_get [u] set1 j ) {
                    T b → { = . # *u inset # i b # u 1 }
                    F _ → {}
                }
                = j + j 1
            }
            ? comp {
                : ~ i b 0
                ~ < b 256 {
                    = . # *u inset b # u ? == 0 # i . # *u inset b 1 0
                    = b + b 1
                }
            } {}
            // Translation target per byte: the matching member of SET2,
            // with the last one repeated once SET2 runs out.
            : s xlat ( nurl_zalloc 256 )
            : ~ i b2 0
            ~ < b2 256 { = . # *u xlat b2 # u b2 = b2 + b2 1 }
            ? & ! del > ( vec_len [u] set2 ) 0 {
                : i n2 ( vec_len [u] set2 )
                : ~ i idx 0
                : ~ i b 0
                ~ < b 256 {
                    ? != 0 # i . # *u inset b {
                        : i pick ? < idx n2 idx - n2 1
                        ?? ( vec_get [u] set2 pick ) {
                            T t → { = . # *u xlat b t }
                            F _ → {}
                        }
                        = idx + idx 1
                    } {}
                    = b + b 1
                }
            } {}
            : String out ( string_new )
            : ~ i last -1
            : ~ b more T
            ~ more {
                : ( Vec u ) chunk ( read_n_bytes 65536 )
                : i cn ( vec_len [u] chunk )
                ? == cn 0 { = more F } {
                    : *u p ( vec_data [u] chunk )
                    : ~ i q 0
                    ~ < q cn {
                        : i c & 255 # i . p q
                        : b inset_hit != 0 # i . # *u inset c
                        ? & del inset_hit {} {
                            : i outc ? del c & 255 # i . # *u xlat c
                            : ~ b emit T
                            ? squeeze {
                                // -s collapses a run only when the byte
                                // was in the set that produced it.
                                : b member ? del != 0 # i . # *u inset outc inset_hit
                                ? & member == outc last { = emit F } {}
                            } {}
                            ? emit { ( string_push_char out outc ) } {}
                            = last outc
                        }
                        = q + q 1
                    }
                    ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
                }
                ( vec_free [u] chunk )
            }
            ( bx_write out )
            ( string_free out )
            ( nurl_free inset )
            ( nurl_free xlat )
            ( vec_free [u] set1 )
            ( vec_free [u] set2 )
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── sort ──────────────────────────────────────────────────────────

: ~ i g_sort_flags 0
: ~ i g_sort_key 0
: ~ i g_sort_key_end 0
: ~ i g_sort_delim -1

: i SORT_REVERSE 1
: i SORT_NUMERIC 2
: i SORT_FOLD 4
: i SORT_BLANKS 8

// The comparison field of `line`, as [from, to).
@ __sort_field String line inout i from inout i to → v {
    = from 0
    = to ( string_len line )
    ? == g_sort_key 0 {
        ? != 0 & g_sort_flags SORT_BLANKS {
            ~ & < from to ( bx_is_blank ( string_get line from ) ) { = from + from 1 }
        } {}
        ^
    } {}
    : i n ( string_len line )
    : ~ i field 1
    : ~ i start 0
    : ~ i i 0
    : ~ i want_start -1
    : ~ i want_end -1
    ~ <= i n {
        : b at_sep ? == i n T ? >= g_sort_delim 0 == ( string_get line i ) g_sort_delim
        & ( bx_is_blank ( string_get line i ) ) ! ( bx_is_blank ( string_get line - i 1 ) )
        ? at_sep {
            ? == field g_sort_key { = want_start start } {}
            ? == field g_sort_key_end { = want_end i } {}
            = field + field 1
            = start ? >= g_sort_delim 0 + i 1 i
        } {}
        = i + i 1
    }
    ? >= want_start 0 {
        = from want_start
        = to ? >= want_end 0 want_end n
    } {}
    ? != 0 & g_sort_flags SORT_BLANKS {
        ~ & < from to ( bx_is_blank ( string_get line from ) ) { = from + from 1 }
    } {}
}

@ bx_is_blank i c → b { ^ | == c 32 == c 9 }

@ __sort_numeric String line i from i to → f {
    : ~ i i from
    ~ & < i to ( bx_is_blank ( string_get line i ) ) { = i + i 1 }
    : String piece ( string_new )
    ~ < i to {
        : i c ( string_get line i )
        ? | | ( bx_is_digit c ) | == c 45 == c 43 | == c 46 == c 101 {
            ( string_push_char piece c )
            = i + i 1
        } { = i to }
    }
    : f v ( nurl_str_to_float ( string_data piece ) )
    ( string_free piece )
    ^ v
}

@ __sort_cmp String a String b → i {
    : ~ i af 0
    : ~ i at 0
    : ~ i bf 0
    : ~ i bt 0
    ( __sort_field a af at )
    ( __sort_field b bf bt )
    : ~ i r 0
    ? != 0 & g_sort_flags SORT_NUMERIC {
        : f x ( __sort_numeric a af at )
        : f y ( __sort_numeric b bf bt )
        = r ( cmp_float x y )
    } {
        : ~ i i af
        : ~ i j bf
        : ~ b going T
        ~ going {
            ? | >= i at >= j bt {
                = going F
                = r ( cmp_int - at i - bt j )
            } {
                : ~ i ca ( string_get a i )
                : ~ i cb ( string_get b j )
                ? != 0 & g_sort_flags SORT_FOLD {
                    ? & >= ca 97 <= ca 122 { = ca - ca 32 } {}
                    ? & >= cb 97 <= cb 122 { = cb - cb 32 } {}
                } {}
                ? != ca cb {
                    = r ( cmp_int ca cb )
                    = going F
                } {
                    = i + i 1
                    = j + j 1
                }
            }
        }
    }
    // A tie on the key falls back to the whole line, which is what makes
    // `sort -k2` deterministic instead of merely grouped.
    ? & == r 0 != g_sort_key 0 { = r ( cmp_string a b ) } {}
    ^ ? != 0 & g_sort_flags SORT_REVERSE - 0 r r
}

@ ap_sort ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `rnufbck:t:sz` `reverse=r,numeric-sort=n,unique=u,ignore-case=f,ignore-leading-blanks=b,check=c,key=k,field-separator=t,stable=s` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        = g_sort_flags 0
        ? ( bx_has o `r` ) { = g_sort_flags | g_sort_flags SORT_REVERSE } {}
        ? ( bx_has o `n` ) { = g_sort_flags | g_sort_flags SORT_NUMERIC } {}
        ? ( bx_has o `f` ) { = g_sort_flags | g_sort_flags SORT_FOLD } {}
        ? ( bx_has o `b` ) { = g_sort_flags | g_sort_flags SORT_BLANKS } {}
        = g_sort_key 0
        = g_sort_key_end 0
        = g_sort_delim ? ( bx_has o `t` ) ( nurl_str_get ( bx_val o `t` ) 0 ) -1
        ? ( bx_has o `k` ) {
            : s spec ( bx_val o `k` )
            : i comma ( nurl_str_find spec `,` )
            = g_sort_key ( nurl_str_to_int ? > comma -1 ( nurl_str_slice spec 0 comma ) spec )
            = g_sort_key_end ? > comma -1 ( nurl_str_to_int ( nurl_str_slice spec + comma 1 - ( nurl_str_len spec ) + comma 1 ) ) 0
        } {}
        : ( Vec String ) ins ( vec_new [String] )
        ( bx_inputs o ins )
        : ( Vec String ) lines ( vec_new [String] )
        : i ni ( vec_len [String] ins )
        : ~ i k 0
        ~ < k ni {
            ? ( bx_read_lines ( bx_at ins k ) lines ) {} { = rc 1 }
            = k + k 1
        }
        ( bx_free_lines ins )
        ? ( bx_has o `c` ) {
            : i n ( vec_len [String] lines )
            : ~ i j 1
            ~ < j n {
                : ~ i bad -1
                ?? ( vec_get [String] lines - j 1 ) {
                    T a → {
                        ?? ( vec_get [String] lines j ) {
                            T b → { ? > ( __sort_cmp a b ) 0 { = bad j } {} }
                            F _ → {}
                        }
                    }
                    F _ → {}
                }
                ? >= bad 0 {
                    ( bx_err `disorder` )
                    = rc 1
                    = j n
                } { = j + j 1 }
            }
        } {
            ( sort_by [String] lines \ String a String b → i { ^ ( __sort_cmp a b ) } )
            : String out ( string_new )
            : i n ( vec_len [String] lines )
            : ~ i j 0
            : ~ i prev -1
            ~ < j n {
                ?? ( vec_get [String] lines j ) {
                    T l → {
                        : ~ b emit T
                        ? & ( bx_has o `u` ) > j 0 {
                            ?? ( vec_get [String] lines - j 1 ) {
                                T p → { ? == ( __sort_cmp p l ) 0 { = emit F } {} }
                                F _ → {}
                            }
                        } {}
                        ? emit {
                            ( string_push_bytes out # *u ( string_data l ) ( string_len l ) )
                            ( string_push_char out ? ( bx_has o `z` ) 0 10 )
                        } {}
                    }
                    F _ → {}
                }
                ? > ( string_len out ) 32768 { ( bx_write out ) ( string_clear out ) } {}
                = j + j 1
            }
            ( bx_write out )
            ( string_free out )
        }
        ( bx_free_lines lines )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── uniq ──────────────────────────────────────────────────────────

@ __uniq_key String line i skip_fields i skip_chars b fold String out → v {
    ( string_clear out )
    : i n ( string_len line )
    : ~ i i 0
    : ~ i f 0
    ~ < f skip_fields {
        ~ & < i n ( bx_is_blank ( string_get line i ) ) { = i + i 1 }
        ~ & < i n ! ( bx_is_blank ( string_get line i ) ) { = i + i 1 }
        = f + f 1
    }
    : ~ i c 0
    ~ & < c skip_chars < i n { = i + i 1 = c + c 1 }
    ~ < i n {
        : ~ i ch ( string_get line i )
        ? & fold & >= ch 65 <= ch 90 { = ch + ch 32 } {}
        ( string_push_char out ch )
        = i + i 1
    }
}

@ ap_uniq ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `cduif:s:w:` `count=c,repeated=d,unique=u,ignore-case=i,skip-fields=f,skip-chars=s,check-chars=w` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i skip_fields ? ( bx_has o `f` ) ( nurl_str_to_int ( bx_val o `f` ) ) 0
        : i skip_chars ? ( bx_has o `s` ) ( nurl_str_to_int ( bx_val o `s` ) ) 0
        : i check ? ( bx_has o `w` ) ( nurl_str_to_int ( bx_val o `w` ) ) -1
        : b fold ( bx_has o `i` )
        : b want_dup ( bx_has o `d` )
        : b want_uniq ( bx_has o `u` )
        : b count ( bx_has o `c` )
        : s input ? > ( bx_operand_count o ) 0 ( bx_operand o 0 ) `-`
        ?? ( bx_reader input ) {
            F _ → { = rc 1 }
            T br → {
                : String line ( string_new )
                : String key ( string_new )
                : String prev ( string_new )
                : String prevkey ( string_new )
                : String out ( string_new )
                : ~ i run 0
                : ~ b have F
                : ~ b more T
                ~ more {
                    ? ( bufreader_read_line_into br line ) {
                        ( __uniq_key line skip_fields skip_chars fold key )
                        ? & >= check 0 > ( string_len key ) check {
                            : String cut ( string_substr key 0 check )
                            ( string_clear key )
                            ( string_push_bytes key # *u ( string_data cut ) ( string_len cut ) )
                            ( string_free cut )
                        } {}
                        : b same & have ( string_eq key prevkey )
                        ? same { = run + run 1 } {
                            ? have { ( __uniq_emit out prev run count want_dup want_uniq ) } {}
                            ( string_clear prev )
                            ( string_push_bytes prev # *u ( string_data line ) ( string_len line ) )
                            ( string_clear prevkey )
                            ( string_push_bytes prevkey # *u ( string_data key ) ( string_len key ) )
                            = run 1
                            = have T
                        }
                    } { = more F }
                }
                ? have { ( __uniq_emit out prev run count want_dup want_uniq ) } {}
                ( bx_write out )
                ( string_free out )
                ( string_free line )
                ( string_free key )
                ( string_free prev )
                ( string_free prevkey )
                ( bufreader_close br )
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

@ __uniq_emit String out String line i run b count b want_dup b want_uniq → v {
    ? & want_dup < run 2 { ^ } {}
    ? & want_uniq > run 1 { ^ } {}
    ? count {
        : s d ( nurl_str_int run )
        : ~ i pad - 7 ( nurl_str_len d )
        ~ > pad 0 { ( string_push_char out 32 ) = pad - pad 1 }
        ( string_push_str out d )
        ( string_push_char out 32 )
    } {}
    ( string_push_bytes out # *u ( string_data line ) ( string_len line ) )
    ( string_push_char out 10 )
}

// ── tee ───────────────────────────────────────────────────────────

@ ap_tee ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `ai` `append=a,ignore-interrupts=i` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        : ( Vec File ) outs ( vec_new [File] )
        : ~ i i 0
        ~ < i nops {
            : s p ( bx_operand o i )
            : !File IoErr r ? ( bx_has o `a` ) ( file_append p ) ( file_create p )
            ?? r {
                T f → { ( vec_push [File] outs f ) }
                F e → {
                    ( bx_err_at p ( bx_ioerr e ) )
                    = rc 1
                }
            }
            = i + i 1
        }
        : ~ b more T
        ~ more {
            : ( Vec u ) chunk ( read_n_bytes 65536 )
            ? == ( vec_len [u] chunk ) 0 { = more F } {
                ( bx_write_bytes chunk )
                : i no ( vec_len [File] outs )
                : ~ i k 0
                ~ < k no {
                    ?? ( vec_get [File] outs k ) {
                        T f → {
                            ?? ( file_write_chunk f chunk ) { T _ → {} F _ → { = rc 1 } }
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
            }
            ( vec_free [u] chunk )
        }
        : i no ( vec_len [File] outs )
        : ~ i k 0
        ~ < k no {
            ?? ( vec_get [File] outs k ) {
                T f → { ( file_close f ) }
                F _ → {}
            }
            = k + k 1
        }
        ( vec_free [File] outs )
    }
    ( bx_opts_free o )
    ^ rc
}
