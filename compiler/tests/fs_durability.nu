// Test: the durability + truncation primitives (stdlib/std/fs.nu) and
// binary stdout (stdlib/core/io.nu).
//
// file_flush pushes libc's buffer into the kernel; file_sync pushes the
// kernel's onto the device. Anything with a write-ahead log needs the
// second one, and needs file_truncate to cut a torn tail back off after
// a crash — leave the torn bytes in place and every later append hides
// behind them. write_bytes is the write-side dual of read_n_bytes: a
// print takes a NUL-terminated string, so binary output had no route out.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`

: ~ s TPATH ``
: ~ s TDIR ``

@ __dur_tmpdir → String {
    : ~ String tdir ( env_var_or `TMPDIR` `` )
    ? == ( string_len tdir ) 0 {
        ( string_free tdir )
        = tdir ( env_var_or `TEMP` `/tmp` )
    } {}
    ^ tdir
}

@ ck b ok s name → v {
    ? ok { ( nurl_print `PASS ` ) } { ( nurl_print `FAIL ` ) }
    ( nurl_print name )
    ( nurl_print `\n` )
}

@ __size_of s path → i {
    ^ ?? ( file_size path ) { T n → n F _ → -1 }
}

@ main → i {
    : String __td ( __dur_tmpdir )
    = TDIR ( strdup ( string_data __td ) )
    ( string_push_str __td `/nurl_fsdur_test.bin` )
    = TPATH ( strdup ( string_data __td ) )
    ( string_free __td )
    ( file_delete TPATH )

    // 100 bytes, then fsync: the call has to succeed on a real handle.
    : ( Vec u ) data ( vec_new [u] )
    : ~ i i 0
    ~ < i 100 { ( vec_push [u] data # u & 255 i ) = i + i 1 }
    ?? ( file_create TPATH ) {
        T f → {
            : ~ b ok T
            ?? ( file_write_chunk f data ) { T _ → {} F _ → { = ok F } }
            ?? ( file_sync f ) { T _ → {} F _ → { = ok F } }
            ( file_close f )
            ( ck ok `file_sync on a written handle` )
        }
        F _ → { ( ck F `file_sync on a written handle` ) }
    }
    ( vec_free [u] data )
    ( ck == ( __size_of TPATH ) 100 `100 bytes landed` )

    // Cut it back — the crash-recovery move.
    ?? ( file_truncate TPATH 40 ) {
        T _ → { ( ck == ( __size_of TPATH ) 40 `file_truncate shortens` ) }
        F _ → { ( ck F `file_truncate shortens` ) }
    }
    // …and the surviving prefix is still the original bytes, not zeros.
    ?? ( read_file_bytes TPATH ) {
        T kept → {
            : ~ i b39 -1
            ?? ( vec_get [u] kept 39 ) { T x → { = b39 # i x } F → {} }
            ( ck & == ( vec_len [u] kept ) 40 == b39 39 `truncation keeps the prefix intact` )
            ( vec_free [u] kept )
        }
        F _ → { ( ck F `truncation keeps the prefix intact` ) }
    }
    ?? ( file_truncate TPATH 0 ) {
        T _ → { ( ck == ( __size_of TPATH ) 0 `file_truncate to empty` ) }
        F _ → { ( ck F `file_truncate to empty` ) }
    }

    // A path that does not exist has nothing to truncate.
    : String gone ( string_from TDIR )
    ( string_push_str gone `/nurl_fsdur_absent.bin` )
    ( file_delete ( string_data gone ) )
    ?? ( file_truncate ( string_data gone ) 8 ) {
        T _ → { ( ck F `file_truncate rejects a missing path` ) }
        F _ → { ( ck T `file_truncate rejects a missing path` ) }
    }
    ( string_free gone )

    // dir_sync is what makes a publish-by-rename durable. It is a no-op
    // on Windows/WASI, so "succeeds on a real directory" is the contract
    // everywhere.
    ?? ( dir_sync TDIR ) {
        T _ → { ( ck T `dir_sync on a directory` ) }
        F _ → { ( ck F `dir_sync on a directory` ) }
    }

    // write_bytes emits the buffer exactly — length, not termination,
    // decides what goes out.
    : ( Vec u ) out ( vec_new [u] )
    ( bytes_extend_str out `bytes:` )
    ( vec_push [u] out # u 226 ) ( vec_push [u] out # u 154 ) ( vec_push [u] out # u 161 )
    ( bytes_extend_str out `:end` )
    ( nurl_print `write_bytes ` )
    ( write_bytes out )
    ( nurl_print `\n` )
    ( vec_free [u] out )

    ( file_delete TPATH )
    ^ 0
}
