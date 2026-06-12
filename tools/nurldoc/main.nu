// tools/nurldoc/main.nu — generate Markdown API docs from NURL source.
//
// Usage:
//   nurldoc <file.nu>            render one module to stdout
//   nurldoc <src-dir> <out-dir>  render every *.nu under src-dir to
//                                out-dir/<name>.md (recursive, via fs_glob)
//
// The rendering lives in stdlib/ext/nurldoc.nu (nurldoc_render); this is
// a thin CLI that handles argv, file discovery, and output.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/nurldoc.nu`

// Basename of a path with the `.nu` extension dropped (`a/b/vec.nu` →
// `vec`). Used as the doc title and output filename stem.
@ __stem s path → String {
    : i n ( nurl_str_len path )
    : ~ i slash -1
    : ~ i k 0
    ~ < k n { ? == ( nurl_str_get path k ) 47 { = slash k } {} = k + k 1 }
    : i start + slash 1
    : ~ i end n
    ? & >= n 3 ( __ends_nu path n ) { = end - n 3 } {}
    : String out ( string_with_cap + - end start 1 )
    : ~ i j start
    ~ < j end { ( string_push_char out ( nurl_str_get path j ) ) = j + j 1 }
    ^ out
}

@ __ends_nu s path i n → b {
    ^ & & == ( nurl_str_get path - n 3 ) 46 == ( nurl_str_get path - n 2 ) 110 == ( nurl_str_get path - n 1 ) 117
}

// Render one source file to Markdown (owned String); empty on read error.
@ __render_file s path → String {
    : !String IoErr r ( read_file path )
    ^ ?? r {
        T content → {
            : String stem ( __stem path )
            : String md ( nurldoc_render ( string_data content ) ( string_data stem ) )
            ( string_free stem )
            ( string_free content )
            ^ md
        }
        F _ → ( string_with_cap 1 )
    }
}

@ __cmp_str s a s b → i { ^ ( nurl_str_cmp a b ) }

@ main → i {
    : i argc ( env_args_count )
    ? < argc 2 {
        ( nurl_eprintln `usage: nurldoc <file.nu> | nurldoc <src-dir> <out-dir>` )
        ^ 1
    } {}
    : String a1 ( env_arg 1 )
    : s src ( string_data a1 )

    // Single-file mode: one arg that is a regular file → stdout.
    ? & < argc 3 == 1 ( nurl_path_type src ) {
        : String md ( __render_file src )
        ( nurl_print ( string_data md ) )
        ( string_free md )
        ( string_free a1 )
        ^ 0
    } {}

    ? < argc 3 {
        ( nurl_eprintln `nurldoc: directory mode needs an <out-dir>` )
        ( string_free a1 )
        ^ 1
    } {}
    : String a2 ( env_arg 2 )
    : s out_dir ( string_data a2 )

    : !v IoErr _mk ( dir_create_all out_dir )
    ?? _mk { T _ → {} F _ → {} }

    // Glob `<src>/**/*.nu`, render each, write `<out>/<stem>.md`.
    : String pat ( string_with_cap + ( nurl_str_len src ) 8 )
    ( string_push_str pat src )
    ( string_push_str pat `/**/*.nu` )
    : !( Vec String ) IoErr gr ( fs_glob ( string_data pat ) )
    ( string_free pat )
    : ~ i count 0
    ?? gr {
        T files → {
            : i nf ( vec_len [String] files )
            // stable order
            : ( @ i String String ) cmp \ String x String y → i { ^ ( __cmp_str ( string_data x ) ( string_data y ) ) }
            ( sort_by [String] files cmp )
            : ~ i k 0
            ~ < k nf {
                : ?String fo ( vec_get [String] files k )
                ?? fo {
                    T f → {
                        : String md ( __render_file ( string_data f ) )
                        : String stem ( __stem ( string_data f ) )
                        : String opath ( string_with_cap + + ( nurl_str_len out_dir ) ( string_len stem ) 5 )
                        ( string_push_str opath out_dir )
                        ( string_push_char opath 47 )
                        ( string_push_str opath ( string_data stem ) )
                        ( string_push_str opath `.md` )
                        : !v IoErr wr ( write_file ( string_data opath ) ( string_data md ) )
                        ?? wr {
                            T _ → { = count + count 1 }
                            F _ → ( nurl_eprintln ( string_data opath ) )
                        }
                        ( string_free opath ) ( string_free stem ) ( string_free md )
                        ( string_free f )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free [String] files )
        }
        F _ → ( nurl_eprintln `nurldoc: glob failed` )
    }
    ( nurl_print `nurldoc: wrote ` )
    ( nurl_print ( nurl_str_int count ) )
    ( nurl_print ` files\n` )
    ( string_free a2 )
    ( string_free a1 )
    ^ 0
}
