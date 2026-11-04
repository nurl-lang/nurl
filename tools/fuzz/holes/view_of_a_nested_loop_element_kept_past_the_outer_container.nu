// view_of_a_nested_loop_element_kept_past_the_outer_container: agora #471 — `~ row vv { ~ x row { ( vec_push [s] ws ( string_data x ) ) } }` over a block-local `( Vec ( Vec String ) )`; `ws` read after the block
// Closed: an inner loop's element is a part of what the outer loop's element is a part of: `fe_` of an element over an element is its owners too (bck_borrow_owners), so the view is reached through an element of `vv` (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of a nested loop element kept past the outer container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
        : ( Vec String ) r0 ( vec_new [String] )
        ( vec_push [String] r0 ( string_from `an inner string freed with the outer Vec` ) )
        ( vec_push [( Vec String )] vv r0 )
        ~ row vv { ~ x row { ( vec_push [s] ws ( string_data x ) ) } }
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
