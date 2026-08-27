// nurlbox — one binary, many utilities.
//
// The busybox idea, in NURL: a single executable that decides which
// utility it is from the name it was invoked under. Symlink `cat` at it
// and it is `cat`; run `nurlbox cat` and it is `cat` too. Everything is
// pure NURL over the shipped stdlib — no shelling out, nothing that
// needs a system `coreutils` underneath.
//
//     nurlbox                  list the applets
//     nurlbox cat file         run one, by name
//     nurlbox --install DIR    populate DIR with a symlink per applet
//     ln -s nurlbox /bin/cat   the busybox way, thereafter `cat file`

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/ext/env.nu`
$ `bx.nu`
$ `text.nu`
$ `sys.nu`
$ `fileops.nu`
$ `find.nu`
$ `filter.nu`
$ `hash.nu`
$ `grep.nu`
$ `shell.nu`
$ `sed.nu`

: s NURLBOX_VERSION `0.1.0`

// Every applet, in the order `nurlbox` lists them.
@ __applet_names → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `[` ) )
    ( vec_push [String] v ( string_from `arch` ) )
    ( vec_push [String] v ( string_from `base64` ) )
    ( vec_push [String] v ( string_from `basename` ) )
    ( vec_push [String] v ( string_from `cat` ) )
    ( vec_push [String] v ( string_from `chmod` ) )
    ( vec_push [String] v ( string_from `cksum` ) )
    ( vec_push [String] v ( string_from `clear` ) )
    ( vec_push [String] v ( string_from `cp` ) )
    ( vec_push [String] v ( string_from `crc32` ) )
    ( vec_push [String] v ( string_from `cut` ) )
    ( vec_push [String] v ( string_from `date` ) )
    ( vec_push [String] v ( string_from `dirname` ) )
    ( vec_push [String] v ( string_from `du` ) )
    ( vec_push [String] v ( string_from `echo` ) )
    ( vec_push [String] v ( string_from `egrep` ) )
    ( vec_push [String] v ( string_from `env` ) )
    ( vec_push [String] v ( string_from `expr` ) )
    ( vec_push [String] v ( string_from `false` ) )
    ( vec_push [String] v ( string_from `fgrep` ) )
    ( vec_push [String] v ( string_from `find` ) )
    ( vec_push [String] v ( string_from `grep` ) )
    ( vec_push [String] v ( string_from `groups` ) )
    ( vec_push [String] v ( string_from `head` ) )
    ( vec_push [String] v ( string_from `hostname` ) )
    ( vec_push [String] v ( string_from `id` ) )
    ( vec_push [String] v ( string_from `ln` ) )
    ( vec_push [String] v ( string_from `logname` ) )
    ( vec_push [String] v ( string_from `ls` ) )
    ( vec_push [String] v ( string_from `md5sum` ) )
    ( vec_push [String] v ( string_from `mkdir` ) )
    ( vec_push [String] v ( string_from `mktemp` ) )
    ( vec_push [String] v ( string_from `mv` ) )
    ( vec_push [String] v ( string_from `nl` ) )
    ( vec_push [String] v ( string_from `nproc` ) )
    ( vec_push [String] v ( string_from `printenv` ) )
    ( vec_push [String] v ( string_from `printf` ) )
    ( vec_push [String] v ( string_from `pwd` ) )
    ( vec_push [String] v ( string_from `readlink` ) )
    ( vec_push [String] v ( string_from `realpath` ) )
    ( vec_push [String] v ( string_from `rev` ) )
    ( vec_push [String] v ( string_from `rm` ) )
    ( vec_push [String] v ( string_from `rmdir` ) )
    ( vec_push [String] v ( string_from `sed` ) )
    ( vec_push [String] v ( string_from `seq` ) )
    ( vec_push [String] v ( string_from `sha1sum` ) )
    ( vec_push [String] v ( string_from `sha256sum` ) )
    ( vec_push [String] v ( string_from `sha512sum` ) )
    ( vec_push [String] v ( string_from `sleep` ) )
    ( vec_push [String] v ( string_from `sort` ) )
    ( vec_push [String] v ( string_from `stat` ) )
    ( vec_push [String] v ( string_from `sync` ) )
    ( vec_push [String] v ( string_from `tac` ) )
    ( vec_push [String] v ( string_from `tail` ) )
    ( vec_push [String] v ( string_from `tee` ) )
    ( vec_push [String] v ( string_from `test` ) )
    ( vec_push [String] v ( string_from `touch` ) )
    ( vec_push [String] v ( string_from `tr` ) )
    ( vec_push [String] v ( string_from `true` ) )
    ( vec_push [String] v ( string_from `truncate` ) )
    ( vec_push [String] v ( string_from `tty` ) )
    ( vec_push [String] v ( string_from `uname` ) )
    ( vec_push [String] v ( string_from `uniq` ) )
    ( vec_push [String] v ( string_from `usleep` ) )
    ( vec_push [String] v ( string_from `wc` ) )
    ( vec_push [String] v ( string_from `which` ) )
    ( vec_push [String] v ( string_from `whoami` ) )
    ( vec_push [String] v ( string_from `xargs` ) )
    ( vec_push [String] v ( string_from `yes` ) )
    ^ v
}

// argv[0]'s basename, with a `.exe` suffix and any `nurlbox-` prefix
// stripped — the three spellings an installed multi-call binary meets.
@ __invoked_as ( Vec String ) argv → String {
    : s a0 ( bx_at argv 0 )
    : String base ( path_basename a0 )
    ? ( string_ends_with base `.exe` ) {
        : String cut ( string_substr base 0 - ( string_len base ) 4 )
        ( string_free base )
        ^ cut
    } {}
    ^ base
}

// The dispatcher. `argv` is the applet's own argument vector: argv[0]
// is the applet name, exactly as a directly-executed utility sees it.
@ __run s name ( Vec String ) argv → i {
    ( bx_set_name name )
    ? ( bx_streq name `[` ) { ^ ( ap_test argv ) } {}
    ? ( bx_streq name `arch` ) { ^ ( ap_arch argv ) } {}
    ? ( bx_streq name `base64` ) { ^ ( ap_base64 argv ) } {}
    ? ( bx_streq name `basename` ) { ^ ( ap_basename argv ) } {}
    ? ( bx_streq name `cat` ) { ^ ( ap_cat argv ) } {}
    ? ( bx_streq name `chmod` ) { ^ ( ap_chmod argv ) } {}
    ? ( bx_streq name `cksum` ) { ^ ( ap_cksum argv ) } {}
    ? ( bx_streq name `clear` ) { ^ ( ap_clear argv ) } {}
    ? ( bx_streq name `cp` ) { ^ ( ap_cp argv ) } {}
    ? ( bx_streq name `crc32` ) { ^ ( ap_crc32 argv ) } {}
    ? ( bx_streq name `cut` ) { ^ ( ap_cut argv ) } {}
    ? ( bx_streq name `date` ) { ^ ( ap_date argv ) } {}
    ? ( bx_streq name `dirname` ) { ^ ( ap_dirname argv ) } {}
    ? ( bx_streq name `du` ) { ^ ( ap_du argv ) } {}
    ? ( bx_streq name `echo` ) { ^ ( ap_echo argv ) } {}
    ? ( bx_streq name `egrep` ) { ^ ( ap_grep argv ) } {}
    ? ( bx_streq name `env` ) { ^ ( ap_env argv ) } {}
    ? ( bx_streq name `expr` ) { ^ ( ap_expr argv ) } {}
    ? ( bx_streq name `false` ) { ^ 1 } {}
    ? ( bx_streq name `fgrep` ) { ^ ( ap_grep argv ) } {}
    ? ( bx_streq name `find` ) { ^ ( ap_find argv ) } {}
    ? ( bx_streq name `grep` ) { ^ ( ap_grep argv ) } {}
    ? ( bx_streq name `groups` ) { ^ ( ap_groups argv ) } {}
    ? ( bx_streq name `head` ) { ^ ( ap_head argv ) } {}
    ? ( bx_streq name `hostname` ) { ^ ( ap_hostname argv ) } {}
    ? ( bx_streq name `id` ) { ^ ( ap_id argv ) } {}
    ? ( bx_streq name `ln` ) { ^ ( ap_ln argv ) } {}
    ? ( bx_streq name `logname` ) { ^ ( ap_logname argv ) } {}
    ? ( bx_streq name `ls` ) { ^ ( ap_ls argv ) } {}
    ? ( bx_streq name `md5sum` ) { ^ ( ap_md5sum argv ) } {}
    ? ( bx_streq name `mkdir` ) { ^ ( ap_mkdir argv ) } {}
    ? ( bx_streq name `mktemp` ) { ^ ( ap_mktemp argv ) } {}
    ? ( bx_streq name `mv` ) { ^ ( ap_mv argv ) } {}
    ? ( bx_streq name `nl` ) { ^ ( ap_nl argv ) } {}
    ? ( bx_streq name `nproc` ) { ^ ( ap_nproc argv ) } {}
    ? ( bx_streq name `printenv` ) { ^ ( ap_printenv argv ) } {}
    ? ( bx_streq name `printf` ) { ^ ( ap_printf argv ) } {}
    ? ( bx_streq name `pwd` ) { ^ ( ap_pwd argv ) } {}
    ? ( bx_streq name `readlink` ) { ^ ( ap_readlink argv ) } {}
    ? ( bx_streq name `realpath` ) { ^ ( ap_realpath argv ) } {}
    ? ( bx_streq name `rev` ) { ^ ( ap_rev argv ) } {}
    ? ( bx_streq name `rm` ) { ^ ( ap_rm argv ) } {}
    ? ( bx_streq name `rmdir` ) { ^ ( ap_rmdir argv ) } {}
    ? ( bx_streq name `sed` ) { ^ ( ap_sed argv ) } {}
    ? ( bx_streq name `seq` ) { ^ ( ap_seq argv ) } {}
    ? ( bx_streq name `sha1sum` ) { ^ ( ap_sha1sum argv ) } {}
    ? ( bx_streq name `sha256sum` ) { ^ ( ap_sha256sum argv ) } {}
    ? ( bx_streq name `sha512sum` ) { ^ ( ap_sha512sum argv ) } {}
    ? ( bx_streq name `sleep` ) { ^ ( ap_sleep argv ) } {}
    ? ( bx_streq name `sort` ) { ^ ( ap_sort argv ) } {}
    ? ( bx_streq name `stat` ) { ^ ( ap_stat argv ) } {}
    ? ( bx_streq name `sync` ) { ^ ( ap_sync argv ) } {}
    ? ( bx_streq name `tac` ) { ^ ( ap_tac argv ) } {}
    ? ( bx_streq name `tail` ) { ^ ( ap_tail argv ) } {}
    ? ( bx_streq name `tee` ) { ^ ( ap_tee argv ) } {}
    ? ( bx_streq name `test` ) { ^ ( ap_test argv ) } {}
    ? ( bx_streq name `touch` ) { ^ ( ap_touch argv ) } {}
    ? ( bx_streq name `tr` ) { ^ ( ap_tr argv ) } {}
    ? ( bx_streq name `true` ) { ^ 0 } {}
    ? ( bx_streq name `truncate` ) { ^ ( ap_truncate argv ) } {}
    ? ( bx_streq name `tty` ) { ^ ( ap_tty argv ) } {}
    ? ( bx_streq name `uname` ) { ^ ( ap_uname argv ) } {}
    ? ( bx_streq name `uniq` ) { ^ ( ap_uniq argv ) } {}
    ? ( bx_streq name `usleep` ) { ^ ( ap_usleep argv ) } {}
    ? ( bx_streq name `wc` ) { ^ ( ap_wc argv ) } {}
    ? ( bx_streq name `which` ) { ^ ( ap_which argv ) } {}
    ? ( bx_streq name `whoami` ) { ^ ( ap_whoami argv ) } {}
    ? ( bx_streq name `xargs` ) { ^ ( ap_xargs argv ) } {}
    ? ( bx_streq name `yes` ) { ^ ( ap_yes argv ) } {}
    ( bx_set_name `nurlbox` )
    ( bx_err_at name `applet not found` )
    ^ 127
}

@ __list_applets → v {
    ( nurl_print `nurlbox ` )
    ( nurl_print NURLBOX_VERSION )
    ( nurl_print ` — a multi-call binary of UNIX utilities, in NURL.\n\n` )
    ( nurl_print `Usage: nurlbox [applet] [arguments]...\n` )
    ( nurl_print `   or: applet [arguments]...\n\n` )
    ( nurl_print `Currently defined applets:\n` )
    : ( Vec String ) names ( __applet_names )
    : i n ( vec_len [String] names )
    : ~ i i 0
    : ~ i col 0
    ~ < i n {
        ( nurl_print ? == col 0 `\t` `, ` )
        ( nurl_print ( bx_at names i ) )
        = col + col 1
        ? >= col 8 { ( nurl_print `\n` ) = col 0 } {}
        = i + i 1
    }
    ? > col 0 { ( nurl_print `\n` ) } {}
    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
}

// Is `name` one of ours? A binary invoked under a name it does not
// implement is the MULTIPLEXER — that is how `nurlbox` behaves when the
// unikernel's loader calls it `main`, and how a copy named anything else
// still works.
@ __is_applet s name → b {
    : ( Vec String ) names ( __applet_names )
    : i n ( vec_len [String] names )
    : ~ b found F
    : ~ i i 0
    ~ < i n {
        ? ( bx_streq ( bx_at names i ) name ) { = found T } {}
        = i + i 1
    }
    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
    ^ found
}

@ main → i {
    : ( Vec String ) argv ( env_args_list )
    : String me ( __invoked_as argv )
    : ~ i rc 0
    ? ! ( __is_applet ( string_data me ) ) {
        ? < ( vec_len [String] argv ) 2 {
            ( __list_applets )
            = rc 0
        } {
            : s sub ( bx_at argv 1 )
            ? | ( bx_streq sub `--help` ) ( bx_streq sub `-h` ) {
                ( __list_applets )
                = rc 0
            } {
                ? | ( bx_streq sub `--version` ) ( bx_streq sub `-V` ) {
                    ( nurl_print `nurlbox ` )
                    ( nurl_print NURLBOX_VERSION )
                    ( nurl_print `\n` )
                    = rc 0
                } {
                    // shift: the applet sees argv[0] = its own name
                    : ( Vec String ) sub_argv ( vec_new [String] )
                    : i n ( vec_len [String] argv )
                    : ~ i i 1
                    ~ < i n {
                        ( vec_push [String] sub_argv ( string_from ( bx_at argv i ) ) )
                        = i + i 1
                    }
                    = rc ( __run sub sub_argv )
                    ( vec_free_with [String] sub_argv \ String x → v { ( string_free x ) } )
                }
            }
        }
    } {
        = rc ( __run ( string_data me ) argv )
    }
    ( string_free me )
    ( vec_free_with [String] argv \ String x → v { ( string_free x ) } )
    ^ rc
}
