// OPEN in 0.72.0 — a view leaving through a helper's return value, as a closure capture: the closure reads freed memory.
// `mkc` returns a closure that captured its parameter `a`; `back` returns ( mkc x ) for its own fresh
// string `x`, then releases `x`. A call result is not checked for views of the arguments it was given
// (a closure literal returned directly is: h141).
// ASan: heap-use-after-free in strlen, when main calls the returned closure.
$ `stdlib/core/string.nu`

@ mkc s a → ( @ i ) { ^ \ → i { ^ ( strlen a ) } }

@ back → ( @ i ) { : s x ( nurl_str_cat `ab` `cd` ) ^ ( mkc x ) }

@ main → i {
    : ( @ i ) f ( back )
    ( nurl_println_int ( f ) )
    ( nurl_println `P32B-MARK` )
    ^ 0
}
