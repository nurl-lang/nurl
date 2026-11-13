// A value a call lends, handed to an enclosing call, is read where that
// call runs: after the calls in its later arguments. Here 'cz' clears
// fs first, so 'two' would read freed memory (agora #604).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cz ( Vec String ) v → i { ( vec_clear [String] v ) ^ 0 }

@ two s a i b → i { ^ + ( nurl_str_len a ) b }

@ main → i {
    : ( Vec String ) fs ( vec_new [String] )
    ( vec_push [String] fs ( string_from `a heap string long enough to own a buffer` ) )
    ( vec_push [String] fs ( string_from `another heap string long enough to own one` ) )
    : String s ( vec_at [String] fs 1 )
    ( nurl_println_int ( two ( string_data s ) ( cz fs ) ) )
    ^ 0
}
