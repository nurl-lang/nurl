// closure_called_with_a_capture_it_only_reads_runs_clean: a closure that only reads its capture, called with it.
// Must keep compiling and running clean beside agora #339's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #339: a closure that only reads its capture, called with it
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String o ( string_from `the owner string long enough for the heap` )
    : ( @ i String ) c \ String p → i { ^ + ( string_len o ) ( string_len p ) }
    ( nurl_println_int ( c o ) )
    ^ 0
}
