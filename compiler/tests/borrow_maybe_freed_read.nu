// borrow_maybe_freed_read.nu — READING a binding that was freed on only
// some paths (docs/MEMORY.md §2.1). On the path that freed it the read is
// a use-after-free, so it is an error, as a definite one always was.
//
// What is NOT a maybe-free, and must stay clean (the controls below):
//   * a handle handed to another name (`= prev t`) — the buffer lives on
//     through that name, so reading `t` is fine;
//   * a free followed by `break` — that path never reaches the read;
//   * a free of a loop-body binding (`~ x xs { ( string_free x ) }`) —
//     each iteration's binding is a fresh one;
//   * a rebind on the freeing path.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ positive i c → i {
    : String x ( string_from `hello` )
    ? > c 0 { ( string_free x ) } {}
    ^ ( string_len x )
}

@ alias_read → i {
    : ~ ( Vec u ) prev ( vec_new [u] )
    : ( Vec u ) t ( vec_new [u] )
    ( vec_push [u] t 7 )
    = prev t
    ^ ( vec_len [u] t )
}

@ break_path → i {
    : ~ i k 0
    ~ < k 10 {
        : String tmp ( string_from `xyz` )
        ? == k 3 { ( string_free tmp ) break } {}
        = k + k ( string_len tmp )
    }
    ^ k
}

@ foreach_elem → i {
    : ( Vec String ) ss ( vec_new [String] )
    ( vec_push [String] ss ( string_from `a` ) )
    : ~ i n 0
    ~ x ss { = n + n ( string_len x ) ( string_free x ) }
    ^ n
}

@ rebind i c → i {
    : ~ String y ( string_from `a` )
    ? > c 0 { ( string_free y ) = y ( string_from `bb` ) } {}
    ^ ( string_len y )
}

@ main → i {
    ^ + + + + ( positive 1 ) ( alias_read ) ( break_path ) ( foreach_elem ) ( rebind 1 )
}
