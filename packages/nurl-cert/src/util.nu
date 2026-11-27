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

@ nc_join s a s b → String {
    : String out ( string_from a )
    ? ! ( string_ends_with out `/` ) { ( string_push_char out 47 ) } {}
    ( string_push_str out b )
    ^ out
}

// Is `path` absolute: `/…`, or on Windows a drive's `X:/…` / `X:\…` or a
// share's `\\…`?
@ nc_is_abs s path → b {
    : i c0 ( nurl_str_get path 0 )
    ? | == c0 47 == c0 92 { ^ T } {}
    : b letter | & >= c0 65 <= c0 90 & >= c0 97 <= c0 122
    ? & letter == ( nurl_str_get path 1 ) 58 {
        : i c2 ( nurl_str_get path 2 )
        ^ | == c2 47 == c2 92
    } {}
    ^ F
}

// `path` made absolute against the working directory.
@ nc_abs s path → String {
    ? ( nc_is_abs path ) { ^ ( string_from path ) } {}
    ^ ?? ( env_cwd ) {
        T cwd → ( nc_join ( string_data cwd ) path )
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
