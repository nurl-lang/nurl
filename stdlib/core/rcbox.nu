// stdlib/core/rcbox.nu — the storage behind an opaque library handle.
//
// A module that hands out a one-word handle over state of its own
// (`: Regex { s ctl }`, `: Sha256 { s ctl }`) keeps that state in an
// rcbox: one heap block, `[ i64 owners ][ T value ]` (Arc's layout), whose
// last owner drops the value — its String / Vec / handle fields, and its
// own `% Drop` if it has one — and frees the block. The handle becomes a
// library handle (docs/MEMORY.md §7.6) with two lines:
//
//   @ Regex_share Regex r → Regex { ^ @ Regex { # s ( rcbox_share # i . r ctl ) } }
//   @ Regex_drop sink Regex r → v { ( mem_forget r ) ( rcbox_release [RegexImpl] # i . r ctl ) }
//
// and every copy of it (a struct field, a closure capture, a Vec element)
// is the same state, as a copied pointer was, while nobody frees it by
// hand. The block pointer travels as an `i`: it is the handle's to own,
// never a string anything else would release.
//
// API:
//
//   ( rcbox_new     [T] T x )  → i     a block with one owner holding x
//   ( rcbox_zero    [T] )      → i     …holding a zeroed T, for a constructor
//                                       that fills it in place (rcbox_ptr)
//   ( rcbox_ptr     [T] i p )  → *T    the value in place (borrowed)
//   ( rcbox_share   i p )      → i     one more owner; p back
//   ( rcbox_release [T] i p )  → v     one owner fewer; the last drops the value

// The owner count: one more (the old count back), one fewer (1 when the
// caller was the last owner). A count of 1 skips the locked RMW.
& `c` @ nurl_rc_share *u p → i

& `c` @ nurl_rc_release *u p → i

: RcBox [T] {
    i owners
    T value
}

@ rcbox_new [T] T x → i {
    : *( RcBox T ) b # *( RcBox T ) ( nurl_alloc Z ( RcBox T ) )
    = . b owners 1
    = . b value x
    ^ # i b
}

@ rcbox_zero [T] → i {
    : *( RcBox T ) b # *( RcBox T ) ( nurl_zalloc Z ( RcBox T ) )
    = . b owners 1
    ^ # i b
}

@ rcbox_ptr [T] i p → *T {
    ^ # *T + p 8
}

@ rcbox_share i p → i {
    ? != 0 p { : i _old ( nurl_rc_share # *u p ) } {}
    ^ p
}

@ rcbox_release [T] i p → v {
    ? == 0 p {} {
        ? != 0 ( nurl_rc_release # *u p ) {
            : *( RcBox T ) b # *( RcBox T ) p
            : T v . b value
            ( mem_take v )
            ( nurl_free # s p )
        } {}
    }
}
