// nurlbox/fileops.nu — the applets that touch the filesystem.
//
// ls / stat / mkdir / rmdir / rm / cp / mv / ln / touch / readlink /
// realpath / truncate / chmod / mktemp.
//
// Everything here goes through `fs_lstat` rather than `fs_stat` when it
// walks: a recursive remove or copy that follows a symlink leaves the
// tree it was given, which is the difference between deleting a
// directory and deleting whatever it happened to point at.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/term.nu`
$ `stdlib/ext/env.nu`
$ `bx.nu`

// ── A directory entry, with the metadata a listing needs ──────────

: BxEnt {
    String name
    i mode
    i size
    i mtime
    i nlink
    i uid
    i gid
    i blocks
    i ino
    b ok  // F when the entry could not be stat'ed at all
}

@ __ent_free BxEnt e → v { ( string_free . e name ) }

@ __ent_of s dir s name b follow → BxEnt {
    : String full ? == ( nurl_str_len dir ) 0 ( string_from name ) ( path_join dir name )
    : ~ BxEnt out @ BxEnt { ( string_from name ) 0 0 0 0 0 0 0 0 F }
    : !FileStat IoErr r ? follow ( fs_stat ( string_data full ) ) ( fs_lstat ( string_data full ) )
    ?? r {
        T st → {
            = out @ BxEnt {
                ( string_from name ) . st mode . st size . st mtime . st nlink
                . st uid . st gid . st blocks . st ino T
            }
        }
        F _ → {}
    }
    ( string_free full )
    ^ out
}

// ── ls ────────────────────────────────────────────────────────────

: i LS_ALL 1  // -a
: i LS_LONG 2  // -l
: i LS_ONE 4  // -1
: i LS_DIRS 8  // -d
: i LS_REVERSE 16  // -r
: i LS_TIME 32  // -t
: i LS_SIZE_SORT 64  // -S
: i LS_RECURSE 128  // -R
: i LS_ALMOST 256  // -A
: i LS_CLASSIFY 512  // -F
: i LS_INODE 1024  // -i
: i LS_HUMAN 2048  // -h
: i LS_NUMERIC 4096  // -n
: i LS_BLOCKS 8192  // -s
: i LS_SLASH 16384  // -p
: i LS_COLUMNS 32768  // -C / a tty

// 1024-based sizes the way `-h` prints them: 4.0K, 1.5M, 12G.
@ bx_human i n → String {
    : String out ( string_new )
    ? < n 1024 {
        ( string_push_int out n )
        ^ out
    } {}
    : s units `KMGTPE`
    : ~ i v n
    : ~ i unit -1
    : ~ i rem 0
    ~ & >= v 1024 < unit 5 {
        = rem - v * / v 1024 1024
        = v / v 1024
        = unit + unit 1
    }
    // One decimal below 10, none above — `9.9K`, then `10K`.
    ? < v 10 {
        : i tenth / + * rem 10 512 1024
        : ~ i whole v
        : ~ i frac tenth
        ? >= frac 10 { = whole + whole 1 = frac 0 } {}
        ( string_push_int out whole )
        ( string_push_char out 46 )
        ( string_push_int out frac )
    } {
        ( string_push_int out ? >= rem 512 + v 1 v )
    }
    ( string_push_char out ( nurl_str_get units unit ) )
    ^ out
}

@ __ls_suffix i flags i mode → i {
    : i k ( nurl_stat_kind mode )
    ? == k FS_KIND_DIR { ^ ? != 0 & flags | LS_CLASSIFY LS_SLASH 47 0 } {}
    ? == 0 & flags LS_CLASSIFY { ^ 0 } {}
    ? == k FS_KIND_SYMLINK { ^ 64 } {}
    ? == k FS_KIND_FIFO { ^ 124 } {}
    ? == k FS_KIND_SOCKET { ^ 61 } {}
    ? & == k FS_KIND_FILE != 0 & mode 73 { ^ 42 } {}
    ^ 0
}

// `Aug 27 14:03` for something in the last six months, `Aug 27  2024`
// for anything older — the rule every ls has followed since v7.
@ __ls_time String out i mtime i now → v {
    : Time t ( time_local mtime )
    : String mon ( time_format t `%b %e ` )
    ( string_push_bytes out # *u ( string_data mon ) ( string_len mon ) )
    ( string_free mon )
    ? | > mtime + now 3600 < mtime - now 15552000 {
        ( string_push_char out 32 )
        : String y ( time_format t `%Y` )
        ( string_push_bytes out # *u ( string_data y ) ( string_len y ) )
        ( string_free y )
    } {
        : String hm ( time_format t `%H:%M` )
        ( string_push_bytes out # *u ( string_data hm ) ( string_len hm ) )
        ( string_free hm )
    }
}

@ __push_right String out s text i width → v {
    : ~ i k - width ( nurl_str_len text )
    ~ > k 0 { ( string_push_char out 32 ) = k - k 1 }
    ( string_push_str out text )
}

// `%-N.Ns` — pad on the right, and TRUNCATE at N, which is what keeps
// a long user name from shifting every column after it.
@ __push_left String out s text i width → v {
    : i n ( nurl_str_len text )
    : i take ? > n width width n
    ( string_push_bytes out # *u text take )
    : ~ i k - width take
    ~ > k 0 { ( string_push_char out 32 ) = k - k 1 }
}

@ __ls_owner i id b numeric b group → String {
    ? numeric { ^ ( string_from ( nurl_str_int id ) ) } {}
    : ?String r ? group ( fs_group_name id ) ( fs_user_name id )
    ?? r {
        T n → { ^ n }
        F _ → { ^ ( string_from ( nurl_str_int id ) ) }
    }
}

@ __ls_cmp BxEnt a BxEnt b i flags → i {
    : ~ i r 0
    ? != 0 & flags LS_TIME {
        = r ( cmp_int . b mtime . a mtime )
        ? == r 0 { = r ( cmp_string . a name . b name ) } {}
    } {
        ? != 0 & flags LS_SIZE_SORT {
            = r ( cmp_int . b size . a size )
            ? == r 0 { = r ( cmp_string . a name . b name ) } {}
        } {
            = r ( cmp_string . a name . b name )
        }
    }
    ^ ? != 0 & flags LS_REVERSE - 0 r r
}

// One entry, long form, into `out`. The column widths are busybox's
// fixed ones — nlink %4, user and group %-8.8s, size %9 (or %7 under
// -h) — not widths computed from the listing, so two `ls -l` runs over
// different directories still line up when you read them side by side.
@ __ls_long BxEnt e s dir i flags i now → v {
    : String out ( string_new )
    ? != 0 & flags LS_INODE {
        ( string_push_int out . e ino )
        ( string_push_char out 32 )
    } {}
    ? != 0 & flags LS_BLOCKS {
        ( __push_right out ( nurl_str_int / . e blocks 2 ) 6 )
        ( string_push_char out 32 )
    } {}
    : FileStat st @ FileStat { . e mode . e size . e mtime 0 . e uid . e gid . e nlink . e ino 0 0 . e blocks 0 0 0 0 0 }
    : String modes ( stat_mode_string st )
    ( string_push_bytes out # *u ( string_data modes ) ( string_len modes ) )
    ( string_free modes )
    ( string_push_char out 32 )
    ( __push_right out ( nurl_str_int . e nlink ) 4 )
    ( string_push_char out 32 )
    : String un ( __ls_owner . e uid != 0 & flags LS_NUMERIC F )
    ( __push_left out ( string_data un ) 8 )
    ( string_free un )
    ( string_push_char out 32 )
    : String gn ( __ls_owner . e gid != 0 & flags LS_NUMERIC T )
    ( __push_left out ( string_data gn ) 8 )
    ( string_free gn )
    ( string_push_char out 32 )
    ? != 0 & flags LS_HUMAN {
        : String h ( bx_human . e size )
        ( __push_right out ( string_data h ) 7 )
        ( string_free h )
    } {
        ( __push_right out ( nurl_str_int . e size ) 9 )
    }
    ( string_push_char out 32 )
    ( __ls_time out . e mtime now )
    ( string_push_char out 32 )
    ( string_push_bytes out # *u ( string_data . e name ) ( string_len . e name ) )
    : i sfx ( __ls_suffix flags . e mode )
    ? != sfx 0 { ( string_push_char out sfx ) } {}
    ? == ( nurl_stat_kind . e mode ) FS_KIND_SYMLINK {
        : String full ? == ( nurl_str_len dir ) 0 ( string_clone . e name ) ( path_join dir ( string_data . e name ) )
        ?? ( fs_readlink ( string_data full ) ) {
            T tgt → {
                ( string_push_str out ` -> ` )
                ( string_push_bytes out # *u ( string_data tgt ) ( string_len tgt ) )
                ( string_free tgt )
            }
            F _ → {}
        }
        ( string_free full )
    } {}
    ( string_push_char out 10 )
    ( bx_write out )
    ( string_free out )
}

@ __ls_name_only BxEnt e i flags → v {
    : String out ( string_new )
    ? != 0 & flags LS_INODE {
        ( string_push_int out . e ino )
        ( string_push_char out 32 )
    } {}
    ? != 0 & flags LS_BLOCKS {
        ( __push_right out ( nurl_str_int / . e blocks 2 ) 6 )
        ( string_push_char out 32 )
    } {}
    ( string_push_bytes out # *u ( string_data . e name ) ( string_len . e name ) )
    : i sfx ( __ls_suffix flags . e mode )
    ? != sfx 0 { ( string_push_char out sfx ) } {}
    ( string_push_char out 10 )
    ( bx_write out )
    ( string_free out )
}

// Down-then-across columns, the layout `ls` uses on a terminal.
@ __ls_columns ( Vec BxEnt ) ents i flags i width → v {
    : i n ( vec_len [BxEnt] ents )
    ? == n 0 { ^ } {}
    : ~ i widest 0
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [BxEnt] ents i ) {
            T e → {
                : i w + ( string_len . e name ) ? != 0 ( __ls_suffix flags . e mode ) 1 0
                ? > w widest { = widest w } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    : i colw + widest 2
    : ~ i cols / width colw
    ? < cols 1 { = cols 1 } {}
    ? > cols n { = cols n } {}
    : i rows / + n - cols 1 cols
    : String out ( string_new )
    : ~ i r 0
    ~ < r rows {
        : ~ i c 0
        ~ < c cols {
            : i idx + r * c rows
            ? < idx n {
                ?? ( vec_get [BxEnt] ents idx ) {
                    T e → {
                        ( string_push_bytes out # *u ( string_data . e name ) ( string_len . e name ) )
                        : i sfx ( __ls_suffix flags . e mode )
                        : ~ i used ( string_len . e name )
                        ? != sfx 0 { ( string_push_char out sfx ) = used + used 1 } {}
                        ? < + idx rows n {
                            : ~ i pad - colw used
                            ~ > pad 0 { ( string_push_char out 32 ) = pad - pad 1 }
                        } {}
                    }
                    F _ → {}
                }
            } {}
            = c + c 1
        }
        ( string_push_char out 10 )
        = r + r 1
    }
    ( bx_write out )
    ( string_free out )
}

@ __ls_emit ( Vec BxEnt ) ents s dir i flags i now → v {
    : i n ( vec_len [BxEnt] ents )
    : b longform != 0 & flags LS_LONG
    // `total` counts 1 KiB blocks and is printed for a DIRECTORY
    // listing only — operands named on the command line get none.
    ? & > ( nurl_str_len dir ) 0 != 0 & flags | LS_LONG LS_BLOCKS {
        : ~ i total 0
        : ~ i i 0
        ~ < i n {
            ?? ( vec_get [BxEnt] ents i ) {
                T e → { = total + total / . e blocks 2 }
                F _ → {}
            }
            = i + i 1
        }
        ( nurl_print `total ` )
        ? != 0 & flags LS_HUMAN {
            : String h ( bx_human * total 1024 )
            ( nurl_print ( string_data h ) )
            ( string_free h )
        } { ( nurl_print ( nurl_str_int total ) ) }
        ( nurl_print `\n` )
    } {}
    ? longform {
        : ~ i k 0
        ~ < k n {
            ?? ( vec_get [BxEnt] ents k ) {
                T e → { ( __ls_long e dir flags now ) }
                F _ → {}
            }
            = k + k 1
        }
    } {
        ? != 0 & flags LS_COLUMNS {
            : ~ i width 80
            ?? ( env_get `COLUMNS` ) {
                T c → {
                    : i w ( nurl_str_to_int ( string_data c ) )
                    ? > w 0 { = width w } {}
                    ( string_free c )
                }
                F _ → {}
            }
            ( __ls_columns ents flags width )
        } {
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [BxEnt] ents k ) {
                    T e → { ( __ls_name_only e flags ) }
                    F _ → {}
                }
                = k + k 1
            }
        }
    }
}

@ __ls_sort ( Vec BxEnt ) ents i flags → v {
    ( sort_by [BxEnt] ents \ BxEnt a BxEnt b → i { ^ ( __ls_cmp a b flags ) } )
}

@ __ls_dir s dir i flags i now b header b more_after → i {
    ?? ( dir_list dir ) {
        F e → {
            ( bx_err_at dir ( bx_ioerr e ) )
            ^ 1
        }
        T names → {
            : ( Vec BxEnt ) ents ( vec_new [BxEnt] )
            ? != 0 & flags LS_ALL {
                ( vec_push [BxEnt] ents ( __ent_of dir `.` F ) )
                ( vec_push [BxEnt] ents ( __ent_of dir `..` F ) )
            } {}
            : i n ( vec_len [String] names )
            : ~ i i 0
            ~ < i n {
                : s nm ( bx_at names i )
                : b hidden == ( nurl_str_get nm 0 ) 46
                ? | ! hidden != 0 & flags | LS_ALL LS_ALMOST {
                    ( vec_push [BxEnt] ents ( __ent_of dir nm F ) )
                } {}
                = i + i 1
            }
            ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
            ( __ls_sort ents flags )
            ? header {
                ( nurl_print dir )
                ( nurl_print `:\n` )
            } {}
            ( __ls_emit ents dir flags now )
            : ~ i rc 0
            ? != 0 & flags LS_RECURSE {
                : i m ( vec_len [BxEnt] ents )
                : ~ i k 0
                ~ < k m {
                    ?? ( vec_get [BxEnt] ents k ) {
                        T e → {
                            : s nm ( string_data . e name )
                            ? & == ( nurl_stat_kind . e mode ) FS_KIND_DIR
                            & ! ( bx_streq nm `.` ) ! ( bx_streq nm `..` ) {
                                : String sub ( path_join dir nm )
                                ( nurl_print `\n` )
                                : i one ( __ls_dir ( string_data sub ) flags now T F )
                                ? != one 0 { = rc 1 } {}
                                ( string_free sub )
                            } {}
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
            } {}
            ( vec_free_with [BxEnt] ents \ BxEnt x → v { ( __ent_free x ) } )
            ^ rc
        }
    }
}

@ ap_ls ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `laAd1rtSRFihnspCUx` `all=a,almost-all=A,long=l,reverse=r,recursive=R,inode=i,human-readable=h,numeric-uid-gid=n,size=s,classify=F,directory=d` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ~ i flags 0
        ? ( bx_has o `a` ) { = flags | flags LS_ALL } {}
        ? ( bx_has o `A` ) { = flags | flags LS_ALMOST } {}
        ? ( bx_has o `l` ) { = flags | flags LS_LONG } {}
        ? ( bx_has o `1` ) { = flags | flags LS_ONE } {}
        ? ( bx_has o `d` ) { = flags | flags LS_DIRS } {}
        ? ( bx_has o `r` ) { = flags | flags LS_REVERSE } {}
        ? ( bx_has o `t` ) { = flags | flags LS_TIME } {}
        ? ( bx_has o `S` ) { = flags | flags LS_SIZE_SORT } {}
        ? ( bx_has o `R` ) { = flags | flags LS_RECURSE } {}
        ? ( bx_has o `F` ) { = flags | flags LS_CLASSIFY } {}
        ? ( bx_has o `p` ) { = flags | flags LS_SLASH } {}
        ? ( bx_has o `i` ) { = flags | flags LS_INODE } {}
        ? ( bx_has o `h` ) { = flags | flags LS_HUMAN } {}
        ? ( bx_has o `n` ) { = flags | flags | LS_NUMERIC LS_LONG } {}
        ? ( bx_has o `s` ) { = flags | flags LS_BLOCKS } {}
        // Columns only when the output is a terminal and nothing asked
        // for one-per-line — the same rule coreutils applies, and the
        // reason `ls | cat` is always one name per line.
        ? & == 0 & flags | LS_LONG LS_ONE | ( bx_has o `C` ) ( term_is_tty 1 ) {
            = flags | flags LS_COLUMNS
        } {}
        : i now ( now_seconds )
        : i nops ( bx_operand_count o )
        : ( Vec BxEnt ) loose ( vec_new [BxEnt] )
        : ( Vec String ) dirs ( vec_new [String] )
        ? == nops 0 {
            ( vec_push [String] dirs ( string_from `.` ) )
        } {
            : ~ i i 0
            ~ < i nops {
                : s p ( bx_operand o i )
                ?? ( fs_lstat p ) {
                    T st → {
                        : ~ b isdir & ( stat_is_dir st ) == 0 & flags LS_DIRS
                        ? & ( stat_is_symlink st ) == 0 & flags LS_DIRS {
                            ?? ( fs_stat p ) {
                                T st2 → { ? ( stat_is_dir st2 ) { = isdir T } {} }
                                F _ → {}
                            }
                        } {}
                        ? isdir {
                            ( vec_push [String] dirs ( string_from p ) )
                        } {
                            ( vec_push [BxEnt] loose ( __ent_of `` p F ) )
                        }
                    }
                    F e → {
                        ( bx_err_at p ( bx_ioerr e ) )
                        = rc 1
                    }
                }
                = i + i 1
            }
        }
        ? > ( vec_len [BxEnt] loose ) 0 {
            ( __ls_sort loose flags )
            ( __ls_emit loose `` flags now )
        } {}
        : i nd ( vec_len [String] dirs )
        : b header | > nd 1 > ( vec_len [BxEnt] loose ) 0
        : ~ i d 0
        ~ < d nd {
            ? | > d 0 > ( vec_len [BxEnt] loose ) 0 { ( nurl_print `\n` ) } {}
            : i one ( __ls_dir ( bx_at dirs d ) flags now | header != 0 & flags LS_RECURSE F )
            ? != one 0 { = rc 1 } {}
            = d + d 1
        }
        ( vec_free_with [BxEnt] loose \ BxEnt x → v { ( __ent_free x ) } )
        ( vec_free_with [String] dirs \ String x → v { ( string_free x ) } )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── mkdir / rmdir ─────────────────────────────────────────────────

@ ap_mkdir ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `pm:v` `parents=p,mode=m,verbose=v` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? == nops 0 {
            ( bx_err `missing operand` )
            = rc 1
        } {}
        : ~ i mode -1
        ? ( bx_has o `m` ) {
            : i m ( bx_parse_mode ( bx_val o `m` ) 493 )
            ? < m 0 {
                ( bx_err_at ( bx_val o `m` ) `invalid mode` )
                = rc 1
            } { = mode m }
        } {}
        ? == rc 0 {
            : ~ i i 0
            ~ < i nops {
                : s p ( bx_operand o i )
                : !v IoErr r ? ( bx_has o `p` ) ( dir_create_all p ) ( dir_create p )
                ?? r {
                    T _ → {
                        ? ( bx_has o `v` ) {
                            ( nurl_print ( bx_name ) )
                            ( nurl_print `: created directory '` )
                            ( nurl_print p )
                            ( nurl_print `'\n` )
                        } {}
                        ? >= mode 0 {
                            ?? ( set_permissions p mode ) { T _ → {} F _ → {} }
                        } {}
                    }
                    F e → {
                        // -p makes an existing directory a success, which
                        // is the entire point of the flag.
                        : ~ b fine F
                        ? ( bx_has o `p` ) {
                            ?? ( fs_stat p ) {
                                T st → { ? ( stat_is_dir st ) { = fine T } {} }
                                F _ → {}
                            }
                        } {}
                        ? ! fine {
                            ( bx_err_at p ( bx_ioerr e ) )
                            = rc 1
                        } {}
                    }
                }
                = i + i 1
            }
        } {}
    }
    ( bx_opts_free o )
    ^ rc
}

@ ap_rmdir ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `pv` `parents=p,verbose=v` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? == nops 0 {
            ( bx_err `missing operand` )
            = rc 1
        } {}
        : ~ i i 0
        ~ < i nops {
            : String p ( string_from ( bx_operand o i ) )
            : ~ b going T
            ~ going {
                = going F
                ?? ( dir_remove ( string_data p ) ) {
                    T _ → {
                        ? ( bx_has o `p` ) {
                            : String parent ( path_dirname ( string_data p ) )
                            ? & > ( string_len parent ) 0 ! ( bx_streq ( string_data parent ) `.` ) {
                                ( string_clear p )
                                ( string_push_bytes p # *u ( string_data parent ) ( string_len parent ) )
                                = going T
                            } {}
                            ( string_free parent )
                        } {}
                    }
                    F e → {
                        ( bx_err_at ( string_data p ) ( bx_ioerr e ) )
                        = rc 1
                    }
                }
            }
            ( string_free p )
            = i + i 1
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── modes ─────────────────────────────────────────────────────────

// An octal mode (`755`, `0644`) or a symbolic one (`u+x`, `a-w`,
// `go=rX`), applied to `base`. Returns -1 when the text is neither.
@ bx_parse_mode s text i base → i {
    : i n ( nurl_str_len text )
    ? == n 0 { ^ -1 } {}
    ? & >= ( nurl_str_get text 0 ) 48 <= ( nurl_str_get text 0 ) 55 {
        : ~ i v 0
        : ~ i k 0
        ~ < k n {
            : i c ( nurl_str_get text k )
            ? ! & >= c 48 <= c 55 { ^ -1 } {}
            = v + * v 8 - c 48
            = k + k 1
        }
        ^ v
    } {}
    : ~ i cur base
    : ~ i i 0
    ~ < i n {
        : ~ i who 0
        : ~ b any_who F
        : ~ b scanning T
        ~ & scanning < i n {
            : i c ( nurl_str_get text i )
            ? == c 117 { = who | who 4 = any_who T = i + i 1 } {
                ? == c 103 { = who | who 2 = any_who T = i + i 1 } {
                    ? == c 111 { = who | who 1 = any_who T = i + i 1 } {
                        ? == c 97 { = who 7 = any_who T = i + i 1 } { = scanning F } } } }
        }
        ? ! any_who { = who 7 } {}
        ? >= i n { ^ -1 } {}
        : i op ( nurl_str_get text i )
        ? ! | == op 43 | == op 45 == op 61 { ^ -1 } {}
        = i + i 1
        : ~ i bits 0
        : ~ b more T
        ~ & more < i n {
            : i c ( nurl_str_get text i )
            ? == c 114 { = bits | bits 4 = i + i 1 } {
                ? == c 119 { = bits | bits 2 = i + i 1 } {
                    ? == c 120 { = bits | bits 1 = i + i 1 } {
                        ? == c 88 { = bits | bits 1 = i + i 1 } {
                            ? == c 115 { = bits | bits 8 = i + i 1 } {
                                ? == c 116 { = bits | bits 16 = i + i 1 } { = more F } } } } } }
        }
        : ~ i mask 0
        ? != 0 & who 4 { = mask | mask << & bits 7 6 } {}
        ? != 0 & who 2 { = mask | mask << & bits 7 3 } {}
        ? != 0 & who 1 { = mask | mask & bits 7 } {}
        ? != 0 & bits 8 {
            ? != 0 & who 4 { = mask | mask 2048 } {}
            ? != 0 & who 2 { = mask | mask 1024 } {}
        } {}
        ? != 0 & bits 16 { = mask | mask 512 } {}
        ? == op 43 { = cur | cur mask } {}
        ? == op 45 { = cur & cur ~ mask } {}
        ? == op 61 {
            : ~ i clear 0
            ? != 0 & who 4 { = clear | clear 448 } {}
            ? != 0 & who 2 { = clear | clear 56 } {}
            ? != 0 & who 1 { = clear | clear 7 } {}
            = cur | & cur ~ clear mask
        } {}
        ? & < i n == ( nurl_str_get text i ) 44 { = i + i 1 } {}
    }
    ^ cur
}

@ __chmod_one s path s spec b recurse b verbose → i {
    : ~ i rc 0
    ?? ( fs_lstat path ) {
        F e → {
            ( bx_err_at path ( bx_ioerr e ) )
            ^ 1
        }
        T st → {
            // A symlink has no mode of its own worth changing; chmod
            // follows it, and chmod on a dangling one is an error.
            ? ! ( stat_is_symlink st ) {
                : i want ( bx_parse_mode spec ( stat_mode_bits st ) )
                ? < want 0 {
                    ( bx_err_at spec `invalid mode` )
                    ^ 1
                } {}
                ?? ( set_permissions path want ) {
                    T _ → {
                        ? verbose {
                            ( nurl_print `mode of '` )
                            ( nurl_print path )
                            ( nurl_print `' changed\n` )
                        } {}
                    }
                    F e2 → {
                        ( bx_err_at path ( bx_ioerr e2 ) )
                        = rc 1
                    }
                }
            } {}
            ? & recurse ( stat_is_dir st ) {
                ?? ( dir_list path ) {
                    T names → {
                        : i n ( vec_len [String] names )
                        : ~ i k 0
                        ~ < k n {
                            : String sub ( path_join path ( bx_at names k ) )
                            : i one ( __chmod_one ( string_data sub ) spec recurse verbose )
                            ? != one 0 { = rc 1 } {}
                            ( string_free sub )
                            = k + k 1
                        }
                        ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
                    }
                    F _ → { = rc 1 }
                }
            } {}
        }
    }
    ^ rc
}

@ ap_chmod ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `Rvcf` `recursive=R,verbose=v,changes=c,silent=f` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? < nops 2 {
            ( bx_err `usage: chmod [-Rv] MODE FILE...` )
            = rc 1
        } {
            : s spec ( bx_operand o 0 )
            : ~ i i 1
            ~ < i nops {
                : i one ( __chmod_one ( bx_operand o i ) spec ( bx_has o `R` ) | ( bx_has o `v` ) ( bx_has o `c` ) )
                ? != one 0 { = rc 1 } {}
                = i + i 1
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── rm ────────────────────────────────────────────────────────────

@ __rm_one s path b recurse b force b verbose → i {
    ?? ( fs_lstat path ) {
        F e → {
            ? force { ^ 0 } {}
            ( bx_err_at path ( bx_ioerr e ) )
            ^ 1
        }
        T st → {
            ? ( stat_is_dir st ) {
                ? ! recurse {
                    ( bx_err_at path `Is a directory` )
                    ^ 1
                } {}
                : ~ i rc 0
                ?? ( dir_list path ) {
                    T names → {
                        : i n ( vec_len [String] names )
                        : ~ i k 0
                        ~ < k n {
                            : String sub ( path_join path ( bx_at names k ) )
                            : i one ( __rm_one ( string_data sub ) recurse force verbose )
                            ? != one 0 { = rc 1 } {}
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
                ?? ( dir_remove path ) {
                    T _ → {
                        ? verbose {
                            ( nurl_print `removed directory '` )
                            ( nurl_print path )
                            ( nurl_print `'\n` )
                        } {}
                    }
                    F e3 → {
                        ( bx_err_at path ( bx_ioerr e3 ) )
                        = rc 1
                    }
                }
                ^ rc
            } {}
            ?? ( file_delete path ) {
                T _ → {
                    ? verbose {
                        ( nurl_print `removed '` )
                        ( nurl_print path )
                        ( nurl_print `'\n` )
                    } {}
                    ^ 0
                }
                F e4 → {
                    ? force { ^ 0 } {}
                    ( bx_err_at path ( bx_ioerr e4 ) )
                    ^ 1
                }
            }
        }
    }
}

@ ap_rm ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `rRfvi` `recursive=r,force=f,verbose=v,interactive=i` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        : b force ( bx_has o `f` )
        ? == nops 0 {
            ? ! force {
                ( bx_err `missing operand` )
                = rc 1
            } {}
        } {
            : b recurse | ( bx_has o `r` ) ( bx_has o `R` )
            : ~ i i 0
            ~ < i nops {
                : i one ( __rm_one ( bx_operand o i ) recurse force ( bx_has o `v` ) )
                ? != one 0 { = rc 1 } {}
                = i + i 1
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── cp ────────────────────────────────────────────────────────────

& `c` @ link s target s linkpath → i32

: i CP_RECURSE 1
: i CP_PRESERVE 2
: i CP_FORCE 4
: i CP_VERBOSE 8
: i CP_NODEREF 16
: i CP_NOCLOBBER 32

@ __cp_verbose s src s dst → v {
    ( nurl_print `'` )
    ( nurl_print src )
    ( nurl_print `' -> '` )
    ( nurl_print dst )
    ( nurl_print `'\n` )
}

@ __cp_preserve s dst FileStat st → v {
    ?? ( set_permissions dst ( stat_mode_bits st ) ) { T _ → {} F _ → {} }
    ?? ( fs_set_times dst . st atime . st atime_ns . st mtime . st mtime_ns T ) { T _ → {} F _ → {} }
}

@ __cp_one s src s dst i flags → i {
    ?? ( fs_lstat src ) {
        F e → {
            ( bx_err_at src ( bx_ioerr e ) )
            ^ 1
        }
        T st → {
            // -n: an existing destination is left alone, silently.
            ? != 0 & flags CP_NOCLOBBER {
                ?? ( fs_lstat dst ) {
                    T _ → { ^ 0 }
                    F _ → {}
                }
            } {}
            ? & ( stat_is_symlink st ) != 0 & flags CP_NODEREF {
                ?? ( fs_readlink src ) {
                    T tgt → {
                        ? != 0 & flags CP_FORCE {
                            ?? ( file_delete dst ) { T _ → {} F _ → {} }
                        } {}
                        : ~ i rc 0
                        ?? ( fs_symlink ( string_data tgt ) dst ) {
                            T _ → { ? != 0 & flags CP_VERBOSE { ( __cp_verbose src dst ) } {} }
                            F e2 → {
                                ( bx_err_at dst ( bx_ioerr e2 ) )
                                = rc 1
                            }
                        }
                        ( string_free tgt )
                        ^ rc
                    }
                    F e3 → {
                        ( bx_err_at src ( bx_ioerr e3 ) )
                        ^ 1
                    }
                }
            } {}
            ? ( stat_is_dir st ) {
                ? == 0 & flags CP_RECURSE {
                    ( bx_err_at src `omitting directory` )
                    ^ 1
                } {}
                : ~ i rc 0
                ?? ( dir_create dst ) {
                    T _ → {}
                    F _ → {
                        // Already a directory is fine; anything else is
                        // reported when the first child fails.
                        ?? ( fs_stat dst ) {
                            T dstat → { ? ! ( stat_is_dir dstat ) { = rc 1 } {} }
                            F _ → { = rc 1 }
                        }
                    }
                }
                ? != rc 0 {
                    ( bx_err_at dst `cannot create directory` )
                    ^ 1
                } {}
                ?? ( dir_list src ) {
                    T names → {
                        : i n ( vec_len [String] names )
                        : ~ i k 0
                        ~ < k n {
                            : String s2 ( path_join src ( bx_at names k ) )
                            : String d2 ( path_join dst ( bx_at names k ) )
                            : i one ( __cp_one ( string_data s2 ) ( string_data d2 ) flags )
                            ? != one 0 { = rc 1 } {}
                            ( string_free s2 )
                            ( string_free d2 )
                            = k + k 1
                        }
                        ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
                    }
                    F e4 → {
                        ( bx_err_at src ( bx_ioerr e4 ) )
                        = rc 1
                    }
                }
                ? != 0 & flags CP_PRESERVE { ( __cp_preserve dst st ) } {}
                ? != 0 & flags CP_VERBOSE { ( __cp_verbose src dst ) } {}
                ^ rc
            } {}
            ? != 0 & flags CP_FORCE {
                ?? ( file_delete dst ) { T _ → {} F _ → {} }
            } {}
            ?? ( fs_copy_file src dst ) {
                T _ → {
                    // Without -p the destination still gets the source's
                    // permission bits, as POSIX cp specifies; -p adds the
                    // timestamps.
                    ?? ( set_permissions dst ( stat_mode_bits st ) ) { T _ → {} F _ → {} }
                    ? != 0 & flags CP_PRESERVE { ( __cp_preserve dst st ) } {}
                    ? != 0 & flags CP_VERBOSE { ( __cp_verbose src dst ) } {}
                    ^ 0
                }
                F e5 → {
                    ( bx_err_at dst ( bx_ioerr e5 ) )
                    ^ 1
                }
            }
        }
    }
}

// `cp a b/` and `cp a b c dir` both end at a directory: the destination
// for each source is dir/basename(source).
@ __dest_for s dst s src b into_dir → String {
    ? ! into_dir { ^ ( string_from dst ) } {}
    : String base ( path_basename src )
    : String full ( path_join dst ( string_data base ) )
    ( string_free base )
    ^ full
}

@ __is_dir s p → b {
    ?? ( fs_stat p ) {
        T st → { ^ ( stat_is_dir st ) }
        F _ → { ^ F }
    }
}

@ ap_cp ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `rRapfvdLnPTi` `recursive=r,archive=a,preserve=p,force=f,verbose=v,no-dereference=d,dereference=L,no-clobber=n,no-target-directory=T` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? < nops 2 {
            ( bx_err `missing destination file operand` )
            = rc 1
        } {
            : ~ i flags 0
            ? | ( bx_has o `r` ) | ( bx_has o `R` ) ( bx_has o `a` ) { = flags | flags CP_RECURSE } {}
            ? | ( bx_has o `p` ) ( bx_has o `a` ) { = flags | flags CP_PRESERVE } {}
            // A recursive copy keeps symlinks as symlinks unless -L says
            // otherwise: dereferencing turns one link into a second full
            // copy of its target, and a link loop into an infinite one.
            ? | ( bx_has o `d` ) | ( bx_has o `P` ) | ( bx_has o `a` ) != 0 & flags CP_RECURSE { = flags | flags CP_NODEREF } {}
            ? ( bx_has o `L` ) { = flags & flags ~ CP_NODEREF } {}
            ? ( bx_has o `f` ) { = flags | flags CP_FORCE } {}
            ? ( bx_has o `v` ) { = flags | flags CP_VERBOSE } {}
            ? ( bx_has o `n` ) { = flags | flags CP_NOCLOBBER } {}
            : s dst ( bx_operand o - nops 1 )
            : b into_dir & ( __is_dir dst ) ! ( bx_has o `T` )
            ? & > nops 3 ! into_dir {
                ( bx_err_at dst `not a directory` )
                = rc 1
            } {
                : ~ i i 0
                ~ < i - nops 1 {
                    : s src ( bx_operand o i )
                    : String d ( __dest_for dst src into_dir )
                    : i one ( __cp_one src ( string_data d ) flags )
                    ? != one 0 { = rc 1 } {}
                    ( string_free d )
                    = i + i 1
                }
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── mv ────────────────────────────────────────────────────────────

@ __mv_one s src s dst b force b verbose → i {
    ? ! force {
        ?? ( fs_lstat dst ) {
            T _ → {}
            F _ → {}
        }
    } {}
    ?? ( fs_rename src dst ) {
        T _ → {
            ? verbose { ( __cp_verbose src dst ) } {}
            ^ 0
        }
        F _ → {}
    }
    // A rename across filesystems is EXDEV; copy then remove is what
    // every mv does about it, and the copy must preserve metadata
    // because a move is not supposed to change the file.
    : i c ( __cp_one src dst | | CP_RECURSE CP_PRESERVE CP_NODEREF )
    ? != c 0 { ^ 1 } {}
    : i r ( __rm_one src T T F )
    ? != r 0 { ^ 1 } {}
    ? verbose { ( __cp_verbose src dst ) } {}
    ^ 0
}

@ ap_mv ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `fvniT` `force=f,verbose=v,no-clobber=n,no-target-directory=T` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? < nops 2 {
            ( bx_err `missing destination file operand` )
            = rc 1
        } {
            : s dst ( bx_operand o - nops 1 )
            : b into_dir & ( __is_dir dst ) ! ( bx_has o `T` )
            : ~ i i 0
            ~ < i - nops 1 {
                : s src ( bx_operand o i )
                : String d ( __dest_for dst src into_dir )
                : ~ b skip F
                ? ( bx_has o `n` ) {
                    ?? ( fs_lstat ( string_data d ) ) {
                        T _ → { = skip T }
                        F _ → {}
                    }
                } {}
                ? ! skip {
                    : i one ( __mv_one src ( string_data d ) ( bx_has o `f` ) ( bx_has o `v` ) )
                    ? != one 0 { = rc 1 } {}
                } {}
                ( string_free d )
                = i + i 1
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── ln ────────────────────────────────────────────────────────────

@ ap_ln ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `sfvnT` `symbolic=s,force=f,verbose=v,no-target-directory=T` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? == nops 0 {
            ( bx_err `missing operand` )
            = rc 1
        } {
            // `ln TARGET` links into the current directory.
            : s dst ? > nops 1 ( bx_operand o - nops 1 ) `.`
            : b into_dir | == nops 1 & ( __is_dir dst ) ! ( bx_has o `T` )
            : i last ? > nops 1 - nops 1 nops
            : ~ i i 0
            ~ < i last {
                : s src ( bx_operand o i )
                : String d ( __dest_for dst src into_dir )
                ? ( bx_has o `f` ) {
                    ?? ( file_delete ( string_data d ) ) { T _ → {} F _ → {} }
                } {}
                ? ( bx_has o `s` ) {
                    ?? ( fs_symlink src ( string_data d ) ) {
                        T _ → { ? ( bx_has o `v` ) { ( __cp_verbose ( string_data d ) src ) } {} }
                        F e → {
                            ( bx_err_at ( string_data d ) ( bx_ioerr e ) )
                            = rc 1
                        }
                    }
                } {
                    : i32 lr ( link src ( string_data d ) )
                    ? != # i lr 0 {
                        ( bx_err_at ( string_data d ) ( bx_ioerr ( _io_err_of_kind ( errno_kind ) ) ) )
                        = rc 1
                    } {
                        ? ( bx_has o `v` ) { ( __cp_verbose ( string_data d ) src ) } {}
                    }
                }
                ( string_free d )
                = i + i 1
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── touch ─────────────────────────────────────────────────────────

@ ap_touch ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `camr:d:t:` `no-create=c,reference=r,date=d` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? == nops 0 {
            ( bx_err `missing operand` )
            = rc 1
        } {}
        : ~ i when ( now_seconds )
        : ~ i when_ns 0
        : ~ b have_time F
        ? ( bx_has o `r` ) {
            ?? ( fs_stat ( bx_val o `r` ) ) {
                T st → {
                    = when . st mtime
                    = when_ns . st mtime_ns
                    = have_time T
                }
                F e → {
                    ( bx_err_at ( bx_val o `r` ) ( bx_ioerr e ) )
                    = rc 1
                }
            }
        } {}
        ? ( bx_has o `d` ) {
            ?? ( time_parse_iso ( bx_val o `d` ) ) {
                T secs → { = when secs = when_ns 0 = have_time T }
                F _ → {
                    ( bx_err_at ( bx_val o `d` ) `invalid date` )
                    = rc 1
                }
            }
        } {}
        : b touch_a | ( bx_has o `a` ) ! ( bx_has o `m` )
        : b touch_m | ( bx_has o `m` ) ! ( bx_has o `a` )
        ? == rc 0 {
            : ~ i i 0
            ~ < i nops {
                : s p ( bx_operand o i )
                : ~ b exists F
                : ~ i atime when
                : ~ i atime_ns when_ns
                : ~ i mtime when
                : ~ i mtime_ns when_ns
                ?? ( fs_stat p ) {
                    T st → {
                        = exists T
                        // -a alone leaves mtime where it was, -m alone
                        // leaves atime — so read the current pair first.
                        ? ! touch_a { = atime . st atime = atime_ns . st atime_ns } {}
                        ? ! touch_m { = mtime . st mtime = mtime_ns . st mtime_ns } {}
                    }
                    F _ → {}
                }
                ? ! exists {
                    ? ( bx_has o `c` ) {
                        = i + i 1
                    } {
                        ?? ( file_create p ) {
                            T f → {
                                ( file_close f )
                                = exists T
                            }
                            F e → {
                                ( bx_err_at p ( bx_ioerr e ) )
                                = rc 1
                            }
                        }
                    }
                } {}
                ? exists {
                    ?? ( fs_set_times p atime atime_ns mtime mtime_ns T ) {
                        T _ → {}
                        F e2 → {
                            ( bx_err_at p ( bx_ioerr e2 ) )
                            = rc 1
                        }
                    }
                } {}
                = i + i 1
            }
        } {}
    }
    ( bx_opts_free o )
    ^ rc
}

// ── readlink / realpath ───────────────────────────────────────────

@ ap_readlink ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `fnv` `canonicalize=f,no-newline=n,verbose=v` )
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
            ? ( bx_has o `f` ) {
                : Path pp ( path_new p )
                ?? ( path_canonical pp ) {
                    T c → {
                        ( nurl_print ( path_str c ) )
                        ( nurl_print ? ( bx_has o `n` ) `` `\n` )
                        ( path_free c )
                    }
                    F _ → {
                        ? ( bx_has o `v` ) { ( bx_err_at p `No such file or directory` ) } {}
                        = rc 1
                    }
                }
                ( path_free pp )
            } {
                ?? ( fs_readlink p ) {
                    T t → {
                        ( nurl_print ( string_data t ) )
                        ( nurl_print ? ( bx_has o `n` ) `` `\n` )
                        ( string_free t )
                    }
                    F _ → {
                        ? ( bx_has o `v` ) { ( bx_err_at p `Invalid argument` ) } {}
                        = rc 1
                    }
                }
            }
            = i + i 1
        }
    }
    ( bx_opts_free o )
    ^ rc
}

@ ap_realpath ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `s` `` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i nops ( bx_operand_count o )
        ? == nops 0 {
            ( bx_err `missing operand` )
            = rc 1
        } {}
        : ~ i i 0
        ~ < i nops {
            : Path pp ( path_new ( bx_operand o i ) )
            ?? ( path_canonical pp ) {
                T c → {
                    ( nurl_print ( path_str c ) )
                    ( nurl_print `\n` )
                    ( path_free c )
                }
                F _ → {
                    ( bx_err_at ( bx_operand o i ) `No such file or directory` )
                    = rc 1
                }
            }
            ( path_free pp )
            = i + i 1
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── truncate ──────────────────────────────────────────────────────

@ ap_truncate ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `s:c` `size=s,no-create=c` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        ? ! ( bx_has o `s` ) {
            ( bx_err `you must specify a size` )
            = rc 1
        } {
            : i want ( bx_count ( bx_val o `s` ) )
            ? < want 0 {
                ( bx_err_at ( bx_val o `s` ) `invalid size` )
                = rc 1
            } {
                : i nops ( bx_operand_count o )
                : ~ i i 0
                ~ < i nops {
                    : s p ( bx_operand o i )
                    : ~ b exists F
                    ?? ( fs_stat p ) {
                        T _ → { = exists T }
                        F _ → {}
                    }
                    ? & ! exists ! ( bx_has o `c` ) {
                        ?? ( file_create p ) {
                            T f → { ( file_close f ) = exists T }
                            F e → {
                                ( bx_err_at p ( bx_ioerr e ) )
                                = rc 1
                            }
                        }
                    } {}
                    ? exists {
                        ?? ( file_truncate p want ) {
                            T _ → {}
                            F e2 → {
                                ( bx_err_at p ( bx_ioerr e2 ) )
                                = rc 1
                            }
                        }
                    } {}
                    = i + i 1
                }
            }
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── mktemp ────────────────────────────────────────────────────────

@ ap_mktemp ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `dup:tq` `directory=d,dry-run=u,tmpdir=p,quiet=q` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : String dir ? ( bx_has o `p` ) ( string_from ( bx_val o `p` ) ) ( env_var_or `TMPDIR` `/tmp` )
        : ~ String prefix ( string_from `tmp.` )
        ? > ( bx_operand_count o ) 0 {
            // A template's XXXXXX is replaced; anything before it is the
            // prefix, which is all the uniqueness machinery needs.
            : s t ( bx_operand o 0 )
            : i x ( nurl_str_find t `XXX` )
            ( string_clear prefix )
            ( string_push_str prefix ? > x -1 ( nurl_str_slice t 0 x ) t )
        } {}
        ? ( bx_has o `d` ) {
            // mkdir(2) fails if the name exists, so the loop IS the
            // uniqueness test — no window between checking and creating.
            : ~ i attempt 0
            : ~ b made F
            ~ & ! made < attempt 200 {
                : String cand ( string_clone dir )
                ( string_push_char cand 47 )
                ( string_push_bytes cand # *u ( string_data prefix ) ( string_len prefix ) )
                ( string_push_int cand + * ( now_ms ) 1000 + attempt * # i ( getpid ) 7 )
                ?? ( dir_create ( string_data cand ) ) {
                    T _ → {
                        ( nurl_print ( string_data cand ) )
                        ( nurl_print `\n` )
                        = made T
                    }
                    F _ → {}
                }
                ( string_free cand )
                = attempt + attempt 1
            }
            ? ! made {
                ? ! ( bx_has o `q` ) { ( bx_err `failed to create directory` ) } {}
                = rc 1
            } {}
        } {
            ?? ( fs_tempfile ( string_data dir ) ( string_data prefix ) ) {
                T p → {
                    ? ( bx_has o `u` ) {
                        ?? ( file_delete ( string_data p ) ) { T _ → {} F _ → {} }
                    } {}
                    ( nurl_print ( string_data p ) )
                    ( nurl_print `\n` )
                    ( string_free p )
                }
                F e → {
                    ? ! ( bx_has o `q` ) { ( bx_err ( bx_ioerr e ) ) } {}
                    = rc 1
                }
            }
        }
        ( string_free prefix )
        ( string_free dir )
    }
    ( bx_opts_free o )
    ^ rc
}
