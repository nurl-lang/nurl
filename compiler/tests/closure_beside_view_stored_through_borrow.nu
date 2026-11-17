// closure_beside_view_stored_through_borrow.nu — a closure stored with a
// view beside it through a borrow (AGORA-901): `( vec_at vv 0 )` lends the
// inner Vec, and a `vec_push` and a `vec_set` through it store elements
// that hold a view of `buf` and a closure, the closure capturing a view
// and a String by value. Each is then called through the Vec and its view
// read. The formal model types this store (`StmtT.editBV`, whose element
// may now hold a closure: what it captures by name, the borrow and the
// owners hold already; here nothing). A closure that captures a stack
// binding by name is refused before it can be stored in any Vec.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`

: S { ( Slice i ) s ( @ i i ) f }

@ mk ( Slice i ) sl sink String tag → ( @ i i ) {
    ^ \ i x → i { ^ + + x ( slice_len [i] sl ) ( string_len tag ) }
}

@ main → i {
    : ~ ( Vec i ) buf ( vec_new [i] )
    ( vec_push [i] buf 3 )
    ( vec_push [i] buf 4 )
    : ( Slice i ) sl ( slice_from_vec [i] buf )
    : ( Vec ( Vec S ) ) vv ( vec_new [( Vec S )] )
    ( vec_push [( Vec S )] vv ( vec_new [S] ) )
    : ( Vec S ) b ( vec_at [( Vec S )] vv 0 )
    ( vec_push [S] b @ S { sl ( mk sl ( string_from `four` ) ) } )
    ( vec_push [S] b @ S { sl ( mk sl ( string_from `seven chars` ) ) } )
    ( vec_set [S] b 0 @ S { sl ( mk sl ( string_from `x` ) ) } )
    : S e ( vec_at [S] b 0 )
    : ( @ i i ) g . e f
    : S e2 ( vec_at [S] b 1 )
    : ( @ i i ) g2 . e2 f
    ( nurl_println_int ( g 10 ) )
    ( nurl_println_int ( g2 100 ) )
    ( nurl_println_int ( slice_len [i] . e s ) )
    ^ 0
}
