// defer_ret_transfer.nu — returning an owned string from a function
// with an active defer chain: the return site must not free the
// returned buffer, and fn_cleanup must not reclaim it either (it is
// recorded in the return-transfer skip list); the caller owns it.
// The pre-defer string is reclaimed in fn_cleanup AFTER the defer body
// read it. ASan: no use-after-free, no double free; LSan: no leak.

$ `stdlib/core/string.nu`

@ make → s {
    : s pre ( nurl_str_cat `kept-` `alive` )
    ; { ( nurl_print `make defer: ` ) ( nurl_print pre ) ( nurl_print `\n` ) }
    : s r ( nurl_str_cat `returned-` `owned` )
    ^ r
}

@ main → i {
    : s got ( make )
    ( nurl_print got ) ( nurl_print `\n` )
    ^ 0
}
