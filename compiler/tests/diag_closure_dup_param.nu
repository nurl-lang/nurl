// diag_closure_dup_param.nu — two parameters of one closure sharing a
// name. The body can only ever name one of them, and the other argument
// is evaluated and then unreachable. The `@`-function spelling of this
// rule has been a diagnostic for years; the closure spelling was not.

@ main → i {
    : ( @ i i i ) f \ i a i a → i { ^ a }
    ^ 0
}
