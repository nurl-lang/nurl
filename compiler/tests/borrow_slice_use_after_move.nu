// borrow_slice_use_after_move.nu — `= e a` moves a's buffer to e, as it does
// a String's: a no longer owns anything, and reading it is refused. (Before
// agora #545 both names kept the buffer, and the next `= e [ … ]` freed it
// under a's read.)
@ main → i {
    : [i a [i | 5 6]
    : ~ [i e [i | 7]
    = e a
    = e [i | 8 8]
    ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
