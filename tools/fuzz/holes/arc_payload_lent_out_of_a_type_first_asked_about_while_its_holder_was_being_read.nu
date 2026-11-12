// arc_payload_lent_out_of_a_type_first_asked_about_while_its_holder_was_being_read: `: C { ( Arc Page ) a }`, `: B { ( Vec A ) parts i n }`, `: A { ( Vec B ) bs C c }` — `A` and `B` hold each other and `A` holds the `Arc`. Two functions taking an `A` come first; then a helper taking a `B` lends a `Slice` over the payload, and the caller writes through it while another thread reads the same page.
// main: accepted — asked about `A`, the holder walk noted "holds none" for `A` while it was still reading it, reached `B`, read `B`'s `( Vec A )` against that note and recorded `B` as holding no `Arc`; the record outlived the walk, so the helper's lend out of a `B` was not a frozen one. With the helper first in the file the same program was refused.
// map: RhsT.arcGet | A3 | rejected | - | a helper handed one of two types that hold each other lends the payload of the Arc the other holds, after the other was asked about first: an answer is kept only for a walk that ran whole (agora #711)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: Page { ( Vec u ) data }
: C { ( Arc Page ) a }
: B { ( Vec A ) parts i n }
: A { ( Vec B ) bs C c }

@ first A x → i { ^ 7 }

@ count A x → i { ^ ( first x ) }

@ holder_bytes B h → ( Slice u ) {
    ^ ( slice_from_vec [u] . ( arc_get [Page] . . ( vec_at [A] . h parts 0 ) c a ) data )
}

@ main → i {
    : ( Arc Page ) a ( arc_new [Page] @ Page { ( vec_zeroed [u] 64 ) } )
    : A x @ A { ( vec_new [B] ) @ C { ( arc_clone [Page] a ) } }
    : i n0 ( count x )
    : ( Vec A ) parts ( vec_new [A] )
    ( vec_push [A] parts x )
    : B h @ B { parts 1 }
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
    ^ - n0 7
}
