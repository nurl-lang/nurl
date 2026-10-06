// cursor_string_owner_slot.nu — a mutable `s` binding that starts as a
// borrow (`: ~ s out st` over a parameter) and is then given owned values.
//
// It owned nothing at birth, so it had no drop slot: every value assigned
// over it leaked. And with a slot, a return still leaked when the last
// assignment was a call that handed the binding's own value back (its
// ownership proof was cleared although the slot still owned the value),
// and when an untracked value was assigned over an owned one (the owned
// one was never freed). The sanitizer run of this test is the check.

$ `stdlib/core/string.nu`

// Hands its argument back for k == 1, a fresh string otherwise.
@ setk s st i k → s {
    ? == k 1 { ^ st } {}
    ^ ( nurl_str_cat st ( nurl_str_int k ) )
}

// Owned values over a borrowed start.
@ grow s st i n → s {
    : ~ s out st
    : ~ i k 0
    ~ < k n { = out ( nurl_str_cat out ( nurl_str_int k ) ) = k + k 1 }
    ^ out
}

// The last assignment hands the binding's own value back.
@ settle s st i n → s {
    : ~ s out st
    : ~ i k 0
    ~ < k n { = out ( setk out k ) = k + k 1 }
    ^ out
}

// A call whose result is owned or lent depending on the path, and a
// recursive one.
@ nest s st i n i depth → s {
    : ~ s out st
    : ~ i k 0
    ~ < k n {
        = out ( setk out k )
        = out ( settle out 2 )
        ? < depth 2 { = out ( nest out 2 + depth 1 ) } {}
        = k + k 1
    }
    ^ out
}

// An untracked value assigned over an owned one, then returned.
@ back_to_param s st s other → s {
    : ~ s out st
    = out ( nurl_str_cat out `!` )
    = out other
    ^ out
}

@ main → i {
    : s a ( nurl_str_cat `x` `` )
    ( nurl_println ( grow a 3 ) )
    ( nurl_println ( settle a 3 ) )
    ( nurl_println ( nest a 3 0 ) )
    ( nurl_println ( back_to_param a `other` ) )
    : ~ i r 0
    ~ < r 50 { : s t ( nest a 2 1 ) = r + r 1 }
    ^ 0
}
