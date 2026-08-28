// brackets — scan an embedded bracket string with a stack; print the
// maximum nesting depth if it is fully balanced, else 0.
$ `stdlib/core/string.nu`

@ main → i {
    : s text `(([{}]))[]{}`
    : i n ( nurl_str_len text )
    : *i stack # *i ( malloc * n 8 )
    : ~ i sp 0
    : ~ i depth 0
    : ~ i maxd 0
    : ~ i bad 0
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get text i )
        ? | == c 40 | == c 91 == c 123 {
            = . stack sp c
            = sp + sp 1
            = depth + depth 1
            ? > depth maxd { = maxd depth } {}
        } {
            ? | == c 41 | == c 93 == c 125 {
                ? == sp 0 {
                    = bad 1
                } {
                    = sp - sp 1
                    : i open . stack sp
                    : ~ i want - c 2
                    ? == c 41 { = want 40 } {}
                    ? == open want {} { = bad 1 }
                    = depth - depth 1
                }
            } {}
        }
        = i + i 1
    }
    : ~ i result 0
    ? & == sp 0 == bad 0 { = result maxd } {}
    ( nurl_println_int result )
    ( free stack )
    ^ 0
}
