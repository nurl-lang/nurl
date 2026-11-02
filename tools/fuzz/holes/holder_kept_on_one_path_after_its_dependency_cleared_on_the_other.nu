// holder_kept_on_one_path_after_its_dependency_cleared_on_the_other: agora #389 — a holder given a view through a callee, then a new value on one arm of a later ?: the other path still views the source
// Closed: dependency facts are logged in a join's arm and joined at the merge (bck_put_vd, __cj_combine), as borrow facts are since #311.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #389: a holder given a view through a callee, then a new value on one arm of a later ?: the other path still views the source
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ main → i {
    : ~ W a @ W { `x` }
    : ~ i n 1
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( k a t )
        ? > n 5 { = a @ W { `lit` } } {}
    }
    ( nurl_println . a v )
    ^ 0
}
