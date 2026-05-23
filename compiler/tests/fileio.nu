// File I/O — read, write, append

$ `stdlib/std/fs.nu`

@ main → i {
    ( nurl_print `File I/O test...\n` )

    // Write a new file
    : *v f ( nurl_file_open `test_output.txt` `w` )
    ( nurl_file_write f `line one\n` )
    ( nurl_file_write f `line two\n` )
    ( nurl_file_write f `line three\n` )
    ( nurl_file_close f )

    ( nurl_print `wrote 3 lines\n` )

    // Read entire file
    : s content ( nurl_file_read `test_output.txt` )
    ( nurl_print `read back:\n` )
    ( nurl_print content )

    // Append
    : *v f2 ( nurl_file_open `test_output.txt` `a` )
    ( nurl_file_write f2 `line four\n` )
    ( nurl_file_close f2 )

    // Read again to verify append
    : s content2 ( nurl_file_read `test_output.txt` )
    ( nurl_print `after append:\n` )
    ( nurl_print content2 )

    // File exists
    ( nurl_print `exists test_output.txt: ` )
    ( nurl_print ? != 0 ( nurl_file_exists `test_output.txt` ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `exists no_such_file.txt: ` )
    ( nurl_print ? != 0 ( nurl_file_exists `no_such_file.txt` ) `yes` `no` )
    ( nurl_print `\n` )

    // File size
    ( nurl_print `size: ` )
    ( nurl_print ( nurl_str_int ( nurl_file_size `test_output.txt` ) ) )
    ( nurl_print ` bytes\n` )

    // Delete
    ( nurl_file_del `test_output.txt` )
    ( nurl_print `after delete exists: ` )
    ( nurl_print ? != 0 ( nurl_file_exists `test_output.txt` ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `done\n` )
    ^ 0
}
