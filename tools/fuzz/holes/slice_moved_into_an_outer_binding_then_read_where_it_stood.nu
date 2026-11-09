// slice_moved_into_an_outer_binding_then_read_where_it_stood: `= e a` with `a` an owned slice of an inner scope and `e` an owned mutable slice of the outer one moved the buffer to e at once, but `a` stayed readable in its scope: the next `= e [i | 3]` freed it under `~ x a`. From a binding of the same scope (`= e a`, then `= e [ … ]`), the move freed the buffer the source still named, in a loop too.
// Closed: the source stays the owner while it lives (agora #540). From the same scope or one around e's, e views it (its owner flag false). From a scope inside e's, e is its heir: where the source is released, e inherits the buffer if it still holds that very one (pointer compare), and the source frees it otherwise. A loop that hands one round's slice on keeps it to the end.
// main ad960922: AddressSanitizer: heap-use-after-free reading `a`.
// map: §7.6 | A2 | runs-clean | - | agora #540: a slice moved into a longer-lived binding was freed by that binding's next assignment while its source still named it
@ main → i {
    : ~ [i e [i | 7]
    ? T {
        : [i a [i | 1 2]
        = e a
        = e [i | 3]
        ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    } {}
    ~ x e { ( nurl_println ( nurl_str_int x ) ) }
    : [i b [i | 5 6]
    : ~ [i d [i | 9]
    = d b
    = d [i | 4]
    ~ x b { ( nurl_println ( nurl_str_int x ) ) }
    : ~ [i h [i | 7]
    : ~ i k 0
    ~ < k 3 {
        : [i c [i | 1 2]
        ? == k 1 { = h c } {}
        = k + k 1
    }
    ~ x h { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
