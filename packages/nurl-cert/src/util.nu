// util.nu — files, hashes and child processes for nurl-cert.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/sysinfo.nu`

@ nc_join s a s b → String {
    : String out ( string_from a )
    ? ! ( string_ends_with out `/` ) { ( string_push_char out 47 ) } {}
    ( string_push_str out b )
    ^ out
}

// Does this host take a backslash for a path separator (Windows)?
@ nc_backslash_sep → b { ^ == ( sys_os ) SYS_OS_WINDOWS }

@ __nc_sep i c → b { ^ | == c 47 & == c 92 ( nc_backslash_sep ) }

// Is `path` fully qualified, the same file from any working directory:
// `/…`; on Windows instead a drive's `X:/…` or `X:\…` and a share's
// `\\host\…` (elsewhere a backslash is a file name's byte). A Windows
// `\x` or `/x` names x on the working directory's drive: not qualified.
@ nc_is_abs s path → b {
    : i c0 ( nurl_str_get path 0 )
    ? ! ( nc_backslash_sep ) { ^ == c0 47 } {}
    ? & ( __nc_sep c0 ) ( __nc_sep ( nurl_str_get path 1 ) ) { ^ T } {}
    : b letter | & >= c0 65 <= c0 90 & >= c0 97 <= c0 122
    ? & letter == ( nurl_str_get path 1 ) 58 { ^ ( __nc_sep ( nurl_str_get path 2 ) ) } {}
    ^ F
}

@ __nc_upper i c → i { ^ ? & >= c 97 <= c 122 - c 32 c }

// The root of Windows directory `d`: its drive `X:`, or the share
// `\\host\share` it lies under; empty for any other.
@ __nc_root String d → String {
    : i n ( string_len d )
    ? & >= n 2 == ( string_get d 1 ) 58 { ^ ( string_substr d 0 2 ) } {}
    ? | < n 2 | ! ( __nc_sep ( string_get d 0 ) ) ! ( __nc_sep ( string_get d 1 ) ) { ^ ( string_new ) } {}
    // past `\\`, the host, its separator, then the share
    : ~ i k 2
    : ~ i seps 0
    ~ & < k n < seps 2 {
        ? ( __nc_sep ( string_get d k ) ) { = seps + seps 1 } {}
        ? < seps 2 { = k + k 1 } {}
    }
    ^ ( string_substr d 0 k )
}

// `path` made absolute against the working directory (on Windows, a path
// rooted on no drive, `\x`, against the working directory's drive), so a
// later change of directory or drive does not change the file it names.
@ nc_abs s path → String {
    ? ( nc_is_abs path ) { ^ ( string_from path ) } {}
    ^ ?? ( env_cwd ) {
        T cwd → {
            // (a drive-relative `X:rel`, on the working directory's drive:
            // under the working directory; on another drive it keeps its
            // drive, and nothing here knows that drive's directory)
            : i p0 ( nurl_str_get path 0 )
            ? & & ( nc_backslash_sep ) == ( nurl_str_get path 1 ) 58 | & >= p0 65 <= p0 90 & >= p0 97 <= p0 122 {
                : String r ( __nc_root cwd )
                ? & == ( string_len r ) 2 == ( __nc_upper ( string_get r 0 ) ) ( __nc_upper p0 ) {
                    : String rest ( string_from path )
                    ^ ( nc_join ( string_data cwd ) ( string_data ( string_substr rest 2 - ( string_len rest ) 2 ) ) )
                } {}
                ^ ( string_from path )
            } {}
            ? ( __nc_sep ( nurl_str_get path 0 ) ) {
                // (the root of the working directory before `\x`: `C:` of
                // `C:\work`, `\\host\share` of `\\host\share\work`)
                : String o ( __nc_root cwd )
                ( string_push_str o path )
                o
            } { ( nc_join ( string_data cwd ) path ) }
        }
        F _ → ( string_from path )
    }
}

// The lowercase hex sha256 of a file's bytes, or none when it cannot be
// read.
@ nc_sha256_file s path → ?String {
    ^ ?? ( read_file_bytes path ) {
        T bytes → @ ?String { T ( bytes_to_hex ( sha256_pure bytes ) ) }
        F _ → @ ?String { F }
    }
}

@ nc_sha256_text s text → String {
    ^ ( bytes_to_hex ( sha256_pure ( bytes_from_str text ) ) )
}

@ nc_read s path → ?String {
    ^ ?? ( read_file path ) {
        T text → @ ?String { T text }
        F _ → @ ?String { F }
    }
}

@ nc_write s path s text → b {
    ^ ?? ( write_file path text ) {
        T _ → T
        F _ → F
    }
}

@ nc_mkdirs s path → b {
    ^ ?? ( dir_create_all path ) {
        T _ → T
        F _ → F
    }
}

// A child's run: whether it started, its exit code, and what it wrote.
: Run {
    b started
    i code
    String out
    String err
}

@ nc_run s cmd ( Vec String ) args → Run {
    ^ ?? ( process_run_strings cmd args `` ) {
        T o → {
            : String so ( string_new )
            ( string_push_str so ( output_stdout o ) )
            : String se ( string_new )
            ( string_push_str se ( output_stderr o ) )
            @ Run { T ( output_exit_code o ) so se }
        }
        F e → {
            : String se ( string_from `could not start ` )
            ( string_push_str se cmd )
            ( string_push_str se `: ` )
            ( string_push_str se ( process_err_name e ) )
            @ Run { F -1 ( string_new ) se }
        }
    }
}

@ nc_sort ( Vec String ) v → v {
    ( sort_by [String] v \ String a String b → i { ^ ( nurl_str_cmp ( string_data a ) ( string_data b ) ) } )
}

// Lines of `text`, without their newlines.
@ nc_lines s text → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ( Slice u ) t ( slice_of_str text )
    : i n ( slice_len [u] t )
    : ~ i a 0
    ~ < a n {
        : ~ i z a
        ~ & < z n != ( slice_byte t z ) 10 { = z + z 1 }
        : String l ( string_new )
        ( string_push_window l t a - z a )
        ( vec_push [String] out l )
        = a + z 1
    }
    ^ out
}

@ nc_is String a s b → b { ^ != 0 ( nurl_str_eq ( string_data a ) b ) }

@ nc_eprint2 s a s b → v {
    ( nurl_eprint a )
    ( nurl_eprintln b )
}
