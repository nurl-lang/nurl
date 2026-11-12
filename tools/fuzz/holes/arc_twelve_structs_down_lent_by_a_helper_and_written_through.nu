// arc_twelve_structs_down_lent_by_a_helper_and_written_through: `: H1 { ( Arc Page ) a i tag }`, `: H2 { H1 a }` … `: H12 { H11 a }` — a helper handed the outermost struct lends a `Slice` over the payload of the `Arc` twelve structs down, and the caller writes through it while another thread reads the same page.
// main: accepted — the walk that asks whether a parameter's type holds an `Arc` gave up ten levels down and answered "holds none", so the lend was not a frozen one; the same program one struct deep (arc_payload_lent_through_a_struct) was refused. The writer and the reader race on the page.
// map: RhsT.arcGet | A3 | rejected | - | a helper handed a struct that holds an Arc twelve fields down lends the payload and the caller writes through the view: the holder walk reads a type whole (agora #711)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

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
    : !Thread ThreadErr r ( thread_spawn \ → v {
        : ~ i k 0
        ~ < k 100000 {
            : ( Slice u ) s ( slice_from_vec [u] . ( arc_get [Page] a ) data )
            : i b ( slice_byte s 3 )
            = k + k 1
        }
    } )
    : ( Slice u ) s ( holder_bytes h )
    : ~ i k 0
    ~ < k 100000 { ( slice_put [u] s 3 # u & k 255 ) = k + k 1 }
    ?? r {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
