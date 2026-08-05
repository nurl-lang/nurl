// Passing `*B` where `*A` is declared. The by-VALUE version of this is
// caught (should_fail_arg_wrong_struct) and the same-base pointer-depth
// version is caught (should_fail_ptr_value_arg), but two DIFFERENT named
// structs behind pointers used to compile: clang accepts the call and
// the callee reads B's bytes as A's fields.
//
// Found the hard way — a `*PktBuf` passed to a `( Vec u )` parameter in
// a test that then read frames out of the wrong object and reported
// failures with no diagnostic anywhere.
$ `stdlib/core/string.nu`

: Alpha { i a i b }
: Beta { i x i y i z }

@ takes_alpha * Alpha p → i { ^ . p a }

@ main → i {
    : *Beta b # *Beta ( nurl_alloc Z Beta )
    = . b x 5
    ^ ( takes_alpha b )
}
