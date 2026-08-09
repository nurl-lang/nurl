// dead_store_both_arms_ret.nu — a `:` binding whose RHS is a `?` join
// where BOTH arms return (`^`) out of the function. The store past the
// join is dead code: g_did_ret=1 and the join's last-type residue is
// 'void' — not a value at all. The nominal-enforcement sweep made
// coerce_store_val's clash checks fire on that residue ("value of type
// 'void' cannot initialise a binding of type '%HttpResponse'"),
// rejecting code that cannot run — nurlapi's stdlib-docs handler
// stopped compiling. The dead-store exemption must cover EVERY clash
// diagnostic, not just the produces-no-value one.

$ `stdlib/ext/http_response.nu`

@ pick b c → HttpResponse {
    : HttpResponse r ? c {
        : HttpResponse rr ( response_text 200 `then-arm` )
        ^ rr
    } {
        : HttpResponse rr ( response_text 200 `else-arm` )
        ( response_set_header rr `X-Arm` `else` )
        ^ rr
    }
    ^ r
}

@ main → i {
    : HttpResponse a ( pick T )
    : HttpResponse b2 ( pick F )
    ( nurl_print_int . a status ) ( nurl_print `\n` )
    ( nurl_print_int . b2 status ) ( nurl_print `\n` )
    ( http_response_free a ) ( http_response_free b2 )
    ^ 0
}
