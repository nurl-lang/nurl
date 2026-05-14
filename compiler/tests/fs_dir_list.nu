// fs_dir_list.nu — exercises stdlib/std/fs.nu dir_list
//
// Expected output:
//   missing: not found
//   dir_create ok
//   write a.txt ok
//   write b.txt ok
//   count: 2
//   has a.txt: T
//   has b.txt: T
//   cleanup ok

$ `stdlib/std/fs.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`

@ has_entry ( Vec String ) v s name → b {
    : i n ( vec_len [String] v )
    : ~ i i 0
    : ~ b found F
    ~ < i n {
        : ?String got ( vec_get [String] v i )
        ?? got {
            T s → {
                ? != 0 ( nurl_str_eq ( string_data s ) name ) {
                    = found T
                } {}
            }
            F → {}
        }
        = i + i 1
    }
    ^ found
}

@ main → i {
    : s dir_path `nurl_dir_list_test_dir`
    : s a_path `nurl_dir_list_test_dir/a.txt`
    : s b_path `nurl_dir_list_test_dir/b.txt`

    // Cleanup leftovers
    ? ( file_exists a_path ) { : !v IoErr _ ( file_delete a_path ) } {}
    ? ( file_exists b_path ) { : !v IoErr _ ( file_delete b_path ) } {}
    ? ( file_exists dir_path ) { : !v IoErr _ ( dir_remove dir_path ) } {}

    // 1. dir_list on missing path → NotFound
    : !( Vec String ) IoErr miss ( dir_list `nurl_no_such_dir_xxx` )
    ?? miss {
        T v → {
            ( nurl_print `unexpected ok\n` )
            : ( @ v String ) drop_str \ String e → v { ( string_free e ) }
            ( vec_free_with [String] v drop_str )
        }
        F e → {
            ( nurl_print `missing: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    // 2. Build a real directory with two files
    : !v IoErr c1 ( dir_create dir_path )
    ?? c1 {
        T → ( nurl_print `dir_create ok\n` )
        F e → { ( nurl_print `dir_create err: ` ) ( nurl_print ( io_err_msg # IoErr e ) ) ( nurl_print `\n` ) }
    }

    : !v IoErr w1 ( write_file a_path `aa` )
    ?? w1 {
        T → ( nurl_print `write a.txt ok\n` )
        F e → { ( nurl_print `write a err: ` ) ( nurl_print ( io_err_msg # IoErr e ) ) ( nurl_print `\n` ) }
    }
    : !v IoErr w2 ( write_file b_path `bb` )
    ?? w2 {
        T → ( nurl_print `write b.txt ok\n` )
        F e → { ( nurl_print `write b err: ` ) ( nurl_print ( io_err_msg # IoErr e ) ) ( nurl_print `\n` ) }
    }

    // 3. List the directory
    : !( Vec String ) IoErr lst ( dir_list dir_path )
    ?? lst {
        T v → {
            ( nurl_print `count: ` )
            ( nurl_print ( nurl_str_int ( vec_len [String] v ) ) )
            ( nurl_print `\n` )
            : b a_in ( has_entry v `a.txt` )
            : b b_in ( has_entry v `b.txt` )
            ( nurl_print `has a.txt: ` )
            ? a_in { ( nurl_print `T` ) } { ( nurl_print `F` ) }
            ( nurl_print `\n` )
            ( nurl_print `has b.txt: ` )
            ? b_in { ( nurl_print `T` ) } { ( nurl_print `F` ) }
            ( nurl_print `\n` )
            : ( @ v String ) drop_str \ String e → v { ( string_free e ) }
            ( vec_free_with [String] v drop_str )
        }
        F e → {
            ( nurl_print `dir_list err: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    // 4. cleanup
    : !v IoErr d1 ( file_delete a_path )
    : !v IoErr d2 ( file_delete b_path )
    : !v IoErr dr ( dir_remove dir_path )
    ?? dr {
        T → ( nurl_print `cleanup ok\n` )
        F e → { ( nurl_print `cleanup err: ` ) ( nurl_print ( io_err_msg # IoErr e ) ) ( nurl_print `\n` ) }
    }

    ^ 0
}
