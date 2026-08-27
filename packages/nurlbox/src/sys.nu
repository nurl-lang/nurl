// nurlbox/sys.nu — the applets that ask the system about itself.
//
// pwd / basename / dirname / env / printenv / printf / sleep / usleep /
// uname / arch / hostname / whoami / id / groups / logname / nproc /
// which / date / sync / clear / tty.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/term.nu`
$ `stdlib/std/sysinfo.nu`
$ `stdlib/ext/env.nu`
$ `bx.nu`

& `c` @ getuid → i32

& `c` @ geteuid → i32

& `c` @ getgid → i32

& `c` @ getegid → i32

& `c` @ getgroups i32 size *u list → i32

// ── pwd ───────────────────────────────────────────────────────────

@ ap_pwd ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `LP` `logical=L,physical=P` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        // -L honours $PWD when it still names this directory; -P (and
        // the default here) is what getcwd(3) answers, with every
        // symlink already resolved.
        : ~ b used F
        ? ( bx_has o `L` ) {
            ?? ( env_get `PWD` ) {
                T p → {
                    ? ( path_is_absolute ( string_data p ) ) {
                        ( nurl_print ( string_data p ) )
                        ( nurl_print `\n` )
                        = used T
                    } {}
                    ( string_free p )
                }
                F _ → {}
            }
        } {}
        ? ! used {
            ?? ( env_cwd ) {
                T c → {
                    ( nurl_print ( string_data c ) )
                    ( nurl_print `\n` )
                    ( string_free c )
                }
                F e → {
                    ( bx_err ( bx_ioerr e ) )
                    = rc 1
                }
            }
        } {}
    }
    ( bx_opts_free o )
    ^ rc
}

// ── basename / dirname ────────────────────────────────────────────

// POSIX basename: strip trailing slashes, take the last component,
// then remove `suffix` unless that would leave nothing.
@ __basename_of s p s suffix → String {
    : String base ( path_basename p )
    : i sl ( nurl_str_len suffix )
    ? > sl 0 {
        : i bl ( string_len base )
        ? & > bl sl ( string_ends_with base suffix ) {
            : String cut ( string_substr base 0 - bl sl )
            ( string_free base )
            ^ cut
        } {}
    } {}
    ^ base
}

@ ap_basename ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `as:z` `multiple=a,suffix=s,zero=z` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? == nops 0 {
            ( bx_err `missing operand` )
            = rc 1
        } {
            : b multi | ( bx_has o `a` ) ( bx_has o `s` )
            : i term ? ( bx_has o `z` ) 0 10
            ? multi {
                : ~ i i 0
                ~ < i nops {
                    : String b ( __basename_of ( bx_operand o i ) ( bx_val o `s` ) )
                    ( nurl_print_bytes ( string_data b ) ( string_len b ) )
                    ( nurl_print ? == term 0 `` `\n` )
                    ( string_free b )
                    = i + i 1
                }
            } {
                : String b ( __basename_of ( bx_operand o 0 ) ? > nops 1 ( bx_operand o 1 ) `` )
                ( nurl_print_bytes ( string_data b ) ( string_len b ) )
                ( nurl_print ? == term 0 `` `\n` )
                ( string_free b )
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

@ ap_dirname ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `z` `zero=z` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? == nops 0 {
            ( bx_err `missing operand` )
            = rc 1
        } {
            : ~ i i 0
            ~ < i nops {
                : String d ( path_dirname ( bx_operand o i ) )
                ( nurl_print ( string_data d ) )
                ( nurl_print ? ( bx_has o `z` ) `` `\n` )
                ( string_free d )
                = i + i 1
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── env / printenv ────────────────────────────────────────────────

@ __env_dump s sep → v {
    : ( Vec String ) all ( env_list )
    : i n ( vec_len [String] all )
    : ~ i i 0
    ~ < i n {
        ( nurl_print ( bx_at all i ) )
        ( nurl_print sep )
        = i + i 1
    }
    ( vec_free_with [String] all \ String x → v { ( string_free x ) } )
}

// Hand the process over to `cmd`. On success this never returns — the
// image is replaced, which is exactly what `env VAR=x prog` means.
@ __exec_argv ( Vec String ) args i from → i {
    : i n - ( vec_len [String] args ) from
    ? <= n 0 { ^ 127 } {}
    : s argvbuf ( nurl_zalloc * 8 + n 1 )
    : ~ i k 0
    ~ < k n {
        ( nurl_poke argvbuf k # i ( bx_at args + from k ) )
        = k + k 1
    }
    : s cmd ( bx_at args from )
    : i32 _rc ( execvp cmd # *u argvbuf )
    : i err ( nurl_errno_get )
    ( nurl_free argvbuf )
    ( bx_err_at cmd ? == err ( posix_const `ENOENT` ) `No such file or directory` `Permission denied` )
    ^ ? == err ( posix_const `ENOENT` ) 127 126
}

@ ap_env ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `iu:0` `ignore-environment=i,unset=u,null=0` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        ? ( bx_has o `i` ) {
            : ( Vec String ) all ( env_list )
            : i n ( vec_len [String] all )
            : ~ i i 0
            ~ < i n {
                : s e ( bx_at all i )
                : i eq ( nurl_str_find e `=` )
                ? > eq 0 {
                    : s nm ( nurl_str_slice e 0 eq )
                    ?? ( env_unset nm ) { T _ → {} F _ → {} }
                } {}
                = i + i 1
            }
            ( vec_free_with [String] all \ String x → v { ( string_free x ) } )
        } {}
        ? ( bx_has o `u` ) {
            ?? ( env_unset ( bx_val o `u` ) ) { T _ → {} F _ → {} }
        } {}
        // Leading NAME=VALUE operands are assignments; the first operand
        // without an `=` starts the command.
        : i nops ( bx_operand_count o )
        : ~ i i 0
        : ~ b assigning T
        ~ & assigning < i nops {
            : s e ( bx_operand o i )
            : i eq ( nurl_str_find e `=` )
            ? > eq 0 {
                : s nm ( nurl_str_slice e 0 eq )
                : s val ( nurl_str_slice e + eq 1 - ( nurl_str_len e ) + eq 1 )
                ?? ( env_set nm val ) { T _ → {} F _ → {} }
                = i + i 1
            } { = assigning F }
        }
        ? < i nops {
            = rc ( __exec_argv . o args i )
        } {
            ( __env_dump ? ( bx_has o `0` ) `` `\n` )
        }
    }
    ( bx_opts_free o )
    ^ rc
}

@ ap_printenv ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `0` `null=0` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        : s sep ? ( bx_has o `0` ) `` `\n`
        ? == nops 0 {
            ( __env_dump sep )
        } {
            : ~ i i 0
            ~ < i nops {
                ?? ( env_get ( bx_operand o i ) ) {
                    T v → {
                        ( nurl_print ( string_data v ) )
                        ( nurl_print sep )
                        ( string_free v )
                    }
                    F _ → { = rc 1 }
                }
                = i + i 1
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── printf ────────────────────────────────────────────────────────

// One `\`-escape at `i` (which points at the backslash), appended to
// `out`; returns the index just past it. Shared by printf's format
// string and by its %b conversion.
@ __pf_one_escape String out s text i i i to → i {
    ? >= + i 1 to {
        ( string_push_char out 92 )
        ^ + i 1
    } {}
    : i e ( nurl_str_get text + i 1 )
    : ~ i k + i 2
    ? == e 110 { ( string_push_char out 10 ) } {
        ? == e 116 { ( string_push_char out 9 ) } {
            ? == e 114 { ( string_push_char out 13 ) } {
                ? == e 92 { ( string_push_char out 92 ) } {
                    ? == e 97 { ( string_push_char out 7 ) } {
                        ? == e 98 { ( string_push_char out 8 ) } {
                            ? == e 102 { ( string_push_char out 12 ) } {
                                ? == e 118 { ( string_push_char out 11 ) } {
                                    ? == e 34 { ( string_push_char out 34 ) } {
                                        ? == e 120 {
                                            : ~ i val 0
                                            : ~ i got 0
                                            ~ & < got 2 & < k to ( bx_is_hex ( nurl_str_get text k ) ) {
                                                = val + * val 16 ( bx_hex_val ( nurl_str_get text k ) )
                                                = k + k 1
                                                = got + got 1
                                            }
                                            ? == got 0 {
                                                ( string_push_char out 92 )
                                                ( string_push_char out e )
                                            } { ( string_push_char out & val 255 ) }
                                        } {
                                            ? & >= e 48 <= e 55 {
                                                : ~ i val - e 48
                                                : ~ i got 1
                                                ~ & < got 3 & < k to & >= ( nurl_str_get text k ) 48 <= ( nurl_str_get text k ) 55 {
                                                    = val + * val 8 - ( nurl_str_get text k ) 48
                                                    = k + k 1
                                                    = got + got 1
                                                }
                                                ( string_push_char out & val 255 )
                                            } {
                                                ( string_push_char out 92 )
                                                ( string_push_char out e )
                                            } } } } } } } } } } }
    ^ k
}

// Every escape in text[from, to).
@ __pf_escape String out s text i from i to → i {
    : ~ i i from
    ~ < i to {
        ? == ( nurl_str_get text i ) 92 {
            = i ( __pf_one_escape out text i to )
        } {
            ( string_push_char out ( nurl_str_get text i ) )
            = i + i 1
        }
    }
    ^ i
}

// An unsigned integer in `base`, upper- or lower-case for hex.
@ __pf_uint String out i val i base b upper → v {
    ? == val 0 { ( string_push_char out 48 ) ^ } {}
    : s digits ? upper `0123456789ABCDEF` `0123456789abcdef`
    : String tmp ( string_with_cap 24 )
    : ~ i v val
    ~ != v 0 {
        : i q ( __pf_udiv v base )
        : i r - v * q base
        ( string_push_char tmp ( nurl_str_get digits r ) )
        = v q
    }
    : ~ i k ( string_len tmp )
    ~ > k 0 {
        ( string_push_char out ( string_get tmp - k 1 ) )
        = k - k 1
    }
    ( string_free tmp )
}

// Unsigned division of a value whose top bit may be set, done in i64.
@ __pf_udiv i v i base → i {
    ? >= v 0 { ^ / v base } {}
    : i half >> & v 9223372036854775807 1
    : i q / half base
    : i r - half * q base
    : i lo | << r 1 & v 1
    ^ + * q 2 / lo base
}

@ __pf_pad String out i width b left String body → v {
    : i n ( string_len body )
    ? & ! left > width n {
        : ~ i k - width n
        ~ > k 0 { ( string_push_char out 32 ) = k - k 1 }
    } {}
    ( string_push_bytes out # *u ( string_data body ) n )
    ? & left > width n {
        : ~ i k - width n
        ~ > k 0 { ( string_push_char out 32 ) = k - k 1 }
    } {}
}

@ ap_printf ( Vec String ) argv → i {
    : i n ( vec_len [String] argv )
    ? < n 2 {
        ( bx_err `usage: printf FORMAT [ARGUMENT]...` )
        ^ 1
    } {}
    : s fmt ( bx_at argv 1 )
    : i fl ( nurl_str_len fmt )
    : String out ( string_new )
    : ~ i ai 2
    : ~ b again T
    ~ again {
        = again F
        : ~ i i 0
        ~ < i fl {
            : i c ( nurl_str_get fmt i )
            ? == c 92 {
                = i ( __pf_one_escape out fmt i fl )
            } {
                ? == c 37 {
                    ? & < + i 1 fl == ( nurl_str_get fmt + i 1 ) 37 {
                        ( string_push_char out 37 )
                        = i + i 2
                    } {
                        : ~ i k + i 1
                        : ~ b left F
                        : ~ b zero F
                        : ~ b plus F
                        : ~ b space F
                        : ~ b more T
                        ~ & more < k fl {
                            : i f ( nurl_str_get fmt k )
                            ? == f 45 { = left T = k + k 1 } {
                                ? == f 48 { = zero T = k + k 1 } {
                                    ? == f 43 { = plus T = k + k 1 } {
                                        ? == f 32 { = space T = k + k 1 } {
                                            ? == f 35 { = k + k 1 } { = more F } } } } }
                        }
                        : ~ i width 0
                        ~ & < k fl ( bx_is_digit ( nurl_str_get fmt k ) ) {
                            = width + * width 10 - ( nurl_str_get fmt k ) 48
                            = k + k 1
                        }
                        : ~ i prec -1
                        ? & < k fl == ( nurl_str_get fmt k ) 46 {
                            = k + k 1
                            = prec 0
                            ~ & < k fl ( bx_is_digit ( nurl_str_get fmt k ) ) {
                                = prec + * prec 10 - ( nurl_str_get fmt k ) 48
                                = k + k 1
                            }
                        } {}
                        // Skip the C length modifiers a script may carry.
                        ~ & < k fl | | == ( nurl_str_get fmt k ) 108 == ( nurl_str_get fmt k ) 104 == ( nurl_str_get fmt k ) 113 {
                            = k + k 1
                        }
                        ? >= k fl {
                            ( string_push_char out 37 )
                            = i k
                        } {
                            : i conv ( nurl_str_get fmt k )
                            : s arg ? < ai n ( bx_at argv ai ) ``
                            : b consumed T
                            : String body ( string_new )
                            ? | == conv 100 == conv 105 {
                                : i v ( nurl_str_to_int arg )
                                ? < v 0 {
                                    ( string_push_char body 45 )
                                    ( __pf_uint body - 0 v 10 F )
                                } {
                                    ? plus { ( string_push_char body 43 ) } {
                                        ? space { ( string_push_char body 32 ) } {}
                                    }
                                    ( __pf_uint body v 10 F )
                                }
                            } {
                                ? == conv 117 { ( __pf_uint body ( nurl_str_to_int arg ) 10 F ) } {
                                    ? == conv 120 { ( __pf_uint body ( nurl_str_to_int arg ) 16 F ) } {
                                        ? == conv 88 { ( __pf_uint body ( nurl_str_to_int arg ) 16 T ) } {
                                            ? == conv 111 { ( __pf_uint body ( nurl_str_to_int arg ) 8 F ) } {
                                                ? == conv 99 {
                                                    ? > ( nurl_str_len arg ) 0 { ( string_push_char body ( nurl_str_get arg 0 ) ) } {}
                                                } {
                                                    ? == conv 115 {
                                                        : i al ( nurl_str_len arg )
                                                        : i take ? & >= prec 0 < prec al prec al
                                                        ( string_push_bytes body # *u arg take )
                                                    } {
                                                        ? == conv 98 {
                                                            : i _e ( __pf_escape body arg 0 ( nurl_str_len arg ) )
                                                        } {
                                                            ? | == conv 102 | == conv 101 == conv 103 {
                                                                ( string_push_float body ( nurl_str_to_float arg ) )
                                                            } {
                                                                ( string_push_char body 37 )
                                                                ( string_push_char body conv )
                                                            } } } } } } } } }
                            ? & zero ! left {
                                : i bn ( string_len body )
                                ? > width bn {
                                    : String padded ( string_new )
                                    : ~ i pk - width bn
                                    // A sign keeps its place in front of
                                    // the zeros, as C's %05d does.
                                    : ~ i st 0
                                    ? > bn 0 {
                                        : i c0 ( string_get body 0 )
                                        ? | == c0 45 | == c0 43 == c0 32 {
                                            ( string_push_char padded c0 )
                                            = st 1
                                        } {}
                                    } {}
                                    ~ > pk 0 { ( string_push_char padded 48 ) = pk - pk 1 }
                                    ( string_push_bytes padded # *u + # i ( string_data body ) st - bn st )
                                    ( string_clear body )
                                    ( string_push_bytes body # *u ( string_data padded ) ( string_len padded ) )
                                    ( string_free padded )
                                } {}
                            } {}
                            ( __pf_pad out width left body )
                            ( string_free body )
                            ? consumed { = ai + ai 1 } {}
                            = i + k 1
                        }
                    }
                } {
                    ( string_push_char out c )
                    = i + i 1
                }
            }
        }
        // POSIX: while arguments remain, the format is reused.
        ? & < ai n > ( __pf_conversions fmt ) 0 { = again T } {}
    }
    ( bx_write out )
    ( string_free out )
    ^ 0
}

// How many argument-consuming conversions the format has — zero means
// reusing it would loop forever.
@ __pf_conversions s fmt → i {
    : i n ( nurl_str_len fmt )
    : ~ i i 0
    : ~ i k 0
    ~ < i n {
        ? == ( nurl_str_get fmt i ) 37 {
            ? & < + i 1 n == ( nurl_str_get fmt + i 1 ) 37 { = i + i 1 } { = k + k 1 }
        } {}
        = i + i 1
    }
    ^ k
}

// ── sleep / usleep ────────────────────────────────────────────────

@ ap_sleep ( Vec String ) argv → i {
    : i n ( vec_len [String] argv )
    ? < n 2 {
        ( bx_err `missing operand` )
        ^ 1
    } {}
    : ~ f total 0.0
    : ~ i i 1
    : ~ i rc 0
    ~ < i n {
        : s a ( bx_at argv i )
        : i al ( nurl_str_len a )
        : i last ? > al 0 ( nurl_str_get a - al 1 ) 0
        : ~ f mult 1.0
        : ~ i cut al
        ? == last 115 { = cut - al 1 } {}
        ? == last 109 { = mult 60.0 = cut - al 1 } {}
        ? == last 104 { = mult 3600.0 = cut - al 1 } {}
        ? == last 100 { = mult 86400.0 = cut - al 1 } {}
        : s num ( nurl_str_slice a 0 cut )
        ? == ( nurl_str_len num ) 0 {
            ( bx_err_at a `invalid number` )
            = rc 1
        } {
            = total + total * ( nurl_str_to_float num ) mult
        }
        = i + i 1
    }
    ? == rc 0 { ( sleep_ms # i * total 1000.0 ) } {}
    ^ rc
}

@ ap_usleep ( Vec String ) argv → i {
    ? < ( vec_len [String] argv ) 2 {
        ( bx_err `missing operand` )
        ^ 1
    } {}
    : i us ( nurl_str_to_int ( bx_at argv 1 ) )
    ( sleep_ms / us 1000 )
    ^ 0
}

// ── uname / arch / hostname ───────────────────────────────────────

@ __uname_or ? String o s dflt → String {
    ?? o {
        T s0 → { ^ s0 }
        F _ → { ^ ( string_from dflt ) }
    }
}

@ ap_uname ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `asnrvmpioA` `all=a,kernel-name=s,nodename=n,kernel-release=r,kernel-version=v,machine=m,processor=p,hardware-platform=i,operating-system=o` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : b all ( bx_has o `a` )
        : ~ b any F
        ? | all ( bx_has o `s` ) { = any T } {}
        ? | ( bx_has o `n` ) | ( bx_has o `r` ) | ( bx_has o `v` ) | ( bx_has o `m` ) | ( bx_has o `p` ) | ( bx_has o `i` ) ( bx_has o `o` ) { = any T } {}
        // Bare `uname` is `uname -s`.
        : b want_s | all | ( bx_has o `s` ) ! any
        : String out ( string_new )
        ? want_s {
            : String v ( __uname_or ( sys_uname_field SYS_SYSNAME ) `unknown` )
            ( string_push_bytes out # *u ( string_data v ) ( string_len v ) )
            ( string_free v )
        } {}
        ? | all ( bx_has o `n` ) {
            ? > ( string_len out ) 0 { ( string_push_char out 32 ) } {}
            : String v ( __uname_or ( sys_uname_field SYS_NODENAME ) `unknown` )
            ( string_push_bytes out # *u ( string_data v ) ( string_len v ) )
            ( string_free v )
        } {}
        ? | all ( bx_has o `r` ) {
            ? > ( string_len out ) 0 { ( string_push_char out 32 ) } {}
            : String v ( __uname_or ( sys_uname_field SYS_RELEASE ) `unknown` )
            ( string_push_bytes out # *u ( string_data v ) ( string_len v ) )
            ( string_free v )
        } {}
        ? | all ( bx_has o `v` ) {
            ? > ( string_len out ) 0 { ( string_push_char out 32 ) } {}
            : String v ( __uname_or ( sys_uname_field SYS_VERSION ) `unknown` )
            ( string_push_bytes out # *u ( string_data v ) ( string_len v ) )
            ( string_free v )
        } {}
        ? | all ( bx_has o `m` ) {
            ? > ( string_len out ) 0 { ( string_push_char out 32 ) } {}
            : String v ( __uname_or ( sys_uname_field SYS_MACHINE ) `unknown` )
            ( string_push_bytes out # *u ( string_data v ) ( string_len v ) )
            ( string_free v )
        } {}
        ? ( bx_has o `p` ) {
            ? > ( string_len out ) 0 { ( string_push_char out 32 ) } {}
            ( string_push_str out `unknown` )
        } {}
        ? ( bx_has o `i` ) {
            ? > ( string_len out ) 0 { ( string_push_char out 32 ) } {}
            ( string_push_str out `unknown` )
        } {}
        ? | all ( bx_has o `o` ) {
            ? > ( string_len out ) 0 { ( string_push_char out 32 ) } {}
            ( string_push_str out `GNU/Linux` )
        } {}
        ( string_push_char out 10 )
        ( bx_write out )
        ( string_free out )
    }
    ( bx_opts_free o )
    ^ rc
}

@ ap_arch ( Vec String ) argv → i {
    : String v ( __uname_or ( sys_uname_field SYS_MACHINE ) `unknown` )
    ( nurl_print ( string_data v ) )
    ( nurl_print `\n` )
    ( string_free v )
    ^ 0
}

@ ap_hostname ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `sifd` `short=s` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : String h ( __uname_or ( sys_hostname ) `unknown` )
        ? | ( bx_has o `s` ) ( bx_has o `d` ) {
            : i dot ( nurl_str_find ( string_data h ) `.` )
            ? > dot 0 {
                ? ( bx_has o `s` ) {
                    : String sh ( string_substr h 0 dot )
                    ( nurl_print ( string_data sh ) )
                    ( string_free sh )
                } {
                    : String dm ( string_substr h + dot 1 - ( string_len h ) + dot 1 )
                    ( nurl_print ( string_data dm ) )
                    ( string_free dm )
                }
            } {
                ? ( bx_has o `s` ) { ( nurl_print ( string_data h ) ) } {}
            }
        } {
            ( nurl_print ( string_data h ) )
        }
        ( nurl_print `\n` )
        ( string_free h )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── whoami / id / groups / logname ────────────────────────────────

@ __name_of_uid i uid → String {
    ?? ( fs_user_name uid ) {
        T n → { ^ n }
        F _ → { ^ ( string_from ( nurl_str_int uid ) ) }
    }
}

@ __name_of_gid i gid → String {
    ?? ( fs_group_name gid ) {
        T n → { ^ n }
        F _ → { ^ ( string_from ( nurl_str_int gid ) ) }
    }
}

@ ap_whoami ( Vec String ) argv → i {
    : String n ( __name_of_uid # i ( geteuid ) )
    ( nurl_print ( string_data n ) )
    ( nurl_print `\n` )
    ( string_free n )
    ^ 0
}

@ ap_logname ( Vec String ) argv → i {
    ?? ( env_get `LOGNAME` ) {
        T v → {
            ( nurl_print ( string_data v ) )
            ( nurl_print `\n` )
            ( string_free v )
            ^ 0
        }
        F _ → {}
    }
    ^ ( ap_whoami argv )
}

// The caller's supplementary groups, as gids.
@ __group_ids → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : i32 n ( getgroups # i32 0 # *u 0 )
    ? <= # i n 0 { ^ out } {}
    : s buf ( nurl_zalloc * 4 + # i n 1 )
    : i32 got ( getgroups n # *u buf )
    : ~ i k 0
    ~ < k # i got {
        // gid_t is a 32-bit int; read four little-endian bytes.
        : *u p # *u buf
        : i off * k 4
        : i g | | | & 255 # i . p off << & 255 # i . p + off 1 8 << & 255 # i . p + off 2 16 << & 255 # i . p + off 3 24
        ( vec_push [i] out g )
        = k + k 1
    }
    ( nurl_free buf )
    ^ out
}

@ ap_groups ( Vec String ) argv → i {
    // The effective group first, then the supplementary ones — the
    // order every `groups` prints, and not the order getgroups(2)
    // happens to return.
    : i egid # i ( getegid )
    : String primary ( __name_of_gid egid )
    ( nurl_print ( string_data primary ) )
    ( string_free primary )
    : ( Vec i ) gs ( __group_ids )
    : i n ( vec_len [i] gs )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [i] gs k ) {
            T g → {
                ? != g egid {
                    ( nurl_print ` ` )
                    : String nm ( __name_of_gid g )
                    ( nurl_print ( string_data nm ) )
                    ( string_free nm )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( nurl_print `\n` )
    ( vec_free [i] gs )
    ^ 0
}

@ __id_pair String out s label i id → v {
    ( string_push_str out label )
    ( string_push_int out id )
    : String nm ( __name_of_gid id )
    // `1000(wau)` — the number is the fact, the name is the courtesy.
    ? ! ( bx_streq ( string_data nm ) ( nurl_str_int id ) ) {
        ( string_push_char out 40 )
        ( string_push_bytes out # *u ( string_data nm ) ( string_len nm ) )
        ( string_push_char out 41 )
    } {}
    ( string_free nm )
}

@ ap_id ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `ugGnr` `user=u,group=g,groups=G,name=n,real=r` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : b real ( bx_has o `r` )
        : i uid ? real # i ( getuid ) # i ( geteuid )
        : i gid ? real # i ( getgid ) # i ( getegid )
        : b nameform ( bx_has o `n` )
        : String out ( string_new )
        ? ( bx_has o `u` ) {
            ? nameform {
                : String nm ( __name_of_uid uid )
                ( string_push_bytes out # *u ( string_data nm ) ( string_len nm ) )
                ( string_free nm )
            } { ( string_push_int out uid ) }
        } {
            ? ( bx_has o `g` ) {
                ? nameform {
                    : String nm ( __name_of_gid gid )
                    ( string_push_bytes out # *u ( string_data nm ) ( string_len nm ) )
                    ( string_free nm )
                } { ( string_push_int out gid ) }
            } {
                ? ( bx_has o `G` ) {
                    : ( Vec i ) gs ( __group_ids )
                    : i gn ( vec_len [i] gs )
                    : ~ i k 0
                    ~ < k gn {
                        ?? ( vec_get [i] gs k ) {
                            T g → {
                                ? > k 0 { ( string_push_char out 32 ) } {}
                                ? nameform {
                                    : String nm ( __name_of_gid g )
                                    ( string_push_bytes out # *u ( string_data nm ) ( string_len nm ) )
                                    ( string_free nm )
                                } { ( string_push_int out g ) }
                            }
                            F _ → {}
                        }
                        = k + k 1
                    }
                    ( vec_free [i] gs )
                } {
                    : String un ( __name_of_uid uid )
                    ( string_push_str out `uid=` )
                    ( string_push_int out uid )
                    ? ! ( bx_streq ( string_data un ) ( nurl_str_int uid ) ) {
                        ( string_push_char out 40 )
                        ( string_push_bytes out # *u ( string_data un ) ( string_len un ) )
                        ( string_push_char out 41 )
                    } {}
                    ( string_free un )
                    ( string_push_char out 32 )
                    ( __id_pair out `gid=` gid )
                    : ( Vec i ) gs ( __group_ids )
                    : i gn ( vec_len [i] gs )
                    ? > gn 0 {
                        ( string_push_str out ` groups=` )
                        : ~ i k 0
                        ~ < k gn {
                            ?? ( vec_get [i] gs k ) {
                                T g → {
                                    ? > k 0 { ( string_push_char out 44 ) } {}
                                    ( __id_pair out `` g )
                                }
                                F _ → {}
                            }
                            = k + k 1
                        }
                    } {}
                    ( vec_free [i] gs )
                } } }
        ( string_push_char out 10 )
        ( bx_write out )
        ( string_free out )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── nproc ─────────────────────────────────────────────────────────

@ ap_nproc ( Vec String ) argv → i {
    ( nurl_print ( nurl_str_int ( sys_cpu_count ) ) )
    ( nurl_print `\n` )
    ^ 0
}

// ── which ─────────────────────────────────────────────────────────

@ __is_executable s p → b {
    ?? ( fs_stat p ) {
        T st → { ^ & ( stat_is_file st ) != 0 & ( stat_mode_bits st ) 73 }
        F _ → { ^ F }
    }
}

@ ap_which ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `a` `all=a` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : String path ( env_var_or `PATH` `/bin:/usr/bin` )
        : ( Vec String ) dirs ( string_split path `:` )
        : i nd ( vec_len [String] dirs )
        : i nops ( bx_operand_count o )
        : ~ i i 0
        ~ < i nops {
            : s want ( bx_operand o i )
            : ~ b found F
            ? > ( nurl_str_find want `/` ) -1 {
                ? ( __is_executable want ) {
                    ( nurl_print want )
                    ( nurl_print `\n` )
                    = found T
                } {}
            } {
                : ~ i d 0
                ~ < d nd {
                    ? | ! found ( bx_has o `a` ) {
                        : String full ( path_join ( bx_at dirs d ) want )
                        ? ( __is_executable ( string_data full ) ) {
                            ( nurl_print ( string_data full ) )
                            ( nurl_print `\n` )
                            = found T
                        } {}
                        ( string_free full )
                    } {}
                    = d + d 1
                }
            }
            ? ! found { = rc 1 } {}
            = i + i 1
        }
        ( vec_free_with [String] dirs \ String x → v { ( string_free x ) } )
        ( string_free path )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── date ──────────────────────────────────────────────────────────

// %Z, %z, %s and %N need the instant, not the calendar, so they are
// substituted here and the rest handed to `time_format`.
@ __date_prepass s fmt i epoch b utc → String {
    : String out ( string_new )
    : i n ( nurl_str_len fmt )
    : i off ? utc 0 ( tz_offset epoch )
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get fmt i )
        ? & == c 37 < + i 1 n {
            : i d ( nurl_str_get fmt + i 1 )
            ? == d 90 {
                ? utc { ( string_push_str out `UTC` ) } {
                    ?? ( tz_name epoch ) {
                        T z → {
                            ( string_push_bytes out # *u ( string_data z ) ( string_len z ) )
                            ( string_free z )
                        }
                        F _ → { ( string_push_str out `UTC` ) }
                    }
                }
                = i + i 2
            } {
                ? == d 122 {
                    : i mins / ? < off 0 - 0 off off 60
                    ( string_push_char out ? < off 0 45 43 )
                    : i hh / mins 60
                    : i mm - mins * hh 60
                    ? < hh 10 { ( string_push_char out 48 ) } {}
                    ( string_push_int out hh )
                    ? < mm 10 { ( string_push_char out 48 ) } {}
                    ( string_push_int out mm )
                    = i + i 2
                } {
                    ? == d 115 {
                        ( string_push_int out epoch )
                        = i + i 2
                    } {
                        ? == d 78 {
                            ( string_push_str out `000000000` )
                            = i + i 2
                        } {
                            ( string_push_char out c )
                            ( string_push_char out d )
                            = i + i 2
                        } } } }
        } {
            ( string_push_char out c )
            = i + i 1
        }
    }
    ^ out
}

@ ap_date ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `uRd:r:` `utc=u,universal=u,rfc-2822=R,date=d,reference=r` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ~ i epoch ( now_seconds )
        ? ( bx_has o `r` ) {
            ?? ( fs_stat ( bx_val o `r` ) ) {
                T st → { = epoch . st mtime }
                F e → {
                    ( bx_err_at ( bx_val o `r` ) ( bx_ioerr e ) )
                    = rc 1
                }
            }
        } {}
        ? ( bx_has o `d` ) {
            ?? ( time_parse_iso ( bx_val o `d` ) ) {
                T secs → { = epoch secs }
                F _ → {
                    ( bx_err_at ( bx_val o `d` ) `invalid date` )
                    = rc 1
                }
            }
        } {}
        ? == rc 0 {
            : b utc ( bx_has o `u` )
            // A leading `+` operand is the format; busybox and coreutils
            // both spell it that way.
            : String fmt ( string_from `%a %b %e %H:%M:%S %Z %Y` )
            ? ( bx_has o `R` ) {
                ( string_clear fmt )
                ( string_push_str fmt `%a, %d %b %Y %H:%M:%S %z` )
            } {}
            ? > ( bx_operand_count o ) 0 {
                : s op ( bx_operand o 0 )
                ? == ( nurl_str_get op 0 ) 43 {
                    ( string_clear fmt )
                    ( string_push_str fmt ( nurl_str_slice op 1 - ( nurl_str_len op ) 1 ) )
                } {}
            } {}
            : String pre ( __date_prepass ( string_data fmt ) epoch utc )
            : Time t ? utc ( time_from_unix epoch ) ( time_local epoch )
            : String txt ( time_format t ( string_data pre ) )
            ( bx_write txt )
            ( nurl_print `\n` )
            ( string_free txt )
            ( string_free pre )
            ( string_free fmt )
        } {}
    }
    ( bx_opts_free o )
    ^ rc
}

// ── sync / clear / tty ────────────────────────────────────────────

@ ap_sync ( Vec String ) argv → i {
    ( flush )
    : i nops - ( vec_len [String] argv ) 1
    : ~ i i 1
    ~ <= i nops {
        ?? ( file_open ( bx_at argv i ) ) {
            T f → {
                ?? ( file_sync f ) { T _ → {} F _ → {} }
                ( file_close f )
            }
            F e → { ( bx_err_at ( bx_at argv i ) ( bx_ioerr e ) ) }
        }
        = i + i 1
    }
    ^ 0
}

@ ap_clear ( Vec String ) argv → i {
    // ESC [ H  — home; ESC [ 2J — erase screen; ESC [ 3J — erase the
    // scrollback, which is what makes `clear` clear rather than scroll.
    : String out ( string_new )
    ( string_push_char out 27 )
    ( string_push_str out `[H` )
    ( string_push_char out 27 )
    ( string_push_str out `[2J` )
    ( string_push_char out 27 )
    ( string_push_str out `[3J` )
    ( bx_write out )
    ( string_free out )
    ( flush )
    ^ 0
}

@ ap_tty ( Vec String ) argv → i {
    ? ( term_is_tty 0 ) {
        ( nurl_print `/dev/tty\n` )
        ^ 0
    } {}
    ( nurl_print `not a tty\n` )
    ^ 1
}
