// OPEN in 0.72.0 — a view leaving through a helper's return value: `^ ( pick x )` hands back a released local.
// `pick` returns its parameter; `back` returns ( pick x ) for its own fresh string `x` and releases `x`
// on the way out. A call result is not tied to the arguments it may hand back: `^ x` would move `x`
// to the caller, while `^ ( pick x )` returns a view of it and releases `x`.
// ASan: heap-use-after-free in fputs <- nurl_println (main), printing the result.
$ `stdlib/core/string.nu`

@ pick s a → s { ^ a }

@ back → s { : s x ( nurl_str_cat `ab` `cd` ) ^ ( pick x ) }

@ main → i {
    : s r ( back )
    ( nurl_println r )
    ( nurl_println `P27B-MARK` )
    ^ 0
}
