// closure_hands_back_a_view: a call through a closure value that hands back a view — a raw string of its parameter or capture (`( string_data x )`), a Slice of a Vec it was handed — was not followed by the borrow walk (its source expression was `*`, not modelled), and a raw string the body lent was taken as owned. Growing the source then left the result dangling.
// Closed: a raw string the closure lent comes back a copy (a call through a closure value owns its result), and any other view it hands back holds every argument and everything the closure captured (`\(f|args)`), so the walk ends it where any of them changes.
// main (before this PR): ASan heap-use-after-free.
// map: §2.11 | A2 | rejected | h220 | closure returns slice view of its Vec arg; Vec grows, slice dangles
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( @ ( Slice i ) ( Vec i ) ) f \ ( Vec i ) w → ( Slice i ) { ( slice_from_vec [i] w ) }
    : ( Slice i ) sl ( f v )
    : ~ i k 0
    ~ < k 100 { ( vec_push [i] v k ) = k + k 1 }
    ?? ( slice_first [i] sl ) { T x → { ( nurl_println_int x ) } F _ → {} }
    ^ 0
}
