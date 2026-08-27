// nurlbox/find.nu — walking a tree: stat, du, find.
//
// All three walk with `fs_lstat`, never `fs_stat`: a walk that follows
// symlinks visits whatever they point at, which turns `du` into a
// double-count and `find -delete` into a way to lose files outside the
// tree you named.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/std/time.nu`
$ `bx.nu`

// ── stat ──────────────────────────────────────────────────────────

@ __stat_kind_word i mode → s {
    : i k ( nurl_stat_kind mode )
    ? == k FS_KIND_DIR { ^ `directory` } {}
    ? == k FS_KIND_SYMLINK { ^ `symbolic link` } {}
    ? == k FS_KIND_CHARDEV { ^ `character special file` } {}
    ? == k FS_KIND_BLOCKDEV { ^ `block special file` } {}
    ? == k FS_KIND_FIFO { ^ `fifo` } {}
    ? == k FS_KIND_SOCKET { ^ `socket` } {}
    ? == k FS_KIND_FILE { ^ `regular file` } {}
    ^ `unknown`
}

@ __stat_octal String out i v i digits → v {
    : ~ i k digits
    ~ > k 0 {
        : i shift * - k 1 3
        ( string_push_char out + 48 & 7 >> v shift )
        = k - k 1
    }
}

@ __stat_hex String out i v → v {
    ? == v 0 { ( string_push_char out 48 ) ^ } {}
    : String tmp ( string_with_cap 16 )
    : ~ i x v
    ~ != x 0 {
        ( string_push_char tmp ( nurl_str_get `0123456789abcdef` & x 15 ) )
        = x >> x 4
    }
    : ~ i k ( string_len tmp )
    ~ > k 0 {
        ( string_push_char out ( string_get tmp - k 1 ) )
        = k - k 1
    }
    ( string_free tmp )
}

@ __stat_name_of i id b group → String {
    : ?String r ? group ( fs_group_name id ) ( fs_user_name id )
    ?? r {
        T n → { ^ n }
        F _ → { ^ ( string_from `UNKNOWN` ) }
    }
}

// The `%`-directives `stat -c` understands.
@ __stat_directive String out FileStat st s path i d → b {
    ? == d 110 { ( string_push_str out path ) ^ T } {}
    ? == d 115 { ( string_push_int out . st size ) ^ T } {}
    ? == d 98 { ( string_push_int out . st blocks ) ^ T } {}
    ? == d 66 { ( string_push_int out 512 ) ^ T } {}
    ? == d 111 { ( string_push_int out . st blksize ) ^ T } {}
    ? == d 102 { ( __stat_hex out . st mode ) ^ T } {}
    // Three octal digits normally, four when setuid/setgid/sticky is
    // set — printing a leading 0 that is always 0 helps nobody.
    ? == d 97 { ( __stat_octal out ( stat_mode_bits st ) ? != 0 & . st mode 3584 4 3 ) ^ T } {}
    ? == d 65 {
        : String m ( stat_mode_string st )
        ( string_push_bytes out # *u ( string_data m ) ( string_len m ) )
        ( string_free m )
        ^ T
    } {}
    ? == d 117 { ( string_push_int out . st uid ) ^ T } {}
    ? == d 103 { ( string_push_int out . st gid ) ^ T } {}
    ? == d 85 {
        : String n ( __stat_name_of . st uid F )
        ( string_push_bytes out # *u ( string_data n ) ( string_len n ) )
        ( string_free n )
        ^ T
    } {}
    ? == d 71 {
        : String n ( __stat_name_of . st gid T )
        ( string_push_bytes out # *u ( string_data n ) ( string_len n ) )
        ( string_free n )
        ^ T
    } {}
    ? == d 104 { ( string_push_int out . st nlink ) ^ T } {}
    ? == d 105 { ( string_push_int out . st ino ) ^ T } {}
    ? == d 100 { ( string_push_int out . st dev ) ^ T } {}
    ? == d 70 { ( string_push_str out ( __stat_kind_word . st mode ) ) ^ T } {}
    ? == d 88 { ( string_push_int out . st atime ) ^ T } {}
    ? == d 89 { ( string_push_int out . st mtime ) ^ T } {}
    ? == d 90 { ( string_push_int out . st ctime ) ^ T } {}
    ^ F
}

@ __stat_timestamp String out i secs i nsec → v {
    : Time t ( time_local secs )
    : String base ( time_format t `%Y-%m-%d %H:%M:%S` )
    ( string_push_bytes out # *u ( string_data base ) ( string_len base ) )
    ( string_free base )
    ( string_push_char out 46 )
    : ~ i k 100000000
    ~ > k 0 {
        ( string_push_char out + 48 % / nsec k 10 )
        = k / k 10
    }
    ( string_push_char out 32 )
    : i off ( tz_offset secs )
    ( string_push_char out ? < off 0 45 43 )
    : i mins / ? < off 0 - 0 off off 60
    : i hh / mins 60
    : i mm - mins * hh 60
    ? < hh 10 { ( string_push_char out 48 ) } {}
    ( string_push_int out hh )
    ? < mm 10 { ( string_push_char out 48 ) } {}
    ( string_push_int out mm )
}

@ __stat_default String out FileStat st s path → v {
    ( string_push_str out `  File: ` )
    ( string_push_str out path )
    ? ( stat_is_symlink st ) {
        ?? ( fs_readlink path ) {
            T t → {
                ( string_push_str out ` -> ` )
                ( string_push_bytes out # *u ( string_data t ) ( string_len t ) )
                ( string_free t )
            }
            F _ → {}
        }
    } {}
    ( string_push_str out `\n  Size: ` )
    : String sz ( string_from ( nurl_str_int . st size ) )
    ( string_push_bytes out # *u ( string_data sz ) ( string_len sz ) )
    : ~ i pad - 10 ( string_len sz )
    ( string_free sz )
    ~ > pad 0 { ( string_push_char out 32 ) = pad - pad 1 }
    ( string_push_str out `\tBlocks: ` )
    : String bl ( string_from ( nurl_str_int . st blocks ) )
    ( string_push_bytes out # *u ( string_data bl ) ( string_len bl ) )
    : ~ i pad2 - 11 ( string_len bl )
    ( string_free bl )
    ~ > pad2 0 { ( string_push_char out 32 ) = pad2 - pad2 1 }
    ( string_push_str out `IO Block: ` )
    : String io ( string_from ( nurl_str_int . st blksize ) )
    ( string_push_bytes out # *u ( string_data io ) ( string_len io ) )
    : ~ i pad3 - 7 ( string_len io )
    ( string_free io )
    ~ > pad3 0 { ( string_push_char out 32 ) = pad3 - pad3 1 }
    ( string_push_str out ( __stat_kind_word . st mode ) )
    ( string_push_str out `\nDevice: ` )
    ( __stat_hex out . st dev )
    ( string_push_str out `h/` )
    ( string_push_int out . st dev )
    ( string_push_str out `d\tInode: ` )
    : String ino ( string_from ( nurl_str_int . st ino ) )
    ( string_push_bytes out # *u ( string_data ino ) ( string_len ino ) )
    : ~ i pad4 - 12 ( string_len ino )
    ( string_free ino )
    ~ > pad4 0 { ( string_push_char out 32 ) = pad4 - pad4 1 }
    ( string_push_str out `Links: ` )
    ( string_push_int out . st nlink )
    ( string_push_str out `\nAccess: (` )
    ( __stat_octal out ( stat_mode_bits st ) 4 )
    ( string_push_char out 47 )
    : String ms ( stat_mode_string st )
    ( string_push_bytes out # *u ( string_data ms ) ( string_len ms ) )
    ( string_free ms )
    ( string_push_str out `)  Uid: (` )
    : String uid ( string_from ( nurl_str_int . st uid ) )
    : ~ i up - 5 ( string_len uid )
    ~ > up 0 { ( string_push_char out 32 ) = up - up 1 }
    ( string_push_bytes out # *u ( string_data uid ) ( string_len uid ) )
    ( string_free uid )
    ( string_push_char out 47 )
    : String un ( __stat_name_of . st uid F )
    : ~ i unp - 8 ( string_len un )
    ~ > unp 0 { ( string_push_char out 32 ) = unp - unp 1 }
    ( string_push_bytes out # *u ( string_data un ) ( string_len un ) )
    ( string_free un )
    ( string_push_str out `)   Gid: (` )
    : String gid ( string_from ( nurl_str_int . st gid ) )
    : ~ i gp - 5 ( string_len gid )
    ~ > gp 0 { ( string_push_char out 32 ) = gp - gp 1 }
    ( string_push_bytes out # *u ( string_data gid ) ( string_len gid ) )
    ( string_free gid )
    ( string_push_char out 47 )
    : String gn ( __stat_name_of . st gid T )
    : ~ i gnp - 8 ( string_len gn )
    ~ > gnp 0 { ( string_push_char out 32 ) = gnp - gnp 1 }
    ( string_push_bytes out # *u ( string_data gn ) ( string_len gn ) )
    ( string_free gn )
    ( string_push_str out `)\nAccess: ` )
    ( __stat_timestamp out . st atime . st atime_ns )
    ( string_push_str out `\nModify: ` )
    ( __stat_timestamp out . st mtime . st mtime_ns )
    ( string_push_str out `\nChange: ` )
    ( __stat_timestamp out . st ctime . st ctime_ns )
    ( string_push_char out 10 )
}

@ ap_stat ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `c:Lt` `format=c,dereference=L,terse=t` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? == nops 0 {
            ( bx_err `missing operand` )
            = rc 1
        } {}
        : ~ i i 0
        ~ < i nops {
            : s p ( bx_operand o i )
            : !FileStat IoErr r ? ( bx_has o `L` ) ( fs_stat p ) ( fs_lstat p )
            ?? r {
                F e → {
                    ( bx_err_at p ( bx_ioerr e ) )
                    = rc 1
                }
                T st → {
                    : String out ( string_new )
                    ? ( bx_has o `c` ) {
                        : s fmt ( bx_val o `c` )
                        : i fl ( nurl_str_len fmt )
                        : ~ i k 0
                        ~ < k fl {
                            : i c ( nurl_str_get fmt k )
                            ? & == c 37 < + k 1 fl {
                                ? ( __stat_directive out st p ( nurl_str_get fmt + k 1 ) ) {} {
                                    ( string_push_char out 37 )
                                    ( string_push_char out ( nurl_str_get fmt + k 1 ) )
                                }
                                = k + k 2
                            } {
                                ? & == c 92 < + k 1 fl {
                                    : i e2 ( nurl_str_get fmt + k 1 )
                                    ? == e2 110 { ( string_push_char out 10 ) } {
                                        ? == e2 116 { ( string_push_char out 9 ) } {
                                            ( string_push_char out 92 )
                                            ( string_push_char out e2 )
                                        } }
                                    = k + k 2
                                } {
                                    ( string_push_char out c )
                                    = k + k 1
                                }
                            }
                        }
                        ( string_push_char out 10 )
                    } {
                        ( __stat_default out st p )
                    }
                    ( bx_write out )
                    ( string_free out )
                }
            }
            = i + i 1
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── du ────────────────────────────────────────────────────────────

: i DU_ALL 1
: i DU_SUMMARY 2
: i DU_HUMAN 4
: i DU_BYTES 8
: i DU_MEGA 16
: i DU_TOTAL 32

@ __du_emit s path i bytes_512 i flags → v {
    : String out ( string_new )
    ? != 0 & flags DU_HUMAN {
        : String h ( bx_human * bytes_512 512 )
        ( string_push_bytes out # *u ( string_data h ) ( string_len h ) )
        ( string_free h )
    } {
        ? != 0 & flags DU_BYTES {
            ( string_push_int out * bytes_512 512 )
        } {
            ? != 0 & flags DU_MEGA {
                ( string_push_int out / + bytes_512 2047 2048 )
            } {
                ( string_push_int out / bytes_512 2 )
            }
        }
    }
    ( string_push_char out 9 )
    ( string_push_str out path )
    ( string_push_char out 10 )
    ( bx_write out )
    ( string_free out )
}

// Returns the subtree's size in 512-byte blocks; prints as it goes.
@ __du_walk s path i flags i depth i maxdepth inout i rc → i {
    ?? ( fs_lstat path ) {
        F e → {
            ( bx_err_at path ( bx_ioerr e ) )
            = rc 1
            ^ 0
        }
        T st → {
            ? ! ( stat_is_dir st ) {
                : i blocks . st blocks
                ? & != 0 & flags DU_ALL <= depth maxdepth {
                    ( __du_emit path blocks flags )
                } {}
                ^ blocks
            } {}
            : ~ i total . st blocks
            ?? ( dir_list path ) {
                T names → {
                    : i n ( vec_len [String] names )
                    : ~ i k 0
                    ~ < k n {
                        : String sub ( path_join path ( bx_at names k ) )
                        = total + total ( __du_walk ( string_data sub ) flags + depth 1 maxdepth rc )
                        ( string_free sub )
                        = k + k 1
                    }
                    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
                }
                F e2 → {
                    ( bx_err_at path ( bx_ioerr e2 ) )
                    = rc 1
                }
            }
            ? <= depth maxdepth { ( __du_emit path total flags ) } {}
            ^ total
        }
    }
}

@ ap_du ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `ashkmcbd:xL` `all=a,summarize=s,human-readable=h,total=c,bytes=b,max-depth=d` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ~ i flags 0
        ? ( bx_has o `a` ) { = flags | flags DU_ALL } {}
        ? ( bx_has o `s` ) { = flags | flags DU_SUMMARY } {}
        ? ( bx_has o `h` ) { = flags | flags DU_HUMAN } {}
        ? ( bx_has o `b` ) { = flags | flags DU_BYTES } {}
        ? ( bx_has o `m` ) { = flags | flags DU_MEGA } {}
        ? ( bx_has o `c` ) { = flags | flags DU_TOTAL } {}
        : ~ i maxdepth 1000000
        ? != 0 & flags DU_SUMMARY { = maxdepth 0 } {}
        ? ( bx_has o `d` ) { = maxdepth ( nurl_str_to_int ( bx_val o `d` ) ) } {}
        : i nops ( bx_operand_count o )
        : ~ i grand 0
        ? == nops 0 {
            = grand ( __du_walk `.` flags 0 maxdepth rc )
        } {
            : ~ i i 0
            ~ < i nops {
                = grand + grand ( __du_walk ( bx_operand o i ) flags 0 maxdepth rc )
                = i + i 1
            }
        }
        ? != 0 & flags DU_TOTAL { ( __du_emit `total` grand flags ) } {}
    }
    ( bx_opts_free o )
    ^ rc
}

// ── find ──────────────────────────────────────────────────────────
//
// A real expression evaluator, not a flag list: `-a` / `-o` / `!` /
// parentheses with POSIX precedence and POSIX short-circuiting, so
// `find . -name '*.tmp' -a -delete` deletes only what matched and
// `find . -type d -o -print` prints only what is not a directory.
//
// The expression is re-walked per visited entry rather than compiled
// into a tree first. That costs a few token comparisons against a stat
// call and a directory read, and it keeps the evaluator one function
// deep — the shape that makes short-circuiting obviously correct.

$ `stdlib/core/posix.nu`

: FindCtx {
    s path
    s name
    i mode
    i size
    i mtime
    i depth
    b live  // F while inside a short-circuited branch: no actions run
}

// The parser cursor. find parses one expression at a time in one
// thread, so a cursor global is simpler than threading `inout i pos`
// through four mutually-recursive functions.
: ~ i g_find_pos 0
: ~ i g_find_maxdepth 1000000
: ~ i g_find_mindepth 0
: ~ b g_find_has_action F
: ~ b g_find_depth_first F
: ~ b g_find_prune F
: ~ i g_find_rc 0

@ __find_tok ( Vec String ) toks i idx → s { ^ ( bx_at toks idx ) }

@ __find_at_end ( Vec String ) toks → b { ^ >= g_find_pos ( vec_len [String] toks ) }

// A size operand: `[+-]N[cwbkMG]`. Returns the comparison in `cmp`
// (-1 less, 0 exact, 1 greater) and the value in units of `unit`.
@ __find_num s text → i {
    : i n ( nurl_str_len text )
    : ~ i i 0
    ? & > n 0 | == ( nurl_str_get text 0 ) 43 == ( nurl_str_get text 0 ) 45 { = i 1 } {}
    : ~ i v 0
    ~ & < i n ( bx_is_digit ( nurl_str_get text i ) ) {
        = v + * v 10 - ( nurl_str_get text i ) 48
        = i + i 1
    }
    ^ v
}

@ __find_cmpdir s text → i {
    ? == ( nurl_str_len text ) 0 { ^ 0 } {}
    ? == ( nurl_str_get text 0 ) 43 { ^ 1 } {}
    ? == ( nurl_str_get text 0 ) 45 { ^ -1 } {}
    ^ 0
}

@ __find_compare i have i want i dir → b {
    ? > dir 0 { ^ > have want } {}
    ? < dir 0 { ^ < have want } {}
    ^ == have want
}

@ __find_type_char i mode i c → b {
    : i k ( nurl_stat_kind mode )
    ? == c 102 { ^ == k FS_KIND_FILE } {}
    ? == c 100 { ^ == k FS_KIND_DIR } {}
    ? == c 108 { ^ == k FS_KIND_SYMLINK } {}
    ? == c 98 { ^ == k FS_KIND_BLOCKDEV } {}
    ? == c 99 { ^ == k FS_KIND_CHARDEV } {}
    ? == c 112 { ^ == k FS_KIND_FIFO } {}
    ? == c 115 { ^ == k FS_KIND_SOCKET } {}
    ^ F
}

// -exec CMD ... {} \;  — a real fork + exec, so the child writes to the
// terminal itself instead of having its output captured and replayed
// out of order.
@ __find_exec ( Vec String ) toks i from i to s path → b {
    : i n - to from
    ? <= n 0 { ^ F } {}
    ( flush )
    : i32 pid ( fork )
    ? == # i pid 0 {
        : s argvbuf ( nurl_zalloc * 8 + n 1 )
        : ~ i k 0
        ~ < k n {
            : s t ( __find_tok toks + from k )
            ( nurl_poke argvbuf k # i ? ( bx_streq t `{}` ) path t )
            = k + k 1
        }
        : i32 _r ( execvp # s ( nurl_peek argvbuf 0 ) # *u argvbuf )
        ( _exit # i32 127 )
        ^ F
    } {}
    ? < # i pid 0 { ^ F } {}
    : s statusbuf ( nurl_zalloc 8 )
    : i32 _w ( waitpid pid # *u statusbuf # i32 0 )
    : i raw ( nurl_peek statusbuf 0 )
    ( nurl_free statusbuf )
    ^ == 0 ( nurl_wait_exit_status & raw 65535 )
}

@ __find_print s path i term → v {
    : String out ( string_new )
    ( string_push_str out path )
    ( string_push_char out term )
    ( bx_write out )
    ( string_free out )
}

// One primary. Advances g_find_pos past it.
@ __find_prim ( Vec String ) toks FindCtx c → b {
    : s t ( __find_tok toks g_find_pos )
    = g_find_pos + g_find_pos 1
    ? ( bx_streq t `-name` ) {
        : s pat ( __find_tok toks g_find_pos )
        = g_find_pos + g_find_pos 1
        ^ ( fs_match pat . c name )
    } {}
    ? ( bx_streq t `-iname` ) {
        : s pat ( __find_tok toks g_find_pos )
        = g_find_pos + g_find_pos 1
        : String lp ( string_to_lower ( string_from pat ) )
        : String ln ( string_to_lower ( string_from . c name ) )
        : b r ( fs_match ( string_data lp ) ( string_data ln ) )
        ( string_free lp )
        ( string_free ln )
        ^ r
    } {}
    ? ( bx_streq t `-path` ) {
        : s pat ( __find_tok toks g_find_pos )
        = g_find_pos + g_find_pos 1
        ^ ( fs_match pat . c path )
    } {}
    ? ( bx_streq t `-type` ) {
        : s ty ( __find_tok toks g_find_pos )
        = g_find_pos + g_find_pos 1
        ^ ( __find_type_char . c mode ( nurl_str_get ty 0 ) )
    } {}
    ? ( bx_streq t `-maxdepth` ) {
        = g_find_maxdepth ( nurl_str_to_int ( __find_tok toks g_find_pos ) )
        = g_find_pos + g_find_pos 1
        ^ T
    } {}
    ? ( bx_streq t `-mindepth` ) {
        = g_find_mindepth ( nurl_str_to_int ( __find_tok toks g_find_pos ) )
        = g_find_pos + g_find_pos 1
        ^ T
    } {}
    ? ( bx_streq t `-size` ) {
        : s spec ( __find_tok toks g_find_pos )
        = g_find_pos + g_find_pos 1
        : i sl ( nurl_str_len spec )
        : i suffix ? > sl 0 ( nurl_str_get spec - sl 1 ) 99
        : i unit ? == suffix 99 1 ? == suffix 119 2 ? == suffix 107 1024 ? == suffix 77 1048576 ? == suffix 71 1073741824 512
        : i want ( __find_num spec )
        // Everything but `c` rounds UP to whole units, which is why
        // `-size 1k` finds a one-byte file.
        : i have ? == unit 1 . c size / + . c size - unit 1 unit
        ^ ( __find_compare have want ( __find_cmpdir spec ) )
    } {}
    ? ( bx_streq t `-empty` ) {
        ? == ( nurl_stat_kind . c mode ) FS_KIND_DIR {
            ?? ( dir_list . c path ) {
                T names → {
                    : b e == 0 ( vec_len [String] names )
                    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
                    ^ e
                }
                F _ → { ^ F }
            }
        } {}
        ^ == . c size 0
    } {}
    ? ( bx_streq t `-newer` ) {
        : s other ( __find_tok toks g_find_pos )
        = g_find_pos + g_find_pos 1
        ?? ( fs_stat other ) {
            T st → { ^ > . c mtime . st mtime }
            F _ → { ^ F }
        }
    } {}
    ? | ( bx_streq t `-mtime` ) ( bx_streq t `-mmin` ) {
        : s spec ( __find_tok toks g_find_pos )
        = g_find_pos + g_find_pos 1
        : i unit ? ( bx_streq t `-mtime` ) 86400 60
        : i age / - ( now_seconds ) . c mtime unit
        ^ ( __find_compare age ( __find_num spec ) ( __find_cmpdir spec ) )
    } {}
    ? ( bx_streq t `-perm` ) {
        : s spec ( __find_tok toks g_find_pos )
        = g_find_pos + g_find_pos 1
        : b exact ! | == ( nurl_str_get spec 0 ) 45 == ( nurl_str_get spec 0 ) 47
        : s bits ? exact spec ( nurl_str_slice spec 1 - ( nurl_str_len spec ) 1 )
        : i want ( bx_parse_mode bits 0 )
        ? < want 0 { ^ F } {}
        : i have & . c mode 4095
        ? exact { ^ == have want } {}
        ? == ( nurl_str_get spec 0 ) 45 { ^ == & have want want } {}
        ^ != 0 & have want
    } {}
    ? ( bx_streq t `-user` ) {
        : s who ( __find_tok toks g_find_pos )
        = g_find_pos + g_find_pos 1
        ?? ( fs_lstat . c path ) {
            T st → {
                : String nm ( __stat_name_of . st uid F )
                : b r | ( bx_streq ( string_data nm ) who ) ( bx_streq ( nurl_str_int . st uid ) who )
                ( string_free nm )
                ^ r
            }
            F _ → { ^ F }
        }
    } {}
    ? ( bx_streq t `-group` ) {
        : s who ( __find_tok toks g_find_pos )
        = g_find_pos + g_find_pos 1
        ?? ( fs_lstat . c path ) {
            T st → {
                : String nm ( __stat_name_of . st gid T )
                : b r | ( bx_streq ( string_data nm ) who ) ( bx_streq ( nurl_str_int . st gid ) who )
                ( string_free nm )
                ^ r
            }
            F _ → { ^ F }
        }
    } {}
    ? ( bx_streq t `-print` ) {
        ? . c live { ( __find_print . c path 10 ) } {}
        ^ T
    } {}
    ? ( bx_streq t `-print0` ) {
        ? . c live { ( __find_print . c path 0 ) } {}
        ^ T
    } {}
    ? ( bx_streq t `-delete` ) {
        ? . c live {
            : ~ b ok T
            ? == ( nurl_stat_kind . c mode ) FS_KIND_DIR {
                ?? ( dir_remove . c path ) { T _ → {} F _ → { = ok F } }
            } {
                ?? ( file_delete . c path ) { T _ → {} F _ → { = ok F } }
            }
            ? ! ok {
                ( bx_err_at . c path `cannot delete` )
                = g_find_rc 1
            } {}
        } {}
        ^ T
    } {}
    ? ( bx_streq t `-prune` ) {
        ? . c live { = g_find_prune T } {}
        ^ T
    } {}
    ? | ( bx_streq t `-exec` ) ( bx_streq t `-execdir` ) {
        : i from g_find_pos
        : ~ i to from
        : i n ( vec_len [String] toks )
        ~ & < to n ! ( bx_streq ( __find_tok toks to ) `;` ) { = to + to 1 }
        = g_find_pos ? < to n + to 1 to
        ? . c live { ^ ( __find_exec toks from to . c path ) } {}
        ^ T
    } {}
    ? ( bx_streq t `-true` ) { ^ T } {}
    ? ( bx_streq t `-false` ) { ^ F } {}
    ? | ( bx_streq t `-depth` ) ( bx_streq t `-d` ) {
        = g_find_depth_first T
        ^ T
    } {}
    ? ( bx_streq t `-follow` ) { ^ T } {}
    ( bx_err_at t `unknown predicate` )
    = g_find_rc 1
    = g_find_pos ( vec_len [String] toks )
    ^ F
}

@ __find_unary ( Vec String ) toks FindCtx c → b {
    : s t ( __find_tok toks g_find_pos )
    ? | ( bx_streq t `!` ) ( bx_streq t `-not` ) {
        = g_find_pos + g_find_pos 1
        ^ ! ( __find_unary toks c )
    } {}
    ? ( bx_streq t `(` ) {
        = g_find_pos + g_find_pos 1
        : b r ( __find_or toks c )
        ? ( bx_streq ( __find_tok toks g_find_pos ) `)` ) { = g_find_pos + g_find_pos 1 } {}
        ^ r
    } {}
    ^ ( __find_prim toks c )
}

@ __find_ends_group ( Vec String ) toks → b {
    ? ( __find_at_end toks ) { ^ T } {}
    : s t ( __find_tok toks g_find_pos )
    ^ | | ( bx_streq t `)` ) ( bx_streq t `-o` ) ( bx_streq t `-or` )
}

@ __find_and ( Vec String ) toks FindCtx c → b {
    : ~ b acc ( __find_unary toks c )
    ~ ! ( __find_ends_group toks ) {
        : s t ( __find_tok toks g_find_pos )
        ? | ( bx_streq t `-a` ) ( bx_streq t `-and` ) { = g_find_pos + g_find_pos 1 } {}
        ? ( __find_ends_group toks ) {} {
            // POSIX short-circuit: the right operand still has to be
            // PARSED (the cursor must land past it) but must not act.
            : FindCtx c2 @ FindCtx { . c path . c name . c mode . c size . c mtime . c depth & . c live acc }
            : b r ( __find_unary toks c2 )
            = acc & acc r
        }
    }
    ^ acc
}

@ __find_or ( Vec String ) toks FindCtx c → b {
    : ~ b acc ( __find_and toks c )
    ~ & ! ( __find_at_end toks ) ! ( bx_streq ( __find_tok toks g_find_pos ) `)` ) {
        : s t ( __find_tok toks g_find_pos )
        ? | ( bx_streq t `-o` ) ( bx_streq t `-or` ) {
            = g_find_pos + g_find_pos 1
            : FindCtx c2 @ FindCtx { . c path . c name . c mode . c size . c mtime . c depth & . c live ! acc }
            : b r ( __find_and toks c2 )
            = acc | acc r
        } { = g_find_pos ( vec_len [String] toks ) }
    }
    ^ acc
}

@ __find_visit ( Vec String ) toks s path s name i depth → v {
    ?? ( fs_lstat path ) {
        F _ → {
            ( bx_err_at path `No such file or directory` )
            = g_find_rc 1
        }
        T st → {
            = g_find_prune F
            : b in_range & >= depth g_find_mindepth <= depth g_find_maxdepth
            : ~ b matched F
            ? in_range {
                : FindCtx c @ FindCtx { path name . st mode . st size . st mtime depth T }
                = g_find_pos 0
                ? > ( vec_len [String] toks ) 0 {
                    = matched ( __find_or toks c )
                } { = matched T }
                // With no action in the expression, a match prints.
                ? & matched ! g_find_has_action { ( __find_print path 10 ) } {}
            } {}
            ? & ( stat_is_dir st ) & < depth g_find_maxdepth ! g_find_prune {
                ?? ( dir_list path ) {
                    T names → {
                        ( sort_by [String] names \ String a String b → i { ^ ( cmp_string a b ) } )
                        : i n ( vec_len [String] names )
                        : ~ i k 0
                        ~ < k n {
                            : String sub ( path_join path ( bx_at names k ) )
                            ( __find_visit toks ( string_data sub ) ( bx_at names k ) + depth 1 )
                            ( string_free sub )
                            = k + k 1
                        }
                        ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
                    }
                    F e → {
                        ( bx_err_at path ( bx_ioerr e ) )
                        = g_find_rc 1
                    }
                }
            } {}
        }
    }
}

@ ap_find ( Vec String ) argv → i {
    = g_find_rc 0
    = g_find_maxdepth 1000000
    = g_find_mindepth 0
    = g_find_has_action F
    = g_find_depth_first F
    : i n ( vec_len [String] argv )
    // Everything before the first `-`/`(`/`!` token is a starting point.
    : ( Vec String ) roots ( vec_new [String] )
    : ( Vec String ) toks ( vec_new [String] )
    : ~ i i 1
    : ~ b in_roots T
    ~ < i n {
        : s t ( bx_at argv i )
        ? in_roots {
            : i tl ( nurl_str_len t )
            ? | | & > tl 0 == ( nurl_str_get t 0 ) 45 ( bx_streq t `(` ) ( bx_streq t `!` ) {
                = in_roots F
            } { ( vec_push [String] roots ( string_from t ) ) }
        } {}
        ? ! in_roots { ( vec_push [String] toks ( string_from t ) ) } {}
        = i + i 1
    }
    ? == ( vec_len [String] roots ) 0 { ( vec_push [String] roots ( string_from `.` ) ) } {}
    // An expression that acts needs no implicit -print.
    : i tn ( vec_len [String] toks )
    : ~ i k 0
    ~ < k tn {
        : s t ( bx_at toks k )
        ? | | | ( bx_streq t `-print` ) ( bx_streq t `-print0` ) ( bx_streq t `-delete` ) | ( bx_streq t `-exec` ) ( bx_streq t `-execdir` ) {
            = g_find_has_action T
        } {}
        = k + k 1
    }
    : i rn ( vec_len [String] roots )
    : ~ i r 0
    ~ < r rn {
        : s root ( bx_at roots r )
        : String base ( path_basename root )
        ( __find_visit toks root ( string_data base ) 0 )
        ( string_free base )
        = r + r 1
    }
    ( vec_free_with [String] roots \ String x → v { ( string_free x ) } )
    ( vec_free_with [String] toks \ String x → v { ( string_free x ) } )
    ^ g_find_rc
}
