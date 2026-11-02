// holder_kept_on_one_match_arm_after_its_dependency_cleared_on_another: agora #389 — as holder_kept_on_one_path_after_its_dependency_cleared_on_the_other, the new value given in one arm of a ??
// Closed: the dependency is either arm's past the join (bck_put_vd, __cj_combine).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #389: as holder_kept_on_one_path_after_its_dependency_cleared_on_the_other, the new value given in one arm of a ??
$ `stdlib/core/string.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ main → i {
    : ~ W a @ W { `x` }
    : ?i o @ ?i { F }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( k a t )
        ?? o { T m → { = a @ W { `lit` } } F → {} }
    }
    ( nurl_println . a v )
    ^ 0
}
