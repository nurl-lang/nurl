// Built-in string operations test

@ main → i {
    ( nurl_print `String operations test...\n` )

    : s s1 `hello`
    : s s2 ` world`
    : s full ( nurl_str_cat s1 s2 )

    ( nurl_print `concat: ` )
    ( nurl_print full )
    ( nurl_print `\n` )

    ( nurl_print `strlen "hello": ` )
    ( nurl_print ( nurl_str_int ( nurl_str_len s1 ) ) )
    ( nurl_print `\n` )

    ( nurl_print `substr 6 5: ` )
    ( nurl_print ( nurl_str_slice full 6 5 ) )
    ( nurl_print `\n` )

    ( nurl_print `find "world": ` )
    ( nurl_print ( nurl_str_int ( nurl_str_find full `world` ) ) )
    ( nurl_print `\n` )

    ( nurl_print `find "xyz": ` )
    ( nurl_print ( nurl_str_int ( nurl_str_find full `xyz` ) ) )
    ( nurl_print `\n` )

    ( nurl_print `char_at 1: ` )
    ( nurl_print ( nurl_str_slice s1 1 1 ) )
    ( nurl_print `\n` )

    ( nurl_print `"hello" == "hello": ` )
    ( nurl_print ? != 0 ( nurl_str_eq s1 `hello` ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `"hello" == "world": ` )
    ( nurl_print ? != 0 ( nurl_str_eq s1 `world` ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `int 42: ` )
    ( nurl_print ( nurl_str_int 42 ) )
    ( nurl_print `\n` )

    ( nurl_print `float 3.14: ` )
    ( nurl_print ( nurl_str_float 3.14 ) )
    ( nurl_print `\n` )

    ^ 0
}
