// A generic signature is complete before any caller is emitted: the type
// substitution and the inout address convention both work before the body.
@ main → i {
    : ~ i n 0
    ( bump_g [u32] n # u32 7 )
    ( nurl_println_int n )
    ^ ? == n 7 0 1
}

@ bump_g [A] inout i slot A item → v {
    = slot + slot # i item
}
