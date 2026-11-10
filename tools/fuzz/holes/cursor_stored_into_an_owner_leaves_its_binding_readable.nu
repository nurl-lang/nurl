// cursor_stored_into_an_owner_leaves_its_binding_readable: agora #545 — `: ~ String c q` then `@ Holder { c }` (or a `vec_push` of `c`): the cursor's value is q's, so the new owner held q's buffer while q stayed readable, and q read freed memory once that owner was dropped.
// Closed: storing a cursor into an owner stores the binding it is over: `q` is moved there as if it had been named, and reading it afterwards is refused.
// main (before this PR): accepted; AddressSanitizer, heap-use-after-free.
// map: §2.1 | A2 | rejected | - | agora #545: a cursor stored into an owner left the binding it was over readable after the owner freed it (UAF)
$ `stdlib/core/string.nu`

: Holder { String name }

@ main → i {
    : String q ( string_from `a long enough string to be on the heap for sure` )
    : ~ String c q
    {
        : Holder g @ Holder { c }
        ( nurl_println ( string_data . g name ) )
    }
    ( nurl_println ( string_data q ) )
    ^ 0
}
