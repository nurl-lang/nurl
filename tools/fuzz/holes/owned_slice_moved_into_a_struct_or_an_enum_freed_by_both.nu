// owned_slice_moved_into_a_struct_or_an_enum_freed_by_both: agora #545 — an owned slice binding stored into a struct literal (`@ Holder { q 1 }`) or an enum payload (`@ Box { Full q }`) and returned: which slice a function owned was a list of names, so `q` freed its buffer at the return and the value handed back held the freed buffer.
// Closed: a `[T` is an owned value by its type, dropped through the handle machinery as a String or a Vec is (twin `%__slc.<elem>`, __slc_twin): the binding, field or payload that holds it releases it once, and a move clears the flag of the binding it leaves (agora #545).
// main (before this PR): AddressSanitizer, heap-use-after-free in each shape (and a double free once the holder drops).
// map: §7.6 | A2 | runs-clean | - | agora #545: an owned slice binding stored into a struct or an enum payload was freed by its name and read through the holder (UAF)
: Holder { [i items i n }
: | Box { Full [i Empty }

@ mk → [i { ^ [i | 1 2] }

@ hold → Holder {
    : [i q ( mk )
    ^ @ Holder { q 1 }
}

@ boxit → Box {
    : [i q ( mk )
    ^ @ Box { Full q }
}

@ main → i {
    : Holder h ( hold )
    ~ x . h items { ( nurl_println ( nurl_str_int x ) ) }
    : Box bx ( boxit )
    ?? bx {
        Full sl → { ~ x sl { ( nurl_println ( nurl_str_int x ) ) } }
        Empty → {}
    }
    ^ 0
}
