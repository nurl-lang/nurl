// diag_inout_string_assign.nu — an `inout s` parameter cannot be given a
// new value. The caller's string may be owned (then the replaced value
// leaked) or borrowed (then freeing it would free the caller's literal or
// view), and the callee cannot tell which. The fix the message gives:
// return the new string, or take a String, which owns its buffer.

$ `stdlib/core/string.nu`

@ bump inout s p → v { = p ( nurl_str_cat p `x` ) }

@ bumped s p → s { ^ ( nurl_str_cat p `x` ) }

@ main → i {
    : ~ s a ( nurl_str_cat `a` `` )
    ( bump a )
    = a ( bumped a )
    ( nurl_println a )
    ^ 0
}
