// inout_argument_kept_by_its_callee_read_after_the_call: agora #545 — a callee that returns its `inout` parameter in a literal takes the value over; the caller stopped releasing its binding but could still read it, after the new owner had freed it.
// Closed: an `inout` argument its callee keeps whole is consumed by the call, as one passed by value is: reading the binding afterwards is refused.
// main (before this PR): accepted; AddressSanitizer, heap-use-after-free.
// map: §2.1 | A2 | rejected | - | agora #545: an inout argument its callee kept in a literal was read by the caller after the new owner freed it (UAF)
$ `stdlib/core/string.nu`

: Holder { String name }

@ in_literal inout String p → Holder { ^ @ Holder { p } }

@ main → i {
    : ~ String q ( string_from `a long enough string to be on the heap for sure` )
    {
        : Holder g ( in_literal q )
        ( nurl_println ( string_data . g name ) )
    }
    ( nurl_println ( string_data q ) )
    ^ 0
}
