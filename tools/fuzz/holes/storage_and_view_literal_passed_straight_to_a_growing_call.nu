// storage_and_view_literal_passed_straight_to_a_growing_call: `( use @ S { sv b } )`, `sv` a view of `b`, `use` growing `. x buf` and reading `. x v`
// Closed: a value that views its own fields takes those views with it — to the struct field it is moved into, re-rooted there — and a literal argument that views its own storage is refused where the callee may drop, replace or move a buffer of it (agora #563).
// main 029b01d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #563: ( use @ S { sv b } ), sv a view of b, use growing . x buf and reading . x v
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Slice i ) v ( Vec i ) buf }

@ use sink S x → v {
    : ~ S y x
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] . y buf k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] . y v 1 ) )
}

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Slice i ) sv ( slice_from_vec [i] b )
    ( use @ S { sv b } )
    ^ 0
}
