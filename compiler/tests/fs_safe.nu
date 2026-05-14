// fs_safe.nu — exercises stdlib/std/fs.nu non-fatal API
//
// Expected output (each block):
//   write_file ok
//   read_file ok: hello fs
//   size 8
//   append_file ok
//   read_file ok: hello fs!
//   delete ok
//   read_file err: not found
//   write_file dir err: not found
//   dir_create ok
//   dir_create exists err: already exists

$ `stdlib/std/fs.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`

@ show_io_result_v ! v IoErr r s ok_msg → v {
    ?? r {
        T → ( nurl_print ok_msg )
        F e → {
            ( nurl_print `err: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
        }
    }
    ( nurl_print `\n` )
}

@ main → i {
    : s path `nurl_fs_test.tmp`
    : s missing `nurl_fs_test_does_not_exist.tmp`
    : s nest_path `nurl_fs_test_dir/nope.tmp`
    : s dir_path `nurl_fs_test_dir`

    // Make sure leftovers from previous runs don't pollute the test.
    ? ( file_exists path ) {
        : !v IoErr _ ( file_delete path )
    } {}
    // The "should fail" path nest_path lives inside dir_path, so cleaning
    // up dir_path also handles any stray file inside it.
    ? ( file_exists nest_path ) {
        : !v IoErr _ ( file_delete nest_path )
    } {}
    ? ( file_exists dir_path ) {
        : !v IoErr _ ( dir_remove dir_path )
    } {}

    // 1. write_file → read_file → file_size
    : !v IoErr w1 ( write_file path `hello fs` )
    ( show_io_result_v w1 `write_file ok` )

    : !String IoErr r1 ( read_file path )
    ?? r1 {
        T s → {
            ( nurl_print `read_file ok: ` )
            ( nurl_print ( string_data s ) )
            ( nurl_print `\n` )
            ( string_free s )
        }
        F e → {
            ( nurl_print `read_file err: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    : !i IoErr sz ( file_size path )
    ?? sz {
        T n → {
            ( nurl_print `size ` )
            ( nurl_print ( nurl_str_int n ) )
            ( nurl_print `\n` )
        }
        F e → {
            ( nurl_print `size err: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    // 2. append_file → read_file
    : !v IoErr a1 ( append_file path `!` )
    ( show_io_result_v a1 `append_file ok` )

    : !String IoErr r2 ( read_file path )
    ?? r2 {
        T s → {
            ( nurl_print `read_file ok: ` )
            ( nurl_print ( string_data s ) )
            ( nurl_print `\n` )
            ( string_free s )
        }
        F e → {
            ( nurl_print `read_file err: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    // 3. delete
    : !v IoErr d1 ( file_delete path )
    ( show_io_result_v d1 `delete ok` )

    // 4. read_file on missing → NotFound
    : !String IoErr r3 ( read_file missing )
    ?? r3 {
        T s → {
            ( nurl_print `unexpected ok\n` )
            ( string_free s )
        }
        F e → {
            ( nurl_print `read_file err: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    // 5. write_file into a directory that doesn't exist → NotFound
    : !v IoErr w2 ( write_file nest_path `data` )
    ?? w2 {
        T → ( nurl_print `unexpected ok\n` )
        F e → {
            ( nurl_print `write_file dir err: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    // 6. dir_create + duplicate dir_create → AlreadyExists
    : !v IoErr c1 ( dir_create dir_path )
    ( show_io_result_v c1 `dir_create ok` )

    : !v IoErr c2 ( dir_create dir_path )
    ?? c2 {
        T → ( nurl_print `unexpected ok\n` )
        F e → {
            ( nurl_print `dir_create exists err: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    ^ 0
}
