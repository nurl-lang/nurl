// nurlbox/proc.nu — what the machine is doing.
//
// ps / kill / killall / pidof / free / uptime / df / mount.
//
// Everything except `kill` and `df` reads `/proc`, because on Linux that
// IS the process table — there is no syscall that enumerates processes,
// and a tool that pretended otherwise would be reading the same files
// through a wrapper. On a machine with no `/proc` (the unikernel, a
// container without it mounted) each of these says so rather than
// reporting an empty system: "no processes" and "I cannot see the
// processes" are different answers.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/bufio.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/std/time.nu`
$ `bx.nu`
$ `filter.nu`

: s PROC_ROOT `/proc`

@ __proc_available → b {
    ?? ( fs_stat `/proc/self` ) {
        T _ → { ^ T }
        F _ → { ^ F }
    }
}

@ __proc_no_procfs → i {
    ( bx_err `/proc is not mounted — this machine cannot answer that` )
    ^ 1
}

// Read a whole /proc file. They report size 0, so `read_file` (which
// trusts the size) comes back empty — the streaming reader is the only
// one that works here, and that is not a detail a caller should have to
// know.
@ __proc_read s path String out → b {
    ( string_clear out )
    ?? ( bufreader_open path ) {
        F _ → { ^ F }
        T br → {
            : String line ( string_new )
            : ~ b more T
            ~ more {
                ? ( bufreader_read_line_raw br line ) {
                    ( string_push_bytes out # *u ( string_data line ) ( string_len line ) )
                } { = more F }
            }
            ( string_free line )
            ( bufreader_close br )
            ^ T
        }
    }
}

// The `n`-th whitespace-separated field of `text`, 0-based.
@ __field s text i want → String {
    : i n ( nurl_str_len text )
    : ~ i i 0
    : ~ i idx 0
    ~ < i n {
        ~ & < i n ( bx_is_blank ( nurl_str_get text i ) ) { = i + i 1 }
        : i start i
        ~ & < i n ! ( bx_is_blank ( nurl_str_get text i ) ) { = i + i 1 }
        ? > i start {
            ? == idx want { ^ ( string_from ( nurl_str_slice text start - i start ) ) } {}
            = idx + idx 1
        } {}
    }
    ^ ( string_new )
}

@ __is_pid_name s name → b {
    : i n ( nurl_str_len name )
    ? == n 0 { ^ F } {}
    : ~ i i 0
    ~ < i n {
        ? ! ( bx_is_digit ( nurl_str_get name i ) ) { ^ F } {}
        = i + i 1
    }
    ^ T
}

// Every pid under /proc, ascending.
@ __proc_pids ( Vec i ) out → b {
    ?? ( dir_list PROC_ROOT ) {
        F _ → { ^ F }
        T names → {
            : i n ( vec_len [String] names )
            : ~ i i 0
            ~ < i n {
                : s nm ( bx_at names i )
                ? ( __is_pid_name nm ) { ( vec_push [i] out ( nurl_str_to_int nm ) ) } {}
                = i + i 1
            }
            ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
            ( sort_by [i] out \ i a i b → i { ^ ( cmp_int a b ) } )
            ^ T
        }
    }
}

@ __proc_path i pid s leaf → String {
    : String p ( string_from PROC_ROOT )
    ( string_push_char p 47 )
    ( string_push_int p pid )
    ( string_push_char p 47 )
    ( string_push_str p leaf )
    ^ p
}

// A process's command as `ps` shows it: the full argv with NULs turned
// into spaces, or the kernel thread's name in brackets when argv is
// empty — which is exactly how the kernel distinguishes the two.
@ __proc_command i pid String out → b {
    ( string_clear out )
    : String p ( __proc_path pid `cmdline` )
    : String raw ( string_new )
    : b ok ( __proc_read ( string_data p ) raw )
    ( string_free p )
    ? ! ok {
        ( string_free raw )
        ^ F
    } {}
    : i n ( string_len raw )
    ? > n 0 {
        : ~ i i 0
        ~ < i n {
            : i c ( string_get raw i )
            ? == c 0 {
                ? < + i 1 n { ( string_push_char out 32 ) } {}
            } { ( string_push_char out c ) }
            = i + i 1
        }
    } {
        : String cp ( __proc_path pid `comm` )
        : String comm ( string_new )
        ? ( __proc_read ( string_data cp ) comm ) {
            : ~ i cn ( string_len comm )
            ~ & > cn 0 == ( string_get comm - cn 1 ) 10 { = cn - cn 1 }
            ( string_push_char out 91 )
            ( string_push_bytes out # *u ( string_data comm ) cn )
            ( string_push_char out 93 )
        } {}
        ( string_free comm )
        ( string_free cp )
    }
    ( string_free raw )
    ^ T
}

// The uid a process runs as, from /proc/PID/status's `Uid:` line.
@ __proc_uid i pid → i {
    : String p ( __proc_path pid `status` )
    : String text ( string_new )
    : ~ i uid -1
    ? ( __proc_read ( string_data p ) text ) {
        : i n ( string_len text )
        : ~ i i 0
        ~ < i n {
            : ~ i e i
            ~ & < e n != ( string_get text e ) 10 { = e + e 1 }
            : String line ( string_substr text i - e i )
            ? ( string_starts_with line `Uid:` ) {
                : String f ( __field ( string_data line ) 1 )
                = uid ( nurl_str_to_int ( string_data f ) )
                ( string_free f )
                = i n
            } { = i + e 1 }
            ( string_free line )
        }
    } {}
    ( string_free text )
    ( string_free p )
    ^ uid
}

// ── ps ────────────────────────────────────────────────────────────

@ ap_ps ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `aefluwo:` `` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        ? ! ( __proc_available ) { = rc ( __proc_no_procfs ) } {
            : ( Vec i ) pids ( vec_new [i] )
            ? ! ( __proc_pids pids ) { = rc ( __proc_no_procfs ) } {
                : String out ( string_from `PID   USER     COMMAND\n` )
                : String cmd ( string_new )
                : i n ( vec_len [i] pids )
                : ~ i i 0
                ~ < i n {
                    ?? ( vec_get [i] pids i ) {
                        T pid → {
                            ? ( __proc_command pid cmd ) {
                                ( bx_push_right out ( nurl_str_int pid ) 5 )
                                ( string_push_char out 32 )
                                : i uid ( __proc_uid pid )
                                : ~ String user ( string_from `?` )
                                ? >= uid 0 {
                                    ?? ( fs_user_name uid ) {
                                        T nm → {
                                            ( string_free user )
                                            = user nm
                                        }
                                        F _ → {
                                            ( string_free user )
                                            = user ( string_from ( nurl_str_int uid ) )
                                        }
                                    }
                                } {}
                                : i w ( string_len user )
                                ( string_push_bytes out # *u ( string_data user ) ? > w 8 8 w )
                                : ~ i pad - 8 ? > w 8 8 w
                                ~ > pad 0 { ( string_push_char out 32 ) = pad - pad 1 }
                                ( string_free user )
                                ( string_push_char out 32 )
                                ( string_push_bytes out # *u ( string_data cmd ) ( string_len cmd ) )
                                ( string_push_char out 10 )
                            } {}
                        }
                        F _ → {}
                    }
                    = i + i 1
                }
                ( bx_write out )
                ( string_free out )
                ( string_free cmd )
            }
            ( vec_free [i] pids )
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── kill / killall / pidof ────────────────────────────────────────

: s BX_SIGNAMES `HUP INT QUIT ILL TRAP ABRT BUS FPE KILL USR1 SEGV USR2 PIPE ALRM TERM STKFLT CHLD CONT STOP TSTP TTIN TTOU URG XCPU XFSZ VTALRM PROF WINCH POLL PWR SYS`

@ __sig_name i n → String {
    : String table ( string_from BX_SIGNAMES )
    : ( Vec String ) names ( string_split table ` ` )
    : ~ String out ( string_new )
    ? & >= n 1 <= n ( vec_len [String] names ) {
        ( string_push_str out ( bx_at names - n 1 ) )
    } {}
    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
    ( string_free table )
    ^ out
}

@ __sig_number s spec → i {
    : i n ( nurl_str_len spec )
    ? == n 0 { ^ -1 } {}
    ? ( bx_is_digit ( nurl_str_get spec 0 ) ) { ^ ( nurl_str_to_int spec ) } {}
    // `-SIGTERM` and `-TERM` name the same signal.
    : s bare ? != 0 ( nurl_str_starts spec `SIG` ) ( nurl_str_slice spec 3 - n 3 ) spec
    : String table ( string_from BX_SIGNAMES )
    : ( Vec String ) names ( string_split table ` ` )
    : i cnt ( vec_len [String] names )
    : ~ i found -1
    : ~ i i 0
    ~ < i cnt {
        ? ( bx_streq ( bx_at names i ) bare ) { = found + i 1 } {}
        = i + i 1
    }
    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
    ( string_free table )
    ^ found
}

@ ap_kill ( Vec String ) argv → i {
    : i n ( vec_len [String] argv )
    : ~ i sig 15
    : ~ i i 1
    : ~ b list F
    ~ & < i n T {
        : s a ( bx_at argv i )
        : i al ( nurl_str_len a )
        ? & > al 1 == 45 ( nurl_str_get a 0 ) {
            ? ( bx_streq a `-l` ) {
                = list T
                = i + i 1
            } {
                : i s2 ( __sig_number ( nurl_str_slice a 1 - al 1 ) )
                ? < s2 0 {
                    ( bx_err_at a `unknown signal` )
                    ^ 1
                } {}
                = sig s2
                = i + i 1
            }
        } { = i n }
    }
    ? list {
        : String out ( string_new )
        : ~ i k 1
        ~ <= k 31 {
            : String nm ( __sig_name k )
            ( bx_push_right out ( nurl_str_int k ) 2 )
            ( string_push_str out `) ` )
            ( string_push_bytes out # *u ( string_data nm ) ( string_len nm ) )
            ( string_push_char out 10 )
            ( string_free nm )
            = k + k 1
        }
        ( bx_write out )
        ( string_free out )
        ^ 0
    } {}
    ? >= i n {
        ( bx_err `usage: kill [-SIGNAL] PID...` )
        ^ 1
    } {}
    : ~ i rc 0
    ~ < i n {
        : s a ( bx_at argv i )
        : i pid ( nurl_str_to_int a )
        : i32 r ( kill # i32 pid # i32 sig )
        ? != # i r 0 {
            ( bx_err_at a `No such process` )
            = rc 1
        } {}
        = i + i 1
    }
    ^ rc
}

// Pids whose command matches `name`, either as the whole argv[0] or as
// its basename — `killall sshd` must find `/usr/sbin/sshd`.
@ __pids_named s name ( Vec i ) out → b {
    : ( Vec i ) pids ( vec_new [i] )
    ? ! ( __proc_pids pids ) {
        ( vec_free [i] pids )
        ^ F
    } {}
    : String cmd ( string_new )
    : i n ( vec_len [i] pids )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [i] pids i ) {
            T pid → {
                ? ( __proc_command pid cmd ) {
                    : String first ( __field ( string_data cmd ) 0 )
                    : String base ( path_basename ( string_data first ) )
                    ? | ( bx_streq ( string_data first ) name ) ( bx_streq ( string_data base ) name ) {
                        ( vec_push [i] out pid )
                    } {}
                    ( string_free base )
                    ( string_free first )
                } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ( string_free cmd )
    ( vec_free [i] pids )
    ^ T
}

@ ap_killall ( Vec String ) argv → i {
    : i n ( vec_len [String] argv )
    : ~ i sig 15
    : ~ i i 1
    ? & > n 1 == 45 ( nurl_str_get ( bx_at argv 1 ) 0 ) {
        : s a ( bx_at argv 1 )
        = sig ( __sig_number ( nurl_str_slice a 1 - ( nurl_str_len a ) 1 ) )
        = i 2
    } {}
    ? >= i n {
        ( bx_err `usage: killall [-SIGNAL] NAME...` )
        ^ 1
    } {}
    ? ! ( __proc_available ) { ^ ( __proc_no_procfs ) } {}
    : ~ i rc 0
    ~ < i n {
        : s name ( bx_at argv i )
        : ( Vec i ) pids ( vec_new [i] )
        ? ( __pids_named name pids ) {
            : i cnt ( vec_len [i] pids )
            ? == cnt 0 {
                ( bx_err_at name `no process killed` )
                = rc 1
            } {
                : ~ i k 0
                ~ < k cnt {
                    ?? ( vec_get [i] pids k ) {
                        T pid → { : i32 _r ( kill # i32 pid # i32 sig ) }
                        F _ → {}
                    }
                    = k + k 1
                }
            }
        } { = rc 1 }
        ( vec_free [i] pids )
        = i + i 1
    }
    ^ rc
}

@ ap_pidof ( Vec String ) argv → i {
    : i n ( vec_len [String] argv )
    ? <= n 1 {
        ( bx_err `usage: pidof NAME...` )
        ^ 1
    } {}
    ? ! ( __proc_available ) { ^ ( __proc_no_procfs ) } {}
    : String out ( string_new )
    : ~ b any F
    : ~ i i 1
    ~ < i n {
        : ( Vec i ) pids ( vec_new [i] )
        ? ( __pids_named ( bx_at argv i ) pids ) {
            // Newest first, which is what a caller piping into `kill`
            // expects: the process it just started is the one it means.
            : ~ i k ( vec_len [i] pids )
            ~ > k 0 {
                ?? ( vec_get [i] pids - k 1 ) {
                    T pid → {
                        ? any { ( string_push_char out 32 ) } {}
                        ( string_push_int out pid )
                        = any T
                    }
                    F _ → {}
                }
                = k - k 1
            }
        } {}
        ( vec_free [i] pids )
        = i + i 1
    }
    ? any { ( string_push_char out 10 ) } {}
    ( bx_write out )
    ( string_free out )
    ^ ? any 0 1
}

// ── free ──────────────────────────────────────────────────────────

// One `Key:  value kB` line out of /proc/meminfo, in kibibytes.
@ __meminfo String text s key → i {
    : i n ( string_len text )
    : ~ i i 0
    ~ < i n {
        : ~ i e i
        ~ & < e n != ( string_get text e ) 10 { = e + e 1 }
        : String line ( string_substr text i - e i )
        : ~ i v -1
        ? ( string_starts_with line key ) {
            : String f ( __field ( string_data line ) 1 )
            = v ( nurl_str_to_int ( string_data f ) )
            ( string_free f )
        } {}
        ( string_free line )
        ? >= v 0 { ^ v } {}
        = i + e 1
    }
    ^ -1
}

@ ap_free ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `bkmgh` `` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : String text ( string_new )
        ? ! ( __proc_read `/proc/meminfo` text ) {
            ( bx_err `/proc/meminfo is not readable — this machine cannot answer that` )
            = rc 1
        } {
            : i total ( __meminfo text `MemTotal:` )
            : i free_ ( __meminfo text `MemFree:` )
            : i avail ( __meminfo text `MemAvailable:` )
            : i buffers ( __meminfo text `Buffers:` )
            : i cached ( __meminfo text `Cached:` )
            : i shared ( __meminfo text `Shmem:` )
            : i swtotal ( __meminfo text `SwapTotal:` )
            : i swfree ( __meminfo text `SwapFree:` )
            : i reclaim ( __meminfo text `SReclaimable:` )
            // `free(1)` counts reclaimable slab as cache, because that is
            // what it is: memory the kernel will hand back on demand.
            : i buffcache + + ? > buffers 0 buffers 0 ? > cached 0 cached 0 ? > reclaim 0 reclaim 0
            : i used - - total free_ buffcache
            : String out ( string_from `              total        used        free      shared  buff/cache   available\n` )
            // The label sits in the same 19-column field the header's
            // `total` ends in, so the numbers line up under it.
            ( string_push_str out `Mem:` )
            ( bx_push_right out ( nurl_str_int total ) 15 )
            ( bx_push_right out ( nurl_str_int used ) 12 )
            ( bx_push_right out ( nurl_str_int free_ ) 12 )
            ( bx_push_right out ( nurl_str_int ? > shared 0 shared 0 ) 12 )
            ( bx_push_right out ( nurl_str_int buffcache ) 12 )
            ( bx_push_right out ( nurl_str_int ? > avail 0 avail 0 ) 12 )
            ( string_push_char out 10 )
            ( string_push_str out `Swap:` )
            ( bx_push_right out ( nurl_str_int ? > swtotal 0 swtotal 0 ) 14 )
            ( bx_push_right out ( nurl_str_int - ? > swtotal 0 swtotal 0 ? > swfree 0 swfree 0 ) 12 )
            ( bx_push_right out ( nurl_str_int ? > swfree 0 swfree 0 ) 12 )
            ( string_push_char out 10 )
            ( bx_write out )
            ( string_free out )
        }
        ( string_free text )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── uptime ────────────────────────────────────────────────────────

// Logged-in users, counted out of /var/run/utmp. The record is 384
// bytes on Linux with `ut_type` a short at offset 0; USER_PROCESS is 7.
// A machine with no utmp answers -1 and `uptime` leaves the field out
// rather than claiming nobody is here.
@ __count_users → i {
    : ~ b ok T
    : ( Vec u ) data ( bx_slurp `/var/run/utmp` ok )
    ? ! ok {
        ( vec_free [u] data )
        ^ -1
    } {}
    : i n ( vec_len [u] data )
    : *u p ( vec_data [u] data )
    : ~ i count 0
    : ~ i off 0
    ~ <= + off 384 n {
        : i kind | & 255 # i . p off << & 255 # i . p + off 1 8
        ? == kind 7 { = count + count 1 } {}
        = off + off 384
    }
    ( vec_free [u] data )
    ^ count
}

@ ap_uptime ( Vec String ) argv → i {
    : String up ( string_new )
    ? ! ( __proc_read `/proc/uptime` up ) {
        ( string_free up )
        ( bx_err `/proc/uptime is not readable — this machine cannot answer that` )
        ^ 1
    } {}
    : String f ( __field ( string_data up ) 0 )
    : i secs # i ( nurl_str_to_float ( string_data f ) )
    ( string_free f )
    ( string_free up )
    : String out ( string_new )
    ( string_push_char out 32 )
    : Time now ( time_now_local )
    : String clock ( time_format now `%H:%M:%S` )
    ( string_push_bytes out # *u ( string_data clock ) ( string_len clock ) )
    ( string_free clock )
    ( string_push_str out ` up ` )
    : i days / secs 86400
    ? > days 0 {
        ( string_push_int out days )
        ( string_push_str out ? == days 1 ` day, ` ` days, ` )
    } {}
    : i hh / - secs * days 86400 3600
    : i mm / - - secs * days 86400 * hh 3600 60
    ? > hh 0 {
        ( bx_push_right out ( nurl_str_int hh ) 2 )
        ( string_push_char out 58 )
        ? < mm 10 { ( string_push_char out 48 ) } {}
        ( string_push_int out mm )
    } {
        ( string_push_int out mm )
        ( string_push_str out ` min` )
    }
    : i users ( __count_users )
    ? >= users 0 {
        ( string_push_str out `,  ` )
        ( string_push_int out users )
        ( string_push_str out ? == users 1 ` user` ` users` )
    } {}
    : String load ( string_new )
    ? ( __proc_read `/proc/loadavg` load ) {
        ( string_push_str out `,  load average: ` )
        : ~ i k 0
        ~ < k 3 {
            ? > k 0 { ( string_push_str out `, ` ) } {}
            : String lf ( __field ( string_data load ) k )
            ( string_push_bytes out # *u ( string_data lf ) ( string_len lf ) )
            ( string_free lf )
            = k + k 1
        }
    } {}
    ( string_free load )
    ( string_push_char out 10 )
    ( bx_write out )
    ( string_free out )
    ^ 0
}

// ── df / mount ────────────────────────────────────────────────────

: MountEnt {
    String dev
    String dir
    String kind
    String opts
}

@ __mounts ( Vec MountEnt ) out → b {
    : String text ( string_new )
    ? ! ( __proc_read `/proc/mounts` text ) {
        ( string_free text )
        ^ F
    } {}
    : i n ( string_len text )
    : ~ i i 0
    ~ < i n {
        : ~ i e i
        ~ & < e n != ( string_get text e ) 10 { = e + e 1 }
        ? > e i {
            : String line ( string_substr text i - e i )
            ( vec_push [MountEnt] out @ MountEnt {
                ( __field ( string_data line ) 0 )
                ( __field ( string_data line ) 1 )
                ( __field ( string_data line ) 2 )
                ( __field ( string_data line ) 3 )
            } )
            ( string_free line )
        } {}
        = i + e 1
    }
    ( string_free text )
    ^ T
}

@ __mount_free MountEnt m → v {
    ( string_free . m dev )
    ( string_free . m dir )
    ( string_free . m kind )
    ( string_free . m opts )
}

@ ap_mount ( Vec String ) argv → i {
    : i n ( vec_len [String] argv )
    ? > n 1 {
        // Mounting is a privileged syscall this package does not wrap;
        // saying so beats a wrong error from somewhere deeper.
        ( bx_err `only the listing form is supported` )
        ^ 1
    } {}
    : ( Vec MountEnt ) ms ( vec_new [MountEnt] )
    ? ! ( __mounts ms ) {
        ( vec_free [MountEnt] ms )
        ^ ( __proc_no_procfs )
    } {}
    : String out ( string_new )
    : i cnt ( vec_len [MountEnt] ms )
    : ~ i i 0
    ~ < i cnt {
        ?? ( vec_get [MountEnt] ms i ) {
            T m → {
                ( string_push_bytes out # *u ( string_data . m dev ) ( string_len . m dev ) )
                ( string_push_str out ` on ` )
                ( string_push_bytes out # *u ( string_data . m dir ) ( string_len . m dir ) )
                ( string_push_str out ` type ` )
                ( string_push_bytes out # *u ( string_data . m kind ) ( string_len . m kind ) )
                ( string_push_str out ` (` )
                ( string_push_bytes out # *u ( string_data . m opts ) ( string_len . m opts ) )
                ( string_push_str out `)\n` )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( bx_write out )
    ( string_free out )
    ( vec_free_with [MountEnt] ms \ MountEnt m → v { ( __mount_free m ) } )
    ^ 0
}

// df's own humaniser: always one decimal, unlike `ls -h`, which drops
// it above 10. Two tools, two long-standing conventions.
@ __df_human i bytes → String {
    : String out ( string_new )
    ? < bytes 1024 {
        ( string_push_int out bytes )
        ^ out
    } {}
    : s units `KMGTPE`
    : ~ i v bytes
    : ~ i unit -1
    : ~ i rem 0
    ~ & >= v 1024 < unit 5 {
        = rem - v * 1024 / v 1024
        = v / v 1024
        = unit + unit 1
    }
    : i tenth / + * rem 10 512 1024
    : ~ i whole v
    : ~ i frac tenth
    ? >= frac 10 { = whole + whole 1 = frac 0 } {}
    ( string_push_int out whole )
    ( string_push_char out 46 )
    ( string_push_int out frac )
    ( string_push_char out ( nurl_str_get units unit ) )
    ^ out
}

@ __df_row String out s dev s dir b human FsStat st → v {
    : i unit . st frsize
    : i total * . st blocks unit
    : i avail * . st bavail unit
    : i used - total * . st bfree unit
    : i dw ( nurl_str_len dev )
    ( string_push_str out dev )
    : ~ i pad - 20 dw
    ~ > pad 0 { ( string_push_char out 32 ) = pad - pad 1 }
    ? human {
        : String a ( __df_human total )
        : String b ( __df_human used )
        : String c ( __df_human avail )
        ( bx_push_right out ( string_data a ) 10 )
        ( bx_push_right out ( string_data b ) 10 )
        ( bx_push_right out ( string_data c ) 10 )
        ( string_free a )
        ( string_free b )
        ( string_free c )
    } {
        ( bx_push_right out ( nurl_str_int / total 1024 ) 10 )
        ( bx_push_right out ( nurl_str_int / used 1024 ) 10 )
        ( bx_push_right out ( nurl_str_int / avail 1024 ) 10 )
    }
    // Truncated, not rounded: a filesystem 91.2% full is 91% full, and
    // this is the number every df has printed for forty years.
    : i denom + used avail
    : i pct ? > denom 0 / * used 100 denom 0
    ( bx_push_right out ( nurl_str_int pct ) 4 )
    ( string_push_str out `% ` )
    ( string_push_str out dir )
    ( string_push_char out 10 )
}

// The device whose mount point is the longest prefix of `path` — the
// same "most specific mount wins" rule the kernel resolves paths with.
@ __device_for s path → String {
    : ( Vec MountEnt ) ms ( vec_new [MountEnt] )
    : ~ String best ( string_from path )
    : ~ i bestlen -1
    ? ( __mounts ms ) {
        : String real ( string_new )
        : Path pp ( path_new path )
        ?? ( path_canonical pp ) {
            T c → {
                ( string_push_str real ( path_str c ) )
                ( path_free c )
            }
            F _ → { ( string_push_str real path ) }
        }
        ( path_free pp )
        : i cnt ( vec_len [MountEnt] ms )
        : ~ i i 0
        ~ < i cnt {
            ?? ( vec_get [MountEnt] ms i ) {
                T m → {
                    : i dl ( string_len . m dir )
                    ? & > dl bestlen ( string_starts_with real ( string_data . m dir ) ) {
                        = bestlen dl
                        ( string_free best )
                        = best ( string_clone . m dev )
                    } {}
                }
                F _ → {}
            }
            = i + i 1
        }
        ( string_free real )
    } {}
    ( vec_free_with [MountEnt] ms \ MountEnt m → v { ( __mount_free m ) } )
    ^ best
}

@ ap_df ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `hkmPia` `human-readable=h,portability=P,all=a` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : b human ( bx_has o `h` )
        : String out ( string_new )
        ( string_push_str out ? human
        `Filesystem                Size      Used Available Use% Mounted on\n`
        `Filesystem           1K-blocks      Used Available Use% Mounted on\n` )
        : i nops ( bx_operand_count o )
        ? > nops 0 {
            : ~ i i 0
            ~ < i nops {
                : s p ( bx_operand o i )
                ?? ( fs_statfs p ) {
                    T st → {
                        // The Filesystem column names the DEVICE, which
                        // only the mount table knows.
                        : String dev ( __device_for p )
                        ( __df_row out ( string_data dev ) p human st )
                        ( string_free dev )
                    }
                    F e → {
                        ( bx_err_at p ( bx_ioerr e ) )
                        = rc 1
                    }
                }
                = i + i 1
            }
        } {
            : ( Vec MountEnt ) ms ( vec_new [MountEnt] )
            ? ! ( __mounts ms ) {
                = rc ( __proc_no_procfs )
            } {
                : i cnt ( vec_len [MountEnt] ms )
                : ~ i i 0
                ~ < i cnt {
                    ?? ( vec_get [MountEnt] ms i ) {
                        T m → {
                            ?? ( fs_statfs ( string_data . m dir ) ) {
                                T st → {
                                    // A pseudo-filesystem with no blocks
                                    // is not a disk; -a asks for it
                                    // anyway.
                                    ? | ( bx_has o `a` ) > . st blocks 0 {
                                        ( __df_row out ( string_data . m dev ) ( string_data . m dir ) human st )
                                    } {}
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                    = i + i 1
                }
            }
            ( vec_free_with [MountEnt] ms \ MountEnt m → v { ( __mount_free m ) } )
        }
        ( bx_write out )
        ( string_free out )
    }
    ( bx_opts_free o )
    ^ rc
}
