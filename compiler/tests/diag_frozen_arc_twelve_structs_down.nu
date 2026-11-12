// A parameter whose type holds an Arc lends frozen views of the payload
// however far down the Arc sits: twelve structs down is the same Arc it is
// one struct down. The holder walk used to give up after ten levels and
// answer that the type held none (agora #711).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/arc.nu`

: Page { ( Vec u ) data }
: H1 { ( Arc Page ) a i tag }
: H2 { H1 a }
: H3 { H2 a }
: H4 { H3 a }
: H5 { H4 a }
: H6 { H5 a }
: H7 { H6 a }
: H8 { H7 a }
: H9 { H8 a }
: H10 { H9 a }
: H11 { H10 a }
: H12 { H11 a }

@ holder_bytes H12 h → ( Slice u ) {
    ^ ( slice_from_vec [u] . ( arc_get [Page] . . . . . . . . . . . . h a a a a a a a a a a a a ) data )
}

@ main → i {
    : ( Arc Page ) a ( arc_new [Page] @ Page { ( vec_zeroed [u] 64 ) } )
    : H12 h @ H12 { @ H11 { @ H10 { @ H9 { @ H8 { @ H7 { @ H6 { @ H5 { @ H4 { @ H3 { @ H2 { @ H1 { ( arc_clone [Page] a ) 1 } } } } } } } } } } } }
    : ( Slice u ) s ( holder_bytes h )
    ( slice_put [u] s 3 # u 7 )
    ^ 0
}
