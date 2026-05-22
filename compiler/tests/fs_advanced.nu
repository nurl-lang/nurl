// fs_advanced.nu — exercises the advanced filesystem operations added
// to stdlib/std/fs.nu: recursive dir_create_all / dir_remove_all and
// the handle-based chunked file reader (file_open / file_read_chunk /
// file_eof / file_close).
//
// Self-cleaning: removes its scratch tree at start and end.
//
// Expected output:
//   create_all nested: ok
//   exists root: T
//   exists a/b/c: T
//   create_all again: ok
//   wrote data file
//   chunks: 3
//   total: 20
//   content: 0123456789ABCDEFGHIJ
//   eof: T
//   remove_all: ok
//   exists after remove: F
//   remove_all missing: not found

$ `stdlib/std/fs.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`

@ main → i {
    : s root `nurl_fs_adv_test`
    : s deep `nurl_fs_adv_test/a/b/c`
    : s data_path `nurl_fs_adv_test/a/b/c/data.bin`

    // Clean any leftovers from a previous run.
    ? ( file_exists root ) {
        : !v IoErr _ ( dir_remove_all root )
    } {}

    // 1. dir_create_all — three nested levels created in one call.
    ?? ( dir_create_all deep ) {
        T → ( nurl_print `create_all nested: ok\n` )
        F e → {
            ( nurl_print `create_all nested: err ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    ( nurl_print `exists root: ` )
    ? ( file_exists root ) { ( nurl_print `T` ) } { ( nurl_print `F` ) }
    ( nurl_print `\n` )

    ( nurl_print `exists a/b/c: ` )
    ? ( file_exists deep ) { ( nurl_print `T` ) } { ( nurl_print `F` ) }
    ( nurl_print `\n` )

    // 2. dir_create_all is idempotent — an existing tree is not an error.
    ?? ( dir_create_all deep ) {
        T → ( nurl_print `create_all again: ok\n` )
        F e → {
            ( nurl_print `create_all again: err ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    // 3. Write a 20-byte file deep in the tree.
    ?? ( write_file data_path `0123456789ABCDEFGHIJ` ) {
        T → ( nurl_print `wrote data file\n` )
        F e → {
            ( nurl_print `write: err ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    // 4. Read it back in 7-byte chunks: 7 + 7 + 6 = 20, then EOF.
    ?? ( file_open data_path ) {
        T fh → {
            : String acc ( string_new )
            : ~ i chunks 0
            : ~ i total 0
            : ~ b reading T
            ~ reading {
                ?? ( file_read_chunk fh 7 ) {
                    T bytes → {
                        : i bn ( vec_len [u] bytes )
                        ? == bn 0 {
                            = reading F
                        } {
                            = chunks + chunks 1
                            = total + total bn
                            ( string_push_bytes acc ( vec_data [u] bytes ) bn )
                        }
                        ( vec_free [u] bytes )
                    }
                    F e → {
                        = reading F
                        ( nurl_print `read: err\n` )
                    }
                }
            }
            ( nurl_print `chunks: ` )
            ( nurl_print ( nurl_str_int chunks ) )
            ( nurl_print `\n` )
            ( nurl_print `total: ` )
            ( nurl_print ( nurl_str_int total ) )
            ( nurl_print `\n` )
            ( nurl_print `content: ` )
            ( nurl_print ( string_data acc ) )
            ( nurl_print `\n` )
            ( nurl_print `eof: ` )
            ? ( file_eof fh ) { ( nurl_print `T` ) } { ( nurl_print `F` ) }
            ( nurl_print `\n` )
            ( string_free acc )
            ( file_close fh )
        }
        F e → {
            ( nurl_print `open: err ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    // 5. dir_remove_all — wipe the whole tree (nested dirs + the file).
    ?? ( dir_remove_all root ) {
        T → ( nurl_print `remove_all: ok\n` )
        F e → {
            ( nurl_print `remove_all: err ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    ( nurl_print `exists after remove: ` )
    ? ( file_exists root ) { ( nurl_print `T` ) } { ( nurl_print `F` ) }
    ( nurl_print `\n` )

    // 6. dir_remove_all on a missing path → NotFound.
    ?? ( dir_remove_all `nurl_no_such_tree_xyz` ) {
        T → ( nurl_print `remove_all missing: unexpected ok\n` )
        F e → {
            ( nurl_print `remove_all missing: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    ^ 0
}
