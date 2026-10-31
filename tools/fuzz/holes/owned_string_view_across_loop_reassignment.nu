// owned_string_view_across_loop_reassignment: the H113 shape in a loop — the view taken at the top of the body, the owner replaced in the middle, the view read at the end.
// map: StmtT.assign | A1 | rejected | h115 | in loop body: view of owner taken, owner replaced, view read
$ `stdlib/core/string.nu`

@ main → i {
    : ~ s x ( nurl_str_cat `ab` `cd` )
    : ~ i t 0
    : ~ i k 0
    ~ < k 3 {
        : s y x
        = x ( nurl_str_cat x `!` )
        = t + t ( nurl_str_len y )
        = k + k 1
    }
    ( nurl_print_int t ) ( nurl_print `\n` )
    ^ 0
}
