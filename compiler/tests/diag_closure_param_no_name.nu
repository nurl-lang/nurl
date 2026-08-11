// diag_closure_param_no_name.nu — a closure parameter type with no name.
//
// The message used to be word-for-word the one gen_fn_param prints, so
// neither said which list it meant and the tool could not tell them
// apart. Each now names its own construct, and the closure's adds the
// spelling between the '\' and the arrow.
@ main → i {
    : ( @ i i i ) f \ i x i → i { ^ x }
    ^ 0
}
