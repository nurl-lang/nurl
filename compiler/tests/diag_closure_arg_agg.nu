// diag_closure_arg_agg.nu — an option passed to a closure declared
// '( @ i i )'. A closure invocation assembles its own call signature
// (opaque pointers), so the mismatch used to compile clean and the
// closure read the option's bytes as its integer parameter. The
// argstr agreement check — the type companion of the closure arity
// check — now rejects it at the call site.

@ main → i {
    : ( @ i i ) cl \ i x → i {
        ^ x
    }
    : ?i o @ ?i { T 5 }
    : i r ( cl o )
    ( nurl_print_int r )
    ^ 0
}
