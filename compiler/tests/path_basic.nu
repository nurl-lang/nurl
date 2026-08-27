// path_basic.nu — exercises stdlib/std/path.nu
//
// All assertions live in correct.txt; this header is just a pointer.
// `basename "/a/b/"` returns "" because the trailing separator means the
// final segment is empty. `dirname "/a/b/"` returns "/a/b" because the
// trailing separator is stripped before locating the parent.

$ `stdlib/std/path.nu`
$ `stdlib/core/string.nu`

@ show_str s label String s → v {
    ( nurl_print label )
    ( nurl_print `: ` )
    ( nurl_print ( string_data s ) )
    ( nurl_print `\n` )
    ( string_free s )
}

@ show_bool s label b v → v {
    ( nurl_print label )
    ( nurl_print `: ` )
    ? v { ( nurl_print `T` ) } { ( nurl_print `F` ) }
    ( nurl_print `\n` )
}

@ test_normalize s input s expected → v {
    : String got ( path_normalize input )
    ( nurl_print `normalize ` )
    ( nurl_print input )
    ( nurl_print `: ` )
    ( nurl_print ( string_data got ) )
    ( nurl_print `\n` )
    ( string_free got )
}

@ test_basename s input → v {
    : String got ( path_basename input )
    ( nurl_print `basename ` )
    ( nurl_print input )
    ( nurl_print `: ` )
    ( nurl_print ( string_data got ) )
    ( nurl_print `\n` )
    ( string_free got )
}

@ test_dirname s input → v {
    : String got ( path_dirname input )
    ( nurl_print `dirname ` )
    ( nurl_print input )
    ( nurl_print `: ` )
    ( nurl_print ( string_data got ) )
    ( nurl_print `\n` )
    ( string_free got )
}

@ test_ext s input → v {
    : String got ( path_extension input )
    ( nurl_print `ext ` )
    ( nurl_print input )
    ( nurl_print `: ` )
    ( nurl_print ( string_data got ) )
    ( nurl_print `\n` )
    ( string_free got )
}

@ test_join s a s b → v {
    : String got ( path_join a b )
    ( nurl_print `join ` )
    ( nurl_print a )
    ( nurl_print ` ` )
    ( nurl_print b )
    ( nurl_print `: ` )
    ( nurl_print ( string_data got ) )
    ( nurl_print `\n` )
    ( string_free got )
}

@ main → i {
    ( show_bool `absolute /a/b` ( path_is_absolute `/a/b` ) )
    ( show_bool `absolute foo/bar` ( path_is_absolute `foo/bar` ) )
    ( show_bool `absolute C:/x` ( path_is_absolute `C:/x` ) )
    ( show_bool `absolute foo` ( path_is_absolute `foo` ) )

    ( test_basename `/a/b/c.txt` )
    ( test_basename `/a/b/` )
    ( test_basename `foo` )
    ( test_basename `.bashrc` )
    ( test_basename `/` )
    ( test_basename `a//b` )

    ( test_dirname `/a/b/c.txt` )
    ( test_dirname `/a/b/` )
    ( test_dirname `foo` )
    ( test_dirname `/foo` )
    ( test_dirname `/` )
    ( test_dirname `a//b` )
    ( test_dirname `/a/` )

    ( test_ext `file.tar.gz` )
    ( test_ext `.bashrc` )
    ( test_ext `noext` )
    ( test_ext `file.` )

    ( test_join `a` `b` )
    ( test_join `a/` `/b` )
    ( test_join `.` `b` )
    ( test_join `a` `/abs` )

    ( test_normalize `a/./b` `a/b` )
    ( test_normalize `a/b/../c` `a/c` )
    ( test_normalize `/a/../../b` `/b` )
    ( test_normalize `//a//b///` `a/b` )
    ( test_normalize `./foo/../bar` `bar` )
    ( test_normalize `C:/a/./b/../c` `C:/a/c` )

    ^ 0
}
