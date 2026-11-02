// holder_kept_through_a_nested_join_after_its_dependency_cleared: agora #389 — the new value given inside a ? nested in another ?'s arm
// Closed: each join level logs and joins the dependency facts (bck_put_vd).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #389: the new value given inside a ? nested in another ?'s arm
$ `stdlib/core/string.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ main → i {
    : ~ W a @ W { `x` }
    : ~ i n 1
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( k a t )
        ? > n 0 { ? > n 5 { = a @ W { `lit` } } {} } {}
    }
    ( nurl_println . a v )
    ^ 0
}
