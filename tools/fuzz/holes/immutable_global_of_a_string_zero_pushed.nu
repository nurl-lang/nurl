// immutable_global_of_a_string_zero_pushed: the String twin of immutable_global_of_a_vec_zero_pushed. `: String g_s 0` is a null control block, and safe code appended to it.
// Closed: as for the Vec. The declaration is refused, since zero bytes are not a String.
// main's compiler: compiled with no `unsafe`; string_push_str wrote through the null handle (SIGSEGV).
// map: §6.5 | A3 | rejected | h976 | immutable zero-initialised String global appended to from safe code through its null handle
$ `stdlib/core/string.nu`

: String g_s 0

@ main → i {
    ( string_push_str g_s `hello` )
    ( nurl_println_int ( string_len g_s ) )
    ^ 0
}
