// param_copy_passed_inout_releases_callers_field: `: ~ T c p` of a parameter `p` is a copy that shares p's fields — it owns none of them (an assignment to `. c f` in place leaves the old field to p's owner, by the field's ownership flag). Passed 'inout' to a function, though, the copy reached a callee that owns what it is given: replacing a field there released p's field, which the caller of this function still owned and freed again (heap-use-after-free).
// Closed: a mutable copy of a parameter (or of such a copy), or a field of one, may not go 'inout' when its type owns anything: the error says to make a copy of its own (`mem_dup`) or take the parameter itself as 'inout'.
// main (before this PR): AddressSanitizer reported heap-use-after-free on the caller's Vec after the second call.
// map: paramOK_inout | A2 | rejected | h295 | a ': ~' copy of a parameter shares its fields; passed inout, the callee replaced a field and released the caller's (UAF)
$ `stdlib/core/vec.nu`

: Inner {
    i a
    ( Vec i ) items
}

: Outer {
    i n
    Inner inner
}

@ reset inout Outer o → v { = . o inner @ Inner { 2 ( vec_new [i] ) } }

@ fresh_view Outer b → i {
    : ~ Outer c b
    ( reset c )
    ^ . c n
}

@ main → i {
    : Outer b @ Outer { 1 @ Inner { 1 ( vec_new [i] ) } }
    ( vec_push [i] . . b inner items 7 )
    : i r1 ( fresh_view b )
    : i r2 ( fresh_view b )
    ( nurl_println_int + + r1 r2 ( vec_len [i] . . b inner items ) )
    ^ 0
}
