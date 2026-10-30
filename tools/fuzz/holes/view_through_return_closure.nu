// view_through_return_closure: a view leaving through a helper's return value, as a closure capture: the closure reads freed memory.
// Closed: a call's result holds views of what the callee lends, stores or hands back inside it (bck_sx_ev), and is checked like any view where it is returned.
// `mkc` returns a closure that captured its parameter `a`; `back` returns ( mkc x ) for its own fresh
// string `x`, then releases `x`. A call result is not checked for views of the arguments it was given
// (a closure literal returned directly is: h141).
// ASan: heap-use-after-free in strlen, when main calls the returned closure.
// map: §2.11 | A2 | rejected | h174 | helper returns closure capturing local's view via call result
$ `stdlib/core/string.nu`

@ mkc s a → ( @ i ) { ^ \ → i { ^ ( strlen a ) } }

@ back → ( @ i ) { : s x ( nurl_str_cat `ab` `cd` ) ^ ( mkc x ) }

@ main → i {
    : ( @ i ) f ( back )
    ( nurl_println_int ( f ) )
    ( nurl_println `P32B-MARK` )
    ^ 0
}
