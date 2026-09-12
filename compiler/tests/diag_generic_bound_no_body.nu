// diag_generic_bound_no_body.nu — a BOUNDED generic function whose body
// brace is missing.
//
// diag_generic_fn_no_body.nu is the plain form (`@ f [T] → T`), which
// the signature pre-pass recognises as a template. The BOUNDED form
// (`[T : Send]`) it does not recognise, so the mistake takes the other
// route — the parser's, which is the one that says which brace is
// missing. Only the bounded spelling reached the collector bug this
// pair exists for, and no hand-written program had used it; deleting
// one token did.

@ ship [T : Send] T v → i
^ 0
}

@ main → i {
    ^ 0
}
