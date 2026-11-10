// owned_slice_bound_a_second_time_then_returned: agora #545 — `: [i q ( mk ) : [i r q ^ r`: the second binding was not on the list of owned names, so `q` freed the buffer at the return and the caller read and freed it again.
// Closed: a `[T` is an owned value by its type, dropped through the handle machinery as a String or a Vec is (twin `%__slc.<elem>`, __slc_twin): the binding, field or payload that holds it releases it once, and a move clears the flag of the binding it leaves (agora #545). `: [i r q` over a local moves the buffer to `r`.
// main (before this PR): AddressSanitizer, heap-use-after-free in main.
// map: §7.6 | A2 | runs-clean | - | agora #545: an owned slice bound a second time and returned by that name was freed by the first (UAF, double free)
@ mk → [i { ^ [i | 1 2] }

@ via → [i {
    : [i q ( mk )
    : [i r q
    ^ r
}

@ main → i {
    : [i a ( via )
    ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
