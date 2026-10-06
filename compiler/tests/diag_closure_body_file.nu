// diag_closure_body_file.nu — a diagnostic inside a closure body names
// the file the closure is in, not the last file imported before it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( @ v ) body \ → v {
        : ( Vec String ) strs ( vec_new [String] )
        : String s ( string_from `x` )
        ( vec_push [String] strs s )
        ( nurl_println_int ( string_len s ) )
    }
    ( body )
    ^ 0
}
