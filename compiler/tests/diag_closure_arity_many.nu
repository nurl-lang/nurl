// diag_closure_arity_many.nu — invoking a closure with more arguments
// than its declared type takes: the dual of the too-few case, and just
// as silent (the surplus value was passed and ignored — usually a
// misread of what the closure does).
@ main → i {
    : ( @ i i ) f \ i a → i { ^ a }
    ^ ( f 1 2 )
}
