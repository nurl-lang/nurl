// self_viewing_struct_moved_into_a_literal_then_grown: `o`, whose `v` views `o.buf`, moved into `@ P { o 0 }`, then `. . p s buf` grown and `. . p s v` read
// Closed: a value that views its own fields takes those views with it — to the struct field it is moved into, re-rooted there — and a literal argument that views its own storage is refused where the callee may drop, replace or move a buffer of it (agora #563).
// main 029b01d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #563: o, whose v views o.buf, moved into @ P { o 0 }, then . . p s buf grown and . . p s v read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf ( Slice i ) v }
: P { S s i n }

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Vec i ) e ( vec_new [i] )
    : ~ S o @ S { b ( slice_from_vec [i] e ) }
    = . o v ( slice_from_vec [i] . o buf )
    : ~ P p @ P { o 0 }
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] . . p s buf k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] . . p s v 1 ) )
    ^ 0
}
